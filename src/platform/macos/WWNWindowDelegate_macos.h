// WWNWindowDelegate_macos.h - macOS window delegate methods
// Extracted from WWNCompositor.m for better organization

#pragma once

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@class WWNCompositor;

// Window delegate category methods
@interface WWNCompositor (WindowDelegate)

- (BOOL)windowShouldClose:(NSWindow *)sender;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)windowDidEnterFullScreen:(NSNotification *)notification;
- (void)windowDidExitFullScreen:(NSNotification *)notification;
- (void)windowDidResize:(NSNotification *)notification;

@end

#endif // !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

