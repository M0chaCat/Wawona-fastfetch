//
//  WWNPopupWindow.h
//  WWN
//
//  Borderless NSWindow-based popup for Wayland xdg_popup.
//  Replaces NSPopover for proper popup semantics (render outside parent bounds).
//

#import "WWNPopupHost.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WWNPopupWindow : NSObject <WWNPopupHost>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, assign) uint64_t windowId;

@end

NS_ASSUME_NONNULL_END
