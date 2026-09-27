#!/usr/bin/env bash
# =============================================================================
# build_twrp_m326b.sh — Complete TWRP Build Script for SM-M326B
# =============================================================================
# Run from your TWRP build root directory (~/twrp-build)
# Requires: Ubuntu 22.04 or 18.04, 16 GB RAM, 60 GB free space
#
# Usage:
#   chmod +x build_twrp_m326b.sh
#   ./build_twrp_m326b.sh [--setup-only | --build-only | --vbmeta-only]
#
# Phases:
#   Phase 1: Prerequisites and repo sync (if --setup-only or default)
#   Phase 2: Apply M326B-specific device tree patches (overwrite from this repo)
#   Phase 3: Build recovery.img
#   Phase 4: Create disabled-verification vbmeta
#   Phase 5: Print SHA256 checksums
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${HOME}/twrp-build"
DEVICE_TREE_SRC="${SCRIPT_DIR}/device/samsung/a32x"
PREBUILT_DIR="${DEVICE_TREE_SRC}/prebuilt"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Parse args ────────────────────────────────────────────────────────────
SETUP_ONLY=0; BUILD_ONLY=0; VBMETA_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --setup-only)   SETUP_ONLY=1 ;;
        --build-only)   BUILD_ONLY=1 ;;
        --vbmeta-only)  VBMETA_ONLY=1 ;;
    esac
done

# ─── PHASE 1: Check prerequisites ─────────────────────────────────────────
check_prereqs() {
    log_info "Checking prerequisites..."

    # Check for prebuilt files from M326B device
    for f in kernel dtb.img dtbo.img; do
        if [ ! -f "${PREBUILT_DIR}/${f}" ]; then
            log_error "Missing prebuilt: ${PREBUILT_DIR}/${f}
  Please extract kernel and dtb.img from M326B stock boot.img:
    dd if=/dev/block/by-name/boot of=/sdcard/M326B_boot.img
    adb pull /sdcard/M326B_boot.img
    ./extract_kernel.py M326B_boot.img ${PREBUILT_DIR}/
  And dump dtbo:
    dd if=/dev/block/by-name/dtbo of=/sdcard/M326B_dtbo.img
    adb pull /sdcard/M326B_dtbo.img ${PREBUILT_DIR}/dtbo.img"
        fi
    done

    log_info "All prebuilt files present."
    for f in "${PREBUILT_DIR}"/*; do
        log_info "  $(basename $f): $(stat -c %s $f) bytes"
    done
}

# ─── PHASE 1.5: Install avbtool ────────────────────────────────────────────
install_avbtool() {
    if ! command -v avbtool &>/dev/null; then
        log_info "Installing avbtool..."
        pip3 install avbtool 2>/dev/null || {
            # Try from AOSP source
            if [ -f "${BUILD_DIR}/external/avb/avbtool.py" ]; then
                ln -sf "${BUILD_DIR}/external/avb/avbtool.py" /usr/local/bin/avbtool
                chmod +x /usr/local/bin/avbtool
            else
                log_warn "avbtool not found. Install it: pip3 install avbtool"
            fi
        }
    fi
    log_info "avbtool: $(avbtool version 2>/dev/null || echo 'not available')"
}

# ─── PHASE 2: Repo init and sync ───────────────────────────────────────────
setup_repo() {
    log_info "Setting up TWRP 12.1 build environment..."

    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    if [ ! -d ".repo" ]; then
        log_info "Initializing repo (TWRP 12.1)..."
        repo init \
            -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
            -b twrp-12.1 \
            --depth=1
    fi

    # Place local manifest
    mkdir -p .repo/local_manifests
    cp "${SCRIPT_DIR}/roomservice.xml" .repo/local_manifests/roomservice.xml
    log_info "Local manifest installed."

    log_info "Syncing (this takes 20-60 minutes on first run)..."
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch -j$(nproc) 2>&1 | \
        grep -v "^Fetching" | grep -v "^remote:" || true

    log_info "Repo sync complete."
}

# ─── PHASE 3: Apply M326B device tree ──────────────────────────────────────
apply_device_tree() {
    log_info "Applying M326B-specific device tree..."

    TARGET="${BUILD_DIR}/device/samsung/a32x"

    # Copy entire device tree
    cp -r "${DEVICE_TREE_SRC}"/. "${TARGET}/"
    log_info "Device tree copied to ${TARGET}"

    # Verify partition sizes are correct
    BOOT_SIZE=$(grep "BOARD_BOOTIMAGE_PARTITION_SIZE" "${TARGET}/BoardConfig.mk" | grep -o '[0-9]*')
    SUPER_SIZE=$(grep "BOARD_SUPER_PARTITION_SIZE" "${TARGET}/BoardConfig.mk" | grep -o '[0-9]*')

    if [ "$BOOT_SIZE" != "33554432" ]; then
        log_error "Boot partition size WRONG: got ${BOOT_SIZE}, expected 33554432 (32 MiB)"
    fi
    if [ "$SUPER_SIZE" != "7864320000" ]; then
        log_error "Super partition size WRONG: got ${SUPER_SIZE}, expected 7864320000"
    fi

    log_info "Partition sizes verified:"
    log_info "  Boot:   ${BOOT_SIZE} bytes (32 MiB) ✓"
    log_info "  Super:  ${SUPER_SIZE} bytes (~7500 MiB) ✓"
}

# ─── PHASE 4: Build ────────────────────────────────────────────────────────
do_build() {
    log_info "Building TWRP recovery.img..."
    cd "${BUILD_DIR}"

    source build/envsetup.sh
    export LC_ALL=C
    export ALLOW_MISSING_DEPENDENCIES=true

    lunch twrp_a32x-eng

    log_info "Starting build (mka recoveryimage)..."
    mka recoveryimage 2>&1 | tee "${SCRIPT_DIR}/build.log"

    RECOVERY="${BUILD_DIR}/out/target/product/a32x/recovery.img"
    if [ ! -f "${RECOVERY}" ]; then
        log_error "Build failed — recovery.img not found. Check ${SCRIPT_DIR}/build.log"
    fi

    RECOVERY_SIZE=$(stat -c %s "${RECOVERY}")
    log_info "recovery.img built: ${RECOVERY_SIZE} bytes"

    # Verify fits in recovery partition (40 MiB = 41943040)
    if [ "${RECOVERY_SIZE}" -gt 41943040 ]; then
        log_error "recovery.img (${RECOVERY_SIZE}) exceeds recovery partition (41943040 bytes)!"
    fi
    log_info "Size check: ${RECOVERY_SIZE} <= 41943040 ✓"

    # Copy to script directory for easy access
    cp "${RECOVERY}" "${SCRIPT_DIR}/M326B_recovery_twrp.img"
    log_info "Copied to: ${SCRIPT_DIR}/M326B_recovery_twrp.img"
}

# ─── PHASE 5: Create vbmeta ───────────────────────────────────────────────
create_vbmeta() {
    log_info "Creating disabled-verification vbmeta..."

    VBMETA_OUT="${SCRIPT_DIR}/M326B_vbmeta_twrp.img"

    if command -v avbtool &>/dev/null; then
        avbtool make_vbmeta_image \
            --flags 3 \
            --padding_size 65536 \
            --output "${VBMETA_OUT}"
        log_info "vbmeta created: ${VBMETA_OUT}"
        log_info "Verifying..."
        avbtool info_image --image "${VBMETA_OUT}"
    else
        log_warn "avbtool not available. Creating binary patch vbmeta..."
        # Create a minimal AVB0 vbmeta with flags=3
        python3 - <<'PYTHON'
import struct

# AVB header for a minimal vbmeta with flags=3, algorithm=NONE
# Header is 256 bytes, padded to 65536
hdr = bytearray(65536)

# Magic
hdr[0:4] = b'AVB0'
# required_libavb_version_major = 1
struct.pack_into('>I', hdr, 4, 1)
# required_libavb_version_minor = 0
struct.pack_into('>I', hdr, 8, 0)
# authentication_data_block_size = 0 (NONE algorithm = no auth block)
struct.pack_into('>Q', hdr, 12, 0)
# auxiliary_data_block_size = 0
struct.pack_into('>Q', hdr, 20, 0)
# algorithm_type = 0 (NONE)
struct.pack_into('>I', hdr, 28, 0)
# flags = 3 (VERIFICATION_DISABLED | HASHTREE_DISABLED)
struct.pack_into('>I', hdr, 120, 3)
# Release string
release = b'avbtool 1.2.0'
hdr[128:128+len(release)] = release

with open('M326B_vbmeta_twrp.img', 'wb') as f:
    f.write(bytes(hdr))
print('Created M326B_vbmeta_twrp.img (65536 bytes, flags=3)')
PYTHON
        mv M326B_vbmeta_twrp.img "${VBMETA_OUT}" 2>/dev/null || true
    fi
}

# ─── PHASE 6: Checksums ────────────────────────────────────────────────────
print_checksums() {
    log_info "=== SHA256 Checksums ==="
    for f in \
        "${SCRIPT_DIR}/M326B_recovery_twrp.img" \
        "${SCRIPT_DIR}/M326B_vbmeta_twrp.img" \
        "${PREBUILT_DIR}/kernel" \
        "${PREBUILT_DIR}/dtb.img" \
        "${PREBUILT_DIR}/dtbo.img"; do
        if [ -f "$f" ]; then
            echo "$(sha256sum "$f")"
        fi
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────
log_info "============================================"
log_info " TWRP Build — SM-M326B (Galaxy M32 5G)"
log_info "============================================"

check_prereqs
install_avbtool

if [ $VBMETA_ONLY -eq 1 ]; then
    create_vbmeta
    print_checksums
    exit 0
fi

if [ $BUILD_ONLY -eq 0 ]; then
    setup_repo
    apply_device_tree
fi

if [ $SETUP_ONLY -eq 0 ]; then
    do_build
    create_vbmeta
    print_checksums
fi

log_info ""
log_info "=== FLASH COMMANDS (run from PC with device in Download Mode) ==="
log_info ""
log_info "# Verify PIT first:"
log_info "  heimdall print-pit | grep -i recovery"
log_info ""
log_info "# Flash TWRP + vbmeta:"
log_info "  heimdall flash \\"
log_info "    --RECOVERY M326B_recovery_twrp.img \\"
log_info "    --VBMETA   M326B_vbmeta_twrp.img \\"
log_info "    --no-reboot"
log_info ""
log_info "# Immediately after flash — boot to TWRP:"
log_info "  adb reboot recovery"
log_info "  # OR: hold Vol Up + Power while device reboots"
log_info ""
log_info "DONE ✓"
