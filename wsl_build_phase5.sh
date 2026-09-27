#!/bin/bash
# Phase 5: Patch repo bug + direct clone missing prebuilts + build
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Phase 5: Patch repo + Clone prebuilts + Build ==="

# ── Fix 1: Patch repo 2.65 /etc/.repo_gitconfig.json bug ──────────────────
# This repo version tries to write to /etc/ which is restricted in WSL
log "Patching repo tool to use /tmp instead of /etc..."
find /mnt/e/twrp-build/.repo/repo/ -name "*.py" -exec \
    grep -l "repo_gitconfig.json" {} \; 2>/dev/null | while read f; do
    log "  Patching: $f"
    sed -i 's|/etc/.repo_gitconfig.json|/tmp/.repo_gitconfig.json|g' "$f"
done
echo '{}' > /tmp/.repo_gitconfig.json
log "Repo patched."

# ── Fix 2: Direct git clone of missing prebuilts (bypass repo entirely) ────
log "Cloning missing prebuilts via git directly..."

direct_clone() {
    local path="$1"  # relative path in tree
    local dest="$BUILD_DIR/$path"
    local url="https://android.googlesource.com/platform/$path"
    
    if [ -d "$dest" ] && [ "$(ls -A $dest 2>/dev/null)" ]; then
        log "  $path: already exists ($(ls $dest | wc -l) files) — skipping"
        return
    fi
    
    log "  Cloning $url ..."
    rm -rf "$dest"
    GIT_TERMINAL_PROMPT=0 git clone \
        --depth=1 \
        --quiet \
        "$url" \
        "$dest" 2>&1 | tail -3
    
    if [ -d "$dest" ] && [ "$(ls -A $dest 2>/dev/null)" ]; then
        log "  OK: $path ($(ls $dest | wc -l) files)"
    else
        log "  FAILED: $path"
    fi
}

direct_clone "prebuilts/go/linux-x86"
direct_clone "prebuilts/misc"

# ── Fix 3: Install system Go as fallback if clone failed ──────────────────
if [ ! -f "$BUILD_DIR/prebuilts/go/linux-x86/bin/go" ]; then
    log "prebuilts/go clone failed — installing system golang..."
    # Kill any lingering dpkg locks
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null
    apt-get install -y golang-go 2>&1 | tail -5

    SYS_GO=$(which go 2>/dev/null || echo "")
    if [ -n "$SYS_GO" ]; then
        SYS_GO_ROOT=$(go env GOROOT 2>/dev/null || dirname $(dirname $SYS_GO))
        log "System Go: $SYS_GO_ROOT ($(go version))"
        
        # Create directory structure TWRP expects
        mkdir -p "$BUILD_DIR/prebuilts/go/linux-x86"
        # Copy Go root entirely
        cp -a "$SYS_GO_ROOT/." "$BUILD_DIR/prebuilts/go/linux-x86/" 2>/dev/null || {
            # Fallback: just ensure bin/go exists
            mkdir -p "$BUILD_DIR/prebuilts/go/linux-x86/bin"
            cp "$SYS_GO" "$BUILD_DIR/prebuilts/go/linux-x86/bin/go"
        }
        log "Go installed to prebuilts: $(ls $BUILD_DIR/prebuilts/go/linux-x86/bin/)"
    fi
fi

# Verify Go
GO_BIN="$BUILD_DIR/prebuilts/go/linux-x86/bin/go"
if [ -f "$GO_BIN" ] || [ -L "$GO_BIN" ]; then
    log "Go toolchain: OK ($($GO_BIN version 2>/dev/null || echo 'binary present'))"
else
    log "FATAL: Go toolchain not available — cannot build"
    exit 1
fi

# ── Fix 4: Re-apply M326B device tree ─────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK."

# ── BUILD ─────────────────────────────────────────────────────────────────
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup OK"

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -5

log "Building with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage|make:)"

# ── Result ────────────────────────────────────────────────────────────────
RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log "=============================="
    log "=== BUILD SUCCESS! ==="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Output: E:\\M326B_recovery_twrp.img"
    log "=============================="
else
    log "=== BUILD FAILED ==="
    log "Last 30 lines:"
    tail -30 "$LOG"
    exit 1
fi
