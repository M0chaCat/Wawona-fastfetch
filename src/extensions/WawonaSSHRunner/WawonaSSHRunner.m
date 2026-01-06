#import <Foundation/Foundation.h>

// Forward declare the HIAHKernel extension handler class
// This class is provided by the linked HIAHKernel library
@interface HIAHExtensionHandler : NSObject
@end

// Force the linker to include the HIAHExtensionHandler class from the static
// library Since it is only referenced by string in Info.plist, it might be
// stripped otherwise
@interface WawonaForceLinks : NSObject
@end

@implementation WawonaForceLinks
+ (void)load {
  // Reference the class to prevent stripping
  [HIAHExtensionHandler class];
  NSLog(@"[WawonaSSHRunner] WawonaForceLinks loaded - HIAHExtensionHandler "
        @"linked");
}
@end

// Note: The extension entry point is assumed to be handled by the system
// loading the principal class or by _NSExtensionMain provided by the HIAHKernel
// library if it exports it. If the build config specifies -e _NSExtensionMain,
// it expects that symbol. If HIAHKernel library does not export
// _NSExtensionMain, we might need a stub here. However, typically extensions
// use the default main.
