# wolfBoot Secure Boot + OTA Demo on QEMU/QNX

This example demonstrates [wolfBoot](https://github.com/wolfSSL/wolfBoot) secure
boot and OTA (Over-The-Air) firmware update with **QNX 8.0** running under
**QEMU x86_64** with UEFI boot.

## Demo Scenarios

| Scenario | Steps | Result |
|---|---|---|
| Secure update v1→v2 | Boot v1, type `update`, `reboot` | wolfBoot verifies v2 signature, commits, boots v2 |
| Tamper detection | Boot v1, `update`, `attack`, `reboot` | wolfBoot detects corrupt hash, rejects update, stays on v1 |
| Version check | Boot v2, `update`, `reboot` | wolfBoot rejects (same version), stays on v2 |
| Simple reboot | Any version, `reboot` | Boots same version |

## How It Works

```
OVMF (UEFI firmware)
  └─▶ wolfBoot.efi  (EFI application on ESP)
       ├─ reads kernel.img and update.img from ESP FAT partition
       ├─ verifies ED25519 signatures (SHA256 hash)
       ├─ if update.img version > kernel.img version:
       │    commit (overwrite kernel.img), delete update.img
       └─▶ QNX startup (PE32+ loaded at 0x1400000)
            └─▶ app_v1  or  app_v2
                 └─ user types "update": writes /proc/boot/ifs_v2_signed.bin
                                          to /fs/esp/update.img via FAT mount
```

## Prerequisites

### Platform

- **Ubuntu 22.04 or 24.04** (x86_64, native or VM)
- ~2 GB free disk space, ~4 GB RAM

### Packages

```bash
sudo apt install \
    qemu-system-x86_64 \
    dosfstools mtools gdisk \
    ovmf gnu-efi \
    git make autoconf automake libtool
```

### QNX SDP 8.0

QNX SDP (Software Development Platform) is commercial software required to
build QNX images and cross-compile the demo applications.

1. Obtain the installer from [BlackBerry QNX](https://www.qnx.com/)
   (a myQNX account and valid license are required)
2. Install to the default location:
   ```bash
   chmod +x qnx-setup-2.0.x-linux.run
   ./qnx-setup-2.0.x-linux.run
   # Accept defaults → installs to ~/qnx800/
   ```
3. Verify the cross-compiler:
   ```bash
   source ~/qnx800/qnxsdp-env.sh
   qcc --version   # Toolchain: gcc  Version: 12.2.0
   ```

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/wolfSSL/wolfboot-examples.git
cd wolfboot-examples/QEMU-QNX

# 2. Source the QNX environment
source ~/qnx800/qnxsdp-env.sh

# 3. Build everything (~10 minutes on the first run)
./scripts/build.sh

# 4. Run the demo
./scripts/run.sh
```

> **Tip:** Enable KVM for much faster boot times (~5 s vs ~90 s):
> ```bash
> sudo usermod -aG kvm $USER   # log out and back in
> ```

## Demo Walkthrough

### Boot v1

After QNX boots you will see:

```
************************************
*  wolfBoot Demo: QNX v1 booted    *
************************************

Commands:
  reboot  -- reboot (stay on v1)
  update  -- write update.img, reboot to upgrade to v2
  attack  -- corrupt update.img then reboot (tamper demo)
```

### Scenario 1 — Secure Update (v1 → v2)

```
> update
Writing update.img to ESP...
ESP mounted: /dev/hd0.efi.0 -> /fs/esp
update.img written: 32127232 bytes
Done. Type 'reboot' to boot v2.
> reboot
```

wolfBoot output on the next boot:

```
Opening file: kernel.img, size: 42838272
Opening file: update.img, size: 32127232
Trying partition 1 at ...
Checking integrity...done
Verifying signature...done
Successfully selected image in part: 1
[WB] Update accepted (version newer), committing
[WB] Committing update.img -> kernel.img
[WB] commit: done
Firmware Valid
```

QNX v2 boots and shows:

```
*********************************************
*  wolfBoot Demo: QNX v2 booted            *
*  Secure OTA update complete!             *
*  wolfBoot verified the v2 signature.     *
*********************************************
```

### Scenario 2 — Tamper Detection

```
> update          # write update.img
> attack          # corrupt 1 byte at offset 512
> reboot
```

wolfBoot output:

```
Checking integrity...FAILED
Failure -1: Part 1, Hdr 1, Hash 0, Sig 0
Active is now: 0
Trying partition 0 at ...
Checking integrity...done
Verifying signature...done
[WB] Update REJECTED: signature verification FAILED (update tampered!)
Firmware Valid
```

QNX v1 boots again — the tampered update is silently discarded.

### Scenario 3 — Version Check (from v2)

```
> update          # write same-version (v2) update.img
> reboot
```

wolfBoot output:

```
[WB] Update rejected: version not newer (update=2, kernel=2)
Firmware Valid
```

QNX v2 continues running.

## Directory Structure

```
QEMU-QNX/
├── README.md
├── Makefile                   QNX cross-compile rules
├── app_v1.c                   Demo app v1 (update trigger + tamper sim)
├── app_v2.c                   Demo app v2 (post-update banner)
├── update_helper.c/h          ESP FAT helper (mount/write/unmount)
├── wolfboot.config            wolfBoot .config (ED25519, x86_64_efi)
├── snippets/
│   ├── v1/ifs_files.custom    Files embedded in v1 IFS (/proc/boot/)
│   ├── v1/post_start.custom   QNX v1 startup command (auto-run app_v1)
│   ├── v2/ifs_files.custom    Files embedded in v2 IFS
│   └── v2/post_start.custom   QNX v2 startup command (auto-run app_v2)
└── scripts/
    ├── build.sh               Full automated build script
    └── run.sh                 QEMU launch script (KVM auto-detect)

build/                         Generated by build.sh (git-ignored)
├── wolfboot/                  wolfBoot clone (qemu-qnx branch)
├── app_v1, app_v2             Compiled demo apps
├── qnx-image-base/            Base QNX image (for local/ defaults)
├── qnx-image-v1/              QNX v1 work directory
├── qnx-image-v2/              QNX v2 work directory
├── keys/                      ED25519 keys and signed images
├── esp.img                    ESP FAT32 image (working copy)
├── wolfboot-demo.img          Final QEMU GPT disk image (640 MB)
└── OVMF_VARS.fd               UEFI variable store (reset with --reset)
```

## License

- Demo application code (`app_v1.c`, `app_v2.c`, `update_helper.*`):
  GPLv2 — Copyright (C) 2025 wolfSSL Inc.

See [wolfBoot LICENSE](https://github.com/wolfSSL/wolfBoot/blob/master/LICENSE)
and [wolfboot-examples LICENSE](../LICENSE) for full terms.
