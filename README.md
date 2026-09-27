# TWRP Port — Samsung Galaxy M32 5G (SM-M326B)

> **All values in this device tree are verified from a live SM-M326B device via ADB root investigation.**
> Do NOT blindly replace with A326B values.

---

## Device Specifications

| Property | Value |
|----------|-------|
| Model | SM-M326B (Galaxy M32 5G) |
| Codename | `a32x` (same as A326B — confirmed from `ro.product.device`) |
| Platform | MT6853 (MediaTek Dimensity 720) |
| Kernel | Linux 4.14.186-27095505 |
| Android | 13 (One UI 5.1) |
| Firmware | M326BDDSCCYD1 (INS/India, Binary C) |
| Boot state | OEM Unlocked (orange) |
| Encryption | FBE v2 (aes-256-xts:aes-256-cts:v2), f2fs userdata |

---

## Critical: M326B vs A326B Differences

| | A326B | **M326B (this tree)** |
|--|-------|----------------------|
| Boot partition | 40 MiB | **32 MiB** (33,554,432) |
| Super partition | ~8.7 GiB | **~7.5 GiB** (7,864,320,000) |
| Kernel size | 18,008,668 bytes | **17,961,251 bytes** (gzip) |
| DTB size | 152,156 bytes | **152,298 bytes** |

**Recovery, dtbo, vbmeta partition sizes match between M326B and A326B.**

---

## Prebuilt Files (inside device/samsung/a32x/prebuilt/)

These were extracted from **SM-M326B stock firmware M326BDDSCCYD1**:

| File | Size | SHA256 | Source |
|------|------|--------|--------|
| `kernel` | 17,961,251 bytes | `8c804f4e...` | Extracted from stock boot.img |
| `dtb.img` | 152,298 bytes | `456a1ccb...` | Extracted from stock boot.img (v2 header) |
| `dtbo.img` | 8,388,608 bytes | TBD | `dd if=/dev/block/by-name/dtbo` |

> **dtbo.img must be dumped from your M326B** — connect via ADB and run:
> ```
> adb shell "su -c 'dd if=/dev/block/by-name/dtbo of=/sdcard/M326B_dtbo.img bs=4096'"
> adb pull /sdcard/M326B_dtbo.img device/samsung/a32x/prebuilt/dtbo.img
> ```

---

## vbmeta

### Pre-generated: M326B_vbmeta_twrp.img

SHA256: `9cce7c2d752df367292cc17b4e2d21834629360f40521cb1784233b87e3c0025`

```
Magic:                 AVB0
AVB version:           1.0
Algorithm:             NONE
Flags:                 0x00000003
  VERIFICATION_DISABLED: True
  HASHTREE_DISABLED:     True
Descriptors:           (none)
Size:                  65,536 bytes (matches M326B vbmeta partition exactly)
```

To regenerate: `python3 make_vbmeta_disabled.py`

### Background
The SM-M326B's stock vbmeta (when Magisk is installed) already has FLAGS=0x3
because Magisk patches it during installation. This pre-generated file produces
the same result for devices without Magisk, or for clean TWRP installs.

---

## Build Instructions

### Requirements
- Ubuntu 22.04 (or 18.04)
- 16 GB RAM, 60 GB free disk
- Python 3, git, curl

### Steps

```bash
# 1. Copy this entire folder to your Linux build machine
scp -r twrp_m326b/ user@buildmachine:~/

# 2. On Linux:
cd ~/twrp_m326b
chmod +x build_twrp_m326b.sh flash_m326b_twrp.sh

# 3. Build (first run downloads ~30 GB)
./build_twrp_m326b.sh

# Output: ~/twrp_m326b/M326B_recovery_twrp.img
#         ~/twrp_m326b/M326B_vbmeta_twrp.img
```

Or manually:
```bash
mkdir ~/twrp-build && cd ~/twrp-build
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --depth=1
mkdir -p .repo/local_manifests
cp ~/twrp_m326b/roomservice.xml .repo/local_manifests/
repo sync -c --no-clone-bundle --no-tags -j$(nproc)
cp -r ~/twrp_m326b/device/samsung/a32x ./device/samsung/a32x
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
lunch twrp_a32x-eng
mka recoveryimage
```

---

## Flash Instructions

### Prerequisites
1. SM-M326B with OEM unlocked bootloader (Settings → Developer Options → OEM Unlocking)
2. Heimdall: `sudo apt-get install heimdall-flash`
3. Backup stock partitions first (see below)

### Backup Stock (DO THIS FIRST)
```bash
adb shell "su -c 'dd if=/dev/block/by-name/boot     of=/sdcard/BACKUP_boot.img'"
adb shell "su -c 'dd if=/dev/block/by-name/recovery of=/sdcard/BACKUP_recovery.img'"
adb shell "su -c 'dd if=/dev/block/by-name/vbmeta   of=/sdcard/BACKUP_vbmeta.img'"
adb pull /sdcard/BACKUP_boot.img
adb pull /sdcard/BACKUP_recovery.img
adb pull /sdcard/BACKUP_vbmeta.img
```

### Enter Download Mode
Power off → Hold **Vol Down + Vol Up** → Connect USB → Press **Vol Up** to accept

### Flash
```bash
# Verify PIT (partition info table) first
heimdall print-pit | grep -i "recovery\|vbmeta"

# Flash TWRP + disabled-verification vbmeta
./flash_m326b_twrp.sh
# OR manually:
heimdall flash \
  --RECOVERY M326B_recovery_twrp.img \
  --VBMETA   M326B_vbmeta_twrp.img \
  --no-reboot
```

### Boot to TWRP (immediately after flash!)
```
# Do NOT let phone boot normally — Samsung recovery-from-boot will overwrite TWRP
adb reboot recovery
# OR: Hold Vol Up + Power → release Power at logo → keep Vol Up
```

### Restore Stock Recovery
```bash
./flash_m326b_twrp.sh --restore-stock
# OR:
heimdall flash --RECOVERY BACKUP_recovery.img --VBMETA BACKUP_vbmeta.img --no-reboot
```

---

## Partitions (Never Touch)

**DO NOT flash or overwrite these partitions — risk of permanent brick:**

`efs` `nvram` `nvdata` `nvcfg` `proinfo` `persistent` `keydata` `keyrefuge`
`sec_efs` `preloader_a` `preloader_b` `seccfg` `protect1` `protect2` `efuse`

---

## Based On

- Goldenkrew3000 A32x TWRP: https://github.com/goldenkrew3000/android_device_samsung_a32x/tree/twrp
- TWRP 12.1 manifest: https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp
- Device investigation: live SM-M326B (serial RZCR904AE4Z, firmware M326BDDSCCYD1)

---

## File Checksums

```
9cce7c2d752df367292cc17b4e2d21834629360f40521cb1784233b87e3c0025  M326B_vbmeta_twrp.img
8c804f4e598c0599a755c8c7e7446598ed27bca57ceebc329660f82a02c0450b  device/samsung/a32x/prebuilt/kernel
456a1ccb9c5480c3f2cd970c1ecfb5442ecbab14416e8e1d73debf57557a9a58  device/samsung/a32x/prebuilt/dtb.img
```
