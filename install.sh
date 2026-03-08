#!/bin/sh
# install.sh – install or update victron-tailscale on a Victron device.
#
# Fetch and run in one command:
#
#   wget -qO- https://raw.githubusercontent.com/konne/victron-tailscale/main/install.sh | sh
#
# What this script does:
#   1. Downloads the repo archive and extracts it, preserving config.sh and state/
#   2. On first install: copies config-template.sh to config.sh and prompts for editing
#   3. Runs setup.sh

set -e

REPO_ARCHIVE_URL="https://github.com/konne/victron-tailscale/archive/refs/heads/main.tar.gz"
INSTALL_DIR="/data/victron-tailscale"
CONFIG="${INSTALL_DIR}/config.sh"
TEMPLATE="${INSTALL_DIR}/config-template.sh"
TMP_ARCHIVE="${INSTALL_DIR}/tmp/update.tgz"
TMP_EXTRACT="${INSTALL_DIR}/tmp/update-extract"

echo "============================================================"
echo "  victron-tailscale installer"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Download and extract – preserve config.sh and state/
# ---------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}/tmp"

echo "Downloading latest release..."
wget -qO "$TMP_ARCHIVE" "$REPO_ARCHIVE_URL" || {
  echo "ERROR: download failed. Check network connectivity."
  exit 1
}

echo "Extracting..."
rm -rf "$TMP_EXTRACT"
mkdir -p "$TMP_EXTRACT"
tar -xzf "$TMP_ARCHIVE" -C "$TMP_EXTRACT" --strip-components=1
rm -f "$TMP_ARCHIVE"

# Copy everything except config.sh (user file) and state/ (runtime data).
# config-template.sh is always updated from the repo.
for f in "$TMP_EXTRACT"/*; do
  name="$(basename "$f")"
  case "$name" in
    config.sh|state)
      # Never overwrite – these belong to the user/runtime
      ;;
    *)
      cp -r "$f" "${INSTALL_DIR}/${name}"
      ;;
  esac
done

rm -rf "$TMP_EXTRACT"

chmod +x "${INSTALL_DIR}/setup.sh" \
         "${INSTALL_DIR}/uninstall.sh" \
         "${INSTALL_DIR}/init.d/tailscaled"

echo "Files updated."

# ---------------------------------------------------------------------------
# 2. First install: create config.sh from template
# ---------------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
  echo ""
  echo "First install detected – creating config.sh from template..."
  cp "$TEMPLATE" "$CONFIG"

  echo ""
  echo "============================================================"
  echo "  CONFIGURATION REQUIRED"
  echo ""
  echo "  Edit ${CONFIG} and set at least:"
  echo "    DEVICE_NAME        – a short unique name for this device"
  echo "    TAILSCALE_AUTH_KEY – optional, for unattended auth"
  echo ""
  echo "  Then re-run:  sh ${INSTALL_DIR}/setup.sh"
  echo "============================================================"
  # Only open an editor when running interactively (stdin is a TTY).
  # When piped from wget | sh there is no TTY and opening an editor
  # would hang waiting for input.
  if [ -t 0 ]; then
    echo "Opening config.sh in nano..."
    nano "$CONFIG" || true
  else
    echo ""
    echo "  (Running non-interactively – skipping editor.)"
    echo "  Edit ${CONFIG} manually and run:  sh ${INSTALL_DIR}/setup.sh"
    exit 0
  fi

  CURRENT_NAME="$(grep '^DEVICE_NAME=' "$CONFIG" | cut -d'"' -f2)"
  if [ "$CURRENT_NAME" = "my-ekrano" ]; then
    echo ""
    echo "Device name not changed. Edit ${CONFIG} and run:"
    echo "  sh ${INSTALL_DIR}/setup.sh"
    exit 0
  fi
else
  echo "Existing config.sh preserved."
fi

# ---------------------------------------------------------------------------
# 3. Run setup
# ---------------------------------------------------------------------------
echo ""
echo "Running setup.sh ..."
sh "${INSTALL_DIR}/setup.sh"
