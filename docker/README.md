# Building the malea iMX8MP firmware locally with Docker

This is the local-dev mirror of `.github/workflows/build-firmware.yml`. It uses
the Docker builder image (`docker/Dockerfile`) instead of Vagrant, so it runs
natively on Apple Silicon.

## Prerequisites

- Docker Desktop (with enough disk: ~50 GB for SDK + buildroot + project state)
- `fwup` on the host (`brew install fwup`)
- Two repos checked out side by side:
  - `grisp_alloy/` (this repo)
  - `malea-imx-firmware/`
- A populated `grisp-alloy-sdk` Docker volume (the SDK was rebuilt with
  `./build-sdk.sh -D phyboard-pollux-imx8mp`, or extracted from the
  `grisp_alloy_sdk_phyboard.tar.gz` release into the volume)
- The boot artefacts in `/tmp/parity-output/`:
  - `flash.bin` — U-Boot SPL+proper bundle
  - `fitImage` — kernel + DTB
  - `uboot-env.bin` — initial U-Boot environment
  - `fwup_fixed.conf` — fwup recipe with phyBOARD-correct labels

## The three steps

All commands run from `grisp_alloy/`.

### 1. Build the Elixir release into a project artefact

```sh
MALEA_ROOT=/path/to/malea-imx-firmware \
./build-project.sh -D -p dev phyboard-pollux-imx8mp \
  /path/to/malea-imx-firmware/targets/alloy_imx8mp
```

Output: `artefacts/malea_alloy_imx8mp-<version>-phyboard-pollux-imx8mp-dev.tgz`

`-D` runs the build inside the Docker builder image. `MALEA_ROOT` is
bind-mounted into the container so Mix `path:` deps under `apps/` resolve.

The Docker block strips any `*/priv/native/*.so` / `*.dylib` it finds under
`MALEA_ROOT` before invoking the container. These are host-arch NIFs left over
from local macOS dev builds and would otherwise get bundled into the release
and rejected by `scrub-otp-release.sh`. They're gitignored, so they regenerate
the next time you do native macOS development.

### 2. Assemble the rootfs squashfs

```sh
MALEA_ROOT=/path/to/malea-imx-firmware \
./build-firmware.sh -D \
  -o system_phyboard-pollux-imx8mp/rootfs_firmware_overlay \
  --dtso-dir system_phyboard-pollux-imx8mp/dts \
  --dtso-dir $MALEA_ROOT/targets/alloy_imx8mp/dts/variants/<variant> \
  phyboard-pollux-imx8mp \
  artefacts/malea_alloy_imx8mp-<version>-phyboard-pollux-imx8mp-dev.tgz
```

The first `--dtso-dir` pulls in board-level overlays that ship with
grisp_alloy (currently the UART3 BT enable for the PEB-WLBT-05). The
second points at project-side per-variant overlays under MALEA_ROOT.

The `-o` overlay carries the udhcpc network script and is mandatory for this
target.

`--dtso-dir <DIR>` points at a directory of `.dtso` files; every `*.dtso`
inside is compiled and merged into the kernel DTB in lexical order. Use
`--dtso <FILE>` (repeatable) instead if you want to point at individual
overlays. Both flags can be combined; `--dtso-dir` entries apply first,
then `--dtso` files in the order given.

The merged DTB lands in the FIT image — overlays are baked at build time,
not applied at runtime, so U-Boot does not need to know about them.

#### DT overlay headers and the `-@` requirement

The `.dtso` files reference kernel headers (`<dt-bindings/...>`,
`"imx8mp-pinfunc.h"`). The SDK ships these under `${SDK}/dt-includes/` and
`build-firmware.sh` resolves them automatically. The base DTB must be
compiled with `dtc -@` so overlay phandle references like `&uart3` resolve;
that is enabled via `BR2_LINUX_KERNEL_DTB_OVERLAY_SUPPORT=y` in
`system_common/defconfig`. If you upgrade or rebuild the SDK from older
sources, make sure both pieces are present.

#### Variant directory layout (recommended)

For projects that target multiple carrier boards, split overlays across
two locations:

- **grisp_alloy `system_phyboard-pollux-imx8mp/dts/`** — overlays that
  describe the reference board itself (Phytec dev kit + accessories).
  Reusable across consumer projects. Pass with
  `--dtso-dir system_phyboard-pollux-imx8mp/dts`.
- **`<project_root>/dts/variants/<board>/`** — overlays for project-
  specific custom hardware (e.g. a customer PCB with a different pinout).
  Pass with
  `--dtso-dir $MALEA_ROOT/targets/alloy_imx8mp/dts/variants/<board>`.

```
grisp_alloy/system_phyboard-pollux-imx8mp/dts/    # board hardware
<project_root>/dts/
├── common/                                       # shared across variants
└── variants/
    └── <custom-pcb>/
        └── *.dtso
```

Build by stacking both `--dtso-dir` flags (`grisp_alloy` first so its
overlays apply before any project-side ones that depend on them):

```sh
./build-firmware.sh -D \
  --dtso-dir system_phyboard-pollux-imx8mp/dts \
  --dtso-dir $MALEA_ROOT/targets/alloy_imx8mp/dts/variants/malea-pcb-rev-a \
  ...
```

Output: `combined.squashfs` lands inside the `grisp-alloy-build` Docker volume
(at `_build/firmware/firmwares/malea_alloy_imx8mp/combined.squashfs`). It is
**not** on the host filesystem because `_build/` is a named volume, not a bind
mount, to keep buildroot IO off macOS bind mounts.

Extract it to the host:

```sh
docker run --rm \
  -v grisp-alloy-build:/build:ro \
  -v "$PWD/artefacts:/out" \
  alpine cp \
    /build/firmware/firmwares/malea_alloy_imx8mp/combined.squashfs \
    /out/combined.squashfs
```

### 3. Package the .fw with fwup (on the host)

```sh
BOOT=/tmp/parity-output
SQUASHFS=$PWD/artefacts/combined.squashfs

GRISP_FW_PRODUCT="phyBOARD-Pollux i.MX8M Plus Firmware" \
GRISP_FW_PLATFORM="phyboard-pollux-imx8mp" \
GRISP_FW_ARCHITECTURE="aarch64-unknown-linux-gnu" \
GRISP_FW_AUTHOR="HomeBrace GmbH" \
GRISP_FW_VERSION="0.2.0/0.3.0/<your-version>" \
GRISP_FW_VCS_IDENTIFIER="$(git -C /path/to/malea-imx-firmware rev-parse --short HEAD)" \
GRISP_SYSTEM="$BOOT" \
UBOOT="$BOOT/flash.bin" \
ROOTFS="$SQUASHFS" \
FITIMAGE="$BOOT/fitImage" \
PRIMARY_ENV_BIN="$BOOT/uboot-env.bin" \
SECONDARY_ENV_BIN="$BOOT/uboot-env.bin" \
fwup -c -f "$BOOT/fwup_fixed.conf" -o malea-imx8mp-<version>-dev.fw
```

Output: `malea-imx8mp-<version>-dev.fw` in `grisp_alloy/`.

## Flashing

```sh
fwup -a -d /dev/rdiskN -t complete -i malea-imx8mp-<version>-dev.fw
```

Use `diskutil list` to find the SD card device on macOS. `/dev/rdiskN` (raw,
not buffered) is much faster than `/dev/diskN`.

## Volumes used

| Volume | Purpose |
|---|---|
| `grisp-alloy-sdk` | Extracted SDK (`/opt/grisp_alloy_sdk/...`) |
| `grisp-alloy-cache` | Buildroot download cache |
| `grisp-alloy-build` | `_build/` — buildroot tree, project tarball staging, firmware staging |

These persist across runs. To wipe and rebuild from scratch:

```sh
docker volume rm grisp-alloy-sdk grisp-alloy-cache grisp-alloy-build
```

## Rebuilding the builder image

The image (`grisp-alloy-builder:latest`) is built automatically on first `-D`
invocation. To force a rebuild:

```sh
./docker/build-image.sh --no-cache
```

Or pass `-P` together with `-D` to any build script.
