//
//  WawonaMacOSPopup.h
//  Wawona
//
//  Wraps NSPopover to provide a Wayland-compatible popup surface.
//

#import "WawonaPopupHost.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WawonaMacOSPopup : NSObject <WawonaPopupHost, NSPopoverDelegate>

@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, assign) uint64_t windowId;

@end

NS_ASSUME_NONNULL_END
