#!/bin/sh
# install.sh – bootstrap victron-tailscale from GitHub onto a Victron device.
#
# Fetch and run in one command (replace <your-github-user> with your username):
#
#   wget -qO- https://raw.githubusercontent.com/<user>/victron-tailscale/main/install.sh | sh
#
# What this script does:
#   1. Clones (or updates) the repo into /data/victron-tailscale
#   2. Prompts you to edit config.sh if DEVICE_NAME is still the placeholder
#   3. Runs setup.sh to install tailscale and configure everything

set -e

REPO_URL="https://github.com/konne/victron-tailscale.git"
INSTALL_DIR="/data/victron-tailscale"
CONFIG="${INSTALL_DIR}/config.sh"

echo "============================================================"
echo "  victron-tailscale installer"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Clone or update the repository
# ---------------------------------------------------------------------------
if [ -d "${INSTALL_DIR}/.git" ]; then
  echo "Existing installation found – pulling latest changes..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "Cloning repository to ${INSTALL_DIR} ..."
  # git may not be available on all Victron firmware versions; fall back to
  # downloading a tarball if needed.
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  else
    echo "git not found – downloading archive instead..."
    ARCHIVE_URL="https://github.com/konne/victron-tailscale/archive/refs/heads/main.tar.gz"
    TMP_ARCHIVE="/tmp/victron-tailscale.tgz"
    wget -qO "$TMP_ARCHIVE" "$ARCHIVE_URL"
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$TMP_ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
    rm -f "$TMP_ARCHIVE"
  fi
fi

chmod +x "${INSTALL_DIR}/setup.sh" \
         "${INSTALL_DIR}/uninstall.sh" \
         "${INSTALL_DIR}/init.d/tailscaled"

# ---------------------------------------------------------------------------
# 2. Ensure config.sh exists and is configured
# ---------------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
  echo "ERROR: config.sh not found in ${INSTALL_DIR}."
  echo "       This should not happen – please check the repository."
  exit 1
fi

# Check whether the user has changed the placeholder device name.
CURRENT_NAME="$(grep '^DEVICE_NAME=' "$CONFIG" | cut -d'"' -f2)"
if [ "$CURRENT_NAME" = "my-ekrano" ]; then
  echo ""
  echo "============================================================"
  echo "  CONFIGURATION REQUIRED"
  echo ""
  echo "  Open ${CONFIG} and set at least:"
  echo "    DEVICE_NAME  – a short unique name for this device"
  echo "    TAILSCALE_AUTH_KEY  – optional, for unattended auth"
  echo ""
  echo "  Then re-run:  sh ${INSTALL_DIR}/setup.sh"
  echo "============================================================"
  echo ""
  echo "Opening config.sh in vi (Ctrl-C to skip)..."
  sleep 2
  vi "$CONFIG" || true

  # Re-read after edit
  CURRENT_NAME="$(grep '^DEVICE_NAME=' "$CONFIG" | cut -d'"' -f2)"
  if [ "$CURRENT_NAME" = "my-ekrano" ]; then
    echo ""
    echo "Device name not changed. Edit ${CONFIG} and run:"
    echo "  sh ${INSTALL_DIR}/setup.sh"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 3. Run setup
# ---------------------------------------------------------------------------
echo ""
echo "Running setup.sh ..."
sh "${INSTALL_DIR}/setup.sh"
