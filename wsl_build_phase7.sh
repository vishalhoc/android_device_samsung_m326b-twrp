#!/bin/bash
# Phase 7 — Fast setup: wrapper script for Go, build on Linux FS for speed
# Run as: wsl -d Ubuntu -u root bash this_script.sh

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Phase 7: Fast wrapper Go setup + Build ==="
log "User: $(id)"

# ── 1. Find system Go (already installed) ────────────────────────────────
GO_SYS=$(which go 2>/dev/null)
[ -z "$GO_SYS" ] && { log "FATAL: go not found — run apt-get install golang-go first"; exit 1; }
GO_REAL=$(realpath "$GO_SYS")
GOROOT_REAL=$(dirname $(dirname "$GO_REAL") 2>/dev/null)
# Try go env GOROOT
GOROOT_ENV=$("$GO_SYS" env GOROOT 2>/dev/null || echo "")
GOROOT="${GOROOT_ENV:-$GOROOT_REAL}"
log "System Go: $GO_SYS → real: $GO_REAL"
log "GOROOT: $GOROOT"

# ── 2. Create wrapper in prebuilts (seconds, not minutes) ────────────────
# Instead of cp -a (slow on NTFS), create a tiny wrapper script that
# invokes the real system Go with correct GOROOT
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"
mkdir -p "$GO_PREBUILT/bin"

# Create the go wrapper script
cat > "$GO_PREBUILT/bin/go" << GOWRAPPER
#!/bin/bash
export GOROOT="$GOROOT"
exec "$GO_REAL" "\$@"
GOWRAPPER
chmod +x "$GO_PREBUILT/bin/go"

# Test the wrapper
WRAPPER_VER=$("$GO_PREBUILT/bin/go" version 2>/dev/null)
log "Go wrapper: $WRAPPER_VER"
[ -z "$WRAPPER_VER" ] && { log "FATAL: Go wrapper broken"; exit 1; }

# ── 3. Python symlink ─────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# ── 4. Apply M326B device tree ────────────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK."

# ── 5. BUILD ─────────────────────────────────────────────────────────────
log "=== BUILDING ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GOROOT"
export PATH="$GO_PREBUILT/bin:$PATH"

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup OK."

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "Building with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage|make:)"

# ── 6. Result ─────────────────────────────────────────────────────────────
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
    tail -40 "$LOG"
    exit 1
fi
