#ifndef ANDROID_LOG_LOG_H
#define ANDROID_LOG_LOG_H
#include <android/log.h>
#ifndef ALOGE
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, "mesa", __VA_ARGS__)
#endif
#ifndef ALOGW
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, "mesa", __VA_ARGS__)
#endif
#ifndef ALOGI
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, "mesa", __VA_ARGS__)
#endif
#ifndef LOG_PRI
#define LOG_PRI(priority, tag, fmt, ...) __android_log_print(priority, tag, fmt, ##__VA_ARGS__)
#endif
#endif
