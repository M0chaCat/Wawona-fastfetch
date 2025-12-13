#import "WawonaPreferences.h"
#import "WawonaPreferencesManager.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <net/if.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
// iOS: Full implementation with table view
#import "WawonaAboutPanel.h"

@interface WawonaPreferences () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *settingsSections;
@end

@implementation WawonaPreferences

+ (instancetype)sharedPreferences {
    static WawonaPreferences *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"Wawona Settings";
        self.modalPresentationStyle = UIModalPresentationPageSheet;
        [self loadSettingsFromBundle];
    }
    return self;
}

- (void)loadSettingsFromBundle {
    NSMutableArray *sections = [NSMutableArray array];
    
    NSString *settingsBundlePath = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSString *rootPlistPath = [settingsBundlePath stringByAppendingPathComponent:@"Root.plist"];
    NSDictionary *rootDict = [NSDictionary dictionaryWithContentsOfFile:rootPlistPath];
    NSArray *specifiers = rootDict[@"PreferenceSpecifiers"];
    
    NSMutableDictionary *currentSection = nil;
    NSMutableArray *currentItems = nil;
    
    for (NSDictionary *specifier in specifiers) {
        NSString *type = specifier[@"Type"];
        
        if ([type isEqualToString:@"PSGroupSpecifier"]) {
            // Start new section
            if (currentSection) {
                currentSection[@"items"] = [currentItems copy];
                [sections addObject:[currentSection copy]];
            }
            currentSection = [NSMutableDictionary dictionary];
            currentItems = [NSMutableArray array];
            currentSection[@"title"] = specifier[@"Title"] ? specifier[@"Title"] : @"";
        } else if ([type isEqualToString:@"PSToggleSwitchSpecifier"]) {
            // Switch item
            if (!currentSection) {
                currentSection = [NSMutableDictionary dictionary];
                currentItems = [NSMutableArray array];
                currentSection[@"title"] = @"General";
            }
            [currentItems addObject:@{
                @"title": specifier[@"Title"],
                @"key": specifier[@"Key"],
                @"type": @"switch",
                @"default": specifier[@"DefaultValue"] ? specifier[@"DefaultValue"] : @NO
            }];
        } else if ([type isEqualToString:@"PSTextFieldSpecifier"]) {
             // Text field item
             [currentItems addObject:@{
                @"title": specifier[@"Title"],
                @"key": specifier[@"Key"],
                @"type": @"textfield",
                @"keyboard": specifier[@"KeyboardType"] ? specifier[@"KeyboardType"] : @"Alphabet"
            }];
        }
    }
    
    // Add last section
    if (currentSection) {
        currentSection[@"items"] = [currentItems copy];
        [sections addObject:[currentSection copy]];
    }
    
    // Append manual About section
    [sections addObject:@{
        @"title": @"About",
        @"items": @[
            @{@"title": @"Version", @"key": @"version", @"type": @"info"},
            @{@"title": @"About Wawona", @"key": @"about", @"type": @"button"}
        ]
    }];
    
    self.settingsSections = sections;
}

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Create table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    
    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add close button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] 
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self
        action:@selector(dismissSettings:)];
}

- (void)dismissSettings:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.settingsSections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.settingsSections[section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *items = self.settingsSections[section][@"items"];
    return items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *items = self.settingsSections[indexPath.section][@"items"];
    NSDictionary *item = items[indexPath.row];
    NSString *type = item[@"type"];
    NSString *title = item[@"title"];
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SettingsCell"];
    }
    
    // Reset all cell properties to avoid reuse issues
    cell.textLabel.text = title;
    cell.detailTextLabel.text = nil; // Clear detail text to prevent version from appearing in reused cells
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    if ([type isEqualToString:@"switch"]) {
        NSString *key = item[@"key"];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // Get value from defaults, or use bundle default if not set
        BOOL value = NO;
        if ([defaults objectForKey:key]) {
            value = [defaults boolForKey:key];
        } else {
            value = [item[@"default"] boolValue];
        }
        
        UISwitch *switchView = [[UISwitch alloc] init];
        switchView.on = value;
        [switchView addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
        switchView.tag = indexPath.section * 1000 + indexPath.row;
        cell.accessoryView = switchView;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"textfield"]) {
        NSString *key = item[@"key"];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 100, 30)];
        textField.textAlignment = NSTextAlignmentRight;
        textField.textColor = [UIColor secondaryLabelColor];
        if ([item[@"keyboard"] isEqualToString:@"NumberPad"]) {
            textField.keyboardType = UIKeyboardTypeNumberPad;
        }
        
        // Value
        if ([defaults objectForKey:key]) {
            if ([item[@"keyboard"] isEqualToString:@"NumberPad"]) {
                textField.text = [NSString stringWithFormat:@"%ld", (long)[defaults integerForKey:key]];
            } else {
                textField.text = [defaults stringForKey:key];
            }
        } else {
            textField.text = @"";
        }
        
        [textField addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
        textField.tag = indexPath.section * 1000 + indexPath.row;
        
        cell.accessoryView = textField;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"info"]) {
        // Only set version for info type cells
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (version) {
            // Format as v0.0.1 (build)
            cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@ (%@)", version, build ? build : @"1"];
        } else {
            cell.detailTextLabel.text = @"Unknown";
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"button"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    return cell;
}

- (void)switchValueChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;
    NSArray *items = self.settingsSections[section][@"items"];
    NSDictionary *item = items[row];
    NSString *key = item[@"key"];
    
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)textFieldChanged:(UITextField *)sender {
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;
    NSArray *items = self.settingsSections[section][@"items"];
    NSDictionary *item = items[row];
    NSString *key = item[@"key"];
    
    if ([item[@"keyboard"] isEqualToString:@"NumberPad"]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.text integerValue] forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:sender.text forKey:key];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSArray *items = self.settingsSections[indexPath.section][@"items"];
    NSDictionary *item = items[indexPath.row];
    NSString *key = item[@"key"];
    
    if ([key isEqualToString:@"about"]) {
        WawonaAboutPanel *aboutPanel = [[WawonaAboutPanel alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:aboutPanel];
        [self presentViewController:navController animated:YES completion:nil];
    }
}

- (void)showPreferences:(id)sender {
    UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    if (rootViewController) {
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self];
        navController.modalPresentationStyle = UIModalPresentationPageSheet;
        [rootViewController presentViewController:navController animated:YES completion:nil];
    }
}

@end

#else

// macOS Implementation with Modern Sidebar Style (Tahoe + 26)

@class WawonaPreferencesContentViewController;

// MARK: - Models

@interface WawonaPreferencesItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, strong) NSColor *iconColor;
@end

@implementation WawonaPreferencesItem
@end

// MARK: - Sidebar View Controller

@interface WawonaPreferencesSidebarViewController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource>
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSArray<WawonaPreferencesItem *> *items;
@property (nonatomic, copy) void (^selectionHandler)(NSString *identifier);
@end

@implementation WawonaPreferencesSidebarViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 500)];
    
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.drawsBackground = NO;
    
    self.outlineView = [[NSOutlineView alloc] initWithFrame:scrollView.bounds];
    self.outlineView.delegate = self;
    self.outlineView.dataSource = self;
    self.outlineView.headerView = nil;
    self.outlineView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
    self.outlineView.backgroundColor = [NSColor clearColor];
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"MainColumn"];
    [self.outlineView addTableColumn:column];
    self.outlineView.outlineTableColumn = column;
    
    scrollView.documentView = self.outlineView;
    [self.view addSubview:scrollView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupItems];
    [self.outlineView reloadData];
    
    // Select first item by default
    if (self.items.count > 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (void)setupItems {
    NSMutableArray *items = [NSMutableArray array];
    
    WawonaPreferencesItem *display = [[WawonaPreferencesItem alloc] init];
    display.title = @"Display";
    display.identifier = @"display";
    display.icon = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Display"];
    display.iconColor = [NSColor systemBlueColor];
    [items addObject:display];
    
    WawonaPreferencesItem *input = [[WawonaPreferencesItem alloc] init];
    input.title = @"Input";
    input.identifier = @"input";
    input.icon = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"Input"];
    input.iconColor = [NSColor systemPurpleColor];
    [items addObject:input];

    WawonaPreferencesItem *graphics = [[WawonaPreferencesItem alloc] init];
    graphics.title = @"Graphics";
    graphics.identifier = @"graphics";
    graphics.icon = [NSImage imageWithSystemSymbolName:@"cpu" accessibilityDescription:@"Graphics"];
    graphics.iconColor = [NSColor systemRedColor];
    [items addObject:graphics];

    WawonaPreferencesItem *network = [[WawonaPreferencesItem alloc] init];
    network.title = @"Network";
    network.identifier = @"network";
    network.icon = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:@"Network"];
    network.iconColor = [NSColor systemOrangeColor];
    [items addObject:network];
    
    WawonaPreferencesItem *advanced = [[WawonaPreferencesItem alloc] init];
    advanced.title = @"Advanced";
    advanced.identifier = @"advanced";
    advanced.icon = [NSImage imageWithSystemSymbolName:@"gearshape.2" accessibilityDescription:@"Advanced"];
    advanced.iconColor = [NSColor systemGrayColor];
    [items addObject:advanced];
    
    WawonaPreferencesItem *waypipe = [[WawonaPreferencesItem alloc] init];
    waypipe.title = @"Waypipe";
    waypipe.identifier = @"waypipe";
    waypipe.icon = [NSImage imageWithSystemSymbolName:@"network" accessibilityDescription:@"Waypipe"];
    waypipe.iconColor = [NSColor systemGreenColor];
    [items addObject:waypipe];
    
    self.items = items;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return item == nil ? self.items.count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item == nil ? self.items[index] : nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return NO;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([item isKindOfClass:[WawonaPreferencesItem class]]) {
        WawonaPreferencesItem *prefItem = (WawonaPreferencesItem *)item;
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"Cell" owner:self];
        
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 30)];
            cell.identifier = @"Cell";
            
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 6, 18, 18)];
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            imageView.tag = 100;
            [cell addSubview:imageView];
            
            NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(26, 6, 170, 18)];
            textField.bordered = NO;
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.tag = 101;
            [cell addSubview:textField];
        }
        
        NSImageView *img = [cell viewWithTag:100];
        NSTextField *txt = [cell viewWithTag:101];
        
        img.image = prefItem.icon;
        img.contentTintColor = prefItem.iconColor;
        txt.stringValue = prefItem.title;
        
        return cell;
    }
    return nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [self.outlineView selectedRow];
    if (row >= 0 && row < (NSInteger)self.items.count) {
        if (self.selectionHandler) {
            self.selectionHandler(self.items[row].identifier);
        }
    }
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    return 32.0;
}

@end

// MARK: - Content View Controller

@interface WawonaPreferencesContentViewController : NSViewController <NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSStackView *stackView;

// Properties for bindings/updates
@property (nonatomic, strong) NSButton *forceServerSideDecorationsCheckbox;
@property (nonatomic, strong) NSButton *renderMacOSPointerCheckbox;
@property (nonatomic, strong) NSButton *autoScaleCheckbox;
@property (nonatomic, strong) NSButton *respectSafeAreaCheckbox;
@property (nonatomic, strong) NSButton *swapCmdWithAltCheckbox;
@property (nonatomic, strong) NSButton *universalClipboardCheckbox;
@property (nonatomic, strong) NSButton *colorOperationsCheckbox;
@property (nonatomic, strong) NSButton *nestedCompositorsCheckbox;
@property (nonatomic, strong) NSButton *multipleClientsCheckbox;

// Graphics
@property (nonatomic, strong) NSButton *vulkanDriversCheckbox;
@property (nonatomic, strong) NSButton *eglDriversCheckbox;
@property (nonatomic, strong) NSButton *dmabufCheckbox;

// Network
@property (nonatomic, strong) NSButton *tcpListenerCheckbox;
@property (nonatomic, strong) NSTextField *tcpPortField;
@property (nonatomic, strong) NSTextField *socketDirField;
@property (nonatomic, strong) NSTextField *displayNumField;

@property (nonatomic, strong) NSTextField *waypipeDisplayField;
@property (nonatomic, strong) NSTextField *waypipeSocketField;
@property (nonatomic, strong) NSPopUpButton *waypipeCompressPopup;
@property (nonatomic, strong) NSTextField *waypipeCompressLevelField;
@property (nonatomic, strong) NSTextField *waypipeThreadsField;
@property (nonatomic, strong) NSPopUpButton *waypipeVideoPopup;
@property (nonatomic, strong) NSPopUpButton *waypipeVideoEncodingPopup;
@property (nonatomic, strong) NSPopUpButton *waypipeVideoDecodingPopup;
@property (nonatomic, strong) NSTextField *waypipeVideoBpfField;
@property (nonatomic, strong) NSButton *waypipeSSHEnabledCheckbox;
@property (nonatomic, strong) NSTextField *waypipeSSHHostField;
@property (nonatomic, strong) NSTextField *waypipeSSHUserField;
@property (nonatomic, strong) NSTextField *waypipeSSHBinaryField;
@property (nonatomic, strong) NSTextField *waypipeRemoteCommandField;
@property (nonatomic, strong) NSTextView *waypipeCustomScriptTextView;
@property (nonatomic, strong) NSButton *waypipeDebugCheckbox;
@property (nonatomic, strong) NSButton *waypipeNoGpuCheckbox;
@property (nonatomic, strong) NSButton *waypipeOneshotCheckbox;
@property (nonatomic, strong) NSButton *waypipeUnlinkSocketCheckbox;
@property (nonatomic, strong) NSButton *waypipeLoginShellCheckbox;
@property (nonatomic, strong) NSButton *waypipeVsockCheckbox;
@property (nonatomic, strong) NSButton *waypipeXwlsCheckbox;
@property (nonatomic, strong) NSTextField *waypipeTitlePrefixField;
@property (nonatomic, strong) NSTextField *waypipeSecCtxField;

- (void)showSection:(NSString *)identifier;

@end

@implementation WawonaPreferencesContentViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)];
    
    self.scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    
    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)];
    documentView.autoresizingMask = NSViewWidthSizable;
    
    self.stackView = [[NSStackView alloc] initWithFrame:documentView.bounds];
    self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stackView.alignment = NSLayoutAttributeLeading;
    self.stackView.spacing = 20;
    self.stackView.edgeInsets = NSEdgeInsetsMake(20, 40, 20, 40);
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [documentView addSubview:self.stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor]
    ]];
    
    self.scrollView.documentView = documentView;
    [self.view addSubview:self.scrollView];
}

- (void)showSection:(NSString *)identifier {
    // Clear existing views
    for (NSView *view in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    
    // Build new section
    if ([identifier isEqualToString:@"display"]) {
        [self buildDisplaySection];
    } else if ([identifier isEqualToString:@"input"]) {
        [self buildInputSection];
    } else if ([identifier isEqualToString:@"graphics"]) {
        [self buildGraphicsSection];
    } else if ([identifier isEqualToString:@"network"]) {
        [self buildNetworkSection];
    } else if ([identifier isEqualToString:@"advanced"]) {
        [self buildAdvancedSection];
    } else if ([identifier isEqualToString:@"waypipe"]) {
        [self buildWaypipeSection];
    }
    
    // Refresh data
    [self loadPreferences];
}

// MARK: - Section Builders

- (void)buildDisplaySection {
    [self addSectionTitle:@"Display"];
    
    NSButton *ssd;
    [self addCheckbox:@"Force Server-Side Decorations"
          description:@"Forces Wayland clients to use macOS-style window decorations (titlebar, controls)."
               action:@selector(forceServerSideDecorationsChanged:)
             checkbox:&ssd];
    self.forceServerSideDecorationsCheckbox = ssd;
    
    NSButton *cursor;
    [self addCheckbox:@"Show macOS Cursor"
          description:@"Toggles the visibility of the macOS cursor when the application is focused."
               action:@selector(renderMacOSPointerChanged:)
             checkbox:&cursor];
    self.renderMacOSPointerCheckbox = cursor;
    
    NSButton *scale;
    [self addCheckbox:@"Auto Scale"
          description:@"Detects and matches macOS UI Scaling."
               action:@selector(autoScaleChanged:)
             checkbox:&scale];
    self.autoScaleCheckbox = scale;

    NSButton *safe;
    [self addCheckbox:@"Respect Safe Area"
          description:@"Avoids rendering content in notch/camera housing areas."
               action:@selector(respectSafeAreaChanged:)
             checkbox:&safe];
    self.respectSafeAreaCheckbox = safe;
}

- (void)buildInputSection {
    [self addSectionTitle:@"Input"];
    
    NSButton *swap;
    [self addCheckbox:@"Swap CMD with ALT"
          description:@"Swaps Command (⌘) and Alt (⌥) keys. Useful for Linux/Windows layouts."
               action:@selector(swapCmdWithAltChanged:)
             checkbox:&swap];
    self.swapCmdWithAltCheckbox = swap;
    
    NSButton *clipboard;
    [self addCheckbox:@"Universal Clipboard"
          description:@"Enables clipboard synchronization between Wawona and macOS."
               action:@selector(universalClipboardChanged:)
             checkbox:&clipboard];
    self.universalClipboardCheckbox = clipboard;
}

- (void)buildGraphicsSection {
    [self addSectionTitle:@"Graphics"];
    
    NSButton *vulkan;
    [self addCheckbox:@"Enable Vulkan Drivers"
          description:@"Enables experimental Vulkan driver support."
               action:@selector(vulkanDriversChanged:)
             checkbox:&vulkan];
    self.vulkanDriversCheckbox = vulkan;
    
    NSButton *egl;
    [self addCheckbox:@"Enable EGL Drivers"
          description:@"Enables EGL for hardware accelerated rendering."
               action:@selector(eglDriversChanged:)
             checkbox:&egl];
    self.eglDriversCheckbox = egl;
    
    NSButton *dmabuf;
    [self addCheckbox:@"Enable DMABUF"
          description:@"Enables zero-copy texture sharing via IOSurface."
               action:@selector(dmabufChanged:)
             checkbox:&dmabuf];
    self.dmabufCheckbox = dmabuf;
}

- (void)buildNetworkSection {
    [self addSectionTitle:@"Network & Ports"];
    
    NSButton *tcp;
    [self addCheckbox:@"Enable TCP Listener"
          description:@"Allows external connections via TCP."
               action:@selector(tcpListenerChanged:)
             checkbox:&tcp];
    self.tcpListenerCheckbox = tcp;
    
    NSTextField *port;
    [self addTextField:@"TCP Listener Port"
           description:@"Port number for TCP listener."
               default:@"6000"
                  icon:@"network"
                 field:&port];
    self.tcpPortField = port;
    
    NSTextField *sock;
    [self addTextField:@"Wayland Socket Directory"
           description:@"Directory for Wayland sockets."
               default:@"/tmp"
                  icon:@"folder"
                 field:&sock];
    self.socketDirField = sock;
    
    NSTextField *disp;
    [self addTextField:@"Display Number"
           description:@"Wayland display number (e.g., 0 for wayland-0)."
               default:@"0"
                  icon:@"display"
                 field:&disp];
    self.displayNumField = disp;
}

- (void)buildAdvancedSection {
    [self addSectionTitle:@"Advanced"];
    
    NSButton *color;
    [self addCheckbox:@"Color Operations"
          description:@"Enables support for color profiles and HDR."
               action:@selector(colorOperationsChanged:)
             checkbox:&color];
    self.colorOperationsCheckbox = color;
    
    NSButton *nested;
    [self addCheckbox:@"Nested Compositors"
          description:@"Enables support for running other Wayland compositors (e.g., Weston, Plasma)."
               action:@selector(nestedCompositorsChanged:)
             checkbox:&nested];
    self.nestedCompositorsCheckbox = nested;
    
    NSButton *clients;
    [self addCheckbox:@"Multiple Clients"
          description:@"Allows multiple Wayland clients to connect simultaneously."
               action:@selector(multipleClientsChanged:)
             checkbox:&clients];
    self.multipleClientsCheckbox = clients;
}

- (void)buildWaypipeSection {
    [self addSectionTitle:@"Waypipe"];
    
    [self addInfoField:@"Local IP Address" value:[self getLocalIPAddress] icon:@"network"];
    
    NSTextField *display;
    [self addTextField:@"Wayland Display"
           description:@"Socket name (e.g., wayland-0)"
               default:@"wayland-0"
                  icon:@"display"
                 field:&display];
    self.waypipeDisplayField = display;
    
    NSTextField *socket;
    NSString *socketPath = [[WawonaPreferencesManager sharedManager] waypipeSocket];
    [self addTextField:@"Socket Path"
           description:@"Unix socket path (read-only)."
               default:socketPath
                  icon:@"folder"
                 field:&socket];
    [socket setEditable:NO];
    self.waypipeSocketField = socket;
    
    NSPopUpButton *compress;
    [self addPopup:@"Compression"
       description:@"Compression method."
           options:@[@"none", @"lz4", @"zstd"]
           default:@"lz4"
              icon:@"archive"
             popup:&compress];
    self.waypipeCompressPopup = compress;
    
    NSTextField *level;
    [self addTextField:@"Compression Level"
           description:@"Zstd level (1-22)."
               default:@"7"
                  icon:@"slider.horizontal.3"
                 field:&level];
    self.waypipeCompressLevelField = level;
    
    NSTextField *threads;
    [self addTextField:@"Threads"
           description:@"Number of threads (0 = auto)."
               default:@"0"
                  icon:@"cpu"
                 field:&threads];
    self.waypipeThreadsField = threads;
    
    [self addSeparator];
    [self addSectionTitle:@"Video Compression"];
    
    NSPopUpButton *video;
    [self addPopup:@"Video Codec"
       description:@"Lossy video codec for DMABUF."
           options:@[@"none", @"h264", @"vp9", @"av1"]
           default:@"none"
              icon:@"video"
             popup:&video];
    self.waypipeVideoPopup = video;
    
    NSPopUpButton *vEnc;
    [self addPopup:@"Encoding"
       description:@"Hardware vs Software encoding."
           options:@[@"hw", @"sw", @"hwenc", @"swenc"]
           default:@"hw"
              icon:@"gearshape"
             popup:&vEnc];
    self.waypipeVideoEncodingPopup = vEnc;
    
    NSPopUpButton *vDec;
    [self addPopup:@"Decoding"
       description:@"Hardware vs Software decoding."
           options:@[@"hw", @"sw", @"hwdec", @"swdec"]
           default:@"hw"
              icon:@"gearshape"
             popup:&vDec];
    self.waypipeVideoDecodingPopup = vDec;
    
    NSTextField *bpf;
    [self addTextField:@"Bits Per Frame"
           description:@"Target bit rate per frame."
               default:@""
                  icon:@"speedometer"
                 field:&bpf];
    self.waypipeVideoBpfField = bpf;
    
    [self addSeparator];
    [self addSectionTitle:@"SSH"];
    
    NSButton *ssh;
    [self addCheckbox:@"Enable SSH"
          description:@"Use SSH for remote connections."
               action:@selector(waypipeSSHEnabledChanged:)
             checkbox:&ssh];
    self.waypipeSSHEnabledCheckbox = ssh;
    
    NSTextField *host;
    [self addTextField:@"Host" description:@"Remote host address." default:@"" icon:@"server.rack" field:&host];
    self.waypipeSSHHostField = host;
    
    NSTextField *user;
    [self addTextField:@"User" description:@"SSH Username." default:@"" icon:@"person" field:&user];
    self.waypipeSSHUserField = user;
    
    NSTextField *cmd;
    [self addTextField:@"Remote Command" description:@"Command to run remotely." default:@"" icon:@"play.circle" field:&cmd];
    self.waypipeRemoteCommandField = cmd;
    
    [self addSeparator];
    [self addSectionTitle:@"Advanced"];
    
    NSButton *debug;
    [self addCheckbox:@"Debug Mode" description:@"Print debug logs." action:@selector(waypipeDebugChanged:) checkbox:&debug];
    self.waypipeDebugCheckbox = debug;
    
    NSButton *noGpu;
    [self addCheckbox:@"Disable GPU" description:@"Block GPU protocols." action:@selector(waypipeNoGpuChanged:) checkbox:&noGpu];
    self.waypipeNoGpuCheckbox = noGpu;

    NSButton *oneshot;
    [self addCheckbox:@"One-shot" description:@"Exit when the last client disconnects." action:@selector(waypipeOneshotChanged:) checkbox:&oneshot];
    self.waypipeOneshotCheckbox = oneshot;

    NSButton *unlink;
    [self addCheckbox:@"Unlink Socket" description:@"Unlink socket on exit." action:@selector(waypipeUnlinkSocketChanged:) checkbox:&unlink];
    self.waypipeUnlinkSocketCheckbox = unlink;
    
    NSButton *login;
    [self addCheckbox:@"Login Shell" description:@"Run remote command in login shell." action:@selector(waypipeLoginShellChanged:) checkbox:&login];
    self.waypipeLoginShellCheckbox = login;
    
    NSButton *vsock;
    [self addCheckbox:@"VSock" description:@"Use VSock for communication." action:@selector(waypipeVsockChanged:) checkbox:&vsock];
    self.waypipeVsockCheckbox = vsock;
    
    NSButton *xwls;
    [self addCheckbox:@"XWayland Support" description:@"Enable XWayland support." action:@selector(waypipeXwlsChanged:) checkbox:&xwls];
    self.waypipeXwlsCheckbox = xwls;
    
    NSTextField *prefix;
    [self addTextField:@"Title Prefix" description:@"Prefix for window titles." default:@"" icon:@"text.format" field:&prefix];
    self.waypipeTitlePrefixField = prefix;
    
    NSTextField *sec;
    [self addTextField:@"Security Context" description:@"SELinux security context." default:@"" icon:@"lock" field:&sec];
    self.waypipeSecCtxField = sec;
}

// MARK: - UI Helpers

- (void)addSectionTitle:(NSString *)title {
    NSTextField *field = [NSTextField labelWithString:title];
    field.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    [self.stackView addArrangedSubview:field];
}

- (void)addCheckbox:(NSString *)title description:(NSString *)desc action:(SEL)action checkbox:(NSButton **)outBtn {
    NSView *container = [[NSView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSButton *btn = [NSButton checkboxWithTitle:title target:self action:action];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:btn];
    
    NSTextField *descField = [NSTextField labelWithString:desc];
    descField.font = [NSFont systemFontOfSize:11];
    descField.textColor = [NSColor secondaryLabelColor];
    descField.translatesAutoresizingMaskIntoConstraints = NO;
    descField.preferredMaxLayoutWidth = 400;
    [container addSubview:descField];
    
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:container.topAnchor],
        [btn.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [descField.topAnchor constraintEqualToAnchor:btn.bottomAnchor constant:2],
        [descField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:18],
        [descField.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [descField.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    
    [self.stackView addArrangedSubview:container];
    if (outBtn) *outBtn = btn;
}

- (void)addTextField:(NSString *)title description:(NSString *)desc default:(NSString *)def icon:(NSString *)icon field:(NSTextField **)outField {
    NSView *container = [[NSView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSImageView *img = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:icon accessibilityDescription:nil]];
    img.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:img];
    
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    
    NSTextField *textField = [NSTextField textFieldWithString:def];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    textField.delegate = self;
    [container addSubview:textField];
    
    NSTextField *descLabel = [NSTextField labelWithString:desc];
    descLabel.font = [NSFont systemFontOfSize:11];
    descLabel.textColor = [NSColor secondaryLabelColor];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:descLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [img.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [img.topAnchor constraintEqualToAnchor:container.topAnchor constant:2],
        [img.widthAnchor constraintEqualToConstant:16],
        [img.heightAnchor constraintEqualToConstant:16],
        
        [label.leadingAnchor constraintEqualToAnchor:img.trailingAnchor constant:8],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor],
        
        [textField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24],
        [textField.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4],
        [textField.widthAnchor constraintEqualToConstant:200],
        
        [descLabel.leadingAnchor constraintEqualToAnchor:textField.trailingAnchor constant:8],
        [descLabel.centerYAnchor constraintEqualToAnchor:textField.centerYAnchor],
        [descLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        
        [container.bottomAnchor constraintEqualToAnchor:textField.bottomAnchor constant:8]
    ]];
    
    [self.stackView addArrangedSubview:container];
    if (outField) *outField = textField;
}

- (void)addPopup:(NSString *)title description:(NSString *)desc options:(NSArray *)opts default:(NSString *)def icon:(NSString *)icon popup:(NSPopUpButton **)outPopup {
    NSView *container = [[NSView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSImageView *img = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:icon accessibilityDescription:nil]];
    img.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:img];
    
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [popup addItemsWithTitles:opts];
    [popup selectItemWithTitle:def];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.target = self;
    popup.action = @selector(popupValueChanged:);
    [container addSubview:popup];
    
    NSTextField *descLabel = [NSTextField labelWithString:desc];
    descLabel.font = [NSFont systemFontOfSize:11];
    descLabel.textColor = [NSColor secondaryLabelColor];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:descLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [img.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [img.topAnchor constraintEqualToAnchor:container.topAnchor constant:2],
        [img.widthAnchor constraintEqualToConstant:16],
        [img.heightAnchor constraintEqualToConstant:16],
        
        [label.leadingAnchor constraintEqualToAnchor:img.trailingAnchor constant:8],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor],
        
        [popup.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24],
        [popup.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4],
        [popup.widthAnchor constraintEqualToConstant:150],
        
        [descLabel.leadingAnchor constraintEqualToAnchor:popup.trailingAnchor constant:8],
        [descLabel.centerYAnchor constraintEqualToAnchor:popup.centerYAnchor],
        [descLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        
        [container.bottomAnchor constraintEqualToAnchor:popup.bottomAnchor constant:8]
    ]];
    
    [self.stackView addArrangedSubview:container];
    if (outPopup) *outPopup = popup;
}

- (void)addInfoField:(NSString *)title value:(NSString *)value icon:(NSString *)icon {
    NSTextField *f;
    [self addTextField:title description:@"(Read Only)" default:value icon:icon field:&f];
    [f setEditable:NO];
}

- (void)addSeparator {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxSeparator;
    [self.stackView addArrangedSubview:box];
}

// MARK: - Actions

- (void)forceServerSideDecorationsChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setForceServerSideDecorations:sender.state]; }
- (void)renderMacOSPointerChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setRenderMacOSPointer:sender.state]; }
- (void)autoScaleChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setAutoScale:sender.state]; }
- (void)respectSafeAreaChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setRespectSafeArea:sender.state]; }

- (void)swapCmdWithAltChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setSwapCmdWithAlt:sender.state]; }
- (void)universalClipboardChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setUniversalClipboardEnabled:sender.state]; }

- (void)vulkanDriversChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setVulkanDriversEnabled:sender.state]; }
- (void)eglDriversChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setEglDriversEnabled:sender.state]; }
- (void)dmabufChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setDmabufEnabled:sender.state]; }

- (void)tcpListenerChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setEnableTCPListener:sender.state]; }

- (void)colorOperationsChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setColorOperations:sender.state]; }
- (void)nestedCompositorsChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setNestedCompositorsSupportEnabled:sender.state]; }
- (void)multipleClientsChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setMultipleClientsEnabled:sender.state]; }

- (void)waypipeSSHEnabledChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeSSHEnabled:sender.state]; }
- (void)waypipeDebugChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeDebug:sender.state]; }
- (void)waypipeNoGpuChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeNoGpu:sender.state]; }
- (void)waypipeOneshotChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeOneshot:sender.state]; }
- (void)waypipeUnlinkSocketChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeUnlinkSocket:sender.state]; }
- (void)waypipeLoginShellChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeLoginShell:sender.state]; }
- (void)waypipeVsockChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeVsock:sender.state]; }
- (void)waypipeXwlsChanged:(NSButton *)sender { [[WawonaPreferencesManager sharedManager] setWaypipeXwls:sender.state]; }

- (void)popupValueChanged:(NSPopUpButton *)sender {
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    if (sender == self.waypipeCompressPopup) [prefs setWaypipeCompress:sender.selectedItem.title];
    else if (sender == self.waypipeVideoPopup) [prefs setWaypipeVideo:sender.selectedItem.title];
    else if (sender == self.waypipeVideoEncodingPopup) [prefs setWaypipeVideoEncoding:sender.selectedItem.title];
    else if (sender == self.waypipeVideoDecodingPopup) [prefs setWaypipeVideoDecoding:sender.selectedItem.title];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *field = notification.object;
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    
    if (field == self.waypipeDisplayField) [prefs setWaypipeDisplay:field.stringValue];
    else if (field == self.waypipeCompressLevelField) [prefs setWaypipeCompressLevel:field.stringValue];
    else if (field == self.waypipeThreadsField) [prefs setWaypipeThreads:field.stringValue];
    else if (field == self.waypipeVideoBpfField) [prefs setWaypipeVideoBpf:field.stringValue];
    else if (field == self.waypipeSSHHostField) [prefs setWaypipeSSHHost:field.stringValue];
    else if (field == self.waypipeSSHUserField) [prefs setWaypipeSSHUser:field.stringValue];
    else if (field == self.waypipeRemoteCommandField) [prefs setWaypipeRemoteCommand:field.stringValue];
    
    else if (field == self.tcpPortField) [prefs setTCPListenerPort:field.integerValue];
    else if (field == self.socketDirField) [prefs setWaylandSocketDir:field.stringValue];
    else if (field == self.displayNumField) [prefs setWaylandDisplayNumber:field.integerValue];
    
    else if (field == self.waypipeTitlePrefixField) [prefs setWaypipeTitlePrefix:field.stringValue];
    else if (field == self.waypipeSecCtxField) [prefs setWaypipeSecCtx:field.stringValue];
}

- (void)loadPreferences {
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    
    if (self.forceServerSideDecorationsCheckbox) self.forceServerSideDecorationsCheckbox.state = prefs.forceServerSideDecorations;
    if (self.renderMacOSPointerCheckbox) self.renderMacOSPointerCheckbox.state = prefs.renderMacOSPointer;
    if (self.autoScaleCheckbox) self.autoScaleCheckbox.state = prefs.autoScale;
    if (self.respectSafeAreaCheckbox) self.respectSafeAreaCheckbox.state = prefs.respectSafeArea;
    
    if (self.swapCmdWithAltCheckbox) self.swapCmdWithAltCheckbox.state = prefs.swapCmdWithAlt;
    if (self.universalClipboardCheckbox) self.universalClipboardCheckbox.state = prefs.universalClipboardEnabled;
    
    if (self.vulkanDriversCheckbox) self.vulkanDriversCheckbox.state = prefs.vulkanDriversEnabled;
    if (self.eglDriversCheckbox) self.eglDriversCheckbox.state = prefs.eglDriversEnabled;
    if (self.dmabufCheckbox) self.dmabufCheckbox.state = prefs.dmabufEnabled;
    
    if (self.tcpListenerCheckbox) self.tcpListenerCheckbox.state = prefs.enableTCPListener;
    if (self.tcpPortField) self.tcpPortField.stringValue = [NSString stringWithFormat:@"%ld", (long)prefs.tcpListenerPort];
    if (self.socketDirField) self.socketDirField.stringValue = prefs.waylandSocketDir ?: @"/tmp";
    if (self.displayNumField) self.displayNumField.stringValue = [NSString stringWithFormat:@"%ld", (long)prefs.waylandDisplayNumber];
    
    if (self.colorOperationsCheckbox) self.colorOperationsCheckbox.state = prefs.colorOperations;
    if (self.nestedCompositorsCheckbox) self.nestedCompositorsCheckbox.state = prefs.nestedCompositorsSupportEnabled;
    if (self.multipleClientsCheckbox) self.multipleClientsCheckbox.state = prefs.multipleClientsEnabled;
    
    if (self.waypipeDisplayField) self.waypipeDisplayField.stringValue = prefs.waypipeDisplay ?: @"wayland-0";
    if (self.waypipeCompressPopup) [self.waypipeCompressPopup selectItemWithTitle:prefs.waypipeCompress ?: @"lz4"];
    if (self.waypipeCompressLevelField) self.waypipeCompressLevelField.stringValue = prefs.waypipeCompressLevel ?: @"7";
    if (self.waypipeThreadsField) self.waypipeThreadsField.stringValue = prefs.waypipeThreads ?: @"0";
    if (self.waypipeVideoPopup) [self.waypipeVideoPopup selectItemWithTitle:prefs.waypipeVideo ?: @"none"];
    if (self.waypipeVideoEncodingPopup) [self.waypipeVideoEncodingPopup selectItemWithTitle:prefs.waypipeVideoEncoding ?: @"hw"];
    if (self.waypipeVideoDecodingPopup) [self.waypipeVideoDecodingPopup selectItemWithTitle:prefs.waypipeVideoDecoding ?: @"hw"];
    if (self.waypipeVideoBpfField) self.waypipeVideoBpfField.stringValue = prefs.waypipeVideoBpf ?: @"";
    if (self.waypipeSSHEnabledCheckbox) self.waypipeSSHEnabledCheckbox.state = prefs.waypipeSSHEnabled;
    if (self.waypipeSSHHostField) self.waypipeSSHHostField.stringValue = prefs.waypipeSSHHost ?: @"";
    if (self.waypipeSSHUserField) self.waypipeSSHUserField.stringValue = prefs.waypipeSSHUser ?: @"";
    if (self.waypipeRemoteCommandField) self.waypipeRemoteCommandField.stringValue = prefs.waypipeRemoteCommand ?: @"";
    if (self.waypipeDebugCheckbox) self.waypipeDebugCheckbox.state = prefs.waypipeDebug;
    if (self.waypipeNoGpuCheckbox) self.waypipeNoGpuCheckbox.state = prefs.waypipeNoGpu;
    if (self.waypipeOneshotCheckbox) self.waypipeOneshotCheckbox.state = prefs.waypipeOneshot;
    if (self.waypipeUnlinkSocketCheckbox) self.waypipeUnlinkSocketCheckbox.state = prefs.waypipeUnlinkSocket;
    if (self.waypipeLoginShellCheckbox) self.waypipeLoginShellCheckbox.state = prefs.waypipeLoginShell;
    if (self.waypipeVsockCheckbox) self.waypipeVsockCheckbox.state = prefs.waypipeVsock;
    if (self.waypipeXwlsCheckbox) self.waypipeXwlsCheckbox.state = prefs.waypipeXwls;
    if (self.waypipeTitlePrefixField) self.waypipeTitlePrefixField.stringValue = prefs.waypipeTitlePrefix ?: @"";
    if (self.waypipeSecCtxField) self.waypipeSecCtxField.stringValue = prefs.waypipeSecCtx ?: @"";
}

- (NSString *)getLocalIPAddress {
    NSString *address = @"Unavailable";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"] ||
                    [[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en1"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

@end

// MARK: - Split View Controller

@interface WawonaPreferencesSplitViewController : NSSplitViewController
@property (nonatomic, strong) WawonaPreferencesSidebarViewController *sidebarVC;
@property (nonatomic, strong) WawonaPreferencesContentViewController *contentVC;
@end

@implementation WawonaPreferencesSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sidebarVC = [[WawonaPreferencesSidebarViewController alloc] init];
    self.contentVC = [[WawonaPreferencesContentViewController alloc] init];
    
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:self.sidebarVC];
    NSSplitViewItem *contentItem = [NSSplitViewItem contentListWithViewController:self.contentVC];
    
    [self addSplitViewItem:sidebarItem];
    [self addSplitViewItem:contentItem];
    
    // Connect sidebar selection
    __weak typeof(self) weakSelf = self;
    self.sidebarVC.selectionHandler = ^(NSString *identifier) {
        [weakSelf.contentVC showSection:identifier];
    };
}

@end

// MARK: - Main Window Controller Implementation

@interface WawonaPreferences ()
@property (nonatomic, strong) WawonaPreferencesSplitViewController *splitViewController;
@end

@implementation WawonaPreferences

+ (instancetype)sharedPreferences {
    static WawonaPreferences *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 550)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Wawona Settings"];
    [window setContentMinSize:NSMakeSize(600, 400)];
    [window center];
    [window setToolbarStyle:NSWindowToolbarStyleUnified];
    
    self = [super initWithWindow:window];
    if (self) {
        self.splitViewController = [[WawonaPreferencesSplitViewController alloc] init];
        self.contentViewController = self.splitViewController;
    }
    return self;
}

- (void)showPreferences:(id)sender {
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

@end

#endif
