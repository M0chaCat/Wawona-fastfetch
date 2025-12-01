#import "WawonaPreferences.h"
#import "WawonaPreferencesManager.h"

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
    
    cell.textLabel.text = title;
    cell.accessoryView = nil; // Reset
    cell.accessoryType = UITableViewCellAccessoryNone;
    
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
        }
        
        [textField addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
        textField.tag = indexPath.section * 1000 + indexPath.row;
        
        cell.accessoryView = textField;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"info"]) {
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", version, build];
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

@interface WawonaPreferences () <NSToolbarDelegate>

@property (nonatomic, strong) NSView *displayView;
@property (nonatomic, strong) NSView *colorManagementView;
@property (nonatomic, strong) NSView *nestedCompositorsView;
@property (nonatomic, strong) NSView *inputView;
@property (nonatomic, strong) NSView *clientManagementView;
@property (nonatomic, strong) NSView *waylandConfigView;
@property (nonatomic, strong) NSView *currentView;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSStackView *contentStackView;

// Input (includes Clipboard)
@property (nonatomic, strong) NSButton *universalClipboardCheckbox;

// Display
@property (nonatomic, strong) NSButton *forceServerSideDecorationsCheckbox;
@property (nonatomic, strong) NSButton *autoRetinaScalingCheckbox;

// Color Management
@property (nonatomic, strong) NSButton *colorSyncSupportCheckbox;

// Nested Compositors
@property (nonatomic, strong) NSButton *nestedCompositorsCheckbox;
@property (nonatomic, strong) NSButton *useMetal4ForNestedCheckbox;

// Input
@property (nonatomic, strong) NSButton *renderMacOSPointerCheckbox;
@property (nonatomic, strong) NSButton *swapCmdAsCtrlCheckbox;

// Client Management
@property (nonatomic, strong) NSButton *multipleClientsCheckbox;

// Network / Remote Access
@property (nonatomic, strong) NSButton *enableTCPListenerCheckbox;
@property (nonatomic, strong) NSTextField *tcpListenerPortField;
@property (nonatomic, strong) NSButton *waypipeRSSupportCheckbox;
@property (nonatomic, strong) NSButton *enableVulkanDriversCheckbox;
@property (nonatomic, strong) NSButton *enableEGLDriversCheckbox;

// Wayland Config
@property (nonatomic, strong) NSTextField *waylandSocketDirField;
@property (nonatomic, strong) NSTextField *waylandDisplayNumberField;

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
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    self = [super init];
    if (self) {
        self.title = @"Wawona Preferences";
    }
    return self;
#else
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500)
                                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [window setTitle:@"Wawona Preferences"];
    [window setContentMinSize:NSMakeSize(600, 400)];
    [window center];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupToolbar];
        [self setupViews];
        [self loadPreferences];
    }
    return self;
#endif
}

- (void)setupToolbar {
    self.toolbar = [[NSToolbar alloc] initWithIdentifier:@"WawonaPreferencesToolbar"];
    self.toolbar.delegate = self;
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    self.toolbar.allowsUserCustomization = NO;
    [self.window setToolbar:self.toolbar];
}

- (void)setupViews {
    NSView *contentView = self.window.contentView;
    
    // Create main content stack view
    self.contentStackView = [[NSStackView alloc] init];
    self.contentStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.contentStackView.spacing = 20;
    self.contentStackView.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    self.contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:self.contentStackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.contentStackView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.contentStackView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.contentStackView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.contentStackView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];
    
    // Create all preference views
    [self createDisplayView];
    [self createColorManagementView];
    [self createNestedCompositorsView];
    [self createInputView]; // Input now includes Clipboard
    [self createClientManagementView];
    [self createRenderingBackendsView];
    [self createWaylandConfigView];
    
    // Show input view by default
    [self showView:self.inputView];
}


- (void)createDisplayView {
    self.displayView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.displayView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.displayView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.displayView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.displayView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.displayView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Display"];
    [stack addArrangedSubview:title];
    
    self.forceServerSideDecorationsCheckbox = [self createCheckbox:@"Force Server-Side Decorations"
                                                            action:@selector(forceServerSideDecorationsChanged:)];
    [stack addArrangedSubview:self.forceServerSideDecorationsCheckbox];
    
    NSTextField *desc1 = [self createDescription:@"Disallow client-side decorations. All Wayland clients will use macOS window decorations."];
    [stack addArrangedSubview:desc1];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    self.autoRetinaScalingCheckbox = [self createCheckbox:@"Auto Retina Scaling Support"
                                                    action:@selector(autoRetinaScalingChanged:)];
    [stack addArrangedSubview:self.autoRetinaScalingCheckbox];
    
    NSTextField *desc2 = [self createDescription:@"Automatically scale content for Retina displays."];
    [stack addArrangedSubview:desc2];
}

- (void)createRenderingBackendsView {
    NSView *view = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];
    NSTextField *title = [self createSectionTitle:@"Rendering Backends"];
    [stack addArrangedSubview:title];
    self.enableVulkanDriversCheckbox = [self createCheckbox:@"Enable Vulkan Drivers" action:@selector(enableVulkanDriversChanged:)];
    [stack addArrangedSubview:self.enableVulkanDriversCheckbox];
    self.enableEGLDriversCheckbox = [self createCheckbox:@"Enable EGL Drivers" action:@selector(enableEGLDriversChanged:)];
    [stack addArrangedSubview:self.enableEGLDriversCheckbox];
    [self.contentStackView addArrangedSubview:view];
}

- (void)createColorManagementView {
    self.colorManagementView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.colorManagementView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.colorManagementView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.colorManagementView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.colorManagementView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.colorManagementView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Color Management"];
    [stack addArrangedSubview:title];
    
    self.colorSyncSupportCheckbox = [self createCheckbox:@"ColorSync - HDR/Color Profiles Support"
                                                   action:@selector(colorSyncSupportChanged:)];
    [stack addArrangedSubview:self.colorSyncSupportCheckbox];
    
    NSTextField *desc = [self createDescription:@"Enable ColorSync integration for HDR and color profile support."];
    [stack addArrangedSubview:desc];
}

- (void)createNestedCompositorsView {
    self.nestedCompositorsView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.nestedCompositorsView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.nestedCompositorsView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.nestedCompositorsView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.nestedCompositorsView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.nestedCompositorsView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Nested Compositors"];
    [stack addArrangedSubview:title];
    
    self.nestedCompositorsCheckbox = [self createCheckbox:@"Enable Nested Compositors Support"
                                                    action:@selector(nestedCompositorsChanged:)];
    [stack addArrangedSubview:self.nestedCompositorsCheckbox];
    
    NSTextField *desc1 = [self createDescription:@"Allow running Wayland compositors (like Weston) inside Wawona."];
    [stack addArrangedSubview:desc1];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    self.useMetal4ForNestedCheckbox = [self createCheckbox:@"Use Metal 4 for Nested Compositors"
                                                      action:@selector(useMetal4ForNestedChanged:)];
    [stack addArrangedSubview:self.useMetal4ForNestedCheckbox];
    
    NSTextField *desc2 = [self createDescription:@"Use Metal 4 instead of Cocoa for rendering nested compositors. Requires Metal 4 support."];
    [stack addArrangedSubview:desc2];
}

- (void)createInputView {
    self.inputView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.inputView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.inputView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.inputView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.inputView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.inputView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Input"];
    [stack addArrangedSubview:title];
    
    // Universal Clipboard
    self.universalClipboardCheckbox = [self createCheckbox:@"Enable Universal Clipboard"
                                                     action:@selector(universalClipboardChanged:)];
    [stack addArrangedSubview:self.universalClipboardCheckbox];
    
    NSTextField *descClipboard = [self createDescription:@"Share clipboard content between macOS and Wayland clients."];
    [stack addArrangedSubview:descClipboard];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    // macOS Pointer
    self.renderMacOSPointerCheckbox = [self createCheckbox:@"Render macOS Pointer"
                                                     action:@selector(renderMacOSPointerChanged:)];
    [stack addArrangedSubview:self.renderMacOSPointerCheckbox];
    
    NSTextField *desc1 = [self createDescription:@"Show macOS cursor while using Wawona."];
    [stack addArrangedSubview:desc1];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    // Keyboard Mapping
    self.swapCmdAsCtrlCheckbox = [self createCheckbox:@"Swap Command as Control"
                                                 action:@selector(swapCmdAsCtrlChanged:)];
    [stack addArrangedSubview:self.swapCmdAsCtrlCheckbox];
    
    NSTextField *desc2 = [self createDescription:@"Map macOS Command key to Control for Wayland clients."];
    [stack addArrangedSubview:desc2];
}

- (void)createClientManagementView {
    self.clientManagementView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clientManagementView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.clientManagementView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.clientManagementView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.clientManagementView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.clientManagementView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Client Management"];
    [stack addArrangedSubview:title];
    
    self.multipleClientsCheckbox = [self createCheckbox:@"Allow Multiple Clients"
                                                  action:@selector(multipleClientsChanged:)];
    [stack addArrangedSubview:self.multipleClientsCheckbox];
    
    NSTextField *desc = [self createDescription:@"Allow multiple Wayland clients to connect simultaneously. When disabled, only one client at a time."];
    [stack addArrangedSubview:desc];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    NSTextField *networkTitle = [self createLabel:@"Network / Remote Access:"];
    [stack addArrangedSubview:networkTitle];
    
    self.enableTCPListenerCheckbox = [self createCheckbox:@"Enable TCP Listener"
                                                   action:@selector(enableTCPListenerChanged:)];
    [stack addArrangedSubview:self.enableTCPListenerCheckbox];
    
    NSTextField *networkDesc = [self createDescription:@"Allow external Wayland clients (e.g., via Waypipe) to connect to this compositor over the network."];
    [stack addArrangedSubview:networkDesc];
    
    NSStackView *portStack = [[NSStackView alloc] init];
    portStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    portStack.spacing = 10;
    
    NSTextField *portLabel = [self createLabel:@"TCP Port:"];
    [portStack addArrangedSubview:portLabel];
    
    self.tcpListenerPortField = [[NSTextField alloc] init];
    self.tcpListenerPortField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tcpListenerPortField setTarget:self];
    [self.tcpListenerPortField setAction:@selector(tcpListenerPortChanged:)];
    [portStack addArrangedSubview:self.tcpListenerPortField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tcpListenerPortField.widthAnchor constraintEqualToConstant:100]
    ]];
    
    [stack addArrangedSubview:portStack];
    
    NSTextField *portDesc = [self createDescription:@"Port for TCP listener (0 for dynamic)."];
    [stack addArrangedSubview:portDesc];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    self.waypipeRSSupportCheckbox = [self createCheckbox:@"Waypipe-RS Support"
                                                    action:@selector(waypipeRSSupportChanged:)];
    [stack addArrangedSubview:self.waypipeRSSupportCheckbox];
    
    NSTextField *desc2 = [self createDescription:@"Enable Waypipe-RS support. Requires conformant Vulkan 1.3 + Metal 4 Apple Silicon KosmicKrisp userland drivers (Mesa 26+)."];
    [stack addArrangedSubview:desc2];
}

- (void)createWaylandConfigView {
    self.waylandConfigView = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 15;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.waylandConfigView addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.waylandConfigView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.waylandConfigView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.waylandConfigView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.waylandConfigView.bottomAnchor]
    ]];
    
    NSTextField *title = [self createSectionTitle:@"Wayland Configuration"];
    [stack addArrangedSubview:title];
    
    NSTextField *socketDirLabel = [self createLabel:@"Wayland Socket Directory:"];
    [stack addArrangedSubview:socketDirLabel];
    
    NSStackView *socketDirStack = [[NSStackView alloc] init];
    socketDirStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    socketDirStack.spacing = 10;
    
    self.waylandSocketDirField = [[NSTextField alloc] init];
    self.waylandSocketDirField.translatesAutoresizingMaskIntoConstraints = NO;
    [socketDirStack addArrangedSubview:self.waylandSocketDirField];
    
    NSButton *browseButton = [[NSButton alloc] init];
    [browseButton setTitle:@"Browse..."];
    [browseButton setButtonType:NSButtonTypeMomentaryPushIn];
    [browseButton setTarget:self];
    [browseButton setAction:@selector(browseSocketDir:)];
    [socketDirStack addArrangedSubview:browseButton];
    
    [stack addArrangedSubview:socketDirStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.waylandSocketDirField.widthAnchor constraintGreaterThanOrEqualToConstant:400]
    ]];
    
    [stack addArrangedSubview:[self createSeparator]];
    
    NSTextField *displayLabel = [self createLabel:@"Wayland Display Number:"];
    [stack addArrangedSubview:displayLabel];
    
    self.waylandDisplayNumberField = [[NSTextField alloc] init];
    self.waylandDisplayNumberField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.waylandDisplayNumberField setTarget:self];
    [self.waylandDisplayNumberField setAction:@selector(waylandDisplayNumberChanged:)];
    [stack addArrangedSubview:self.waylandDisplayNumberField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.waylandDisplayNumberField.widthAnchor constraintEqualToConstant:100]
    ]];
    
    NSTextField *desc = [self createDescription:@"Set the Wayland display number (0, 1, 2, etc.). Changes require restart."];
    [stack addArrangedSubview:desc];
}


- (NSTextField *)createSectionTitle:(NSString *)title {
    NSTextField *field = [[NSTextField alloc] init];
    field.stringValue = title;
    field.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    field.alignment = NSTextAlignmentLeft;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.editable = NO;
    field.selectable = NO;
    return field;
}

- (NSButton *)createCheckbox:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] init];
    [button setButtonType:NSButtonTypeSwitch];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:action];
    return button;
}

- (NSTextField *)createLabel:(NSString *)text {
    NSTextField *field = [[NSTextField alloc] init];
    field.stringValue = text;
    field.font = [NSFont systemFontOfSize:13];
    field.alignment = NSTextAlignmentLeft;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.editable = NO;
    field.selectable = NO;
    return field;
}

- (NSTextField *)createDescription:(NSString *)text {
    NSTextField *field = [[NSTextField alloc] init];
    field.stringValue = text;
    field.font = [NSFont systemFontOfSize:11];
    field.textColor = [NSColor secondaryLabelColor];
    field.alignment = NSTextAlignmentLeft;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.editable = NO;
    field.selectable = NO;
    field.preferredMaxLayoutWidth = 600;
    return field;
}

- (NSBox *)createSeparator {
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1].active = YES;
    return separator;
}

- (void)showView:(NSView *)view {
    if (self.currentView) {
        [self.currentView removeFromSuperview];
    }
    
    self.currentView = view;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStackView addArrangedSubview:view];
    
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:self.contentStackView.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:self.contentStackView.trailingAnchor]
    ]];
}

- (void)loadPreferences {
    WawonaPreferencesManager *prefs = [WawonaPreferencesManager sharedManager];
    
    self.universalClipboardCheckbox.state = prefs.universalClipboardEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.forceServerSideDecorationsCheckbox.state = prefs.forceServerSideDecorations ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoRetinaScalingCheckbox.state = prefs.autoRetinaScalingEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.colorSyncSupportCheckbox.state = prefs.colorSyncSupportEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.nestedCompositorsCheckbox.state = prefs.nestedCompositorsSupportEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.useMetal4ForNestedCheckbox.state = prefs.useMetal4ForNested ? NSControlStateValueOn : NSControlStateValueOff;
    self.renderMacOSPointerCheckbox.state = prefs.renderMacOSPointer ? NSControlStateValueOn : NSControlStateValueOff;
    self.swapCmdAsCtrlCheckbox.state = prefs.swapCmdAsCtrl ? NSControlStateValueOn : NSControlStateValueOff;
    self.multipleClientsCheckbox.state = prefs.multipleClientsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.enableTCPListenerCheckbox.state = prefs.enableTCPListener ? NSControlStateValueOn : NSControlStateValueOff;
    self.tcpListenerPortField.stringValue = [NSString stringWithFormat:@"%ld", (long)prefs.tcpListenerPort];
    self.waypipeRSSupportCheckbox.state = prefs.waypipeRSSupportEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.enableVulkanDriversCheckbox.state = [prefs vulkanDriversEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    self.enableEGLDriversCheckbox.state = [prefs eglDriversEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    
    self.waylandSocketDirField.stringValue = prefs.waylandSocketDir;
    self.waylandDisplayNumberField.stringValue = [NSString stringWithFormat:@"%ld", (long)prefs.waylandDisplayNumber];
}

// Action methods
- (void)universalClipboardChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setUniversalClipboardEnabled:sender.state == NSControlStateValueOn];
}

- (void)forceServerSideDecorationsChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setForceServerSideDecorations:sender.state == NSControlStateValueOn];
}

- (void)autoRetinaScalingChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setAutoRetinaScalingEnabled:sender.state == NSControlStateValueOn];
}

- (void)colorSyncSupportChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setColorSyncSupportEnabled:sender.state == NSControlStateValueOn];
}

- (void)nestedCompositorsChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setNestedCompositorsSupportEnabled:sender.state == NSControlStateValueOn];
}

- (void)useMetal4ForNestedChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setUseMetal4ForNested:sender.state == NSControlStateValueOn];
}

- (void)renderMacOSPointerChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setRenderMacOSPointer:sender.state == NSControlStateValueOn];
}

- (void)swapCmdAsCtrlChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setSwapCmdAsCtrl:sender.state == NSControlStateValueOn];
}

- (void)multipleClientsChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setMultipleClientsEnabled:sender.state == NSControlStateValueOn];
}

- (void)enableTCPListenerChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setEnableTCPListener:sender.state == NSControlStateValueOn];
}

- (void)tcpListenerPortChanged:(NSTextField *)sender {
    NSInteger port = [sender.stringValue integerValue];
    [[WawonaPreferencesManager sharedManager] setTCPListenerPort:port];
}

- (void)waypipeRSSupportChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setWaypipeRSSupportEnabled:sender.state == NSControlStateValueOn];
}

- (void)waylandDisplayNumberChanged:(NSTextField *)sender {
    NSInteger number = [sender.stringValue integerValue];
    [[WawonaPreferencesManager sharedManager] setWaylandDisplayNumber:number];
}

- (void)enableVulkanDriversChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setVulkanDriversEnabled:(sender.state == NSControlStateValueOn)];
}

- (void)enableEGLDriversChanged:(NSButton *)sender {
    [[WawonaPreferencesManager sharedManager] setEglDriversEnabled:(sender.state == NSControlStateValueOn)];
}

- (void)showPreferences:(id)sender {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Preferences UI not implemented yet
    (void)sender;
#else
    if (!self.window) {
        // Reinitialize if window was closed
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500)
                                                         styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
        [window setTitle:@"Wawona Preferences"];
        [window setContentMinSize:NSMakeSize(600, 400)];
        [window center];
        [self setWindow:window];
        [self setupToolbar];
        [self setupViews];
        [self loadPreferences];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
#endif
}

- (void)browseSocketDir:(NSButton *)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    
    if ([panel runModal] == NSModalResponseOK) {
        NSString *path = panel.URL.path;
        self.waylandSocketDirField.stringValue = path;
        [[WawonaPreferencesManager sharedManager] setWaylandSocketDir:path];
    }
}

- (void)openDonateLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://ko-fi.com/aspauldingcode"]];
}

- (void)openGitHubLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/aspauldingcode"]];
}

- (void)openPortfolioLink:(NSButton *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://aspauldingcode.com"]];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"Display", @"Color", @"Nested", @"Input", @"Clients", @"Wayland"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    
    if ([itemIdentifier isEqualToString:@"Display"]) {
        item.label = @"Display";
        item.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Display"];
        item.target = self;
        item.action = @selector(showDisplay:);
    } else if ([itemIdentifier isEqualToString:@"Color"]) {
        item.label = @"Color";
        item.image = [NSImage imageWithSystemSymbolName:@"paintpalette" accessibilityDescription:@"Color"];
        item.target = self;
        item.action = @selector(showColor:);
    } else if ([itemIdentifier isEqualToString:@"Nested"]) {
        item.label = @"Nested";
        item.image = [NSImage imageWithSystemSymbolName:@"square.stack.3d.up" accessibilityDescription:@"Nested"];
        item.target = self;
        item.action = @selector(showNested:);
    } else if ([itemIdentifier isEqualToString:@"Input"]) {
        item.label = @"Input";
        item.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"Input"];
        item.target = self;
        item.action = @selector(showInput:);
    } else if ([itemIdentifier isEqualToString:@"Clients"]) {
        item.label = @"Clients";
        item.image = [NSImage imageWithSystemSymbolName:@"app.badge" accessibilityDescription:@"Clients"];
        item.target = self;
        item.action = @selector(showClients:);
    } else if ([itemIdentifier isEqualToString:@"Wayland"]) {
        item.label = @"Wayland";
        item.image = [NSImage imageWithSystemSymbolName:@"gear" accessibilityDescription:@"Wayland"];
        item.target = self;
        item.action = @selector(showWayland:);
    }
    
    return item;
}

- (void)showDisplay:(id)sender {
    [self showView:self.displayView];
}

- (void)showColor:(id)sender {
    [self showView:self.colorManagementView];
}

- (void)showNested:(id)sender {
    [self showView:self.nestedCompositorsView];
}

- (void)showInput:(id)sender {
    [self showView:self.inputView];
}

- (void)showClients:(id)sender {
    [self showView:self.clientManagementView];
}

- (void)showWayland:(id)sender {
    [self showView:self.waylandConfigView];
}


@end
#endif
