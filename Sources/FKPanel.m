//
//  FKPanel.m — hidden toolkit panel, home screen and panel lifecycle
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import <ctype.h>
#import <math.h>

#pragma mark - Tile

@interface FKTileView : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
+ (instancetype)tileWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint;
@end

@implementation FKTileView

+ (instancetype)tileWithTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint {
    FKTileView *tile = [[FKTileView alloc] initWithFrame:CGRectMake(0, 0, 100, 96)];
    tile.iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    tile.iconView.contentMode = UIViewContentModeScaleAspectFit;
    tile.iconView.tintColor = tint;
    tile.iconView.backgroundColor = [tint colorWithAlphaComponent:0.16];
    tile.iconView.layer.cornerRadius = 13;
    tile.iconView.layer.cornerCurve = kCACornerCurveContinuous;
    tile.iconView.clipsToBounds = YES;
    [tile addSubview:tile.iconView];

    tile.titleLabel = [[UILabel alloc] init];
    tile.titleLabel.text = title;
    tile.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    tile.titleLabel.textColor = [UIColor labelColor];
    tile.titleLabel.textAlignment = NSTextAlignmentCenter;
    tile.titleLabel.numberOfLines = 2;
    [tile addSubview:tile.titleLabel];
    return tile;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 44;
    self.iconView.frame = CGRectMake((self.bounds.size.width - side) / 2, 8, side, side);
    self.titleLabel.frame = CGRectMake(2, 58, self.bounds.size.width - 4, self.bounds.size.height - 60);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.alpha = highlighted ? 0.55 : 1.0;
        self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - Badge

@interface FKBadgeLabel : UILabel
@end

@implementation FKBadgeLabel

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(3, 8, 3, 8))];
}

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + 16, size.height + 6);
}

@end

static FKBadgeLabel *FKMakeBadge(NSString *text, UIColor *color) {
    FKBadgeLabel *label = [[FKBadgeLabel alloc] init];
    label.text = text;
    label.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightSemibold];
    label.textColor = color;
    label.backgroundColor = [color colorWithAlphaComponent:0.15];
    label.layer.cornerRadius = 6;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.clipsToBounds = YES;
    return label;
}

#pragma mark - Home

@interface FKPanelHomeViewController : UIViewController
@end

@implementation FKPanelHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ForgeKit";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                           target:self
                                                                                           action:@selector(close)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(openSettings)];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    scroll.contentInset = UIEdgeInsetsMake(12, 14, 28, 14);
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(14, 12, self.view.bounds.size.width - 28, 0)];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-28],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-28],
    ]];

    [stack addArrangedSubview:[self headerCard]];
    [stack addArrangedSubview:[self tileGrid]];
    [stack addArrangedSubview:[self footerCard]];
}

- (UIView *)headerCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.heightAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon60x60"] ?: [UIImage systemImageNamed:@"app.fill"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.layer.cornerRadius = 12;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    icon.tintColor = [UIColor systemOrangeColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *name = [[UILabel alloc] init];
    name.text = FKAppName();
    name.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    UILabel *identifier = [[UILabel alloc] init];
    identifier.text = [NSString stringWithFormat:@"%@ · %@", FKAppIdentifier(), FKAppVersion()];
    identifier.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    identifier.textColor = [UIColor secondaryLabelColor];
    identifier.adjustsFontSizeToFitWidth = YES;
    identifier.minimumScaleFactor = 0.7;
    identifier.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:identifier];

    UIStackView *badges = [[UIStackView alloc] init];
    badges.axis = UILayoutConstraintAxisHorizontal;
    badges.spacing = 6;
    badges.translatesAutoresizingMaskIntoConstraints = NO;
    [badges addArrangedSubview:FKMakeBadge(FKIsJailbroken() ? @"JAILBROKEN" : @"SANDBOXED",
                                           FKIsJailbroken() ? [UIColor systemGreenColor] : [UIColor systemOrangeColor])];
    [badges addArrangedSubview:FKMakeBadge([NSString stringWithFormat:@"iOS %@", FKOSVersionString()], [UIColor systemBlueColor])];
    [badges addArrangedSubview:FKMakeBadge(@"MCP", [UIColor systemPurpleColor])];
    [card addSubview:badges];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [icon.widthAnchor constraintEqualToConstant:52],
        [icon.heightAnchor constraintEqualToConstant:52],
        [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [name.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [identifier.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [identifier.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [identifier.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],
        [badges.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [badges.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [badges.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [badges.heightAnchor constraintEqualToConstant:20],
    ]];
    return card;
}

- (UIView *)tileGrid {
    NSArray *tiles = @[
        @{ @"title": @"Files", @"symbol": @"folder.fill", @"tint": [UIColor systemBlueColor], @"action": @"files" },
        @{ @"title": @"App", @"symbol": @"shippingbox.fill", @"tint": [UIColor systemOrangeColor], @"action": @"app" },
        @{ @"title": @"Defaults", @"symbol": @"slider.horizontal.3", @"tint": [UIColor systemTealColor], @"action": @"defaults" },
        @{ @"title": @"Keychain", @"symbol": @"key.fill", @"tint": [UIColor systemYellowColor], @"action": @"keychain" },
        @{ @"title": @"Runtime", @"symbol": @"chevron.left.forwardslash.chevron.right", @"tint": [UIColor systemPurpleColor], @"action": @"runtime" },
        @{ @"title": @"Network", @"symbol": @"antenna.radiowaves.left.and.right", @"tint": [UIColor systemGreenColor], @"action": @"server" },
        @{ @"title": @"Log", @"symbol": @"text.alignleft", @"tint": [UIColor systemGrayColor], @"action": @"log" },
        @{ @"title": @"Device", @"symbol": @"iphone", @"tint": [UIColor systemIndigoColor], @"action": @"device" },
        @{ @"title": @"Settings", @"symbol": @"gearshape.fill", @"tint": [UIColor systemPinkColor], @"action": @"settings" },
        @{ @"title": @"Unity", @"symbol": @"cube.transparent.fill", @"tint": [UIColor systemBrownColor], @"action": @"unity" },
        @{ @"title": @"Shell", @"symbol": @"terminal.fill", @"tint": [UIColor systemGreenColor], @"action": @"shell" },
        @{ @"title": @"Utilities", @"symbol": @"wrench.and.screwdriver.fill", @"tint": [UIColor systemGrayColor], @"action": @"utilities" },
    ];

    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10;
    NSMutableArray *rowStack = nil;
    for (NSUInteger i = 0; i < tiles.count; i++) {
        if (i % 3 == 0) {
            rowStack = [NSMutableArray array];
            UIStackView *row = [[UIStackView alloc] init];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 8;
            row.distribution = UIStackViewDistributionFillEqually;
            row.tag = 100 + (NSInteger)(i / 3);
            [grid addArrangedSubview:row];
        }
        UIStackView *row = grid.arrangedSubviews.lastObject;
        NSDictionary *info = tiles[i];
        NSString *action = info[@"action"];
        FKTileView *tile = [FKTileView tileWithTitle:info[@"title"] symbol:info[@"symbol"] tint:info[@"tint"]];
        tile.tag = 200 + (NSInteger)i;
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [tile.heightAnchor constraintEqualToConstant:96].active = YES;
        [row addArrangedSubview:tile];
        (void)rowStack;
        (void)action;
    }
    return grid;
}

- (UIView *)footerCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *hint = [[UILabel alloc] init];
    hint.numberOfLines = 0;
    hint.font = [UIFont systemFontOfSize:11];
    hint.textColor = [UIColor secondaryLabelColor];
    NSString *port = [NSString stringWithFormat:@"%ld", (long)[FKPrefs integerForKey:@"port" defaultValue:8787]];
    hint.text = [NSString stringWithFormat:
                 @"Long-press the time in the status bar, or press volume up then down.\n"
                 @"MCP endpoint: http://%@:%@/mcp\n"
                 @"Dashboard: http://%@:%@/?token=%@",
                 FKLanAddress(), port, FKLanAddress(), port, [FKPrefs token]];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [hint.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [hint.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [hint.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];
    return card;
}

- (void)tileTapped:(FKTileView *)sender {
    NSInteger index = sender.tag - 200;
    NSArray *actions = @[@"files", @"app", @"defaults", @"keychain", @"runtime", @"server", @"log", @"device", @"settings", @"unity", @"shell", @"utilities"];
    if (index < 0 || index >= (NSInteger)actions.count) return;
    NSString *action = actions[(NSUInteger)index];
    UIViewController *controller = nil;
    if ([action isEqualToString:@"files"]) controller = [FKFileBrowserViewController browserAtPath:FKContainerPath()];
    else if ([action isEqualToString:@"defaults"]) controller = [[FKDefaultsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    else if ([action isEqualToString:@"keychain"]) controller = [[FKKeychainViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    else if ([action isEqualToString:@"runtime"]) controller = [[FKRuntimeViewController alloc] init];
    else if ([action isEqualToString:@"server"]) controller = [[FKServerViewController alloc] init];
    else if ([action isEqualToString:@"settings"]) controller = [[FKSettingsViewController alloc] init];
    else if ([action isEqualToString:@"log"]) controller = [FKLogViewController logController];
    else if ([action isEqualToString:@"app"]) controller = [self appInfoController];
    else if ([action isEqualToString:@"device"]) controller = [self deviceController];
    else if ([action isEqualToString:@"unity"]) controller = [[FKUnityViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    else if ([action isEqualToString:@"shell"]) controller = [[FKShellViewController alloc] init];
    else if ([action isEqualToString:@"utilities"]) controller = [[FKUtilitiesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    if (controller) [self.navigationController pushViewController:controller animated:YES];
}

- (UIViewController *)appInfoController {
    NSDictionary *info = FKInfoPlist();
    NSMutableArray *identityRows = [NSMutableArray array];
    void (^addRow)(NSString *, NSString *) = ^(NSString *title, NSString *value) {
        [identityRows addObject:@{ @"title": title, @"subtitle": value ?: @"", @"value": value ?: @"" }];
    };
    addRow(@"Bundle identifier", FKAppIdentifier());
    addRow(@"Name", FKAppName());
    addRow(@"Version", FKAppVersion());
    addRow(@"Minimum iOS", info[@"MinimumOSVersion"] ?: @"—");
    addRow(@"SDK", info[@"DTSDKName"] ?: @"—");
    addRow(@"Executable", info[@"CFBundleExecutable"] ?: @"—");

    NSMutableArray *pathRows = [NSMutableArray array];
    [FKApplicationPaths() enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSArray class]]) {
            for (NSString *path in value) [pathRows addObject:@{ @"title": key, @"subtitle": path }];
        } else {
            [pathRows addObject:@{ @"title": key, @"subtitle": [value description] }];
        }
    }];

    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:@{ @"title": @"Identity", @"rows": identityRows }];
    [sections addObject:@{ @"title": @"Paths", @"rows": pathRows }];

    NSDictionary *entitlements = FKEntitlements();
    if (entitlements.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *key in [entitlements.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [rows addObject:@{ @"title": key, @"subtitle": FKJSONString(entitlements[key], NO) }];
        }
        [sections addObject:@{ @"title": @"Entitlements", @"rows": rows }];
    }

    NSArray *binaries = [FKTools callTool:@"app_binaries" arguments:@{}][@"binaries"];
    if (binaries.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *binary in binaries) {
            [rows addObject:@{ @"title": [binary[@"path"] lastPathComponent], @"subtitle": binary[@"path"],
                               @"value": FKHumanSize([binary[@"size"] unsignedLongLongValue]) }];
        }
        [sections addObject:@{ @"title": @"Mach-O images", @"rows": rows }];
    }

    [sections addObject:@{ @"title": @"Inspection", @"rows": @[
        @{ @"title": @"Dump Info.plist", @"chevron": @YES, @"action": ^{
            NSData *xml = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            NSString *text = xml ? [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] : @"";
            [self.navigationController pushViewController:
                [FKTextViewController viewerWithTitle:@"Info.plist" text:text] animated:YES];
        } },
        @{ @"title": @"View entitlements", @"chevron": @YES, @"action": ^{
            [self.navigationController pushViewController:
                [FKTextViewController viewerWithTitle:@"Entitlements" text:FKJSONString(entitlements, YES)] animated:YES];
        } },
        @{ @"title": @"Loaded images", @"chevron": @YES, @"action": ^{
            UIViewController *vc = [FKTextViewController viewerWithTitle:@"Loaded images"
                                                                  text:[FKLoadedImages() componentsJoinedByString:@"\n"]];
            [self.navigationController pushViewController:vc animated:YES];
        } },
    ] }];

    return [FKListViewController listWithTitle:@"Application" sections:sections];
}

- (UIViewController *)deviceController {
    uint64_t memory = FKResidentMemory();
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{ @"title": @"Model", @"subtitle": FKDeviceModelIdentifier() }];
    [rows addObject:@{ @"title": @"System", @"subtitle": [NSString stringWithFormat:@"%@ %@", [UIDevice currentDevice].systemName, FKOSVersionString()] }];
    [rows addObject:@{ @"title": @"Name", @"subtitle": [UIDevice currentDevice].name ?: @"—" }];
    [rows addObject:@{ @"title": @"PID", @"subtitle": [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]] }];
    [rows addObject:@{ @"title": @"Resident memory", @"subtitle": FKHumanSize(memory) }];
    [rows addObject:@{ @"title": @"Uptime", @"subtitle": [NSString stringWithFormat:@"%.0f s", [[NSProcessInfo processInfo] systemUptime]] }];
    [rows addObject:@{ @"title": @"Jailbroken", @"subtitle": FKIsJailbroken() ? @"yes" : @"no" }];
    [rows addObject:@{ @"title": @"LAN addresses", @"subtitle": [FKLanAddresses() componentsJoinedByString:@", "] }];
    return [FKListViewController listWithTitle:@"Device" sections:@[ @{ @"title": @"Process", @"rows": rows } ]];
}

- (void)close { [[FKPanel sharedPanel] hide]; }

- (void)openSettings {
    [self.navigationController pushViewController:[[FKSettingsViewController alloc] init] animated:YES];
}

@end


#pragma mark - Status bar clock

static BOOL FKClockLikeString(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 3 || trimmed.length > 9) return NO;
    NSRange colon = [trimmed rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location < 1 || colon.location > 2) return NO;
    for (NSUInteger i = 0; i < colon.location; i++) {
        if (!isdigit((unsigned char)[trimmed characterAtIndex:i])) return NO;
    }
    if (trimmed.length < colon.location + 3) return NO;
    for (NSUInteger i = 0; i < 2; i++) {
        if (!isdigit((unsigned char)[trimmed characterAtIndex:colon.location + 1 + i])) return NO;
    }
    NSString *suffix = [[trimmed substringFromIndex:colon.location + 3]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].uppercaseString;
    return suffix.length == 0 || [suffix isEqualToString:@"AM"] || [suffix isEqualToString:@"PM"];
}

static NSString *FKClockCandidateString(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) return ((UILabel *)view).text;
    if (view.accessibilityLabel.length) return view.accessibilityLabel;
    if (view.accessibilityIdentifier.length) return view.accessibilityIdentifier;
    return nil;
}

static CGRect FKFindClockView(UIView *view, UIWindow *window, CGRect *timeFallback) {
    if (!view || view.hidden || view.alpha < 0.05) return CGRectNull;
    CGRect frame = [view convertRect:view.bounds toCoordinateSpace:window.screen.coordinateSpace];
    if (FKClockLikeString(FKClockCandidateString(view))) return frame;

    // Some builds expose the clock through a class name instead of text.
    if (timeFallback && CGRectIsNull(*timeFallback)) {
        NSString *className = NSStringFromClass([view class]);
        if ([className containsString:@"Time"] && frame.size.width >= 16 &&
            frame.size.height >= 10 && frame.size.height <= 40) {
            *timeFallback = frame;
        }
    }
    for (UIView *subview in view.subviews) {
        CGRect result = FKFindClockView(subview, window, timeFallback);
        if (!CGRectIsNull(result)) return result;
    }
    return CGRectNull;
}

// Screen-space frame of the status bar clock, or CGRectNull when it is not
// rendered (app hides the bar, immersive content, external display).
static CGRect FKStatusBarClockFrame(void) {
    UIApplication *application = [UIApplication sharedApplication];
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSString *className = NSStringFromClass([window class]);
            BOOL isStatusBarWindow = [className containsString:@"StatusBar"] ||
                                     fabs(window.windowLevel - UIWindowLevelStatusBar) < 1.0;
            if (!isStatusBarWindow) continue;
            CGRect fallback = CGRectNull;
            CGRect frame = FKFindClockView(window, window, &fallback);
            if (!CGRectIsNull(frame) && frame.size.width > 4 && frame.size.height > 4) return frame;
            if (!CGRectIsNull(fallback)) return fallback;
        }
    }
    return CGRectNull;
}

#pragma mark - Panel

@interface FKPanel () <UIGestureRecognizerDelegate>
@end

@implementation FKPanel {
    UIWindow *_window;
    UINavigationController *_navigation;
    NSHashTable<UIWindow *> *_observedWindows;
    __weak UIWindow *_previousKeyWindow;
}

+ (instancetype)sharedPanel {
    static FKPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [[FKPanel alloc] init]; });
    return panel;
}

- (instancetype)init {
    self = [super init];
    if (self) _observedWindows = [NSHashTable weakObjectsHashTable];
    return self;
}

- (BOOL)isVisible {
    if (![NSThread isMainThread]) {
        __block BOOL visible = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{ visible = [self isVisible]; });
        return visible;
    }
    return _window != nil && !_window.hidden && _window.alpha > 0.01;
}

- (void)show {
    if (![NSThread isMainThread]) { FKRunOnMain(^{ [self show]; }); return; }
    if (self.isVisible) return;

    UIWindowScene *scene = FKActiveWindowScene();
    UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                             : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 100;
    window.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];

    FKPanelHomeViewController *home = [[FKPanelHomeViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:home];
    navigation.navigationBar.prefersLargeTitles = NO;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.92];
    navigation.navigationBar.standardAppearance = appearance;
    navigation.navigationBar.scrollEdgeAppearance = appearance;
    window.rootViewController = navigation;

    _previousKeyWindow = FKKeyWindow();
    window.alpha = 0;
    window.hidden = NO;
    [window makeKeyAndVisible];
    _window = window;
    _navigation = navigation;
    FKLog(@"panel opened in %@", FKAppIdentifier());

    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        window.alpha = 1;
    } completion:nil];
}

- (void)hide {
    if (![NSThread isMainThread]) { FKRunOnMain(^{ [self hide]; }); return; }
    UIWindow *window = _window;
    if (!window) return;
    _window = nil;
    _navigation = nil;
    [UIView animateWithDuration:0.16 animations:^{
        window.alpha = 0;
    } completion:^(BOOL finished) {
        window.hidden = YES;
        window.rootViewController = nil;
        UIWindow *previous = self->_previousKeyWindow;
        if (previous) [previous makeKeyWindow];
    }];
}

- (void)toggle { self.isVisible ? [self hide] : [self show]; }

#pragma mark Gesture

- (void)installGestureOnWindow:(UIWindow *)window {
    if (!window) return;
    @synchronized(_observedWindows) {
        if ([_observedWindows containsObject:window]) return;
        [_observedWindows addObject:window];
    }
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleClockPress:)];
    press.minimumPressDuration = MAX(0.25, [FKPrefs doubleForKey:@"gestureDuration" defaultValue:0.5]);
    press.allowableMovement = 18;
    press.cancelsTouchesInView = NO;
    press.delegate = self;
    [window addGestureRecognizer:press];
}

// Trigger zone in the recognizer window's coordinate space. Prefers the real
// clock frame; falls back to the top-left status bar area when the clock cannot
// be located (hidden status bar, unusual status bar implementation).
- (CGRect)clockZoneInWindow:(UIWindow *)window {
    if (!window) return CGRectNull;
    CGRect screenFrame = FKStatusBarClockFrame();
    if (!CGRectIsNull(screenFrame)) {
        return CGRectInset([window convertRect:screenFrame fromWindow:nil], -4, -4);
    }
    if (![FKPrefs boolForKey:@"clockFallback" defaultValue:YES]) return CGRectNull;
    CGFloat statusHeight = 44;
    UIWindowScene *scene = window.windowScene ?: FKActiveWindowScene();
    if (scene.statusBarManager) statusHeight = MAX(20, scene.statusBarManager.statusBarFrame.size.height);
    return CGRectMake(0, 0, 130, statusHeight + 8);
}

- (void)handleClockPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIView *view = gesture.view;
    CGRect zone = [self clockZoneInWindow:view.window];
    if (CGRectIsNull(zone)) return;
    CGPoint point = [gesture locationInView:view];
    if (!CGRectContainsPoint(zone, point)) return;
    if ([FKPrefs boolForKey:@"haptics" defaultValue:YES]) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
    [self show];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = gestureRecognizer.view;
    if (!view) return NO;
    CGRect zone = [self clockZoneInWindow:view.window];
    if (CGRectIsNull(zone)) return NO;
    return CGRectContainsPoint(zone, [touch locationInView:view]);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end
