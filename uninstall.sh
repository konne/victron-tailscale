#!/bin/sh
# uninstall.sh – remove victron-tailscale and all associated components.
#
# Run as root on the Victron device:
#   sh /data/victron-tailscale/uninstall.sh
#
# What this removes:
#   - Tailscale serve routes for all configured services
#   - tailscale node logout (removes device from tailnet)
#   - tailscaled init.d script and rc.d symlinks
#   - tailscale and tailscaled binaries from /usr/bin
#   - /data/victron-tailscale directory (the module itself)
#
# What this does NOT remove:
#   - The device entries in the Tailscale admin console – remove those manually
#     at https://login.tailscale.com/admin/machines

set -e

INSTALL_DIR="/data/victron-tailscale"
CONFIG="${INSTALL_DIR}/config.sh"

echo "============================================================"
echo "  victron-tailscale uninstaller"
echo "============================================================"
echo ""
echo "This will remove tailscale from this device."
printf "Continue? [y/N] "
read -r CONFIRM
case "$CONFIRM" in
  y|Y) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# Load config to know service names (best-effort)
# shellcheck source=config.sh
[ -f "$CONFIG" ] && . "$CONFIG" || true

# ---------------------------------------------------------------------------
# 1. Remove Tailscale Serve routes
# ---------------------------------------------------------------------------
if command -v tailscale >/dev/null 2>&1 && pgrep tailscaled >/dev/null 2>&1; then
  echo "Removing Tailscale Serve routes..."
  if [ -n "$SERVICES" ] && [ -n "$DEVICE_NAME" ]; then
    echo "$SERVICES" | grep -v '^$' | while IFS='|' read -r svc _local _path; do
      svc="$(echo "$svc" | tr -d ' \t')"
      [ -z "$svc" ] && continue
      SERVICE_NAME="svc:${DEVICE_NAME}-${svc}"
      echo "  Removing serve for ${SERVICE_NAME}..."
      tailscale serve --service="$SERVICE_NAME" --remove / 2>/dev/null || true
    done
  fi

  # ---------------------------------------------------------------------------
  # 2. Log out from Tailscale (removes all nodes from tailnet)
  # ---------------------------------------------------------------------------
  echo "Logging out from Tailscale..."
  tailscale logout 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 3. Stop and remove init.d script
# ---------------------------------------------------------------------------
if [ -f /etc/init.d/tailscaled ]; then
  echo "Stopping tailscaled..."
  /etc/init.d/tailscaled stop 2>/dev/null || true

  echo "Removing init.d script..."
  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d tailscaled remove 2>/dev/null || true
  fi
  # Remove any rc.d symlinks manually as a fallback
  rm -f /etc/rc*.d/*tailscaled 2>/dev/null || true
  rm -f /etc/init.d/tailscaled
fi

# ---------------------------------------------------------------------------
# 4. Remove binaries
# ---------------------------------------------------------------------------
echo "Removing tailscale binaries..."
rm -f /usr/bin/tailscale /usr/bin/tailscaled

# ---------------------------------------------------------------------------
# 5. Remove module directory
# ---------------------------------------------------------------------------
echo "Removing ${INSTALL_DIR} ..."
rm -rf "$INSTALL_DIR"

echo ""
echo "============================================================"
echo "  Uninstall complete."
echo ""
echo "  Remember to remove the device nodes from the Tailscale"
echo "  admin console: https://login.tailscale.com/admin/machines"
echo "============================================================"
