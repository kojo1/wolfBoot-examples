/* update_helper.h
 * wolfBoot EFI update helper for QNX x86_64
 *
 * Mounts the EFI System Partition (ESP) as a FAT volume and writes
 * wolfBoot's update.img trigger file.
 */

#ifndef UPDATE_HELPER_H
#define UPDATE_HELPER_H

/* ESP mount point inside QNX */
#define ESP_MOUNT_POINT   "/fs/esp"

/* ESP device node (QNX 8, QEMU AHCI + GPT: partition 1 = EFI System) */
#define ESP_DEV           "/dev/hd0.efi.0"

/* wolfBoot image filenames on the ESP */
#define WOLFBOOT_KERNEL_IMG  ESP_MOUNT_POINT "/kernel.img"
#define WOLFBOOT_UPDATE_IMG  ESP_MOUNT_POINT "/update.img"

/* Source of the v2 signed image (embedded in the v1 IFS at build time) */
#define UPDATE_SRC_PATH   "/proc/boot/ifs_v2_signed.bin"

/**
 * Mount the ESP FAT partition.
 * Returns 0 on success, -1 on failure.
 */
int esp_mount(void);

/**
 * Unmount the ESP FAT partition.
 */
void esp_umount(void);

/**
 * Copy src to update.img on the ESP (wolfBoot update trigger).
 * Pass NULL for src to use UPDATE_SRC_PATH.
 * Returns 0 on success, -1 on failure.
 */
int esp_write_update(const char *src);

/**
 * Remove update.img from the ESP (rollback / cleanup).
 * Returns 0 on success, -1 on failure.
 */
int esp_remove_update(void);

#endif /* UPDATE_HELPER_H */
