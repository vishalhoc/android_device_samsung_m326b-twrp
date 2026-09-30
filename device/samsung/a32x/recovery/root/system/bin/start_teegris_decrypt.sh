#!/system/bin/sh
# Universal Dual-ROM Startup for Samsung Galaxy M32 5G (SM-M326B)
# Supports BOTH Samsung Stock One UI (TEEGRIS FBE decryption) AND LineageOS/AOSP
export PATH=/system/bin:/vendor/bin:$PATH

echo "[TEEGRIS] Initializing security & crypto properties..."
/system/bin/init_fscrypt_keyring 2>/dev/null || true
/system/bin/resetprop ro.crypto.state encrypted
/system/bin/resetprop ro.crypto.type file
/system/bin/resetprop ro.crypto.metadata.enabled true
/system/bin/resetprop ro.hardware.keystore_desede true
/system/bin/resetprop ro.Build.BOOTLOADER M326BDDSCCYD1
/system/bin/resetprop ro.boot.bootloader M326BDDSCCYD1
/system/bin/resetprop ro.build.version.release 13
/system/bin/resetprop ro.build.version.security_patch 2025-04-01
/system/bin/resetprop ro.vendor.build.security_patch 2025-04-01
/system/bin/resetprop ro.bootimage.build.security_patch 2025-04-01

# Probe for /vendor partition (try up to 8 times ~2.4 seconds)
mkdir -p /vendor
attempts=0
has_samsung_teegris=0

while [ $attempts -lt 8 ]; do
    attempts=$((attempts + 1))
    dm_vendor=$(for d in /sys/block/dm-*; do [ "$(cat $d/dm/name 2>/dev/null)" = "vendor" ] && echo "/dev/block/$(basename $d)"; done)
    if [ -n "$dm_vendor" ]; then
        mount -t ext4 -o ro "$dm_vendor" /vendor 2>/dev/null || true
    fi
    if ! mountpoint -q /vendor; then
        mount -t ext4 -o ro /dev/block/mapper/vendor /vendor 2>/dev/null || \
        mount -t ext4 -o ro /dev/block/dm-3 /vendor 2>/dev/null || \
        mount -t ext4 -o ro /dev/block/dm-2 /vendor 2>/dev/null || true
    fi
    if mountpoint -q /vendor; then
        if [ -f /vendor/bin/tzdaemon ]; then
            has_samsung_teegris=1
            break
        else
            echo "[TEEGRIS] LineageOS/AOSP vendor detected (no tzdaemon). Unmounting vendor."
            umount -l /vendor 2>/dev/null || true
            break
        fi
    fi
    sleep 0.3
done

if [ $has_samsung_teegris -eq 1 ]; then
    echo "[TEEGRIS] Samsung One UI detected! Starting TEEGRIS stack..."

    if [ ! -f /vendor/manifest.xml ]; then
        mount -o remount,rw /vendor 2>/dev/null || true
        ln -sf /vendor/etc/vintf/manifest.xml /vendor/manifest.xml 2>/dev/null || true
        mount -o remount,ro /vendor 2>/dev/null || true
    fi

    # Create RAM-only /mnt/vendor/efs snapshot from READ-ONLY physical EFS
    umount -l /efs 2>/dev/null || true
    mkdir -p /mnt/vendor/efs /efs /tmp/efs_ro_src
    if ! mountpoint -q /mnt/vendor/efs; then
        mount -t tmpfs -o size=32M,mode=0771,uid=1000,gid=1001 tmpfs /mnt/vendor/efs
    fi
    if mount -t ext4 -o ro,noload /dev/block/by-name/efs /tmp/efs_ro_src 2>/dev/null; then
        cp -af /tmp/efs_ro_src/. /mnt/vendor/efs/ 2>/dev/null || true
        umount /tmp/efs_ro_src 2>/dev/null || umount -l /tmp/efs_ro_src 2>/dev/null
    fi
    chmod -R 0777 /mnt/vendor/efs/tee 2>/dev/null || true
    mount -o bind /mnt/vendor/efs /efs 2>/dev/null || true

    # Start tzdaemon and wait for Ready
    if ! pidof tzdaemon >/dev/null 2>&1; then
        LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 /vendor/bin/tzdaemon >/dev/null 2>&1 &
    fi
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(getprop vendor.tzdaemon)" = "Ready" ] && break
        sleep 0.2
    done

    # Start tzts_daemon
    if ! pidof tzts_daemon >/dev/null 2>&1; then
        LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 /vendor/bin/tzts_daemon >/dev/null 2>&1 &
    fi
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(getprop vendor.tzts_daemon)" = "Ready" ] && break
        sleep 0.2
    done

    # Start Keymaster 4.0 and Gatekeeper 1.0 HALs
    killall -9 android.hardware.keymaster@4.0-service 2>/dev/null || true
    killall -9 android.hardware.gatekeeper@1.0-service 2>/dev/null || true
    sleep 0.2
    LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib64/hw:/system/lib64 /vendor/bin/hw/android.hardware.keymaster@4.0-service >/dev/null 2>&1 &
    LD_LIBRARY_PATH=/vendor/lib64:/vendor/lib64/hw:/system/lib64 /vendor/bin/hw/android.hardware.gatekeeper@1.0-service >/dev/null 2>&1 &

    # Start Keystore2
    mkdir -p /tmp/misc/keystore
    killall -9 keystore2 2>/dev/null || true
    /system/bin/keystore2 /tmp/misc/keystore >/dev/null 2>&1 &
else
    echo "[TEEGRIS] Operating in LineageOS / Standard AOSP mode."
fi

# Set vendor.teegris.ready so TWRP knows startup completed
setprop vendor.teegris.ready 1

# Ensure touch firmware is updated
echo fw_update > /sys/class/sec/tsp/cmd 2>/dev/null

# Keep process group alive
while true; do
    sleep 3600
done
