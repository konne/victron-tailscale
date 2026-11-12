#!/bin/sh
# Sourced by setup.sh. Keep this helper self-contained for manual installations.

register_boot_hook() {
    # Only replace invocations owned by this extension; retain other user code.
    # Put the entry immediately after the shebang, before any existing exit.
    if [ ! -f "$RC_LOCAL" ]; then
        printf '#!/bin/sh\n' > "$RC_LOCAL"
    fi
    BOOT_TMP="$(mktemp "${RC_LOCAL}.XXXXXX")"
    awk -v script="$SETUP_SCRIPT" -v marker="$MARKER" '
        BEGIN { entry = "# " marker "\nsh " script " --boot &" }
        NR == 1 {
            if ($0 ~ /^#!/) { print; print entry; next }
            print "#!/bin/sh"; print entry
        }
        $0 == "# " marker { next }
        $1 == "sh" && $2 == script { next }
        { print }
        END { if (NR == 0) { print "#!/bin/sh"; print entry } }
    ' "$RC_LOCAL" > "$BOOT_TMP"
    if ! cmp -s "$RC_LOCAL" "$BOOT_TMP"; then
        cp -p "$RC_LOCAL" "${RC_LOCAL}.backup-${MARKER}"
        chmod 755 "$BOOT_TMP"
        mv "$BOOT_TMP" "$RC_LOCAL"
    else
        rm -f "$BOOT_TMP"
    fi
    # Victron skips a non-executable rc.local, even if its contents are correct.
    chmod 755 "$RC_LOCAL"
}

prepare_rootfs() {
    if awk '$2 == "/" && $4 ~ /(^|,)rw(,|$)/ { found = 1 } END { exit !found }' /proc/mounts; then
        return 0
    fi
    echo "Root filesystem is read-only; remounting read/write for setup."
    if ! mount -o remount,rw /; then
        echo "ERROR: cannot remount root filesystem; setup stopped before modifying /usr or /etc."
        return 1
    fi
}

# The lock is on /run, so a reboot cannot leave a stale lock. The parent holds
# fd 9 across retries; workers/daemons must close it so they cannot retain it.
acquire_setup_lock() {
    command -v flock >/dev/null 2>&1 || {
        echo "ERROR: flock is required to serialize setup." >&2
        exit 1
    }
    exec 9>"${SETUP_LOCK_FILE:-/run/${MARKER}-setup.lock}"
    if ! flock -n 9; then
        echo "Another ${MARKER} setup is already running; skipping duplicate."
        exit 0
    fi
}

run_boot_setup() {
    BOOT_ATTEMPT=1
    BOOT_DELAY=10
    while :; do
        echo "Boot recovery attempt ${BOOT_ATTEMPT}"
        # A separate shell preserves set -e inside the worker even though its
        # exit status is tested here. No retry may hide an intermediate failure.
        if sh "$SETUP_SCRIPT" --boot-once "$@" 9>&-; then
            echo "Boot recovery completed after ${BOOT_ATTEMPT} attempt(s)."
            return 0
        else
            BOOT_RESULT=$?
        fi
        echo "Boot setup failed (exit ${BOOT_RESULT}); retrying in ${BOOT_DELAY}s."
        sleep "$BOOT_DELAY"
        BOOT_ATTEMPT=$((BOOT_ATTEMPT + 1))
        BOOT_DELAY=$((BOOT_DELAY * 2))
        [ "$BOOT_DELAY" -le 300 ] || BOOT_DELAY=300
    done
}
