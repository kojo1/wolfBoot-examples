/* app_v1.c
 * wolfBoot demo application v1
 *
 * Prints a banner and waits for commands:
 *   reboot  -- reboot (stays on v1)
 *   update  -- write update.img to the ESP and reboot (triggers v2 update)
 *   attack  -- corrupt one byte in update.img (simulate tamper attack)
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
    printf("************************************\n");
    printf("*  wolfBoot Demo: QNX v1 booted    *\n");
    printf("************************************\n");
    printf("\n");
    printf("Commands:\n");
    printf("  reboot  -- reboot (stay on v1)\n");
    printf("  update  -- write update.img, reboot to upgrade to v2\n");
    printf("  attack  -- corrupt update.img then reboot (tamper demo)\n");
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
            printf("Writing update.img to ESP...\n");
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
            printf("Done. Type 'reboot' to boot v2.\n");

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
            /* Show 8 bytes before corrupting */
            unsigned char before[8];
            lseek(fd, 512, SEEK_SET);
            read(fd, before, sizeof(before));
            printf("  before [offset 512]: ");
            for (int i = 0; i < 8; i++) printf("%02X ", before[i]);
            printf("\n");

            /* Flip one byte */
            unsigned char corrupt = 0xFF;
            lseek(fd, 512, SEEK_SET);
            write(fd, &corrupt, 1);

            /* Confirm the change */
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
