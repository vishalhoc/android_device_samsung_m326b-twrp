#!/bin/bash
# Phase 3: Fix missing prebuilts + build
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Phase 3: Fix prebuilts + Build ==="

# Fix 1: pre-create repo config file that was blocking re-sync
echo '{}' > /etc/.repo_gitconfig.json 2>/dev/null || true
chmod 644 /etc/.repo_gitconfig.json 2>/dev/null || true

# Fix 2: ensure python symlink exists
which python 2>/dev/null || ln -sf /usr/bin/python3 /usr/local/bin/python
log "python: $(python --version 2>&1)"

cd "$BUILD_DIR"

# Fix 3: Sync ONLY the repos that failed (targeted, faster than full sync)
log "Syncing missing/failed repos..."
FAILED_REPOS="prebuilts/go/linux-x86 prebuilts/misc prebuilts/sdk prebuilts/rust prebuilts/clang/host/linux-x86"
for repo_path in $FAILED_REPOS; do
    log "  Syncing $repo_path ..."
    repo sync "$repo_path" -c --no-clone-bundle --no-tags --force-sync -j4 2>&1 | tail -3 | tee -a "$LOG"
done
log "Targeted sync complete."

# Verify go toolchain now exists
if [ ! -d "/mnt/e/twrp-build/prebuilts/go/linux-x86" ]; then
    log "ERROR: prebuilts/go/linux-x86 still missing after sync!"
    log "Trying full re-sync of prebuilts..."
    repo sync prebuilts/ -c --no-clone-bundle --no-tags --force-sync -j4 2>&1 | tail -5 | tee -a "$LOG"
fi

if [ -d "/mnt/e/twrp-build/prebuilts/go/linux-x86" ]; then
    log "Go toolchain: OK ($(ls /mnt/e/twrp-build/prebuilts/go/linux-x86/bin/ | head -3))"
else
    log "Go toolchain still missing — trying to use system Go"
    apt-get install -y golang-go 2>&1 | tail -3 | tee -a "$LOG"
    GO_BIN=$(which go)
    mkdir -p /mnt/e/twrp-build/prebuilts/go/linux-x86/bin
    ln -sf "$GO_BIN" /mnt/e/twrp-build/prebuilts/go/linux-x86/bin/go
    log "Linked system go: $GO_BIN"
fi

# Fix 4: Re-apply device tree
log "Re-applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK."

# ── BUILD (source without pipe!) ───────────────────────────────────────────
log "Starting build..."
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true

# Source envsetup — NO PIPE (pipe = subshell = loses function definitions)
source build/envsetup.sh
log "envsetup sourced. Running lunch twrp_a32x-eng..."

lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -5

log "Building with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | grep -E "(error:|FAILED|Building|Packaging|Installed|recoveryimage)"

# ── Check output ────────────────────────────────────────────────────────────
RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log "=== BUILD SUCCESS ==="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Saved to: E:\\M326B_recovery_twrp.img"
else
    log "=== BUILD FAILED ==="
    log "Last build errors:"
    grep -i "error\|FAILED" "$LOG" | tail -20
    exit 1
fi
