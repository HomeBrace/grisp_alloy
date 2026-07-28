# brcmfmac firmware for the Ezurio Sterling LWB5+ (CYW4373)

Describes the blobs in
`rootfs_firmware_overlay/lib/firmware/brcm/`. This file is deliberately kept
*outside* the overlay tree so it is not copied onto the device rootfs.

These blobs land at `/lib/firmware/brcm/` on the read-only rootfs and are loaded
by the **kernel** `brcmfmac` driver when usdhc1 enumerates the Wi-Fi SDIO card.

They must live here, not in the Elixir release: the OTP release's `priv/` is
invisible to the kernel firmware loader. (Contrast the Bluetooth patch RAM
`lwb5plus.hcd`, which *is* in the release — BlueHeron uploads it from userspace.
Same module, same vendor bundle, two different loaders.)

`build-firmware.sh` accepts only one `-o/--overlay` directory, and this tree is
already it, so no SDK rebuild is needed to ship or refresh these files:

```sh
./build-firmware.sh -D -o system_phyboard-pollux-imx8mp/rootfs_firmware_overlay ...
```

## Files

| File | Original name in the tarball | Notes |
| --- | --- | --- |
| `brcmfmac4373-sdio.bin` | `brcmfmac4373-sdio-prod_v13.10.246.343.bin` | FullMAC firmware |
| `brcmfmac4373-sdio.txt` | `brcmfmac4373-sa.txt` | NVRAM — **single-antenna** variant |
| `brcmfmac4373-sdio.clm_blob` | `brcmfmac4373-clm-sa.clm_blob` | Regulatory/CLM data, single-antenna |

The tarball ships those canonical names as symlinks to the versioned files; we
dereference them and store real files, matching how `lwb5plus.hcd` is handled on
the Elixir side. brcmfmac probes
`brcmfmac4373-sdio.<board-compatible>.{bin,txt}` first and falls back to these
plain names, which is what we rely on.

**Single-antenna is the correct variant for the Malea PCB**: U1301 exposes one
`RF_OUT` (pin 50) on schematic P00077 sheet 13, and it is the same `sdio-sa`
bundle the shipped Bluetooth `lwb5plus.hcd` came from. Do not mix in the
`sdio-div` (diversity) or `-m2` NVRAM — wrong antenna calibration degrades range
silently rather than failing loudly.

## MAC address caveat

`brcmfmac4373-sdio.txt` contains `macaddr=00:90:4c:c5:12:38`, the vendor's
default. Because this NVRAM is baked into a read-only rootfs shared by every
unit, **all devices come up with the same Wi-Fi MAC**. That is fine for a single
board on a bench, and breaks as soon as two chairs join the same network. Fix it
at runtime (derive a stable MAC from the device serial and `ip link set wlan0
address …`) rather than by forking this file per device.

## Source

[Ezurio/SonaIF-Release-Packages — `LRD-REL-12.103.0.5`](https://github.com/Ezurio/SonaIF-Release-Packages/releases/tag/LRD-REL-12.103.0.5)

### Refresh

```bash
gh release download LRD-REL-12.103.0.5 \
  --repo Ezurio/SonaIF-Release-Packages \
  --pattern 'summit-lwb5plus-sdio-sa-firmware-*.tar.bz2'

tar -xjf summit-lwb5plus-sdio-sa-firmware-*.tar.bz2
cp -L lib/firmware/brcm/brcmfmac4373-sdio.bin      brcmfmac4373-sdio.bin
cp -L lib/firmware/brcm/brcmfmac4373-sdio.txt      brcmfmac4373-sdio.txt
cp -L lib/firmware/brcm/brcmfmac4373-sdio.clm_blob brcmfmac4373-sdio.clm_blob
cp LICENSE.cypress LICENSE.ezurio .
```

Keep the Bluetooth `.hcd` in
`malea-imx-firmware/targets/alloy_imx8mp/priv/firmware/brcm/` on the **same**
release tag — the BT patch RAM and the WLAN firmware are validated together.

## Licensing

`LICENSE.cypress` and `LICENSE.ezurio` are the redistribution terms shipped
inside the source tarball — do not remove.
