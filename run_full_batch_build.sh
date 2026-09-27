#!/bin/bash
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

echo "=== Starting Full Batch Build with Ninja -j2 -k 0 ==="
/mnt/e/twrp-build/prebuilts/build-tools/linux-x86/bin/ninja -f /root/twrp-out/combined-twrp_a32x.ninja -j2 -k 0 recoveryimage 2>&1 | tee /mnt/e/twrp-full-build.log
NINJA_EXIT=${PIPESTATUS[0]}
echo "=== Ninja exited with status $NINJA_EXIT ==="

grep -nE 'FAILED:|error:' /mnt/e/twrp-full-build.log > /mnt/e/twrp-errors.txt 2>&1 || true

echo "=== Top Diagnostics ==="
grep -oE '\[-Werror-[^]]+\]' /mnt/e/twrp-full-build.log | sort | uniq -c | sort -nr || true

exit $NINJA_EXIT
