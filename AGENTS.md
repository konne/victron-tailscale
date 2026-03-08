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
