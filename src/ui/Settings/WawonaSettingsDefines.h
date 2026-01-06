#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WawonaSettingType) {
  WSettingSwitch,
  WSettingText,
  WSettingNumber,
  WSettingPopup,
  WSettingButton,
  WSettingInfo,
  WSettingPassword,
  WSettingLink,       // Clickable URL link
  WSettingHeader      // Header with image (for About section)
};
