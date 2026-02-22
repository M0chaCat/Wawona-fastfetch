#import <UIKit/UIKit.h>

@interface WWNSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property(strong, nonatomic) UIWindow *window;

/// The intermediate container that holds all Wayland surface views.
/// It is pinned either to the safe area (Respect Safe Area = ON)
/// or to the full screen edges (OFF).
@property(strong, nonatomic) UIView *compositorContainer;

/// Re-evaluate constraints and output size for the current
/// Respect Safe Area preference.  Called on init and on toggle.
- (void)applyRespectSafeAreaPreference;

@end
