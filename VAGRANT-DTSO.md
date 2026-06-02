# Building the malea iMX8MP firmware with Vagrant (incl. device-tree overlays)

This is the Vagrant-VM path for `build-firmware.sh`. On non-Linux hosts
(macOS, etc.) the script switches to Vagrant automatically; on Linux you can
force it with `-V`. It is the alternative to the Docker flow documented in
`docker/README.md`, and — like Docker — it now applies `--dtso` / `--dtso-dir`
device-tree overlays (see `PLAN-DTSO.md` for the overlay architecture).

## Prerequisites

- [Vagrant](https://www.vagrantup.com/) with a provider:
  - **VMware Desktop** (`vagrant-vmware-desktop` plugin) — preferred on Apple
    Silicon / macOS, uses GHFS for the `artefacts/` share.
  - **VirtualBox** — uses NFS by default; set `VAGRANT_DISABLE_NFS=1` to fall
    back to VirtualBox shared folders.
- `rsync` and `ssh` on the host (used to push overlays / DTSOs into the VM).
- `fwup` on the host (`brew install fwup`) for inspecting/flashing the result.
- The SDK tarball present in `artefacts/`
  (`grisp_alloy_sdk-…-phyboard-pollux-imx8mp-…-linux-aarch64.tar.gz`). The
  `artefacts/` directory is a **live synced folder**, so the SDK is visible in
  the VM and the finished `.fw` lands straight back on the host.
- A project artefact in `artefacts/`, e.g.
  `malea_alloy_imx8mp-0.1.0-phyboard-pollux-imx8mp.tgz`
  (produced by `build-project.sh`).

## One-time / after-update provisioning

The VM receives the system definitions by file-copy provisioning (not a live
mount). `system_phyboard-pollux-imx8mp` is in that list (added so this target
builds in Vagrant). If you just pulled this change into an already-running VM,
re-provision once so the VM gets the target system:

```sh
./build-firmware.sh -V -P phyboard-pollux-imx8mp …   # -P re-provisions
# or, directly:
vagrant provision
```

`-P` triggers `vagrant provision`; without it, `vagrant up` only provisions on
first boot. Re-provision any time `system_*`, `scripts/`, or the build scripts
change on the host, since those are snapshots, not live mounts.

> **DTSO files are different:** `--dtso` / `--dtso-dir` paths are rsynced fresh
> into the VM on **every** build, so editing an overlay does **not** require
> re-provisioning — just rebuild.

## Build invocations

All commands run from `grisp_alloy/`. `-V` is optional on macOS (Vagrant is the
default there) but harmless to state explicitly.

### Phytec Pollux dev kit (UART3 BT overlay, in-repo)

```sh
./build-firmware.sh -V \
  -o system_phyboard-pollux-imx8mp/rootfs_firmware_overlay \
  --dtso-dir system_phyboard-pollux-imx8mp/dts \
  phyboard-pollux-imx8mp \
  artefacts/malea_alloy_imx8mp-0.1.0-phyboard-pollux-imx8mp.tgz
```

### Custom Malea PCB rev A (external variant dir)

```sh
export MALEA_ROOT=/path/to/malea-imx-firmware
./build-firmware.sh -V \
  -o system_phyboard-pollux-imx8mp/rootfs_firmware_overlay \
  --dtso-dir "$MALEA_ROOT/targets/alloy_imx8mp/dts/variants/malea-pcb-rev-a" \
  phyboard-pollux-imx8mp \
  artefacts/malea_alloy_imx8mp-0.1.0-phyboard-pollux-imx8mp.tgz
```

**Rule (same as Docker):** pick exactly one `--dtso-dir` source per board
target. Stacking the dev-kit dir with a project variant dir produces a
semantically broken merge — see "Stacking conflict" in `PLAN-DTSO.md`.

## How the DTSO flags reach the VM

The Vagrant block of `build-firmware.sh` mirrors the Docker bind-mount logic
using rsync + path rewriting:

| Host flag | Synced to in VM | Re-passed as |
|---|---|---|
| `--dtso-dir <DIR>` | `…/_build/firmware/dtso-dir/<NN>/` | `--dtso-dir …/dtso-dir/<NN>` |
| `--dtso <FILE>` | `…/_build/firmware/dtso/<NN>_<base>` | `--dtso …/dtso/<NN>_<base>` |

The `<NN>` numeric prefix preserves application order and prevents basename
collisions between directories. `--dtso-dir` entries apply before `--dtso`
entries, exactly as on a native build. Inside the VM the overlays are compiled
and merged into the SDK base DTB (`apply_dt_overlays`), and the merged DTB is
routed through the boot scheme via `BOOTSCHEME_DTB_PATH`.

## Output & verification

The firmware is written to `artefacts/<name>-<ver>-phyboard-pollux-imx8mp.fw`
on the host (live synced folder). Confirm the overlay was applied by checking
the FIT's FDT size in the build log — for the dev-kit overlay it should be
~68999 B (see `PLAN-DTSO.md` "Verification"). After flashing:

```sh
dmesg | grep ttymxc2                       # should mention rtscts
cat /proc/device-tree/.../serial@30880000/uart-has-rtscts  # exists
# BlueHeron should detect HCI on /dev/ttymxc2
```

## Notes

- By default the VM is halted on exit. Pass `-K` / `--keep-vagrant` to keep it
  running between builds (faster iteration).
- A security pack (`-S`) is copied into the VM and **deleted on exit**
  regardless of success/failure; this is unchanged.
- If you only need a quick native-on-Linux or Apple-Silicon build, the Docker
  flow (`-D`, see `docker/README.md`) is usually faster and needs no VM.
