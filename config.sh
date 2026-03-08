#!/bin/sh
# victron-tailscale configuration
# Edit this file to match your setup, then run setup.sh.
#
# All paths are relative to the module root at /data/victron-tailscale.

# ---------------------------------------------------------------------------
# Device identity
# ---------------------------------------------------------------------------

# Base hostname used for all Tailscale service names.
# The device will register as:
#   <DEVICE_NAME>-victron        (main HTTPS proxy)
#   <DEVICE_NAME>-nodered        (Node-RED full UI)
#   <DEVICE_NAME>-ui             (Node-RED /ui dashboard only)
# Keep it short, lowercase, no spaces.
DEVICE_NAME="my-ekrano"

# ---------------------------------------------------------------------------
# Tailscale authentication
# ---------------------------------------------------------------------------

# Option A - Auth key (recommended for unattended/automated installs).
# Generate a reusable, pre-approved key at https://login.tailscale.com/admin/settings/keys
# Leave empty to use interactive browser login (Option B).
#
# IMPORTANT after first login (Option B):
#   1. Open https://login.tailscale.com/admin/machines
#   2. Disable key expiry for every node registered by this device.
#   3. Approve each node if your tailnet requires device approval.
TAILSCALE_AUTH_KEY=""

# Tailscale control server (leave empty for the default Tailscale SaaS).
# Set to your Headscale URL if you self-host, e.g. "https://headscale.example.com"
TAILSCALE_LOGIN_SERVER=""

# ---------------------------------------------------------------------------
# SSH access via Tailscale
# ---------------------------------------------------------------------------

# Expose SSH through Tailscale (tailscale ssh).
# Allows key-based SSH access from any device in your tailnet without
# opening a port on the local network.
ENABLE_SSH=true

# ---------------------------------------------------------------------------
# Services exposed via Tailscale Serve
# ---------------------------------------------------------------------------
# Each service creates a separate Tailscale node so that HTTPS (443) can be
# served per-service without conflicting with the device's local HTTPS port.
#
# Format: "service-suffix|local-url|path-prefix"
#   service-suffix  appended to DEVICE_NAME, e.g. "victron" -> svc:<DEVICE_NAME>-victron
#   local-url       the local endpoint to proxy (https+insecure:// for self-signed certs)
#   path-prefix     URL path to expose; use "/" for the whole site
#
# The three default services mirror the original setup:
#   *-victron   -> Victron Ekrano web UI  (port 443)
#   *-nodered   -> Node-RED editor        (port 1881, full path)
#   *-ui        -> Node-RED dashboard     (port 1881, /ui only)

SERVICES="
victron|https+insecure://localhost:443|/
nodered|https+insecure://localhost:1881|/
ui|https+insecure://localhost:1881|/ui
"

# ---------------------------------------------------------------------------
# Tailscale binary
# ---------------------------------------------------------------------------

# Architecture of the Victron device (arm for Ekrano/Cerbo GX).
TAILSCALE_ARCH="arm"

# Pin to a specific version, or leave empty to auto-detect the latest stable
# release from https://pkgs.tailscale.com/stable/#static at install time.
# Example: TAILSCALE_VERSION="1.94.2"
TAILSCALE_VERSION=""

# ---------------------------------------------------------------------------
# Paths (change only if you know what you are doing)
# ---------------------------------------------------------------------------

MODULE_DIR="/data/victron-tailscale"
STATE_DIR="${MODULE_DIR}/state"
TMP_DIR="${MODULE_DIR}/tmp"
LOG_FILE="${MODULE_DIR}/setup.log"
