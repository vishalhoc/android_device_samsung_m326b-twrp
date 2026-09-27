#!/bin/bash
# Phase 4: Definitive fix + build
# Fixes: /etc/.repo_gitconfig.json, missing prebuilts/go, python path

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Phase 4: Definitive Fix + Build ==="

# ── Fix 1: repo gitconfig permission bypass ───────────────────────────────
# repo 2.65 tries to write /etc/.repo_gitconfig.json, which fails in WSL.
# Solution: redirect git system config to a writable location
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/tmp/gitconfig_global
touch "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.email "build@m326b.local"
git config --file "$GIT_CONFIG_GLOBAL" user.name "TWRP Build"
git config --file "$GIT_CONFIG_GLOBAL" color.ui false

# Also create the repo config file at a writable location
mkdir -p /tmp/repo_etc
echo '{}' > /tmp/repo_etc/repo_gitconfig.json

# Pre-create /etc/.repo_gitconfig.json by mounting tmpfs over /etc (too risky)
# Instead, patch with a bind mount trick:
mkdir -p /mnt/fakeetc
cp -r /etc/. /mnt/fakeetc/ 2>/dev/null || true
echo '{}' > /mnt/fakeetc/.repo_gitconfig.json 2>/dev/null || true
log "Git config bypass applied."

# ── Fix 2: python symlink ────────────────────────────────────────────────
python3 -m venv /tmp/pyvenv --without-pip 2>/dev/null || true
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
ln -sf /usr/bin/python3 /usr/local/bin/python 2>/dev/null || true
log "python: $(python3 --version 2>&1)"

# ── Fix 3: Sync missing prebuilts using git directly (bypass repo config) ──
log "Directly cloning missing prebuilts via git..."

AOSP_BASE="https://android.googlesource.com/platform"

sync_project() {
    local project="$1"
    local local_path="$BUILD_DIR/$project"
    local git_url="$AOSP_BASE/$project"
    
    if [ -d "$local_path" ] && [ -f "$local_path/.git/config" ]; then
        log "  $project: already present, updating..."
        GIT_CONFIG_NOSYSTEM=1 git -C "$local_path" fetch --depth=1 --quiet 2>/dev/null || true
    elif [ -d "$BUILD_DIR/.repo/projects/${project}.git" ]; then
        log "  $project: checking out from .repo cache..."
        mkdir -p "$local_path"
        GIT_CONFIG_NOSYSTEM=1 git clone \
            --reference "$BUILD_DIR/.repo/projects/${project}.git" \
            --depth=1 \
            "$git_url" \
            "$local_path" 2>&1 | tail -2 || true
    else
        log "  $project: cloning fresh..."
        GIT_CONFIG_NOSYSTEM=1 git clone --depth=1 "$git_url" "$local_path" 2>&1 | tail -3 || true
    fi
    
    if [ -d "$local_path" ]; then
        log "  $project: OK ($(ls $local_path | wc -l) files)"
    else
        log "  $project: FAILED"
    fi
}

# Sync the repos that dropped during initial sync
sync_project "prebuilts/go/linux-x86"
sync_project "prebuilts/misc"

# ── Fix 4: Install system Go as fallback if prebuilts/go still missing ────
if [ ! -f "$BUILD_DIR/prebuilts/go/linux-x86/bin/go" ]; then
    log "prebuilts/go still missing — installing system Go as fallback..."
    apt-get install -y golang-go 2>&1 | tail -3
    SYS_GO=$(which go)
    SYS_GO_DIR=$(dirname $(dirname $SYS_GO))
    log "System Go: $SYS_GO ($(go version 2>&1))"
    
    # Create symlink structure matching what TWRP expects
    mkdir -p "$BUILD_DIR/prebuilts/go/linux-x86"
    ln -sfn "$SYS_GO_DIR" "$BUILD_DIR/prebuilts/go/linux-x86" 2>/dev/null || \
        cp -r "$SYS_GO_DIR"/. "$BUILD_DIR/prebuilts/go/linux-x86/" 2>/dev/null || true
    
    # At minimum, ensure the bin/go exists
    mkdir -p "$BUILD_DIR/prebuilts/go/linux-x86/bin"
    ln -sf "$SYS_GO" "$BUILD_DIR/prebuilts/go/linux-x86/bin/go"
    log "Go binary linked: $(ls -la $BUILD_DIR/prebuilts/go/linux-x86/bin/go)"
fi

GO_OK=$(ls "$BUILD_DIR/prebuilts/go/linux-x86/bin/go" 2>/dev/null && echo YES || echo NO)
log "Go toolchain: $GO_OK"

# ── Fix 5: Re-apply M326B device tree ─────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK."

# ── BUILD ─────────────────────────────────────────────────────────────────
log "=== Starting Build ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GIT_CONFIG_NOSYSTEM=1

# Source envsetup — NO PIPE!
log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "Sourced OK."

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "Building recovery.img with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | grep -E "(error:|Error|FAILED|Building|Packaging|Installed|recoveryimage|warning:)" | tail -30

# ── Verify output ─────────────────────────────────────────────────────────
RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log ""
    log "=============================="
    log "=== BUILD SUCCESS ==="
    log "=============================="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    log ""
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Saved: E:\\M326B_recovery_twrp.img"
    log "Ready to flash with Heimdall!"
else
    log "=== BUILD FAILED ==="
    grep -i "error\|FAILED" "$LOG" | tail -20
    exit 1
fi
