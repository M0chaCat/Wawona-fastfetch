#import "WawonaUIHelpers.h"

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR

@interface NSObject (UIGlassEffectPrivate)
+ (UIVisualEffect *)effectWithStyle:(NSInteger)style;
@end

@implementation WawonaUIHelpers

+ (UIButton *)createLiquidGlassButtonWithImage:(UIImage *)image target:(id)target action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        if ([UIButtonConfiguration respondsToSelector:@selector(glassButtonConfiguration)]) {
            UIButtonConfiguration *config = [UIButtonConfiguration performSelector:@selector(glassButtonConfiguration)];
            config.image = image;
            config.baseForegroundColor = [UIColor whiteColor];
            config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleLarge];
            button.configuration = config;
        } else {
            Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
            if (glassEffectClass) {
                UIVisualEffect *glassEffect = [glassEffectClass effectWithStyle:1];
                UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:glassEffect];
                glassView.userInteractionEnabled = NO;
                glassView.layer.cornerRadius = 25.0;
                glassView.clipsToBounds = YES;
                glassView.frame = CGRectMake(0, 0, 50, 50);
                glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [button insertSubview:glassView atIndex:0];
            } else {
                [self applyFallbackBlurToButton:button];
            }
        }
    } else {
        [self applyFallbackBlurToButton:button];
    }
#else
    [self applyFallbackBlurToButton:button];
#endif

    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];

    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 4);
    button.layer.shadowOpacity = 0.3;
    button.layer.shadowRadius = 8.0;

    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (void)applyFallbackBlurToButton:(UIButton *)button {
    UIBlurEffectStyle style = UIBlurEffectStyleRegular;
    if (@available(iOS 13.0, *)) {
        style = UIBlurEffectStyleSystemThinMaterialDark;
    }

    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:style];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.userInteractionEnabled = NO;
    blurView.layer.cornerRadius = 25.0;
    blurView.clipsToBounds = YES;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.frame = CGRectMake(0, 0, 50, 50);

    blurView.layer.borderWidth = 1.0;
    blurView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;

    [button insertSubview:blurView atIndex:0];
}

@end

#endif
