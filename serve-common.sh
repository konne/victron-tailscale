#!/bin/sh
# Sourced by setup.sh; log(), DEVICE_NAME and SERVICES are supplied by it.

configure_services() {
  printf '%s\n' "$SERVICES" | while IFS='|' read -r svc local_url path; do
    svc="$(printf '%s' "$svc" | tr -d ' \t\r')"
    local_url="$(printf '%s' "$local_url" | tr -d ' \t\r')"
    path="$(printf '%s' "$path" | tr -d ' \t\r')"
    [ -n "${svc}${local_url}${path}" ] || continue

    if [ -z "$svc" ]; then
      SERVICE_NAME="svc:${DEVICE_NAME}"
    else
      SERVICE_NAME="svc:${DEVICE_NAME}-${svc}"
    fi

    # `serve --service=... status` still reports ALL services in Tailscale
    # 1.104.1. Matching localhost:1881 confuses the editor with the dashboard.
    # Apply each exact service/target pair instead. Serve updates that route
    # and advertises the service, including when its route already exists.
    log "  ${SERVICE_NAME}: applying HTTPS :443 -> ${local_url}${path}"
    if SERVE_OUTPUT="$(tailscale serve --bg --service="$SERVICE_NAME" --https=443 "${local_url}${path}" 2>&1)"; then
      # Keep Tailscale's approval notices visible instead of discarding them.
      if [ -n "$SERVE_OUTPUT" ]; then
        log "$SERVE_OUTPUT"
      fi
    else
      log "  ERROR: failed to configure ${SERVICE_NAME}: ${SERVE_OUTPUT}"
      if printf '%s\n' "$SERVE_OUTPUT" | grep -q 'tagged nodes'; then
        log "  This device needs a tag-based identity to host Tailscale Services."
        log "  Configure its tags in the Tailscale admin console, then re-run setup."
      fi
      # The while loop is the last pipeline command, so failure reaches setup.
      exit 1
    fi
  done
}
