#!/usr/bin/env bash
# build.sh — Build the wolfBoot + QNX UEFI Secure Boot / OTA demo
#
# Phases:
#   0.  Clone wolfBoot (qemu-qnx branch) and build keytools
#   1.  Cross-compile demo apps (requires QNX SDP 8.0)
#   2.  Build QNX UEFI images (v1 and v2)
#   3.  Generate ED25519 keys and sign images
#   4.  Embed signed v2 image into v1 IFS and re-sign
#   5.  Build wolfBoot.efi
#   6.  Create QEMU GPT disk image
#
# Usage:
#   source ~/qnx800/qnxsdp-env.sh   # or let the script do it
#   ./scripts/build.sh

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"       # QEMU-QNX/
BUILD_DIR="$DEMO_DIR/build"               # all generated artifacts go here

WOLFBOOT_DIR="$DEMO_DIR/wolfboot"
WOLFBOOT_BRANCH="${WOLFBOOT_BRANCH:-qemu-qnx}"
SNIPPETS_DIR="$DEMO_DIR/snippets"
KEYS_DIR="$BUILD_DIR/keys"
QNX_IMAGE_BASE="$BUILD_DIR/qnx-image-base"
QNX_IMAGE_V1="$BUILD_DIR/qnx-image-v1"
QNX_IMAGE_V2="$BUILD_DIR/qnx-image-v2"
ESP_IMG="$BUILD_DIR/esp.img"
DISK_IMG="$BUILD_DIR/wolfboot-demo.img"

# ── QNX SDP ────────────────────────────────────────────────────────────────
QNX_SDP="${QNX_SDP:-${HOME}/qnx800}"
QNX_ENV="$QNX_SDP/qnxsdp-env.sh"

# ── OVMF ───────────────────────────────────────────────────────────────────
find_ovmf() {
    local var="$1"; shift
    for path in "$@"; do
        if [ -f "$path" ]; then
            printf -v "$var" '%s' "$path"
            return 0
        fi
    done
    return 1
}

find_ovmf OVMF_CODE \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/ovmf/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF.fd \
    /usr/share/ovmf/OVMF.fd || true

find_ovmf OVMF_VARS_TPL \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/ovmf/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/ovmf/OVMF_VARS.fd || true

# ── Helpers ────────────────────────────────────────────────────────────────
log()  { echo ">>> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' not found. Install: $2"
}

# ── Phase: Prerequisites ───────────────────────────────────────────────────
check_prereqs() {
    log "Checking prerequisites..."

    require_cmd qemu-system-x86_64 "sudo apt install qemu-system-x86_64"
    require_cmd mkdosfs            "sudo apt install dosfstools"
    require_cmd mmd                "sudo apt install mtools"
    require_cmd mcopy              "sudo apt install mtools"
    require_cmd sgdisk             "sudo apt install gdisk"
    require_cmd git                "sudo apt install git"
    require_cmd make               "sudo apt install make"

    [ -f "$QNX_ENV" ] || die "QNX SDP not found at $QNX_SDP
  Install QNX SDP 8.0 and set QNX_SDP=/path/to/qnx800 if non-default."

    [ -n "${OVMF_CODE:-}" ] || die "OVMF firmware not found.
  Run: sudo apt install ovmf"

    [ -n "${OVMF_VARS_TPL:-}" ] || die "OVMF_VARS not found.
  Run: sudo apt install ovmf"

    log "Prerequisites OK"
    log "  OVMF CODE: $OVMF_CODE"
    log "  OVMF VARS: $OVMF_VARS_TPL"
}

# ── Phase 0: Clone wolfBoot ────────────────────────────────────────────────
clone_wolfboot() {
    log "Phase 0: Clone wolfBoot (branch: $WOLFBOOT_BRANCH)"

    if [ -d "$WOLFBOOT_DIR/.git" ]; then
        log "  wolfBoot already cloned at $WOLFBOOT_DIR"
        cd "$WOLFBOOT_DIR"
        local current
        current=$(git rev-parse --abbrev-ref HEAD)
        if [ "$current" != "$WOLFBOOT_BRANCH" ]; then
            log "  Switching branch $current -> $WOLFBOOT_BRANCH"
            git checkout "$WOLFBOOT_BRANCH"
        fi
    else
        git clone --branch "$WOLFBOOT_BRANCH" \
            https://github.com/wolfSSL/wolfBoot.git "$WOLFBOOT_DIR"
        cd "$WOLFBOOT_DIR"
        git submodule update --init lib/wolfssl
    fi

    log "  Building keytools..."
    make -C "$WOLFBOOT_DIR/tools/keytools" --no-print-directory -j"$(nproc)"
    log "  keytools built"
}

# ── Phase 1: Build demo apps ───────────────────────────────────────────────
build_apps() {
    log "Phase 1: Cross-compile demo apps"

    # Source QNX environment if not already loaded
    if ! command -v qcc &>/dev/null; then
        # shellcheck source=/dev/null
        source "$QNX_ENV"
    fi
    command -v qcc &>/dev/null || die "qcc not found after sourcing $QNX_ENV"

    mkdir -p "$BUILD_DIR"
    make -C "$DEMO_DIR" OUTDIR="$BUILD_DIR" --no-print-directory
    log "  app_v1 and app_v2 built in $BUILD_DIR"
}

# ── Helper: setup a QNX image work directory ──────────────────────────────
#   $1 = dest dir (qnx-image-v1 or qnx-image-v2)
#   $2 = snippet version ("v1" or "v2")
setup_qnx_image_dir() {
    local dest="$1"
    local ver="$2"

    mkdir -p "$dest"

    # If local/ doesn't exist yet, copy it from the base build
    if [ ! -d "$dest/local" ]; then
        [ -d "$QNX_IMAGE_BASE/local" ] || die "Base QNX image not built yet"
        cp -r "$QNX_IMAGE_BASE/local" "$dest/"
    fi

    # Install our custom snippets
    cp "$SNIPPETS_DIR/$ver/ifs_files.custom"  "$dest/local/snippets/ifs_files.custom"
    cp "$SNIPPETS_DIR/$ver/post_start.custom" "$dest/local/snippets/post_start.custom"
}

# ── Helper: build QNX UEFI image in a work directory ─────────────────────
#   Produces output/ifs.bin as a PE32+ UEFI application
build_uefi_ifs() {
    local dir="$1"

    cd "$dir"
    mkqnximage --force --clean

    # Patch ifs.build: multiboot → uefi, remove -zz (UART debug suppression)
    sed -i 's/\[virtual=x86_64,multiboot \]/[virtual=x86_64,uefi]/' \
        output/build/ifs.build
    sed -i 's/-D8250\.\.[0-9]* -zz/-D8250..115200/' \
        output/build/ifs.build

    cp output/build/ifs.build output/build/ifs_uefi.build
    mkifs -o output output/build/ifs_uefi.build output/ifs.bin

    file output/ifs.bin | grep -q "PE32+" || \
        die "ifs.bin in $dir is not a PE32+ EFI image"
    log "  UEFI image: $dir/output/ifs.bin"
}

# ── Phase 3: Build QNX UEFI images ────────────────────────────────────────
build_qnx_images() {
    log "Phase 2: Build QNX UEFI images"

    if ! command -v mkqnximage &>/dev/null; then
        # shellcheck source=/dev/null
        source "$QNX_ENV"
    fi
    command -v mkqnximage &>/dev/null || die "mkqnximage not found"

    # Build a base image once to get the default local/ structure
    if [ ! -d "$QNX_IMAGE_BASE/local" ]; then
        log "  Building base QNX image (first run, may take a while)..."
        mkdir -p "$QNX_IMAGE_BASE"
        cd "$QNX_IMAGE_BASE"
        mkqnximage --force --clean
        log "  Base image ready"
    fi

    # v1 (initial, without v2 signed binary yet)
    setup_qnx_image_dir "$QNX_IMAGE_V1" "v1"
    log "  Building QNX v1 UEFI image..."
    build_uefi_ifs "$QNX_IMAGE_V1"

    # v2
    setup_qnx_image_dir "$QNX_IMAGE_V2" "v2"
    log "  Building QNX v2 UEFI image..."
    build_uefi_ifs "$QNX_IMAGE_V2"
}

# ── Phase 4: Generate keys and sign images ────────────────────────────────
generate_keys_and_sign() {
    log "Phase 3: Generate ED25519 keys and sign images"
    mkdir -p "$KEYS_DIR"

    local KEYGEN="$WOLFBOOT_DIR/tools/keytools/keygen"
    local SIGN="$WOLFBOOT_DIR/tools/keytools/sign"

    # keygen must run inside wolfboot/ so it writes src/keystore.c
    cd "$WOLFBOOT_DIR"

    if [ ! -f "$KEYS_DIR/ed25519.der" ]; then
        log "  Generating ED25519 key pair..."
        "$KEYGEN" --ed25519 -g "$KEYS_DIR/ed25519.der"
        log "  Keys: $KEYS_DIR/ed25519.der (private), ed25519_pub_key.c (public in src/keystore.c)"
    else
        log "  Keys already exist, skipping keygen"
    fi

    # Sign v1 (version=1)
    cp "$QNX_IMAGE_V1/output/ifs.bin" "$KEYS_DIR/ifs_v1.bin"
    "$SIGN" --ed25519 "$KEYS_DIR/ifs_v1.bin" "$KEYS_DIR/ed25519.der" 1
    log "  Signed: $KEYS_DIR/ifs_v1_v1_signed.bin"

    # Sign v2 (version=2)
    cp "$QNX_IMAGE_V2/output/ifs.bin" "$KEYS_DIR/ifs_v2.bin"
    "$SIGN" --ed25519 "$KEYS_DIR/ifs_v2.bin" "$KEYS_DIR/ed25519.der" 2
    log "  Signed: $KEYS_DIR/ifs_v2_v2_signed.bin"
}

# ── Phase 5: Embed signed v2 image into v1 IFS, rebuild, re-sign ──────────
rebuild_v1_with_v2() {
    log "Phase 4: Embed v2 signed image into v1 IFS and re-sign"

    local V2_SIGNED="$KEYS_DIR/ifs_v2_v2_signed.bin"
    [ -f "$V2_SIGNED" ] || die "Missing $V2_SIGNED (Phase 4 must succeed first)"

    # Append v2 signed image entry to v1's ifs_files.custom (idempotent)
    local SNIPPET="$QNX_IMAGE_V1/local/snippets/ifs_files.custom"
    if ! grep -q "ifs_v2_signed.bin" "$SNIPPET"; then
        cat >> "$SNIPPET" <<'EOF'

# Signed v2 image embedded for app_v1 OTA update
[uid=0 gid=0 perms=0644]
ifs_v2_signed.bin=../keys/ifs_v2_v2_signed.bin
EOF
        log "  Added ifs_v2_signed.bin entry to v1 ifs_files.custom"
    fi

    # Rebuild v1 IFS with the additional file
    cd "$QNX_IMAGE_V1"
    mkifs -o output output/build/ifs_uefi.build output/ifs.bin
    log "  v1 IFS rebuilt with ifs_v2_signed.bin"

    # Re-sign v1 (content changed)
    local SIGN="$WOLFBOOT_DIR/tools/keytools/sign"
    cp "$QNX_IMAGE_V1/output/ifs.bin" "$KEYS_DIR/ifs_v1.bin"
    "$SIGN" --ed25519 "$KEYS_DIR/ifs_v1.bin" "$KEYS_DIR/ed25519.der" 1
    log "  Re-signed: $KEYS_DIR/ifs_v1_v1_signed.bin"
}

# ── Phase 6: Build wolfBoot.efi ────────────────────────────────────────────
build_wolfboot_efi() {
    log "Phase 5: Build wolfBoot.efi"

    cp "$DEMO_DIR/wolfboot.config" "$WOLFBOOT_DIR/.config"
    make -C "$WOLFBOOT_DIR" --no-print-directory -j"$(nproc)"

    [ -f "$WOLFBOOT_DIR/wolfboot.efi" ] || die "wolfBoot.efi not produced"
    local sz
    sz=$(wc -c < "$WOLFBOOT_DIR/wolfboot.efi")
    log "  wolfboot.efi built (${sz} bytes)"
}

# ── Phase 7: Create QEMU GPT disk image ───────────────────────────────────
create_disk_image() {
    log "Phase 6: Create QEMU GPT disk image"

    local V1_SIGNED="$KEYS_DIR/ifs_v1_v1_signed.bin"
    [ -f "$V1_SIGNED" ] || die "Missing $V1_SIGNED"

    # 640 MB GPT disk: partition 1 = ESP (256 MB), partition 2 = QNX Data (rest)
    dd if=/dev/zero of="$DISK_IMG" bs=1M count=640 status=none
    sgdisk -n 1:2048:+256M -t 1:EF00 -c 1:"EFI System" "$DISK_IMG" >/dev/null
    sgdisk -n 2:0:0        -t 2:8300 -c 2:"QNX Data"   "$DISK_IMG" >/dev/null

    # Build ESP FAT32 image
    dd if=/dev/zero of="$ESP_IMG" bs=1M count=256 status=none
    mkdosfs -F 32 -n "EFI" "$ESP_IMG" >/dev/null
    mmd   -i "$ESP_IMG" ::/EFI ::/EFI/BOOT
    mcopy -i "$ESP_IMG" "$WOLFBOOT_DIR/wolfboot.efi"  ::/EFI/BOOT/BOOTX64.EFI
    mcopy -i "$ESP_IMG" "$V1_SIGNED"                  ::/kernel.img
    log "  ESP image built (wolfboot.efi + kernel.img)"

    # Write ESP into GPT disk at partition 1 start (sector 2048)
    local ESP_START=2048
    dd if="$ESP_IMG" of="$DISK_IMG" bs=512 seek=$ESP_START conv=notrunc status=none

    # Copy OVMF vars template
    cp "$OVMF_VARS_TPL" "$BUILD_DIR/OVMF_VARS.fd"

    log "  Disk image: $DISK_IMG"
    log "  OVMF VARS:  $BUILD_DIR/OVMF_VARS.fd"
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    echo "======================================================"
    echo " wolfBoot + QNX UEFI Secure Boot / OTA Demo — Build"
    echo "======================================================"
    echo "  DEMO_DIR  : $DEMO_DIR"
    echo "  BUILD_DIR : $BUILD_DIR"
    echo ""

    check_prereqs
    clone_wolfboot
    build_apps
    build_qnx_images
    generate_keys_and_sign
    rebuild_v1_with_v2
    build_wolfboot_efi
    create_disk_image

    echo ""
    echo "======================================================"
    echo " Build complete!"
    echo "======================================================"
    echo "  Disk image : $DISK_IMG"
    echo ""
    echo "  Run the demo:"
    echo "    ./scripts/run.sh"
    echo ""
    echo "  NOTE: First boot takes ~60-90 seconds without KVM."
    echo "        Add yourself to the 'kvm' group for faster boots:"
    echo "          sudo usermod -aG kvm \$USER  (then log out/in)"
}

main "$@"
