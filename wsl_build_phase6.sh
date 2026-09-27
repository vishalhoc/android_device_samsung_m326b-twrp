#!/bin/bash
# Phase 6: Run as ROOT — install Go from apt, fix python, then build
# Must be launched with: wsl -d Ubuntu -u root bash this_script.sh

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Phase 6: ROOT build ==="
log "Running as: $(id)"

# ── 1. Clear lingering package manager locks ───────────────────────────────
log "Clearing dpkg locks..."
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a 2>&1 | tail -3 | tee -a "$LOG" || true

# ── 2. Install Go from apt ──────────────────────────────────────────────────
log "Installing golang-go from apt..."
apt-get update -qq 2>&1 | tail -2 | tee -a "$LOG"
apt-get install -y golang-go 2>&1 | tail -5 | tee -a "$LOG"

GO_SYS=$(which go 2>/dev/null)
if [ -z "$GO_SYS" ]; then
    # Try snap
    log "apt go not found, trying snap..."
    snap install go --classic 2>&1 | tail -3 | tee -a "$LOG" || true
    GO_SYS=$(which go 2>/dev/null)
fi

if [ -z "$GO_SYS" ]; then
    # Download directly from go.dev
    log "Installing Go 1.21 from go.dev..."
    wget -q https://go.dev/dl/go1.21.13.linux-amd64.tar.gz -O /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    GO_SYS=/usr/local/go/bin/go
    export PATH=$PATH:/usr/local/go/bin
fi

GO_VER=$($GO_SYS version 2>/dev/null || echo "unknown")
log "Go: $GO_SYS ($GO_VER)"

# ── 3. Create prebuilts/go structure that build system expects ─────────────
log "Setting up prebuilts/go/linux-x86..."
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"
GO_ROOT=$(dirname $(dirname $GO_SYS))

rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT"

# Copy entire Go installation into prebuilts location
cp -a "$GO_ROOT/." "$GO_PREBUILT/" 2>/dev/null || {
    # Minimal fallback: just bin/go
    mkdir -p "$GO_PREBUILT/bin"
    cp "$GO_SYS" "$GO_PREBUILT/bin/go"
    # Also need go tool
    GO_TOOL_DIR=$(dirname $GO_SYS)/../pkg/tool/linux_amd64
    if [ -d "$GO_TOOL_DIR" ]; then
        mkdir -p "$GO_PREBUILT/pkg/tool/linux_amd64"
        cp -a "$GO_TOOL_DIR/." "$GO_PREBUILT/pkg/tool/linux_amd64/"
    fi
}

# Verify
if [ -f "$GO_PREBUILT/bin/go" ] || [ -L "$GO_PREBUILT/bin/go" ]; then
    log "Go prebuilt: OK ($($GO_PREBUILT/bin/go version 2>/dev/null))"
else
    log "FATAL: Could not set up Go toolchain"
    exit 1
fi

# ── 4. Fix Python symlink ────────────────────────────────────────────────────
log "Setting up python symlink..."
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
ln -sf /usr/bin/python3 /usr/local/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1 || python3 --version 2>&1)"

# ── 5. Apply M326B device tree ──────────────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK — partition sizes:"
grep "PARTITION_SIZE" "$BUILD_DIR/device/samsung/a32x/BoardConfig.mk" | grep -E "BOOT|SUPER" | tee -a "$LOG"

# ── 6. BUILD ─────────────────────────────────────────────────────────────────
log "=== STARTING BUILD ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export PATH="$GO_PREBUILT/bin:$PATH"

# Source envsetup — NO PIPE (subshell would lose function definitions)
log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup sourced OK"

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

CORES=$(nproc)
log "Building with $CORES cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage|make:|warning:)" | \
    tail -50

# ── 7. Verify result ──────────────────────────────────────────────────────────
RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log ""
    log "=============================="
    log "=== BUILD SUCCESS! ==="
    log "=============================="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    [ "$SIZE" -le 41943040 ] && log "Size check: PASS (<= 40 MiB)" || log "WARNING: exceeds 40 MiB partition!"
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Output: E:\\M326B_recovery_twrp.img"
else
    log "=== BUILD FAILED ==="
    log "Last 40 build log lines:"
    tail -40 "$LOG"
    exit 1
fi
