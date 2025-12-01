#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface WawonaUIHelpers : NSObject
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
+ (UIButton *)createLiquidGlassButtonWithImage:(UIImage *)image target:(id)target action:(SEL)action;
#endif
@end

NS_ASSUME_NONNULL_END
