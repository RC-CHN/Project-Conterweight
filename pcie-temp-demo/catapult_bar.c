#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define CATAPULT_VENDOR 0x1172
#define CATAPULT_DEVICE 0xe003
#define BAR0_SIZE       0x40

#define REG_ID          0x00
#define REG_HEARTBEAT   0x10
#define REG_TEMPERATURE 0x20
#define REG_CONTROL     0x30

static int read_hex_file(const char *path, unsigned int *value)
{
    FILE *file = fopen(path, "r");
    int result;

    if (!file)
        return -1;
    result = fscanf(file, "%x", value) == 1 ? 0 : -1;
    fclose(file);
    return result;
}

static char *find_device(void)
{
    const char *forced = getenv("CATAPULT_BDF");
    glob_t devices = {0};
    size_t i;

    if (forced) {
        char *path = malloc(strlen(forced) + 23);
        if (path)
            sprintf(path, "/sys/bus/pci/devices/%s", forced);
        return path;
    }

    if (glob("/sys/bus/pci/devices/*", 0, NULL, &devices) != 0)
        return NULL;

    for (i = 0; i < devices.gl_pathc; ++i) {
        char path[512];
        unsigned int vendor;
        unsigned int device;

        snprintf(path, sizeof(path), "%s/vendor", devices.gl_pathv[i]);
        if (read_hex_file(path, &vendor) != 0)
            continue;
        snprintf(path, sizeof(path), "%s/device", devices.gl_pathv[i]);
        if (read_hex_file(path, &device) != 0)
            continue;
        if (vendor == CATAPULT_VENDOR && device == CATAPULT_DEVICE) {
            char *result = strdup(devices.gl_pathv[i]);
            globfree(&devices);
            return result;
        }
    }

    globfree(&devices);
    return NULL;
}

static uint32_t reg_read(volatile uint8_t *bar, unsigned long offset)
{
    return *(volatile uint32_t *)(bar + offset);
}

static void reg_write(volatile uint8_t *bar, unsigned long offset, uint32_t value)
{
    *(volatile uint32_t *)(bar + offset) = value;
}

static double temperature_c(uint32_t value)
{
    return (693.0 * (value & 0x3ff) / 1024.0) - 265.0;
}

static void show_info(const char *device_path, volatile uint8_t *bar)
{
    uint32_t id = reg_read(bar, REG_ID);
    uint32_t heartbeat1 = reg_read(bar, REG_HEARTBEAT);
    uint32_t temperature = reg_read(bar, REG_TEMPERATURE);
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 100000000};
    uint32_t heartbeat2;

    nanosleep(&delay, NULL);
    heartbeat2 = reg_read(bar, REG_HEARTBEAT);

    printf("device=%s\n", strrchr(device_path, '/') + 1);
    printf("id=0x%08x%s\n", id, id == 0x43505433 ? " (CPT3)" : " (unexpected)");
    printf("heartbeat=0x%08x -> 0x%08x%s\n", heartbeat1, heartbeat2,
           heartbeat1 != heartbeat2 ? " (running)" : " (stalled)");
    if (temperature & (1u << 10))
        printf("temperature_raw=%u temperature_c=%.2f\n",
               temperature & 0x3ff, temperature_c(temperature));
    else
        printf("temperature=not-ready\n");
    printf("control=0x%08x\n", reg_read(bar, REG_CONTROL));
}

static void usage(const char *program)
{
    fprintf(stderr,
            "Usage: %s info|temp|watch|read OFFSET|write OFFSET VALUE\n"
            "Set CATAPULT_BDF=dddd:bb:ss.f to select a specific endpoint.\n",
            program);
}

int main(int argc, char **argv)
{
    char *device_path;
    char resource_path[512];
    volatile uint8_t *bar;
    unsigned long offset;
    unsigned long value;
    int writable;
    int fd;

    if (argc < 2) {
        usage(argv[0]);
        return 2;
    }

    device_path = find_device();
    if (!device_path) {
        fprintf(stderr, "Catapult endpoint 1172:e003 not found\n");
        return 1;
    }

    writable = strcmp(argv[1], "write") == 0;
    snprintf(resource_path, sizeof(resource_path), "%s/resource0", device_path);
    fd = open(resource_path, (writable ? O_RDWR : O_RDONLY) | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", resource_path, strerror(errno));
        free(device_path);
        return 1;
    }
    bar = mmap(NULL, BAR0_SIZE, PROT_READ | (writable ? PROT_WRITE : 0),
               MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
        fprintf(stderr, "mmap %s: %s\n", resource_path, strerror(errno));
        close(fd);
        free(device_path);
        return 1;
    }

    if (strcmp(argv[1], "info") == 0) {
        show_info(device_path, bar);
    } else if (strcmp(argv[1], "temp") == 0) {
        value = reg_read(bar, REG_TEMPERATURE);
        if (!(value & (1u << 10))) {
            fprintf(stderr, "Temperature conversion is not ready\n");
            return 1;
        }
        printf("%.2f\n", temperature_c(value));
    } else if (strcmp(argv[1], "watch") == 0) {
        for (;;) {
            show_info(device_path, bar);
            fflush(stdout);
            sleep(1);
        }
    } else if (strcmp(argv[1], "read") == 0 && argc == 3) {
        offset = strtoul(argv[2], NULL, 0);
        if ((offset & 3) || offset >= BAR0_SIZE) {
            fprintf(stderr, "Offset must be 32-bit aligned and below 0x%x\n", BAR0_SIZE);
            return 2;
        }
        printf("0x%08x\n", reg_read(bar, offset));
    } else if (strcmp(argv[1], "write") == 0 && argc == 4) {
        offset = strtoul(argv[2], NULL, 0);
        value = strtoul(argv[3], NULL, 0);
        if ((offset & 3) || offset >= BAR0_SIZE) {
            fprintf(stderr, "Offset must be 32-bit aligned and below 0x%x\n", BAR0_SIZE);
            return 2;
        }
        reg_write(bar, offset, (uint32_t)value);
        printf("0x%08x\n", reg_read(bar, offset));
    } else {
        usage(argv[0]);
        return 2;
    }

    munmap((void *)bar, BAR0_SIZE);
    close(fd);
    free(device_path);
    return 0;
}
