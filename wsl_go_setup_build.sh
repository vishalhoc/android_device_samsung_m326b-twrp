#!/bin/bash
# Go wrapper quick setup + full build — Phase 7 fixed
# Run as: wsl -d Ubuntu -u root bash /mnt/e/.../wsl_go_setup_build.sh

set -e
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

log "=== Go Wrapper Setup + TWRP Build ==="
log "User: $(id)"

# Find system Go (installed by apt in phase 6)
GO_SYS=$(which go 2>/dev/null || echo "")
if [ -z "$GO_SYS" ]; then
    log "Installing golang-go..."
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
    apt-get install -y golang-go 2>&1 | tail -3
    GO_SYS=$(which go)
fi

GO_REAL=$(realpath "$GO_SYS")
GOROOT=$("$GO_SYS" env GOROOT)
log "Go: $GO_SYS -> $GO_REAL"
log "GOROOT: $GOROOT"

# Clean any broken prebuilt dir and recreate
log "Creating Go wrapper in prebuilts..."
rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT/bin"

# Write wrapper using a temp file approach to avoid shell escaping issues
WRAPPER="$GO_PREBUILT/bin/go"
GOROOT_ESC="$GOROOT"
GO_REAL_ESC="$GO_REAL"

python3 -c "
import os
wrapper = '''#!/bin/bash
export GOROOT=\"$GOROOT_ESC\"
exec \"$GO_REAL_ESC\" \"\$@\"
'''
with open('$WRAPPER', 'w') as f:
    f.write(wrapper)
os.chmod('$WRAPPER', 0o755)
print('Wrapper written OK')
"

# Test wrapper
log "Testing Go wrapper..."
WRAPPER_VER=$("$WRAPPER" version 2>&1)
log "Go wrapper: $WRAPPER_VER"
echo "$WRAPPER_VER" | grep -q "go version" || { log "FATAL: wrapper not working"; cat "$WRAPPER"; exit 1; }

# Python symlink
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# Apply M326B device tree
log "Applying device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK"

# BUILD
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GOROOT"
export PATH="$GO_PREBUILT/bin:$PATH"

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup sourced OK"

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "mka recoveryimage with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage)"

RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log "=============================="
    log "BUILD SUCCESS!"
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Output: E:\\M326B_recovery_twrp.img"
    log "=============================="
else
    log "BUILD FAILED — last 30 lines:"
    tail -30 "$LOG"
    exit 1
fi
