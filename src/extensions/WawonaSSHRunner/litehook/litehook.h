#ifndef LITEHOOK_H
#define LITEHOOK_H

#include <stdio.h>
#include <stdbool.h>
#include <mach/mach.h>
#include <mach-o/loader.h>

#ifdef __arm64__
typedef struct mach_header_64 mach_header_u;
typedef struct segment_command_64 segment_command_u;
typedef struct section_64 section_u;
typedef struct nlist_64 nlist_u;
#define LC_SEGMENT_U LC_SEGMENT_64
#else
typedef struct mach_header mach_header_u;
typedef struct segment_command segment_command_u;
typedef struct section section_u;
typedef struct nlist nlist_u;
#define LC_SEGMENT_U LC_SEGMENT
#endif

void *litehook_find_symbol(const mach_header_u *header, const char *symbolName);
void *litehook_find_symbol_file(const mach_header_u *header, const char *symbolName);
kern_return_t litehook_hook_function(void *source, void *target);

#define LITEHOOK_REBIND_GLOBAL NULL
void litehook_rebind_symbol(const mach_header_u * _Nullable targetHeader, void *replacee, void *replacement, bool (* _Nullable exceptionFilter)(const mach_header_u *header));

#define DEFINE_HOOK(func, return_type, signature) \
    static return_type (*orig_##func) signature = (return_type (*) signature)func; \
    static return_type hook_##func signature

#define DO_HOOK_GLOBAL(func) \
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, (void *)func, (void *)hook_##func, nil)

#define ORIG_FUNC(func) \
    orig_##func

#endif
