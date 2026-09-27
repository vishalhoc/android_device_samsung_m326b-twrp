#!/bin/bash
# Go 1.17.13 extract fix + full TWRP build
set -e
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
GO117_DIR="/usr/local/go117"
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Go 1.17 Extract Fix + Final Build ==="
log "User: $(id)"

# ── 1. Extract Go 1.17.13 to correct location ─────────────────────────────
if [ -f "$GO117_DIR/bin/go" ]; then
    log "Go 1.17 already installed: $($GO117_DIR/bin/go version)"
else
    # Find the tarball — check both locations
    TGZ=""
    [ -f "/mnt/e/go117.tar.gz" ] && TGZ="/mnt/e/go117.tar.gz"
    [ -z "$TGZ" ] && [ -f "/tmp/go117.tar.gz" ] && TGZ="/tmp/go117.tar.gz"

    if [ -z "$TGZ" ]; then
        log "ERROR: go117.tar.gz not found. Downloading..."
        wget -q https://go.dev/dl/go1.17.13.linux-amd64.tar.gz -O /tmp/go117.tar.gz
        TGZ="/tmp/go117.tar.gz"
    fi

    log "Extracting $TGZ to $GO117_DIR ..."
    rm -rf "$GO117_DIR"
    # Extract directly with --transform to rename go/ -> go117/
    tar -xzf "$TGZ" -C /usr/local/ --transform='s|^go/|go117/|' --show-transformed-names 2>&1 | tail -3
    log "Go 1.17: $($GO117_DIR/bin/go version)"
fi

# Verify stdlib is pre-compiled (should be in pkg/linux_amd64/)
STDLIB_COUNT=$(ls "$GO117_DIR/pkg/linux_amd64/" 2>/dev/null | wc -l)
log "Stdlib precompiled packages: $STDLIB_COUNT"

# ── 2. Create Go 1.17 prebuilt wrapper ────────────────────────────────────
log "Setting up prebuilts/go/linux-x86 wrapper..."
rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT/bin"

python3 -c "
goroot  = '$GO117_DIR'
go_bin  = '$GO117_DIR/bin/go'
wp      = '$GO_PREBUILT/bin/go'
txt = '#!/bin/bash\nexport GOROOT=\"' + goroot + '\"\nexec \"' + go_bin + '\" \"\$@\"\n'
open(wp, 'w').write(txt)
import os; os.chmod(wp, 0o755)
print('Go 1.17 wrapper OK')
"
log "Wrapper: $($GO_PREBUILT/bin/go version)"

# ── 3. Test compile directly (verify stdlib visible) ──────────────────────
log "Testing compile with microfactory.go..."
export GOROOT="$GO117_DIR"
TESTOUT=$("$GO117_DIR/pkg/tool/linux_amd64/compile" -N -l \
    -o /tmp/test_mf.a \
    -p "github.com/google/blueprint/microfactory" \
    -complete -pack -c 8 \
    -trimpath "$BUILD_DIR" \
    "$BUILD_DIR/build/blueprint/microfactory/microfactory.go" 2>&1 || true)
if [ -f "/tmp/test_mf.a" ]; then
    log "Compile test: PASSED — Go 1.17 stdlib found"
    rm /tmp/test_mf.a
else
    log "Compile test output: $TESTOUT"
    log "WARNING: compile test failed, proceeding anyway..."
fi

# ── 4. Python symlink ─────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# ── 5. Apply M326B device tree ────────────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK"

# ── 6. BUILD ─────────────────────────────────────────────────────────────
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

log "lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "mka recoveryimage ($(nproc) cores)..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage)"

# ── 7. Result ─────────────────────────────────────────────────────────────
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
    log "BUILD FAILED — last errors:"
    tail -30 "$LOG"
    exit 1
fi
