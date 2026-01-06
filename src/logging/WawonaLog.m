/**
 * WawonaLog.m
 * Wawona Unified Logging System (Objective-C Implementation)
 */

#import "WawonaLog.h"
#include <time.h>

void WawonaLogImpl(NSString *module, NSString *format, ...) {
    // Get current timestamp
    time_t now;
    struct tm *tm_info;
    char time_str[64];
    
    time(&now);
    tm_info = localtime(&now);
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
    
    // Format the message
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Output: YYYY-MM-DD HH:MM:SS [MODULE] message
    // Use fprintf to avoid NSLog's own timestamp
    fprintf(stdout, "%s [%s] %s\n", time_str, [module UTF8String], [message UTF8String]);
    fflush(stdout);
    
#if DEBUG
    // Also log to system log in debug builds
    NSLog(@"[%@] %@", module, message);
#endif
}

