# PEB-WLBT-05 WiFi/BLE Expansion Board

WiFi (SDIO) and BLE (UART) support for the phyBOARD-Pollux i.MX8MP.

The PEB-WLBT-05 ships with two module variants. The device tree, kernel
drivers, BlueZ stack, and boot flow are identical for both. Only the
firmware blobs and one Buildroot config line differ.

## Module Variants

| | Sterling-LWB5 | Sterling-LWB5+ |
|---|---|---|
| Chipset | CYW43455 (BCM43455) | CYW4373 |
| WiFi | 802.11ac | 802.11ac |
| Bluetooth | 4.2 | 5.0 (2M PHY, LE Coded PHY) |
| PEB-WLBT-05 models | -25C, -25E | check order |
| WiFi firmware source | linux-firmware (`CYW43XXX`) | linux-firmware (`CYW43XX`) |
| BT firmware source | Debian bluez-firmware | Ezurio release packages |
| BT firmware file | `BCM4345C0.hcd` | `BCM4373A0.hcd` |

## Switching Between Modules

### Step 1: Select firmware package in defconfig

Edit `system_phyboard-pollux-imx8mp/defconfig` and uncomment the matching line:

```
# Sterling-LWB5 (CYW43455):
BR2_PACKAGE_LINUX_FIRMWARE_CYPRESS_CYW43XXX=y
#BR2_PACKAGE_LINUX_FIRMWARE_CYPRESS_CYW43XX=y

# Sterling-LWB5+ (CYW4373) — swap comments:
#BR2_PACKAGE_LINUX_FIRMWARE_CYPRESS_CYW43XXX=y
BR2_PACKAGE_LINUX_FIRMWARE_CYPRESS_CYW43XX=y
```

### Step 2: Copy firmware overlay

The BT firmware (HCD file) and optional NVRAM are in module-specific overlay
directories. Copy the contents of the matching directory into `rootfs_overlay/`:

**For LWB5:**
```bash
cp -r rootfs_firmware_overlay_lwb5/lib rootfs_overlay/
```

This places `BCM4345C0.hcd` at `rootfs_overlay/lib/firmware/brcm/BCM4345C0.hcd`.

**For LWB5+:**
```bash
cp -r rootfs_firmware_overlay_lwb5plus/lib rootfs_overlay/
```

This places:
- `BCM4373A0.hcd` at `rootfs_overlay/lib/firmware/brcm/BCM4373A0.hcd`
- `brcmfmac4373-sdio.txt` at `rootfs_overlay/lib/firmware/brcm/brcmfmac4373-sdio.txt`

### Step 3: Rebuild

Clean rebuild recommended when switching modules (firmware package change):
```bash
# rebuild SDK then firmware
```

## Firmware Sources

### LWB5 (CYW43455)

- **WiFi:** `cyfmac43455-sdio.bin` + `.clm_blob` from Buildroot `linux-firmware`
- **BT:** `BCM4345C0.hcd` from Debian bluez-firmware
  - Source: https://github.com/RPi-Distro/bluez-firmware (bookworm branch)
  - License: Cypress Wireless Connectivity Devices EULA
  - Same CYW43455 silicon as Raspberry Pi 3B+/4

### LWB5+ (CYW4373)

- **WiFi:** `cyfmac4373-sdio.bin` + `.clm_blob` from Buildroot `linux-firmware`
- **BT:** `BCM4373A0.hcd` from Ezurio release packages
  - Source: https://github.com/Ezurio/Connectivity_Stack_Release_Packages/releases
  - Tarball: `summit-lwb5plus-sdio-sa-firmware-13.98.0.12.tar.bz2`
  - License: Cypress + Ezurio (use with Cypress/Ezurio ICs)
- **NVRAM:** `brcmfmac4373-sdio.txt` from same Ezurio tarball
  - Tuned for Sterling-LWB5+ single-antenna configuration

## Verification

After flashing, run on the board:

```bash
# WiFi: check firmware loaded and interface present
dmesg | grep brcmfmac
ip link show wlan0

# BLE: check firmware loaded and HCI interface works
dmesg | grep -i "btbcm\|hci\|BCM43"
hciconfig hci0 up
hcitool lescan

# WiFi connection test
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
udhcpc -i wlan0
```

## Architecture

```
Elixir App (rustler_btleplug)
    |
    | D-Bus
    v
bluetoothd (BlueZ)
    |
    | HCI socket
    v
Kernel: hci_uart / btbcm
    |
    | UART3 (ttymxc2)
    v
Sterling-LWB5/LWB5+ BT radio


Elixir App (wpa_supplicant via System.cmd or VintageNet)
    |
    v
wpa_supplicant
    |
    v
Kernel: brcmfmac (SDIO)
    |
    | USDHC1
    v
Sterling-LWB5/LWB5+ WiFi radio
```

## Files Modified/Added

| File | Purpose |
|------|---------|
| `linux/imx8mp-phyboard-pollux-rdk-wlbt05.dts` | Custom DTS with WLBT-05 nodes |
| `defconfig` | Custom DTS path, WiFi/BLE packages |
| `crucible.sh` | Updated DTB filename for FIT image |
| `rootfs_overlay/sbin/early-init.sh` | Starts dbus-daemon + bluetoothd |
| `rootfs_firmware_overlay_lwb5/` | BT firmware for Sterling-LWB5 |
| `rootfs_firmware_overlay_lwb5plus/` | BT firmware + NVRAM for Sterling-LWB5+ |
| `PEB-WLBT-05.md` | This documentation |
