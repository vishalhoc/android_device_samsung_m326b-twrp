#!/usr/bin/env bash
# =============================================================================
# flash_m326b_twrp.sh — Heimdall flash script for SM-M326B TWRP
# =============================================================================
# Run from Linux with device in Download Mode:
#   Power off → Hold Vol Down + Vol Up → Connect USB → Press Vol Up
#
# Usage:
#   ./flash_m326b_twrp.sh [--recovery-only | --vbmeta-only | --restore-stock]
# =============================================================================

set -e

RECOVERY_IMG="${1:-M326B_recovery_twrp.img}"
VBMETA_IMG="M326B_vbmeta_twrp.img"
BACKUP_RECOVERY="BACKUP_recovery.img"
BACKUP_VBMETA="BACKUP_vbmeta.img"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

# ─── Pre-flight checks ─────────────────────────────────────────────────────
preflight() {
    log_step "Pre-flight checks..."

    # Check heimdall
    command -v heimdall &>/dev/null || log_error "heimdall not found. Install: sudo apt-get install heimdall-flash"

    # Detect device
    log_info "Detecting device in Download Mode..."
    if ! heimdall detect 2>/dev/null; then
        log_error "Device not detected!
  Put SM-M326B in Download Mode:
    Power off → Hold Vol Down + Vol Up → Connect USB → Press Vol Up when warning appears"
    fi
    log_info "Device detected ✓"

    # Read PIT and verify partition names
    log_step "Reading PIT (partition info table)..."
    PIT_OUTPUT=$(heimdall print-pit 2>&1)
    echo "$PIT_OUTPUT" > /tmp/m326b_pit.txt

    # Verify RECOVERY partition exists
    if echo "$PIT_OUTPUT" | grep -qi "recovery"; then
        log_info "RECOVERY partition found in PIT ✓"
        echo "$PIT_OUTPUT" | grep -i recovery
    else
        log_warn "RECOVERY not found in PIT! Showing all partitions:"
        echo "$PIT_OUTPUT" | grep "Partition Name"
        log_error "Cannot flash — RECOVERY partition not found. PIT saved to /tmp/m326b_pit.txt"
    fi

    # Verify VBMETA partition exists
    if echo "$PIT_OUTPUT" | grep -qi "vbmeta"; then
        log_info "VBMETA partition found in PIT ✓"
    else
        log_warn "VBMETA partition not found — will skip vbmeta flash"
    fi
}

# ─── Flash TWRP ───────────────────────────────────────────────────────────
flash_twrp() {
    log_step "Verifying files..."

    [ -f "$RECOVERY_IMG" ] || log_error "recovery.img not found: $RECOVERY_IMG"
    [ -f "$VBMETA_IMG" ]   || log_error "vbmeta.img not found: $VBMETA_IMG"

    RECOVERY_SIZE=$(stat -c %s "$RECOVERY_IMG")
    VBMETA_SIZE=$(stat -c %s "$VBMETA_IMG")

    log_info "Recovery: $RECOVERY_IMG ($RECOVERY_SIZE bytes)"
    log_info "VBMeta:   $VBMETA_IMG ($VBMETA_SIZE bytes)"

    # Sanity check
    [ "$RECOVERY_SIZE" -le 41943040 ] || log_error "Recovery too large: $RECOVERY_SIZE > 41943040 (40 MiB)"
    [ "$VBMETA_SIZE"   -le 65536 ]    || log_error "VBMeta too large: $VBMETA_SIZE > 65536 (64 KiB)"
    [ "$VBMETA_SIZE"   -gt 0 ]        || log_error "VBMeta is empty"

    echo -e "\n${YELLOW}=== ABOUT TO FLASH ===${NC}"
    echo "  RECOVERY → M326B recovery partition (sdc44, 40 MiB)"
    echo "  VBMETA   → M326B vbmeta partition   (sdc18, 64 KiB)"
    echo ""
    echo "  SAFE TO FLASH:  recovery, vbmeta"
    echo "  WILL NOT TOUCH: boot, dtbo, super, userdata, efs, nvram, etc."
    echo ""
    echo -e "${YELLOW}Press ENTER to flash or Ctrl+C to cancel...${NC}"
    read

    log_step "Flashing TWRP recovery + disabled-verification vbmeta..."
    heimdall flash \
        --RECOVERY "$RECOVERY_IMG" \
        --VBMETA   "$VBMETA_IMG" \
        --no-reboot

    log_info "Flash complete! ✓"
    log_warn "DO NOT let the phone boot normally — it will restore stock recovery!"
    log_warn "Immediately boot to recovery:"
    echo ""
    echo "  Method 1 (ADB):  adb reboot recovery"
    echo "  Method 2 (Keys): Hold Vol Up + Power → release Power at Samsung logo → keep Vol Up"
    echo ""
}

# ─── Flash recovery only ─────────────────────────────────────────────────
flash_recovery_only() {
    log_step "Flashing recovery only (no vbmeta change)..."
    [ -f "$RECOVERY_IMG" ] || log_error "recovery.img not found: $RECOVERY_IMG"
    heimdall flash --RECOVERY "$RECOVERY_IMG" --no-reboot
    log_info "Recovery flashed ✓"
}

# ─── Restore stock ──────────────────────────────────────────────────────
restore_stock() {
    log_step "Restoring stock recovery and vbmeta..."

    [ -f "$BACKUP_RECOVERY" ] || log_error "Stock recovery backup not found: $BACKUP_RECOVERY"
    [ -f "$BACKUP_VBMETA" ]   || log_error "Stock vbmeta backup not found: $BACKUP_VBMETA"

    echo -e "${RED}=== RESTORE STOCK ===${NC}"
    echo "  This will restore STOCK SAMSUNG RECOVERY"
    echo "  Recovery: $BACKUP_RECOVERY"
    echo "  VBMeta:   $BACKUP_VBMETA"
    echo ""
    echo "Press ENTER to continue or Ctrl+C to cancel..."
    read

    heimdall flash \
        --RECOVERY "$BACKUP_RECOVERY" \
        --VBMETA   "$BACKUP_VBMETA" \
        --no-reboot

    log_info "Stock recovery restored ✓"
}

# ─── Main ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  TWRP Flash — SM-M326B (Galaxy M32 5G)    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

preflight

case "${1}" in
    --recovery-only)  flash_recovery_only ;;
    --vbmeta-only)
        log_step "Flashing vbmeta only..."
        [ -f "$VBMETA_IMG" ] || log_error "vbmeta.img not found"
        heimdall flash --VBMETA "$VBMETA_IMG" --no-reboot
        log_info "VBMeta flashed ✓"
        ;;
    --restore-stock)  restore_stock ;;
    *)                flash_twrp ;;
esac
