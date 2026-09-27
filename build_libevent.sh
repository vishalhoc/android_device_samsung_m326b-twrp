#!/bin/bash
set -e
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT=/usr/local/go117
export GOPATH=/tmp/gopath
export PATH=/usr/local/go117/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export OUT_DIR=/root/twrp-out
export TW_THEME=portrait_hdpi
export TARGET_SCREEN_WIDTH=1080
export TARGET_SCREEN_HEIGHT=2408
export TW_EXTRA_LANGUAGES=true
export TARGET_RECOVERY_PIXEL_FORMAT=RGBX_8888
export OUT=/root/twrp-out/target/product/a32x
export SKIP_BLUEPRINT_TESTS=1
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

cd /mnt/e/twrp-build
source build/envsetup.sh
lunch twrp_a32x-eng

rm -f /root/twrp-out/.ninja_fifo

echo "=== Building libevent -j2 ==="
mka libevent -j2
echo "=== libevent built successfully! ==="

echo "=== Building recoveryimage -j2 ==="
mka recoveryimage -j2
echo "=== recoveryimage built successfully! ==="

RECOVERY="/root/twrp-out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    ls -lh "$RECOVERY"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    echo "Copied to /mnt/e/M326B_recovery_twrp.img"
fi
