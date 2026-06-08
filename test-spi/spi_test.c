// spi_test.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <devctl.h>
#include <hw/io-spi.h>

int main(void) {
    // Device path: /dev/io-spi/<busno>/<devno>
    int fd = open("/dev/io-spi/0/0", O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    // Build xchng struct with inline data
    uint8_t tx[] = {0xDE, 0xAD, 0xBE, 0xEF};
    size_t nbytes = sizeof(tx);

    spi_xchng_t *xchng = malloc(sizeof(spi_xchng_t) + nbytes * 2);
    xchng->nbytes = nbytes;
    memcpy(xchng->data, tx, nbytes);           // TX in first half
    memset(xchng->data + nbytes, 0, nbytes);   // RX in second half

    int r = devctl(fd, DCMD_SPI_DATA_XCHNG, xchng, sizeof(spi_xchng_t) + nbytes * 2, NULL);
    if (r != EOK) {
        fprintf(stderr, "devctl failed: %s\n", strerror(r));
        free(xchng);
        close(fd);
        return 1;
    }

    uint8_t *rx = xchng->data + nbytes;
    printf("TX: %02X %02X %02X %02X\n", tx[0], tx[1], tx[2], tx[3]);
    printf("RX: %02X %02X %02X %02X\n", rx[0], rx[1], rx[2], rx[3]);

    free(xchng);
    close(fd);
    return 0;
}