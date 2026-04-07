/* update_helper.c
 * wolfBoot EFI update helper for QNX x86_64
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/stat.h>

#include "update_helper.h"

#define COPY_BUF_SIZE (64 * 1024)  /* 64 KB copy buffer */

int esp_mount(void)
{
    int ret;
    char cmd[256];

    /* QNX path manager creates the mount point automatically */
    snprintf(cmd, sizeof(cmd),
             "mount -t dos %s %s", ESP_DEV, ESP_MOUNT_POINT);
    ret = system(cmd);
    if (ret != 0) {
        fprintf(stderr, "esp_mount: mount failed (ret=%d)\n", ret);
        fprintf(stderr, "  command: %s\n", cmd);
        return -1;
    }

    printf("ESP mounted: %s -> %s\n", ESP_DEV, ESP_MOUNT_POINT);
    return 0;
}

void esp_umount(void)
{
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "umount %s", ESP_MOUNT_POINT);
    system(cmd);
    printf("ESP unmounted: %s\n", ESP_MOUNT_POINT);
}

int esp_write_update(const char *src)
{
    int fd_in = -1, fd_out = -1;
    char buf[COPY_BUF_SIZE];
    ssize_t n, written;
    off_t total = 0;
    int ret = -1;

    if (src == NULL)
        src = UPDATE_SRC_PATH;

    printf("Writing update image: %s -> %s\n", src, WOLFBOOT_UPDATE_IMG);

    fd_in = open(src, O_RDONLY);
    if (fd_in < 0) {
        fprintf(stderr, "esp_write_update: open src %s failed: %s\n",
                src, strerror(errno));
        goto done;
    }

    fd_out = open(WOLFBOOT_UPDATE_IMG, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd_out < 0) {
        fprintf(stderr, "esp_write_update: open dst %s failed: %s\n",
                WOLFBOOT_UPDATE_IMG, strerror(errno));
        goto done;
    }

    while ((n = read(fd_in, buf, sizeof(buf))) > 0) {
        written = write(fd_out, buf, n);
        if (written != n) {
            fprintf(stderr, "esp_write_update: write error: %s\n",
                    strerror(errno));
            goto done;
        }
        total += written;
    }

    if (n < 0) {
        fprintf(stderr, "esp_write_update: read error: %s\n",
                strerror(errno));
        goto done;
    }

    printf("update.img written: %lld bytes\n", (long long)total);
    ret = 0;

done:
    if (fd_in  >= 0) close(fd_in);
    if (fd_out >= 0) close(fd_out);
    return ret;
}

int esp_remove_update(void)
{
    if (unlink(WOLFBOOT_UPDATE_IMG) != 0) {
        if (errno == ENOENT) {
            printf("esp_remove_update: update.img not present\n");
            return 0;
        }
        fprintf(stderr, "esp_remove_update: unlink failed: %s\n",
                strerror(errno));
        return -1;
    }
    printf("update.img removed from ESP\n");
    return 0;
}
