//
//  WawonaMacOSWindowPopup.h
//  Wawona
//
//  Created by Wawona Agent.
//

#import "WawonaPopupHost.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WawonaMacOSWindowPopup : NSObject <WawonaPopupHost>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, assign) uint64_t windowId;

@end

NS_ASSUME_NONNULL_END
