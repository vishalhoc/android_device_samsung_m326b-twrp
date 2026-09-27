#!/bin/bash
# TWRP M326B Build Script — Clean version using real prebuilt toolchain
# 
# Requirements:
#   - prebuilts/clang/host/linux-x86/clang-r416183b1/ runtime libs installed
#   - prebuilts/go/linux-x86/ = Go 1.17.x
#   - OUT_DIR on Linux ext4 (case-sensitive)
#
set -e
set -o pipefail

LOG="/root/twrp-out/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
OUT_DIR="/root/twrp-out"
PRODUCT="a32x"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

mkdir -p "$(dirname "$LOG")"
[ -f "$LOG" ] && mv "$LOG" "${LOG}.prev"
echo "=== Build started $(date) ===" > "$LOG"

log "=== TWRP M326B Build ==="
log "User: $(id)"

# ── 1. Verify clang prebuilt bin and libs ────────────────────────────────
CLANG_BIN="$BUILD_DIR/prebuilts/clang/host/linux-x86/clang-r416183b1/bin/clang"
BUILTINS="$BUILD_DIR/prebuilts/clang/host/linux-x86/clang-r416183b1/lib64/clang/12.0.7/lib/linux/libclang_rt.builtins-aarch64-android.a"

if [ ! -f "$CLANG_BIN" ] && [ ! -L "$CLANG_BIN" ]; then
    log "ERROR: clang not found — run setup_clang_bin.sh"
    exit 1
fi
log "Clang: $(readlink -f "$CLANG_BIN" | xargs -I{} file {} | cut -d: -f2 | xargs)"

if [ -f "$BUILTINS" ]; then
    log "libclang_rt.builtins-aarch64-android.a: OK ($(du -h "$BUILTINS" | cut -f1))"
else
    log "ERROR: libclang_rt.builtins-aarch64-android.a missing — run fetch_real_clang.sh"
    exit 1
fi

# ── 2. Go prebuilt ────────────────────────────────────────────────────────
GO117="/usr/local/go117"
if [ ! -f "$GO117/bin/go" ]; then
    log "Installing Go 1.17.13..."
    wget -q https://go.dev/dl/go1.17.13.linux-amd64.tar.gz -O /tmp/go117.tar.gz
    tar -xzf /tmp/go117.tar.gz -C /usr/local/ --transform='s|^go/|go117/|'
fi
# Always use symlink to guarantee Go 1.17 (synced prebuilt may not have been restored)
rm -rf "$BUILD_DIR/prebuilts/go/linux-x86"
mkdir -p "$BUILD_DIR/prebuilts/go"
ln -sf "$GO117" "$BUILD_DIR/prebuilts/go/linux-x86"
log "Go: $($GO117/bin/go version)"

# ── 2b. Rust prebuilt ─────────────────────────────────────────────────────
if [ ! -d "$BUILD_DIR/prebuilts/rust" ] && [ -d "/root/prebuilts_rust" ]; then
    cp -r /root/prebuilts_rust "$BUILD_DIR/prebuilts/rust"
fi
[ -d "$BUILD_DIR/prebuilts/rust" ] && log "Rust: OK ($BUILD_DIR/prebuilts/rust)"

# ── 3. Patch microfactory.go ──────────────────────────────────────────────
MFGO="$BUILD_DIR/build/blueprint/microfactory/microfactory.go"
if grep -q 'nolocalimports' "$MFGO" 2>/dev/null; then
    sed -i 's/"-complete", "-pack", "-nolocalimports"/"-complete", "-pack"/' "$MFGO"
fi
log "microfactory.go: patched ✓"

# ── 4. Apply M326B device tree ────────────────────────────────────────────
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
[ -d "$DT_SRC" ] && cp -r "$DT_SRC/." "$BUILD_DIR/device/samsung/a32x/" && log "Device tree: applied ✓"

# ── 5. Python symlink ─────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "Python: $(python --version 2>&1)"

# ── Pre-populate clang_rt intermediates BEFORE soong/kati regenerate them ─
# Do this here so they survive any concurrent cleanup.
log "=== Pre-populating clang_rt intermediates ==="
CLANG_RT_DIR="$BUILD_DIR/prebuilts/clang/host/linux-x86/clang-r416183b1/lib64/clang/12.0.7/lib/linux"
OBJ_DIR="$OUT_DIR/target/product/$PRODUCT/obj/STATIC_LIBRARIES"
POPULATED=0
MISSING=0
for LIB_PATH in "$CLANG_RT_DIR"/libclang_rt*.a; do
    LIB_NAME=$(basename "$LIB_PATH")
    BASE="${LIB_NAME%.a}"
    IDIR="$OBJ_DIR/${BASE}_intermediates"
    ITGT="$IDIR/$LIB_NAME"
    mkdir -p "$IDIR"
    cp -f "$LIB_PATH" "$ITGT"
    POPULATED=$((POPULATED+1))
done
log "  Populated $POPULATED real clang_rt intermediates from AOSP prebuilt"

# Also populate from the product ninja if it has additional paths we didn't cover
if [ -f "$OUT_DIR/build-twrp_a32x.ninja" ]; then
    while IFS= read -r IPATH; do
        ILIB=$(basename "$IPATH")
        IBASE="${ILIB%.a}"
        RTSRC="$CLANG_RT_DIR/$ILIB"
        if [ -f "$RTSRC" ] && [ ! -f "$IPATH" ]; then
            mkdir -p "$(dirname "$IPATH")"
            cp -f "$RTSRC" "$IPATH"
            POPULATED=$((POPULATED+1))
        elif [ ! -f "$RTSRC" ] && [ ! -f "$IPATH" ]; then
            MISSING=$((MISSING+1))
        fi
    done < <(grep -o '/root/twrp-out[^ ]*libclang_rt[^ ]*\.a' "$OUT_DIR/build-twrp_a32x.ninja" | sort -u 2>/dev/null)
    log "  Total after ninja-scan: $POPULATED populated, $MISSING not in prebuilt (ok if 0)"
fi

# ── Build environment ──────────────────────────────────────────────────────
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GO117"
export GOPATH="/tmp/gopath"
export PATH="$GO117/bin:$PATH"
export OUT_DIR="$OUT_DIR"
mkdir -p "$OUT_DIR"
log "OUT_DIR: $OUT_DIR"

export TW_THEME=portrait_hdpi
export TARGET_SCREEN_WIDTH=1080
export TARGET_SCREEN_HEIGHT=2408
export TW_EXTRA_LANGUAGES=true
export TARGET_RECOVERY_PIXEL_FORMAT=RGBX_8888
export OUT="$OUT_DIR/target/product/$PRODUCT"
mkdir -p "$OUT/recovery/root/twres"

export SKIP_BLUEPRINT_TESTS=1
touch /tmp/skip_blueprint_tests
log "Blueprint test skip: ✓"

BOOTSTRAP_BIN="$OUT_DIR/soong/.bootstrap/bin"
mkdir -p "$BOOTSTRAP_BIN"
for TOOL in gotestmain gotestrunner; do
    if [ ! -f "$BOOTSTRAP_BIN/$TOOL" ]; then
        log "Pre-building $TOOL..."
        "$GO117/bin/go" build -o "$BOOTSTRAP_BIN/$TOOL" \
            "build/blueprint/$TOOL/$TOOL.go" >> "$LOG" 2>&1 \
            && log "$TOOL: built ✓" || log "$TOOL: FAILED (non-fatal)"
    else
        log "$TOOL: exists ✓"
    fi
done

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup: OK"

log "lunch twrp_a32x-eng..."
lunch twrp_a32x-eng >> "$LOG" 2>&1

if [ "$TARGET_PRODUCT" != "twrp_a32x" ]; then
    log "ERROR: lunch selected '$TARGET_PRODUCT'"
    exit 1
fi
log "Product: $TARGET_PRODUCT ✓"

# Remove stale .ninja_fifo
rm -f "$OUT_DIR/.ninja_fifo"

BUILD_JOBS="${BUILD_JOBS:-2}"

# ── LIVE PROGRESS TAIL ────────────────────────────────────────────────────
# Tail the log file to stdout so task output shows progress.
# mka writes to LOG via direct redirect (prevents soong FIFO deadlock).
log "=== mka recoveryimage ($BUILD_JOBS jobs) — live log below ==="
log "=== (errors will appear as: FAILED or error:) ==="
tail -f "$LOG" --pid=$$ &
TAIL_PID=$!

# mka: redirect to log, NOT pipe (pipe deadlocks soong's ninja FIFO)
mka -j"$BUILD_JOBS" recoveryimage >> "$LOG" 2>&1
MKA_EXIT=$?
kill $TAIL_PID 2>/dev/null
wait $TAIL_PID 2>/dev/null || true

if [ $MKA_EXIT -ne 0 ]; then
    log "=== mka FAILED (exit $MKA_EXIT) — first error ==="
    # Find the FIRST error block (not cascade errors)
    grep -n 'FAILED:\|^error:\|^ninja: ' "$LOG" | head -5 | tee -a "$LOG"
    log "--- Full last 50 lines ---"
    tail -50 "$LOG"
    exit 1
fi

# ── Result ────────────────────────────────────────────────────────────────
RECOVERY="$OUT_DIR/target/product/$PRODUCT/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log "=============================="
    log "BUILD SUCCESS!"
    log "recovery.img: $SIZE bytes (limit: 41943040)"
    log "SHA256: $SHA"
    [ $SIZE -gt 41943040 ] && log "WARNING: exceeds 40 MiB partition!"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Output: E:\\M326B_recovery_twrp.img"
    log "=============================="
else
    log "BUILD FAILED — recovery.img not produced"
    exit 1
fi
