#import "WawonaSettingsDefines.h"
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

@interface WawonaSettingItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *desc;
@property(nonatomic, assign) WawonaSettingType type;
@property(nonatomic, strong) id defaultValue;
@property(nonatomic, strong) NSArray *options;
@property(nonatomic, copy) void (^actionBlock)(void);
@property(nonatomic, copy) NSString *urlString; // For WSettingLink type
@property(nonatomic, copy)
    NSString *imageURL; // For WSettingHeader type (remote image)
@property(nonatomic, copy)
    NSString *imageName; // For WSettingHeader type (local asset)
@property(nonatomic, copy)
    NSString *iconURL; // For WSettingLink type (small icon)

+ (instancetype)itemWithTitle:(NSString *)title
                          key:(NSString *)key
                         type:(WawonaSettingType)type
                      default:(id)def
                         desc:(NSString *)desc;
@end

@interface WawonaPreferencesSection : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *icon;
#if TARGET_OS_IPHONE
@property(nonatomic, strong) UIColor *iconColor;
#else
@property(nonatomic, strong) NSColor *iconColor;
#endif
@property(nonatomic, strong) NSArray<WawonaSettingItem *> *items;
@end
