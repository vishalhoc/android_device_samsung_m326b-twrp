#!/bin/bash
# TWRP SM-M326B Full Auto-Build Script
# Runs inside WSL Ubuntu, builds on E drive
# DO NOT INTERRUPT — takes ~60-90 min first time

set -e
LOG="/mnt/e/twrp_build.log"
BUILD_DIR="/mnt/e/twrp-build"
DEVICE_TREE_SRC="/mnt/e/idm/Compressed/galaxy-at-tool-master/galaxy-at-tool-master/twrp_m326b/device/samsung/a32x"

exec 2>&1

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }

log "=== TWRP M326B Build Started ==="
log "Ubuntu: $(lsb_release -d -s 2>/dev/null || cat /etc/os-release | grep PRETTY | cut -d= -f2)"
log "RAM: $(free -h | grep Mem | awk '{print $2}')"
log "E Drive: $(df -h /mnt/e | tail -1 | awk '{print $4}') free"

# ── 1. Install build dependencies ────────────────────────────────────────
log "Step 1/6: Installing build dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>&1 | tail -1

apt-get install -y --no-install-recommends \
    git curl wget python3 python3-pip python-is-python3 \
    bc bison build-essential ccache flex g++ g++-multilib \
    gcc-multilib gperf imagemagick libncurses-dev libncurses5-dev \
    libssl-dev libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip zlib1g-dev \
    lib32ncurses-dev lib32z1-dev liblz4-tool \
    libsdl1.2-dev libwxgtk3.2-dev 2>&1 | grep -E "(already|newly|Setting up)" | tail -20

# For Ubuntu 26.04 some packages might have different names
apt-get install -y libwxgtk3.0-gtk3-dev 2>/dev/null || true
apt-get install -y lib32readline-dev 2>/dev/null || true

log "Dependencies installed."

# ── 2. Install repo tool ─────────────────────────────────────────────────
log "Step 2/6: Setting up repo tool..."
mkdir -p /usr/local/bin
if [ ! -f /usr/local/bin/repo ]; then
    curl -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
    chmod a+x /usr/local/bin/repo
fi
export PATH=/usr/local/bin:$PATH
log "repo: $(repo --version 2>&1 | head -1)"

# Configure git (required for repo)
git config --global user.email "build@m326b.local" 2>/dev/null || true
git config --global user.name "TWRP Build" 2>/dev/null || true
git config --global color.ui false 2>/dev/null || true

# ── 3. Initialize TWRP source ────────────────────────────────────────────
log "Step 3/6: Initializing TWRP source (twrp-12.1)..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d ".repo" ]; then
    log "  Running repo init (this creates .repo dir)..."
    repo init \
        -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
        -b twrp-12.1 \
        --depth=1 \
        --no-clone-bundle 2>&1 | tail -5
    log "  repo init done."
else
    log "  .repo already exists, skipping init."
fi

# Place local manifest for device tree
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/roomservice.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="goldenkrew3000/android_device_samsung_a32x"
           path="device/samsung/a32x"
           remote="github"
           revision="twrp" />
</manifest>
EOF
log "  Local manifest placed."

# ── 4. Repo sync ─────────────────────────────────────────────────────────
log "Step 4/6: Syncing TWRP source (~30 GB, this takes 30-90 min)..."
log "  Started at $(date). Go grab a coffee."

repo sync -c \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --force-sync \
    -j$(nproc) 2>&1 | grep -v "^remote:" | grep -v "^Fetching" | grep -v "^From " | tail -5

log "Repo sync complete at $(date)."

# ── 5. Apply M326B device tree ───────────────────────────────────────────
log "Step 5/6: Applying M326B-specific device tree..."

if [ -d "$DEVICE_TREE_SRC" ]; then
    # Copy device tree (our M326B-specific version over the cloned A326B tree)
    cp -r "$DEVICE_TREE_SRC"/. "$BUILD_DIR/device/samsung/a32x/"
    log "  M326B device tree applied over A326B base."

    # Verify critical partition sizes
    BOOT_SZ=$(grep "BOARD_BOOTIMAGE_PARTITION_SIZE" "$BUILD_DIR/device/samsung/a32x/BoardConfig.mk" | grep -o '[0-9]*$')
    SUPER_SZ=$(grep "BOARD_SUPER_PARTITION_SIZE" "$BUILD_DIR/device/samsung/a32x/BoardConfig.mk" | grep -o '[0-9]*$')
    log "  Boot partition: $BOOT_SZ bytes (expect 33554432)"
    log "  Super partition: $SUPER_SZ bytes (expect 7864320000)"
    [ "$BOOT_SZ" = "33554432" ] || { log "ERROR: Boot size wrong!"; exit 1; }
    [ "$SUPER_SZ" = "7864320000" ] || { log "ERROR: Super size wrong!"; exit 1; }
    log "  Partition sizes verified OK."
else
    log "ERROR: Device tree not found at $DEVICE_TREE_SRC"
    log "  This means the Windows E: drive path wasn't found."
    ls /mnt/e/ 2>&1 || true
    exit 1
fi

# ── 6. Build ─────────────────────────────────────────────────────────────
log "Step 6/6: Building TWRP recovery.img..."
cd "$BUILD_DIR"

source build/envsetup.sh 2>&1 | tail -3
export LC_ALL=C
export ALLOW_MISSING_DEPENDENCIES=true

lunch twrp_a32x-eng 2>&1 | tail -5

log "  Starting mka recoveryimage..."
mka recoveryimage -j$(nproc) 2>&1 | tee -a "$LOG" | grep -E "(ERROR|error:|FAILED|Building|Packaging|Installed)" | tail -20

RECOVERY="$BUILD_DIR/out/target/product/a32x/recovery.img"
if [ -f "$RECOVERY" ]; then
    SIZE=$(stat -c %s "$RECOVERY")
    SHA=$(sha256sum "$RECOVERY" | cut -d' ' -f1)
    log ""
    log "=== BUILD SUCCESS ==="
    log "recovery.img: $SIZE bytes"
    log "SHA256: $SHA"
    log ""
    
    # Copy to accessible location on E drive
    cp "$RECOVERY" "/mnt/e/M326B_recovery_twrp.img"
    log "Copied to: E:\\M326B_recovery_twrp.img"
    log ""
    log "=== NEXT: Flash with Heimdall ==="
    log "heimdall flash --RECOVERY E:\\M326B_recovery_twrp.img --VBMETA <vbmeta_twrp.img> --no-reboot"
else
    log "=== BUILD FAILED ==="
    log "Check log: $LOG"
    tail -50 "$LOG"
    exit 1
fi

log "=== ALL DONE at $(date) ==="
