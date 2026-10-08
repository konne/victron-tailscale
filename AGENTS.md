# AGENTS.md – AI session history

This file tracks significant changes made by AI agents (Ona / Claude) to this repository. Append a new entry for each session that produces meaningful changes.

---

## 2025-07-10 – Initial scaffold (Ona / Claude Sonnet 4.6)

**Goal:** Create a self-contained Victron Ekrano Tailscale extension that survives firmware updates.

**Changes made:**

- `config.sh` – single configuration file covering device name, auth key, SSH toggle, service definitions, Tailscale version/arch, and all paths.
- `init.d/tailscaled` – improved init.d script with `restart` and `status` actions; calls `setup.sh --boot` on start to re-apply configuration after firmware updates.
- `setup.sh` – idempotent setup script that:
  - Creates the directory structure under `/data/victron-tailscale`
  - Downloads and installs Tailscale binaries if missing or version-mismatched (downloads to `tmp/`, cleans up after)
  - Installs the init.d script
  - Starts `tailscaled` if not running
  - Authenticates via auth key or interactive browser login (with prominent post-login checklist)
  - Applies all `tailscale serve` routes from `SERVICES` config
- `install.sh` – bootstrap script safe to pipe from a GitHub raw URL; clones or updates the repo, prompts for config edit, then runs `setup.sh`.
- `uninstall.sh` – full removal: serve routes, logout, init.d, binaries, module directory.
- `README.md` – full documentation covering installation, configuration, service layout, updating, uninstalling, and troubleshooting.

**Design decisions:**

- Module lives entirely in `/data/victron-tailscale` (survives firmware updates).
- Separate Tailscale service nodes per web interface because the device's local port 443 is already bound, preventing a single node from serving multiple HTTPS paths.
- `https+insecure://` used in serve routes because Victron uses self-signed certificates locally.
- Tailscale state stored in `state/` subdirectory (not `/etc/tailscale`) so it persists across firmware updates.
- Download uses `wget` (available on Victron firmware); `git` is used if present, tarball fallback otherwise.

## 2026-10-08 – Firmware recovery and boot diagnostics (Codex)

- Confirmed the Ekrano boot hook is executable and wired through `S99custom-rc-late.sh`; the Node-RED log demonstrates a read-only rootfs failure.
- Register/repair the persistent hook before installation, preserving unrelated entries and avoiding boot-time hook rewrites.
- Remount rootfs read/write before system modifications; capture Tailscale boot output from the beginning with boot ID and exit status.
- Ship runnable scripts with executable permissions and protect sourced config with mode 600.
- Keep internet-based binary downloads and existing state storage; no persistent binary cache or automatic retry loop.
- Added isolated regression checks for hook migration, permissions, remount failure, and early boot logging. Actual reboot verification is still required on the device.

## 2026-10-08 – Missing dashboard service (Codex)

- Found that Tailscale 1.104.1 Serve status is global even with the parent `--service` flag; shared port 1881 caused the editor route to falsely satisfy the UI check.
- Apply every named service with its complete proxy target, preserve CLI approval notices, and fail setup when a Serve command fails.
- Clarify that local route configuration does not establish admin approval or backend health; include the base service in the printed URLs.
- Added mocked regressions for shared backends, re-advertising existing routes, approval output, and command failure.
