#!/bin/sh
# setup.sh – install, configure, and maintain victron-tailscale.
#
# Safe to run multiple times; each step checks whether it is already done.
# Called directly by the user on first install, and automatically on every
# boot via /data/rc.local (the Victron-native hook that survives firmware
# updates). Firmware updates wipe /usr/bin and /etc/init.d; this script
# re-installs both on the next boot.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.sh"
TEMPLATE="${SCRIPT_DIR}/config-template.sh"

# ---------------------------------------------------------------------------
# Load config (create from template on first run)
# ---------------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
  if [ -f "$TEMPLATE" ]; then
    echo "No config.sh found – copying from config-template.sh."
    echo "Edit ${CONFIG} to set your DEVICE_NAME before continuing."
    cp "$TEMPLATE" "$CONFIG"
  fi
  echo "ERROR: config.sh not found at ${CONFIG}"
  echo "       Edit it and re-run setup.sh."
  exit 1
fi
# shellcheck source=config-template.sh
. "$CONFIG"

BOOT_MODE=false
[ "$1" = "--boot" ] && BOOT_MODE=true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------------------------------------------------------------------------
# 1. Ensure directory structure
# ---------------------------------------------------------------------------
log "Ensuring directory structure..."
mkdir -p "$STATE_DIR" "$TMP_DIR"

# ---------------------------------------------------------------------------
# 2. Install tailscale binaries if missing or outdated
# ---------------------------------------------------------------------------
fetch_latest_version() {
  # Scrape the latest stable version for static binaries from the package index.
  # The page lists files like tailscale_1.94.2_arm.tgz in the #static section.
  # We grab the first version number that appears next to an arm tarball link.
  wget -qO- "https://pkgs.tailscale.com/stable/" \
    | grep -o 'tailscale_[0-9][0-9.]*_arm\.tgz' \
    | head -n 1 \
    | sed 's/tailscale_\([0-9][0-9.]*\)_arm\.tgz/\1/'
}

install_tailscale() {
  # Resolve version: use pinned value from config, or auto-detect latest.
  if [ -z "$TAILSCALE_VERSION" ]; then
    log "TAILSCALE_VERSION not set – detecting latest stable version..."
    TAILSCALE_VERSION="$(fetch_latest_version)"
    if [ -z "$TAILSCALE_VERSION" ]; then
      log "ERROR: could not detect latest Tailscale version. Set TAILSCALE_VERSION in config.sh."
      exit 1
    fi
    log "Latest stable version: ${TAILSCALE_VERSION}"
  fi

  log "Installing tailscale ${TAILSCALE_VERSION} (${TAILSCALE_ARCH})..."

  ARCHIVE="tailscale_${TAILSCALE_VERSION}_${TAILSCALE_ARCH}.tgz"
  DOWNLOAD_URL="https://pkgs.tailscale.com/stable/${ARCHIVE}"
  ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE}"
  EXTRACT_DIR="${TMP_DIR}/tailscale_extract"

  log "Downloading ${DOWNLOAD_URL} ..."
  wget -q -O "$ARCHIVE_PATH" "$DOWNLOAD_URL" || {
    log "ERROR: download failed. Check TAILSCALE_DOWNLOAD_URL and network."
    exit 1
  }

  mkdir -p "$EXTRACT_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"

  # The archive unpacks to a directory named tailscale_<version>_<arch>/
  INNER_DIR="${EXTRACT_DIR}/tailscale_${TAILSCALE_VERSION}_${TAILSCALE_ARCH}"
  cp "${INNER_DIR}/tailscaled" /usr/bin/tailscaled
  cp "${INNER_DIR}/tailscale"  /usr/bin/tailscale
  chmod +x /usr/bin/tailscaled /usr/bin/tailscale

  # Clean up – /data space is limited
  rm -rf "$ARCHIVE_PATH" "$EXTRACT_DIR"
  log "tailscale ${TAILSCALE_VERSION} installed."
}

NEED_INSTALL=false
if ! command -v tailscale >/dev/null 2>&1; then
  NEED_INSTALL=true
elif [ -n "$TAILSCALE_VERSION" ]; then
  # Only enforce a version check when a specific version is pinned in config.
  INSTALLED_VER="$(tailscale version 2>/dev/null | head -n 1 | awk '{print $1}')"
  if [ "$INSTALLED_VER" != "$TAILSCALE_VERSION" ]; then
    log "Installed version (${INSTALLED_VER}) differs from pinned (${TAILSCALE_VERSION})."
    NEED_INSTALL=true
  fi
else
  log "tailscale already installed: $(tailscale version 2>/dev/null | head -n 1)"
fi

$NEED_INSTALL && install_tailscale

# ---------------------------------------------------------------------------
# 3. Register in /data/rc.local (the Victron-native boot hook)
# ---------------------------------------------------------------------------
# /data/rc.local survives firmware updates; /etc/init.d does not.
# We add a single line that calls this setup.sh on every boot.
# The line is guarded so it is only added once.
RC_LOCAL="/data/rc.local"
RC_ENTRY="sh ${SCRIPT_DIR}/setup.sh --boot"

if [ ! -f "$RC_LOCAL" ]; then
  log "Creating ${RC_LOCAL}..."
  printf '#!/bin/sh\n%s\n' "$RC_ENTRY" > "$RC_LOCAL"
  chmod +x "$RC_LOCAL"
elif ! grep -qF "$RC_ENTRY" "$RC_LOCAL"; then
  log "Adding victron-tailscale entry to ${RC_LOCAL}..."
  echo "$RC_ENTRY" >> "$RC_LOCAL"
else
  log "${RC_LOCAL} already contains victron-tailscale entry."
fi

# ---------------------------------------------------------------------------
# 4. Install init.d script
# ---------------------------------------------------------------------------
INITD_SRC="${SCRIPT_DIR}/init.d/tailscaled"
INITD_DST="/etc/init.d/tailscaled"

if [ ! -f "$INITD_DST" ] || ! diff -q "$INITD_SRC" "$INITD_DST" >/dev/null 2>&1; then
  log "Installing init.d script..."
  cp "$INITD_SRC" "$INITD_DST"
  chmod +x "$INITD_DST"
  # Register with update-rc.d if available, otherwise use symlinks
  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d tailscaled defaults >/dev/null 2>&1 || true
  fi
fi

# ---------------------------------------------------------------------------
# 4. Start tailscaled if not running
# ---------------------------------------------------------------------------
if ! pgrep tailscaled >/dev/null 2>&1; then
  log "Starting tailscaled..."
  /etc/init.d/tailscaled start
  sleep 3
fi

# ---------------------------------------------------------------------------
# 5. Authenticate / bring up the tailscale node
# ---------------------------------------------------------------------------
TS_STATUS="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo 'unknown')"
log "Tailscale backend state: ${TS_STATUS}"

if [ "$TS_STATUS" = "Running" ]; then
  log "Tailscale is already authenticated and running – skipping tailscale up."
else
  log "Tailscale not running (state: ${TS_STATUS}) – authenticating..."

  UP_ARGS="--hostname=${DEVICE_NAME}-victron"

  if [ -n "$TAILSCALE_LOGIN_SERVER" ]; then
    UP_ARGS="${UP_ARGS} --login-server=${TAILSCALE_LOGIN_SERVER}"
  fi

  if [ "$ENABLE_SSH" = "true" ]; then
    UP_ARGS="${UP_ARGS} --ssh"
  fi

  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    UP_ARGS="${UP_ARGS} --authkey=${TAILSCALE_AUTH_KEY}"
    # shellcheck disable=SC2086
    tailscale up $UP_ARGS
  else
    # Interactive login – print the URL prominently so the user sees it.
    # shellcheck disable=SC2086
    tailscale up $UP_ARGS --qr 2>&1 | tee /dev/stderr &
    TS_UP_PID=$!

    echo ""
    echo "============================================================"
    echo "  ACTION REQUIRED – open the URL above in your browser to"
    echo "  authenticate this device with Tailscale."
    echo ""
    echo "  After logging in, remember to:"
    echo "    1. Disable key expiry for EACH node registered below:"
    echo "         ${DEVICE_NAME}-victron"
    echo "$SERVICES" | grep -v '^$' | while IFS='|' read -r svc _rest; do
      svc="$(echo "$svc" | tr -d ' \t')"
      [ -n "$svc" ] && echo "         ${DEVICE_NAME}-${svc}"
    done
    echo "    2. Approve each node if your tailnet requires approval."
    echo "============================================================"
    echo ""

    wait $TS_UP_PID
  fi
fi

# ---------------------------------------------------------------------------
# 6. Configure Tailscale Serve routes (idempotent)
# ---------------------------------------------------------------------------
log "Checking Tailscale Serve configuration..."

echo "$SERVICES" | grep -v '^$' | while IFS='|' read -r svc local_url path; do
  # Trim whitespace
  svc="$(echo "$svc" | tr -d ' \t')"
  local_url="$(echo "$local_url" | tr -d ' \t')"
  path="$(echo "$path" | tr -d ' \t')"

  [ -z "$svc" ] && continue

  SERVICE_NAME="svc:${DEVICE_NAME}-${svc}"

  # Check whether this exact service is already configured by querying its
  # own serve status. Using --service scopes the output to just this node,
  # avoiding false matches when multiple services share the same local port.
  SVC_STATUS="$(tailscale serve --service="$SERVICE_NAME" status 2>/dev/null || true)"
  if echo "$SVC_STATUS" | grep -qF "$local_url"; then
    log "  ${SERVICE_NAME}: already configured – skipping."
  else
    log "  ${SERVICE_NAME}: configuring ${path} -> ${local_url}${path}"
    tailscale serve --service="$SERVICE_NAME" "${local_url}${path}" || {
      log "  WARNING: failed to configure serve for ${SERVICE_NAME}"
    }
  fi
done

# ---------------------------------------------------------------------------
# 7. Done
# ---------------------------------------------------------------------------
log "Setup complete."

if ! $BOOT_MODE; then
  echo ""
  echo "============================================================"
  echo "  victron-tailscale is running."
  echo ""
  echo "  Your services:"
  echo "$SERVICES" | grep -v '^$' | while IFS='|' read -r svc _local _path; do
    svc="$(echo "$svc" | tr -d ' \t')"
    [ -z "$svc" ] && continue
    echo "    https://${DEVICE_NAME}-${svc}.<tailnet>.ts.net"
  done
  echo ""
  echo "  Run 'tailscale status' to see all nodes."
  echo "============================================================"
fi
