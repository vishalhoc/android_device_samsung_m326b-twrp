#!/bin/bash
# Patch microfactory + fix misc + build TWRP with Go 1.21
set -e
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Patch + Build ==="
log "User: $(id)"

# ── 1. Patch microfactory.go — remove -nolocalimports (removed in Go 1.19+) ──
MFGO="$BUILD_DIR/build/blueprint/microfactory/microfactory.go"
log "Patching $MFGO ..."
log "  Before: $(grep -n 'nolocalimports' $MFGO)"
sed -i 's/"-complete", "-pack", "-nolocalimports"/"-complete", "-pack"/' "$MFGO"
if grep -q 'nolocalimports' "$MFGO"; then
    log "  ERROR: patch failed!"
    exit 1
fi
log "  Patched OK — nolocalimports removed"

# ── 2. Extract prebuilts/misc from user-downloaded tarball ─────────────────
MISC_TGZ="/mnt/e/idm/Compressed/misc-refs_tags_android-12.1.0_r4.tar.gz"
MISC_DEST="$BUILD_DIR/prebuilts/misc"
log "Extracting prebuilts/misc..."
rm -rf "$MISC_DEST"
mkdir -p "$MISC_DEST"
# googlesource archive has files at root (starts with .prebuilt_info/)
tar -xzf "$MISC_TGZ" -C "$MISC_DEST" 2>&1 | tail -2
log "  misc contents: $(ls $MISC_DEST | head -6 | tr '\n' ' ')"

# ── 3. Set up Go 1.21 prebuilt wrapper ────────────────────────────────────
GO_INST="/usr/local/go121"
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"

if [ ! -f "$GO_INST/bin/go" ]; then
    log "Extracting Go 1.21.13 from E: drive..."
    rm -rf /tmp/go_extract "$GO_INST"
    mkdir -p /tmp/go_extract
    tar -xzf "/mnt/e/idm/Compressed/go1.21.13.linux-amd64.tar.gz" -C /tmp/go_extract/
    mv /tmp/go_extract/go "$GO_INST"
fi
log "Go 1.21: $($GO_INST/bin/go version)"

log "Creating Go wrapper..."
rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT/bin"
python3 -c "
goroot = '$GO_INST'
go_bin = '$GO_INST/bin/go'
wp = '$GO_PREBUILT/bin/go'
txt = '#!/bin/bash\nexport GOROOT=\"' + goroot + '\"\nexec \"' + go_bin + '\" \"\$@\"\n'
open(wp,'w').write(txt)
import os; os.chmod(wp, 0o755)
print('wrapper OK')
"
log "Wrapper: $($GO_PREBUILT/bin/go version)"

# ── 4. Python symlink ────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# ── 5. Apply M326B device tree ───────────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK"

# ── 6. BUILD ─────────────────────────────────────────────────────────────
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GO_INST"
export GOPATH="/tmp/gopath"
export PATH="$GO_PREBUILT/bin:$PATH"

log "Sourcing envsetup..."
source build/envsetup.sh
log "envsetup OK"

log "lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -5

log "mka recoveryimage ($(nproc) cores)..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|FAILED|Building|Packaging|Installed|recoveryimage)"

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
    log "BUILD FAILED"
    tail -30 "$LOG"
    exit 1
fi
