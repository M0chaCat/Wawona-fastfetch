#include "litehook.h"
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#if __arm64__
#include <ptrauth.h>
#else
#define ptrauth_strip(ptr, key) (ptr)
#define ptrauth_auth_and_resign(ptr, key, s1, s2, s3) (ptr)
#define ptrauth_auth_function(ptr, key, s1) (ptr)
#endif

typedef struct {
    const mach_header_u *sourceHeader;
    void *replacee;
    void *replacement;
    bool (*exceptionFilter)(const mach_header_u *header);
} global_rebind;

uint32_t gRebindCount = 0;
global_rebind *gRebinds = NULL;

static void _litehook_rebind_symbol_in_section(const mach_header_u *targetHeader, section_u *section, void *replacee, void *replacement) {
    unsigned long sectionSize = 0;
    uint8_t *sectionStart = getsectiondata(targetHeader, section->segname, section->sectname, &sectionSize);
    if (!sectionStart) return;

    void **symbolPointers = (void **)sectionStart;
    void *stripped_replacee = ptrauth_strip(replacee, 0);

    for (uint32_t i = 0; i < (sectionSize / sizeof(void *)); i++) {
        void *current = ptrauth_strip(symbolPointers[i], 0);
        if (current == stripped_replacee) {
            vm_protect(mach_task_self(), (mach_vm_address_t)&symbolPointers[i], sizeof(void *), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
            symbolPointers[i] = ptrauth_strip(replacement, 0);
            vm_protect(mach_task_self(), (mach_vm_address_t)&symbolPointers[i], sizeof(void *), false, PROT_READ);
        }
    }
}

__attribute__((visibility("default")))
void litehook_rebind_symbol(const mach_header_u *targetHeader, void *replacee, void *replacement, bool (*exceptionFilter)(const mach_header_u *header)) {
    if (targetHeader == LITEHOOK_REBIND_GLOBAL) {
        // Global rebind setup
        Dl_info info;
        if (dladdr(replacement, &info) == 0) return;
        
        gRebinds = realloc(gRebinds, sizeof(global_rebind) * ++gRebindCount);
        gRebinds[gRebindCount-1] = (global_rebind){NULL, replacee, replacement, exceptionFilter};
        
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            litehook_rebind_symbol((const mach_header_u *)_dyld_get_image_header(i), replacee, replacement, exceptionFilter);
        }
    } else {
        // Rebind in specific header
        struct load_command *lcp = (void *)((uintptr_t)targetHeader + sizeof(mach_header_u));
        for(int i = 0; i < targetHeader->ncmds; i++) {
            if (lcp->cmd == LC_SEGMENT_U) {
                segment_command_u *segCmd = (segment_command_u *)lcp;
                if (strncmp(segCmd->segname, "__DATA", 6) == 0 || strncmp(segCmd->segname, "__AUTH", 6) == 0) {
                    section_u *sections = (void *)((uintptr_t)lcp + sizeof(segment_command_u));
                    for (int j = 0; j < segCmd->nsects; j++) {
                        uint32_t type = sections[j].flags & SECTION_TYPE;
                        if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                            _litehook_rebind_symbol_in_section(targetHeader, &sections[j], replacee, replacement);
                        }
                    }
                }
            }
            lcp = (void *)((uintptr_t)lcp + lcp->cmdsize);
        }
    }
}
