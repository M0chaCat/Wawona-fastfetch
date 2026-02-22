#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * WWNCompositorView_ios
 *
 * An iOS view that represents a Wayland surface.
 * It uses a CALayer for content rendering (bridged from Rust/IOSurface)
 * and translates UIKit touches to Wayland pointer events.
 *
 * Conforms to UITextInput for full IME/autocorrect/dictation support
 * (when Text Assist is enabled in settings) and UIKeyInput as fallback.
 */
@interface WWNCompositorView_ios : UIView <UITextInput>

/// The Wayland window ID associated with this view
@property(nonatomic, assign) uint64_t wwnWindowId;

/// Access to the content layer for rendering
@property(nonatomic, strong, readonly) CALayer *contentLayer;

/// Whether the keyboard is currently active for this view
@property(nonatomic, assign, readonly) BOOL keyboardActive;

/// Show the iOS virtual keyboard for this view
- (void)activateKeyboard;

/// Hide the iOS virtual keyboard for this view
- (void)deactivateKeyboard;

/// Update the Wayland cursor image displayed in touchpad mode.
/// Pass nil to hide the cursor.
- (void)updateCursorImage:(nullable id)image
                    width:(uint32_t)width
                   height:(uint32_t)height
                 hotspotX:(float)hotspotX
                 hotspotY:(float)hotspotY;

@end

NS_ASSUME_NONNULL_END
