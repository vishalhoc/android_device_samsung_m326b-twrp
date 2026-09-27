#!/bin/bash
# Extract user-downloaded files + build TWRP
# Files: E:\idm\Compressed\misc-refs_tags_android-12.1.0_r4.tar.gz
#        E:\idm\Compressed\go1.21.13.linux-amd64.tar.gz

set -e
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
log "=== Extract + Build (user downloaded files) ==="
log "User: $(id)"

# ── 1. Extract prebuilts/misc ─────────────────────────────────────────────
MISC_TGZ="/mnt/e/idm/Compressed/misc-refs_tags_android-12.1.0_r4.tar.gz"
MISC_DEST="$BUILD_DIR/prebuilts/misc"

log "Extracting prebuilts/misc (~1.98 GB)..."
log "  Source: $MISC_TGZ"
rm -rf "$MISC_DEST"
mkdir -p "$MISC_DEST"

# Check tarball structure first
FIRST_ENTRY=$(tar -tzf "$MISC_TGZ" 2>/dev/null | head -1)
log "  Tar first entry: $FIRST_ENTRY"

if echo "$FIRST_ENTRY" | grep -q "^linux-x86\|^Darwin\|^[a-z]"; then
    # Files are at root level — extract directly into MISC_DEST
    tar -xzf "$MISC_TGZ" -C "$MISC_DEST" 2>&1 | tail -3
else
    # Has a top-level directory — extract to temp and move
    tar -xzf "$MISC_TGZ" -C /tmp/misc_extract/ 2>&1 | tail -3
    mv /tmp/misc_extract/*/* "$MISC_DEST/" 2>/dev/null || \
    mv /tmp/misc_extract/* "$MISC_DEST/" 2>/dev/null || true
fi

log "  misc extracted: $(ls $MISC_DEST | head -5 | tr '\n' ' ')"

# ── 2. Set up Go from downloaded tarball ─────────────────────────────────
GO_TGZ="/mnt/e/idm/Compressed/go1.21.13.linux-amd64.tar.gz"
GO_INST="/usr/local/go121"
GO_PREBUILT="$BUILD_DIR/prebuilts/go/linux-x86"

log "Extracting Go 1.21.13..."
rm -rf "$GO_INST" /tmp/go_extract
mkdir -p /tmp/go_extract
tar -xzf "$GO_TGZ" -C /tmp/go_extract/
mv /tmp/go_extract/go "$GO_INST"
GO_VER=$("$GO_INST/bin/go" version)
log "Go installed: $GO_VER"

# Create prebuilts wrapper
log "Creating Go wrapper..."
rm -rf "$GO_PREBUILT"
mkdir -p "$GO_PREBUILT/bin"

python3 -c "
goroot  = '$GO_INST'
go_bin  = '$GO_INST/bin/go'
wrapper_path = '$GO_PREBUILT/bin/go'
wrapper = '#!/bin/bash\nexport GOROOT=\"' + goroot + '\"\nexec \"' + go_bin + '\" \"\$@\"\n'
with open(wrapper_path, 'w') as f:
    f.write(wrapper)
import os; os.chmod(wrapper_path, 0o755)
print('Go wrapper created: ' + wrapper_path)
"
log "Wrapper test: $($GO_PREBUILT/bin/go version)"

# ── 3. Python symlink ────────────────────────────────────────────────────
ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
log "python: $(python --version 2>&1)"

# ── 4. Apply M326B device tree ───────────────────────────────────────────
log "Applying M326B device tree..."
DT_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"
cp -r "$DT_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
log "Device tree OK"

# ── 5. BUILD ─────────────────────────────────────────────────────────────
log "=== BUILDING TWRP ==="
cd "$BUILD_DIR"
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true
export GOROOT="$GO_INST"
export GOPATH="/tmp/gopath"
export PATH="$GO_PREBUILT/bin:$PATH"

log "Sourcing build/envsetup.sh..."
source build/envsetup.sh
log "envsetup sourced OK"

log "Running lunch twrp_a32x-eng..."
lunch twrp_a32x-eng 2>&1 | tee -a "$LOG" | tail -8

log "mka recoveryimage with $(nproc) cores..."
mka recoveryimage 2>&1 | tee -a "$LOG" | \
    grep -E "(error:|Error:|FAILED|Building|Packaging|Installed|recoveryimage|nolocalimports|compile)"

# ── 6. Result ────────────────────────────────────────────────────────────
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
    # Check if it's the -nolocalimports Go version issue
    if grep -q "nolocalimports" "$LOG" 2>/dev/null; then
        log ">>> Go 1.21 incompatible — need Go 1.17.13"
        log ">>> Download: https://go.dev/dl/go1.17.13.linux-amd64.tar.gz"
        log ">>> Save to E:\\go117.tar.gz then run wsl_go117_setup.sh"
    fi
    tail -30 "$LOG"
    exit 1
fi
