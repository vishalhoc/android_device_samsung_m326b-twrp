#!/bin/bash
# Go 1.17.13 setup + TWRP build
# TWRP 12.1 / android-12.1.0_r4 requires Go 1.17.x (not 1.18+)
# Run as: wsl -d Ubuntu -u root bash this_script.sh

set -e
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
GO117_DIR="/usr/local/go117"
GO117_TGZ="/tmp/go117.tar.gz"
GO117_URL="https://go.dev/dl/go1.17.13.linux-amd64.tar.gz"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

log "=== Go 1.17.13 Setup + TWRP Build ==="
log "User: $(id)"

# ── Install Go 1.17.13 ────────────────────────────────────────────────────
if [ -f "$GO117_DIR/bin/go" ]; then
    log "Go 1.17.13 already installed: $($GO117_DIR/bin/go version)"
else
    # Check if user already downloaded to E: drive
    if [ -f "/mnt/e/go117.tar.gz" ]; then
        log "Using user-downloaded go117.tar.gz from E: drive..."
        GO117_TGZ="/mnt/e/go117.tar.gz"
    else
        log "Downloading Go 1.17.13 from go.dev (~130 MB)..."
        wget -q --show-progress "$GO117_URL" -O "$GO117_TGZ" 2>&1 | tail -3
    fi

    log "Extracting Go 1.17.13 to $GO117_DIR..."
    rm -rf "$GO117_DIR"
    mkdir -p "$GO117_DIR"
    tar -xzf "$GO117_TGZ" -C /tmp/
    mv /tmp/go/. "$GO117_DIR/"
    log "Go 1.17.13 installed: $($GO117_DIR/bin/go version)"
fi

# ── Set up prebuilts/go/linux-x86 wrapper ────────────────────────────────
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"
log "Creating Go 1.17 wrapper in prebuilts..."
rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT/bin"

python3 -c "
go_real = '$GO117_DIR/bin/go'
goroot  = '$GO117_DIR'
wrapper = '#!/bin/bash\nexport GOROOT=\"' + goroot + '\"\nexec \"' + go_real + '\" \"\$@\"\n'
with open('$GO_PREBUILT/bin/go', 'w') as f:
    f.write(wrapper)
import os; os.chmod('$GO_PREBUILT/bin/go', 0o755)
print('Wrapper written')
"

WRAPPER_VER=$("$GO_PREBUILT/bin/go" version)
log "Wrapper: $WRAPPER_VER"
echo "$WRAPPER_VER" | grep -q "go1.17" || { log "ERROR: wrong Go version"; exit 1; }

# ── Python symlink ────────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# ── Apply M326B device tree ───────────────────────────────────────────────
log "Applying device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK"

# ── BUILD ─────────────────────────────────────────────────────────────────
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GO117_DIR"
export GOPATH="/tmp/gopath"
export PATH="$GO_PREBUILT/bin:$PATH"

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup sourced OK"

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "mka recoveryimage with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage)"

# ── Result ────────────────────────────────────────────────────────────────
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
    log "BUILD FAILED"
    tail -40 "$LOG"
    exit 1
fi
