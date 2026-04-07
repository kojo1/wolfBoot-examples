/* app_v2.c
 * wolfBoot demo application v2
 *
 * Prints a banner and waits for commands:
 *   reboot  -- reboot (stays on v2)
 *   update  -- write same-version update.img (wolfBoot will reject: not newer)
 *   attack  -- corrupt update.img (wolfBoot will reject: bad signature)
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/sysmgr.h>

#include "update_helper.h"

int main(void)
{
    char buf[64];

    printf("\n");
    printf("*********************************************\n");
    printf("*  wolfBoot Demo: QNX v2 booted            *\n");
    printf("*  Secure OTA update complete!             *\n");
    printf("*  wolfBoot verified the v2 signature.     *\n");
    printf("*********************************************\n");
    printf("\n");
    printf("Commands:\n");
    printf("  reboot  -- reboot (stay on v2)\n");
    printf("  update  -- write same-version update.img (version check demo)\n");
    printf("  attack  -- corrupt update.img (signature check demo)\n");
    printf("\n");

    for (;;) {
        printf("> ");
        fflush(stdout);

        if (fgets(buf, sizeof(buf), stdin) == NULL)
            break;

        buf[strcspn(buf, "\n")] = '\0';

        if (strcmp(buf, "reboot") == 0) {
            printf("Rebooting...\n");
            sleep(1);
            sysmgr_reboot();

        } else if (strcmp(buf, "update") == 0) {
            printf("Writing same-version (v2) update.img to ESP...\n");
            if (esp_mount() != 0) {
                printf("ERROR: failed to mount ESP\n");
                continue;
            }
            if (esp_write_update(NULL) != 0) {
                printf("ERROR: failed to write update.img\n");
                esp_umount();
                continue;
            }
            esp_umount();
            printf("Done. Type 'reboot' -- wolfBoot will reject (version not newer).\n");

        } else if (strcmp(buf, "attack") == 0) {
            printf("[attack] Corrupting update.img...\n");
            if (esp_mount() != 0) {
                printf("ERROR: failed to mount ESP\n");
                continue;
            }
            int fd = open(WOLFBOOT_UPDATE_IMG, O_RDWR);
            if (fd < 0) {
                printf("ERROR: update.img not found (run 'update' first)\n");
                esp_umount();
                continue;
            }
            unsigned char before[8];
            lseek(fd, 512, SEEK_SET);
            read(fd, before, sizeof(before));
            printf("  before [offset 512]: ");
            for (int i = 0; i < 8; i++) printf("%02X ", before[i]);
            printf("\n");

            unsigned char corrupt = 0xFF;
            lseek(fd, 512, SEEK_SET);
            write(fd, &corrupt, 1);

            unsigned char after[8];
            lseek(fd, 512, SEEK_SET);
            read(fd, after, sizeof(after));
            printf("  after  [offset 512]: ");
            for (int i = 0; i < 8; i++) printf("%02X ", after[i]);
            printf("\n");

            close(fd);
            esp_umount();
            printf("[attack] Done. Type 'reboot' -- wolfBoot will detect the tamper.\n");

        } else if (buf[0] != '\0') {
            printf("Unknown command. Use: reboot / update / attack\n");
        }
    }

    return 0;
}
