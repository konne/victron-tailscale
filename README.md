# victron-tailscale

Adds [Tailscale](https://tailscale.com) to a Victron Ekrano (or Cerbo GX) and exposes the device's web interfaces as named Tailscale services. The module lives entirely under `/data/victron-tailscale`, which survives Victron firmware updates. On each boot the init.d script re-applies the configuration, so a firmware update only requires a reboot to restore full connectivity.

## How it works

Victron firmware updates wipe `/usr/bin` and `/etc/init.d` but leave `/data` intact. This module uses `/data/rc.local` — the [Victron-native boot hook](https://www.victronenergy.com/live/ccgx:root_access#hooks_to_installrun_own_code_at_boot) that survives firmware updates — to re-apply everything on each boot:

1. `setup.sh` registers itself in `/data/rc.local` on first install.
2. On every boot, `rc.local` calls `setup.sh --boot`, which re-installs the Tailscale binaries if missing, re-installs the init.d script, and re-applies all `tailscale serve` routes.
3. Tailscale state is stored under `/data/victron-tailscale/state/` and is never wiped.

### Why separate service nodes?

The Victron device already binds port 443 locally, so a single Tailscale hostname cannot serve HTTPS on that port for multiple paths without conflicts. Each service (`victron`, `nodered`, `ui`) registers as a distinct Tailscale node (`svc:<name>-<suffix>`), each with its own HTTPS endpoint.

| Service node | Proxies to | Purpose |
|---|---|---|
| `<name>-victron` | `https://localhost:443` | Victron Ekrano web UI |
| `<name>-nodered` | `https://localhost:1881` | Node-RED editor |
| `<name>-ui` | `https://localhost:1881/ui` | Node-RED dashboard only |

---

## Installation

### One-line install (recommended)

SSH into the device and run:

```sh
wget -qO- https://raw.githubusercontent.com/konne/victron-tailscale/main/install.sh | sh
```

The installer will:
1. Clone the repo to `/data/victron-tailscale`
2. Open `config.sh` in `vi` so you can set your device name and optional auth key
3. Run `setup.sh` to install Tailscale and configure everything

### Manual install

```sh
# Clone
git clone https://github.com/konne/victron-tailscale.git /data/victron-tailscale

# Edit config
vi /data/victron-tailscale/config.sh

# Run setup
sh /data/victron-tailscale/setup.sh
```

---

## Configuration

All options are in [`config.sh`](config.sh). The key settings:

### Device name

```sh
DEVICE_NAME="my-ekrano"
```

Used as the prefix for all Tailscale node names. Keep it short and lowercase.

### Authentication

**Option A – Auth key (unattended/automated):**

```sh
TAILSCALE_AUTH_KEY="tskey-auth-..."
```

Generate a reusable key at <https://login.tailscale.com/admin/settings/keys>.

**Option B – Interactive login (leave key empty):**

```sh
TAILSCALE_AUTH_KEY=""
```

`setup.sh` will print a login URL and QR code. Open the URL in a browser to authenticate.

> **After first login (Option B), you must:**
> 1. Go to <https://login.tailscale.com/admin/machines>
> 2. **Disable key expiry** for each node (`<name>-victron`, `<name>-nodered`, `<name>-ui`)
> 3. **Approve each node** if your tailnet has device approval enabled

### SSH access

```sh
ENABLE_SSH=true   # expose SSH via Tailscale (default: on)
```

When enabled, you can SSH to the device from any machine in your tailnet without opening a port on the local network.

### Services

```sh
SERVICES="
victron|https+insecure://localhost:443|/
nodered|https+insecure://localhost:1881|/
ui|https+insecure://localhost:1881|/ui
"
```

Each line defines one Tailscale service node. Format: `suffix|local-url|path`

- **suffix** – appended to `DEVICE_NAME`, e.g. `victron` → node `svc:<name>-victron`
- **local-url** – the local endpoint to proxy; use `https+insecure://` for self-signed certs
- **path** – URL path to expose; use `/` for the whole site

#### Adding a service

To add a new service, append a line to `SERVICES` and re-run `setup.sh`:

```sh
SERVICES="
victron|https+insecure://localhost:443|/
nodered|https+insecure://localhost:1881|/
ui|https+insecure://localhost:1881|/ui
grafana|http://localhost:3000|/
"
```

Then run:

```sh
sh /data/victron-tailscale/setup.sh
```

The new node `<name>-grafana` will appear in your tailnet. Remember to disable key expiry and approve it if required.

### Tailscale version

```sh
TAILSCALE_ARCH="arm"
TAILSCALE_VERSION=""   # empty = auto-detect latest stable
```

By default `setup.sh` fetches the latest stable version from `https://pkgs.tailscale.com/stable/` at install time. To pin a specific version set `TAILSCALE_VERSION="1.94.2"`. When pinned, `setup.sh` will replace the installed binary if the versions differ.

---

## File layout

```
/data/
├── rc.local                        # Victron boot hook (created/updated by setup.sh)
└── victron-tailscale/
    ├── config.sh                   # your configuration (edit this)
    ├── setup.sh                    # install / re-apply configuration
    ├── install.sh                  # bootstrap script (fetched from GitHub)
    ├── uninstall.sh                # full removal
    ├── init.d/
    │   └── tailscaled              # init.d script (copied to /etc/init.d/ on each boot)
    ├── state/
    │   └── tailscaled.state        # Tailscale persistent state (survives firmware updates)
    └── tmp/                        # temporary download directory (auto-cleaned)
```

---

## Updating

Pull the latest version and re-run setup:

```sh
git -C /data/victron-tailscale pull
sh /data/victron-tailscale/setup.sh
```

Or re-run the one-line installer – it detects an existing installation and does a `git pull`.

---

## Uninstall

```sh
sh /data/victron-tailscale/uninstall.sh
```

This removes:
- All Tailscale serve routes
- The Tailscale node logout (removes device from tailnet)
- The init.d script
- The `tailscale` and `tailscaled` binaries
- The `/data/victron-tailscale` directory

After uninstalling, remove the stale node entries from the Tailscale admin console at <https://login.tailscale.com/admin/machines>.

---

## Troubleshooting

**Check the setup log:**
```sh
cat /data/victron-tailscale/setup.log
```

**Check tailscale status:**
```sh
tailscale status
```

**Restart tailscaled manually:**
```sh
/etc/init.d/tailscaled restart
```

**Re-apply serve routes without full reinstall:**
```sh
sh /data/victron-tailscale/setup.sh
```

**tailscale not found after firmware update:**
Reboot the device. The init.d script will detect the missing binary, download it, and re-apply the configuration automatically.