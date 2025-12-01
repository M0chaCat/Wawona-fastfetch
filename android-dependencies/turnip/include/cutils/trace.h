#ifndef ANDROID_CUTILS_TRACE_H
#define ANDROID_CUTILS_TRACE_H
#define ATRACE_TAG 0
#define ATRACE_TAG_GRAPHICS 0
static inline void atrace_begin(unsigned long long tag, const char* name) { (void)tag; (void)name; }
static inline void atrace_end(unsigned long long tag) { (void)tag; }
static inline void atrace_init(void) {}
#define ATRACE_BEGIN(x) atrace_begin(ATRACE_TAG, x)
#define ATRACE_END() atrace_end(ATRACE_TAG)
#endif
