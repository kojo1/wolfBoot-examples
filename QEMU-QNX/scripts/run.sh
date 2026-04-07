#!/usr/bin/env bash
# run.sh — Launch the wolfBoot + QNX UEFI demo in QEMU
#
# Usage:
#   ./scripts/run.sh [--reset]
#
#   --reset   Reset OVMF_VARS.fd (clears UEFI variables, fresh boot)
#
# Exit QEMU: Ctrl-A X

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$DEMO_DIR/build"

DISK_IMG="$BUILD_DIR/wolfboot-demo.img"
OVMF_VARS="$BUILD_DIR/OVMF_VARS.fd"

# Find OVMF CODE firmware
OVMF_CODE=""
for p in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/ovmf/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF.fd \
    /usr/share/ovmf/OVMF.fd; do
    [ -f "$p" ] && { OVMF_CODE="$p"; break; }
done

OVMF_VARS_TPL=""
for p in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/ovmf/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/ovmf/OVMF_VARS.fd; do
    [ -f "$p" ] && { OVMF_VARS_TPL="$p"; break; }
done

# Handle --reset flag
for arg in "$@"; do
    if [ "$arg" = "--reset" ]; then
        echo "Resetting OVMF_VARS.fd..."
        [ -n "$OVMF_VARS_TPL" ] || { echo "ERROR: OVMF_VARS template not found"; exit 1; }
        cp "$OVMF_VARS_TPL" "$OVMF_VARS"
        echo "Done."
    fi
done

# Sanity checks
[ -f "$DISK_IMG" ]  || { echo "ERROR: $DISK_IMG not found. Run ./scripts/build.sh first."; exit 1; }
[ -f "$OVMF_VARS" ] || { echo "ERROR: $OVMF_VARS not found. Run ./scripts/build.sh first."; exit 1; }
[ -n "$OVMF_CODE" ] || { echo "ERROR: OVMF firmware not found. Install: sudo apt install ovmf"; exit 1; }

# KVM acceleration (available on native Ubuntu; skip on WSL2)
KVM_ARGS=""
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_ARGS="-enable-kvm"
    echo "KVM: enabled  (fast mode)"
else
    echo "KVM: not available  (slow mode — add yourself to the kvm group for speed)"
fi

echo ""
echo "======================================================"
echo " wolfBoot + QNX UEFI Demo"
echo "======================================================"
echo "  Disk   : $DISK_IMG"
echo "  OVMF   : $OVMF_CODE"
echo "  VARS   : $OVMF_VARS"
echo ""
echo "  Exit QEMU: Ctrl-A X"
echo "  Reset UEFI vars: ./scripts/run.sh --reset"
echo "======================================================"
echo ""

qemu-system-x86_64 \
    -machine q35 \
    -smp 2 \
    -cpu max \
    $KVM_ARGS \
    -m 1G \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive file="$DISK_IMG",format=raw,if=ide,id=drv0 \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -nographic \
    -serial mon:stdio
