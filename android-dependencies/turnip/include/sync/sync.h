#ifndef ANDROID_SYNC_SYNC_H
#define ANDROID_SYNC_SYNC_H
static inline int sync_wait(int fd, int timeout) { (void)fd; (void)timeout; return 0; }
#endif
