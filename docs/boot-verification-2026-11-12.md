# Live boot verification — 2026-11-12

Test device: Ekrano GX running Venus OS v3.85. All times below are Pacific/Auckland (NZDT).

## Root cause

The executable `/data/rc.local` hooks ran correctly. On the original failed boot,
setup began at 2026-11-12 12:18:28 NZDT, while Ethernet received its IP address at
12:19:23 NZDT. Git package downloads failed and Tailscale could not resolve its
package host. Both scripts exited without retrying. Git remained absent, causing
Node-RED to disable Projects and load its fallback flow file.

## Repair

- Retry failed boot setup after 10, 20, 40, 80 and 160 seconds, then every
  300 seconds until setup succeeds. Manual setup remains a single attempt.
- Serialize each module's setup with a `/run` flock; close the lock descriptor
  in workers and daemons. Concurrent init.d/rc.local startup is skipped.
- Preserve Node-RED restart intent across a partially successful setup.
- Give Tailscale boot login a 30-second timeout and propagate its actual exit
  status. Bound binary downloads, detect either missing executable, and avoid
  recursively launching setup when setup itself starts the daemon.

## Test 1: recovery with missing binaries

Reboot requested at 2026-11-12 17:08:00 NZDT. Git and Tailscale were both absent;
neither setup script was manually run after deployment.

Boot ID: `39acd76b-cddc-4eb3-af45-b2f13f7b8882`.

Both modules failed their first four network attempts, retried automatically,
and succeeded on attempt five. Git 2.44.4 was installed, Node-RED was restarted
through `/service/node-red-venus`, and Tailscale 1.104.6 was downloaded and started
using its existing persistent state. Tailscale setup completed at 17:12:10 NZDT.
Node-RED loaded `node-red-project-camper` and started its flows at 17:12:20 NZDT.

## Test 2: normal reboot with final scripts

Reboot requested at 2026-11-12 17:23:14 NZDT.

Boot ID: `e1d4aa59-bd30-439d-85ef-ed6172616804`.

- Git/Projects setup completed on attempt one without an unnecessary restart.
- Node-RED loaded the camper project and started flows at 17:24:34 NZDT; the
  BlueZ D-Bus BLE adapter initialized.
- Tailscale's early init.d job timed out twice while networking was unavailable.
  The concurrent rc.local job was correctly skipped by the lock. Attempt three
  completed at 17:25:26 NZDT, with Tailscale online and all service routes present.
- Both setup locks were released after completion. One tailscaled and one
  Node-RED process were running.
- Victron HTTPS responded with its expected HTTP 302 redirect; Node-RED and
  the dashboard returned HTTP 200, both locally and through their configured
  Tailscale service hostnames (requests made from the camper).
- The InfluxDB hostname resolved and its `/health` endpoint returned HTTP 200.
  Early startup DNS errors stopped after connectivity returned.
- SHA-256 checks confirmed the project flow, credential, and package files were
  unchanged. Deployed script checksums matched the local final scripts.

The Mac changed Wi-Fi networks during both reboots, delaying observation; no
manual setup was used to obtain either successful result. A transient Tailscale
host-approval notice during startup did not prevent the later endpoint checks.
An existing solar-charger instance 273 lookup warning appeared during the first
recovery; the flow was not modified. These checks establish startup and service
availability, not the operation of every sensor or actuator.

## Local checks and cleanup

18 Node-RED setup tests and 15 Tailscale tests passed, covering retry delays,
error propagation, duplicate setup, lock lifetime, restart persistence, settings
preservation and service routes. Shell syntax and whitespace checks also passed.

Original scripts and reboot logs were preserved on the device under
`/data/startup-repair-20261112` and in a private local diagnostic archive. The
forgotten-passphrase public key was removed from the device at the user's
request. The temporary repair key was then removed from the device and deleted
from the Mac after verification. No authorized SSH keys remained on the device;
the device's password login configuration was not changed.
