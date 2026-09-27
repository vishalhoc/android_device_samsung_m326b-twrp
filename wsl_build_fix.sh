#!/bin/bash
# Fix script: re-sync failed repos then build TWRP
# Fixes the source-in-subshell bug from previous run

set -e
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

log "=== TWRP Build (Phase 2: Fix + Compile) ==="

# ── 1. Re-sync to catch any failed repos ─────────────────────────────────
log "Re-syncing to fix connection-dropped repos..."
cd "$BUILD_DIR"
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --force-sync -j8 2>&1 | \
    tee -a "$LOG" | tail -5
log "Re-sync complete."

# ── 2. Apply M326B device tree again (ensure it's current) ───────────────
log "Re-applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree applied."

# ── 3. Build — SOURCE WITHOUT PIPE (the key fix) ─────────────────────────
log "Building TWRP recovery.img..."
cd "$BUILD_DIR"

export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export OUT_DIR="$BUILD_DIR/out"

# Source envsetup WITHOUT piping (pipe creates subshell, losing functions)
source build/envsetup.sh

# Now lunch and mka are available in this shell
log "Sourced envsetup.sh OK. Running lunch..."
lunch twrp_a32x-eng
log "Lunch done. Starting build with $(nproc) cores..."

mka recoveryimage 2>&1 | tee -a "$LOG" | grep -E "(error:|FAILED|Building recovery|Installed|Packaging)"

# ── 4. Check result ────────────────────────────────────────────────────────
RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log ""
    log "=== BUILD SUCCESS ==="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Output: E:\\M326B_recovery_twrp.img"
else
    log "=== BUILD FAILED — last 30 lines of log ==="
    tail -30 "$LOG"
    exit 1
fi
