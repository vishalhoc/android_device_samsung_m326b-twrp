#!/bin/bash
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT=/usr/local/go117
export GOPATH=/tmp/gopath
export PATH=/usr/local/go117/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export OUT_DIR=/root/twrp-out
export SKIP_BLUEPRINT_TESTS=1
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true

cd /mnt/e/twrp-build
source build/envsetup.sh
lunch twrp_a32x-eng > /dev/null

echo "--- VERIFYING ARCH VARIABLES ---"
echo "TARGET_ARCH: $(get_build_var TARGET_ARCH)"
echo "TARGET_2ND_ARCH: $(get_build_var TARGET_2ND_ARCH)"
echo "TARGET_SUPPORTS_32_BIT_APPS: $(get_build_var TARGET_SUPPORTS_32_BIT_APPS)"
