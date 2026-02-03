/**
 * WawonaLog.m
 * Wawona Unified Logging System (Objective-C Implementation)
 */

#import "WawonaLog.h"
#include "logging.h"

void WawonaLogImpl(NSString *module, NSString *format, ...) {
  // Format the message
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  // Use the unified C logging function
  wawona_log([module UTF8String], "%s", [message UTF8String]);
}
