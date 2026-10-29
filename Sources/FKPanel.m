//
//  FKPanel.m — hidden toolkit panel, home screen and panel lifecycle
//

#import "ForgeKit.h"
#import <QuartzCore/QuartzCore.h>
#import "FKPanelScreens.h"
#import "FKUtilities.h"
#import "FKRuntimeKit.h"
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
    tile.iconView.backgroundColor = [tint colorWithAlphaComponent:0.18];
    tile.iconView.layer.cornerRadius = 12;
    tile.iconView.layer.cornerCurve = kCACornerCurveContinuous;
    tile.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
    tile.layer.cornerRadius = 16;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.borderWidth = 1;
    tile.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.07].CGColor;
    tile.iconView.clipsToBounds = YES;
    [tile addSubview:tile.iconView];

    tile.titleLabel = [[UILabel alloc] init];
    tile.titleLabel.text = title;
    tile.titleLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightMedium];
    tile.titleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.88];
    tile.titleLabel.textAlignment = NSTextAlignmentCenter;
    tile.titleLabel.numberOfLines = 2;
    [tile addSubview:tile.titleLabel];
    return tile;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat labelHeight = 26;
    CGFloat available = self.bounds.size.height - labelHeight - 12;
    CGFloat side = MIN(MIN(self.bounds.size.width - 16, available), (CGFloat)46);
    side = MAX(side, 20);
    self.iconView.frame = CGRectMake((self.bounds.size.width - side) / 2, 6, side, side);
    self.iconView.layer.cornerRadius = MAX(6, side * 0.28);
    self.titleLabel.frame = CGRectMake(2, CGRectGetMaxY(self.iconView.frame) + 2,
                                       self.bounds.size.width - 4,
                                       self.bounds.size.height - CGRectGetMaxY(self.iconView.frame) - 2);
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

@interface FKGradientView : UIView
@end
@implementation FKGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
@end

@interface FKQuickActionView : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIColor *tint;
- (void)configureTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint active:(BOOL)active;
@end
@implementation FKQuickActionView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.7;
        [self addSubview:_titleLabel];
    }
    return self;
}
- (void)configureTitle:(NSString *)title symbol:(NSString *)symbol tint:(UIColor *)tint active:(BOOL)active {
    self.tint = tint;
    self.iconView.image = [UIImage systemImageNamed:symbol];
    self.iconView.tintColor = active ? tint : [UIColor colorWithWhite:0.75 alpha:1.0];
    self.titleLabel.text = title;
    self.backgroundColor = active ? [tint colorWithAlphaComponent:0.16] : [UIColor colorWithWhite:1 alpha:0.06];
    self.layer.borderColor = (active ? [tint colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:1 alpha:0.08]).CGColor;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.iconView.frame = CGRectMake((self.bounds.size.width - 18) / 2, 9, 18, 18);
    self.titleLabel.frame = CGRectMake(2, 30, self.bounds.size.width - 4, self.bounds.size.height - 32);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}
@end

@interface FKPanelHomeViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation FKPanelHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ForgeKit";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.045 green:0.05 blue:0.065 alpha:1.0];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonItemStyleDone
                                                                                           target:self
                                                                                           action:@selector(close)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(openSettings)];

    UIStackView *root = [[UIStackView alloc] init];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 9;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [root.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [root.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [root.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];

    UIView *header = [self headerCard];
    [root addArrangedSubview:header];
    [header.heightAnchor constraintEqualToConstant:88].active = YES;

    UIView *quick = [self quickActionsRow];
    [root addArrangedSubview:quick];
    [quick.heightAnchor constraintEqualToConstant:58].active = YES;

    UIStackView *grid = (UIStackView *)[self tileGrid];
    [grid setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [root addArrangedSubview:grid];

    UIView *footer = [self footerCard];
    [root addArrangedSubview:footer];
    [footer.heightAnchor constraintEqualToConstant:14].active = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshStatus)
                                                 name:FKServerDidChangeNotification object:nil];
    [self refreshStatus];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)refreshStatus {
    if (![NSThread isMainThread]) {
        FKRunOnMain(^{ [self refreshStatus]; });
        return;
    }
    FKHTTPServer *server = [FKHTTPServer sharedServer];
    NSString *state = server.isRunning ? [NSString stringWithFormat:@"MCP :%u", server.port] : @"MCP off";
    self.statusLabel.text = [NSString stringWithFormat:@"%@ · %lu tools", state,
                             (unsigned long)[FKTools toolDefinitions].count];
    self.statusLabel.textColor = server.isRunning ? [UIColor colorWithRed:0.45 green:1.0 blue:0.6 alpha:1.0]
                                                  : [UIColor colorWithWhite:0.8 alpha:0.8];
    [self rebuildQuickActions];
}

- (UIView *)headerCard {
    FKGradientView *card = [[FKGradientView alloc] init];
    CAGradientLayer *gradient = (CAGradientLayer *)card.layer;
    gradient.colors = @[ (id)[UIColor colorWithRed:0.95 green:0.45 blue:0.18 alpha:1.0].CGColor,
                         (id)[UIColor colorWithRed:0.78 green:0.16 blue:0.32 alpha:1.0].CGColor ];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppIcon60x60"] ?: [UIImage systemImageNamed:@"app.fill"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = [UIColor whiteColor];
    icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    icon.layer.cornerRadius = 11;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:icon];

    UILabel *name = [[UILabel alloc] init];
    name.text = FKAppName();
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    name.textColor = [UIColor whiteColor];
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumScaleFactor = 0.7;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    UILabel *identifier = [[UILabel alloc] init];
    identifier.text = [NSString stringWithFormat:@"%@ · %@", FKAppIdentifier(), FKAppVersion()];
    identifier.font = [UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightRegular];
    identifier.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    identifier.adjustsFontSizeToFitWidth = YES;
    identifier.minimumScaleFactor = 0.6;
    identifier.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:identifier];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:8.5 weight:UIFontWeightMedium];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:self.statusLabel];

    UIStackView *badges = [[UIStackView alloc] init];
    badges.axis = UILayoutConstraintAxisHorizontal;
    badges.spacing = 5;
    badges.translatesAutoresizingMaskIntoConstraints = NO;
    FKBadgeLabel *sandbox = FKMakeBadge(FKIsJailbroken() ? @"JAILBROKEN" : @"SANDBOXED", [UIColor whiteColor]);
    sandbox.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    FKBadgeLabel *ios = FKMakeBadge([NSString stringWithFormat:@"iOS %@", FKOSVersionString()], [UIColor whiteColor]);
    ios.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    [badges addArrangedSubview:sandbox];
    [badges addArrangedSubview:ios];
    [card addSubview:badges];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:13],
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:11],
        [icon.widthAnchor constraintEqualToConstant:40],
        [icon.heightAnchor constraintEqualToConstant:40],
        [name.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:13],
        [name.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusLabel.leadingAnchor constant:-8],
        [identifier.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [identifier.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2],
        [identifier.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-13],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-13],
        [self.statusLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:90],
        [badges.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:13],
        [badges.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:7],
        [badges.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-9],
        [badges.heightAnchor constraintEqualToConstant:18],
    ]];
    return card;
}

- (UIView *)quickActionsRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;
    row.tag = 900;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self populateQuickActionsInRow:row];
    return row;
}

- (void)rebuildQuickActions {
    UIStackView *row = (UIStackView *)[self.view viewWithTag:900];
    if (!row) return;
    [self populateQuickActionsInRow:row];
}

- (void)populateQuickActionsInRow:(UIStackView *)row {
    for (UIView *view in row.arrangedSubviews) {
        [row removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    BOOL serverRunning = [FKHTTPServer sharedServer].isRunning;
    NSArray *definitions = @[
        @{ @"title": serverRunning ? @"Stop MCP" : @"Start MCP",
           @"symbol": @"antenna.radiowaves.left.and.right",
           @"tint": [UIColor systemGreenColor], @"active": @(serverRunning) },
        @{ @"title": @"Capture",
           @"symbol": @"waveform.path.ecg",
           @"tint": [UIColor systemOrangeColor],
           @"active": @([FKPrefs boolForKey:@"netCapture" defaultValue:YES]) },
        @{ @"title": @"Inspector",
           @"symbol": @"safari",
           @"tint": [UIColor systemBlueColor],
           @"active": @([FKPrefs boolForKey:@"webInspector" defaultValue:NO]) },
        @{ @"title": @"Frames",
           @"symbol": @"rectangle.dashed",
           @"tint": [UIColor systemPurpleColor], @"active": @NO },
    ];
    for (NSUInteger i = 0; i < definitions.count; i++) {
        NSDictionary *definition = definitions[i];
        FKQuickActionView *action = [[FKQuickActionView alloc] initWithFrame:CGRectZero];
        action.tag = 900 + (NSInteger)i;
        [action configureTitle:definition[@"title"] symbol:definition[@"symbol"]
                          tint:definition[@"tint"] active:[definition[@"active"] boolValue]];
        [action addTarget:self action:@selector(quickActionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addArrangedSubview:action];
    }
}

- (void)quickActionTapped:(FKQuickActionView *)sender {
    NSInteger index = sender.tag - 900;
    if (index == 0) {
        FKHTTPServer *server = [FKHTTPServer sharedServer];
        if (server.isRunning) {
            [server stop];
        } else {
            NSError *error = nil;
            if (![server startOnPort:(uint16_t)[FKPrefs integerForKey:@"port" defaultValue:8787] error:&error])
                FKPresentAlert(@"MCP server", error.localizedDescription ?: @"cannot start");
        }
    } else if (index == 1) {
        BOOL enabled = [FKPrefs boolForKey:@"netCapture" defaultValue:YES];
        [FKPrefs setBool:!enabled forKey:@"netCapture"];
    } else if (index == 2) {
        BOOL enabled = [FKPrefs boolForKey:@"webInspector" defaultValue:NO];
        [FKUtilities setWebInspectorEnabled:!enabled];
    } else if (index == 3) {
        [FKRuntimeKit highlightAllViewsInWindow:FKKeyWindow() duration:2.0];
    }
    [self refreshStatus];
}

- (UIView *)tileGrid {
    NSArray *tiles = @[
        @{ @"title": @"FLEX", @"symbol": @"ladybug.fill", @"tint": [UIColor systemRedColor], @"action": @"flex" },
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
    NSInteger columns = 4;
    NSInteger rows = ((NSInteger)tiles.count + columns - 1) / columns;
    UIStackView *grid = [[UIStackView alloc] init];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;
    grid.distribution = UIStackViewDistributionFillEqually;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger row = 0; row < rows; row++) {
        UIStackView *rowStack = [[UIStackView alloc] init];
        rowStack.axis = UILayoutConstraintAxisHorizontal;
        rowStack.spacing = 8;
        rowStack.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger column = 0; column < columns; column++) {
            NSInteger index = row * columns + column;
            if (index < (NSInteger)tiles.count) {
                NSDictionary *info = tiles[(NSUInteger)index];
                FKTileView *tile = [FKTileView tileWithTitle:info[@"title"] symbol:info[@"symbol"] tint:info[@"tint"]];
                tile.tag = 200 + index;
                [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
                [rowStack addArrangedSubview:tile];
            } else {
                UIView *placeholder = [[UIView alloc] init];
                placeholder.userInteractionEnabled = NO;
                [rowStack addArrangedSubview:placeholder];
            }
        }
        [grid addArrangedSubview:rowStack];
    }
    return grid;
}

- (UIView *)footerCard {
    UIView *container = [[UIView alloc] init];
    UILabel *hint = [[UILabel alloc] init];
    hint.text = [NSString stringWithFormat:@"clock hold · volume up/down · MCP :%ld · %lu tools",
                 (long)[FKPrefs integerForKey:@"port" defaultValue:8787],
                 (unsigned long)[FKTools toolDefinitions].count];
    hint.font = [UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightRegular];
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.38];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.adjustsFontSizeToFitWidth = YES;
    hint.minimumScaleFactor = 0.7;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [hint.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [hint.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];
    return container;
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
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    FKPanelHomeViewController *home = [[FKPanelHomeViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:home];
    navigation.navigationBar.prefersLargeTitles = NO;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName: [UIColor whiteColor] };
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
