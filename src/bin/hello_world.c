#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((visibility("default")))
int hello_entry(int argc, char *argv[]) {
    NSLog(@"--- Hello from Wawona Dynamic Library (NSLog)! ---");
    NSLog(@"PID: %d", getpid());
    NSLog(@"UID: %d, GID: %d", getuid(), getgid());
    
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd)) != NULL) {
        NSLog(@"CWD: %s", cwd);
    }
    
    NSLog(@"Arguments:");
    for (int i = 0; i < argc; i++) {
        NSLog(@"  argv[%d]: %s", i, argv[i]);
    }
    
    printf("--- Hello from Wawona Dynamic Library (printf)! ---\n");
    return 0;
}

int main(int argc, char *argv[]) {
    return hello_entry(argc, argv);
}
