#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <linux/random.h>
#include <sys/syscall.h>
#include <errno.h>
#endif

void randombytes(uint8_t *buf, uint64_t len) {
#ifdef __ANDROID__
    while (len > 0) {
        ssize_t n = syscall(SYS_getrandom, buf, len, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            int fd = open("/dev/urandom", O_RDONLY);
            if (fd < 0) return;
            while (len > 0) {
                n = read(fd, buf, len);
                if (n <= 0) break;
                buf += n;
                len -= (uint64_t)n;
            }
            close(fd);
            return;
        }
        buf += n;
        len -= (uint64_t)n;
    }
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return;
    while (len > 0) {
        ssize_t n = read(fd, buf, len);
        if (n <= 0) break;
        buf += n;
        len -= (uint64_t)n;
    }
    close(fd);
#endif
}
