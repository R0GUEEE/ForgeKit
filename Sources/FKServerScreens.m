//
//  FKServerScreens.m — network console and JavaScript runtime screens
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import <CoreImage/CoreImage.h>

static UIView *FKCard(UIView *content) {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 14;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];
    return card;
}

static UILabel *FKLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

static UIButton *FKActionButton(NSString *title, UIColor *color, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 10;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(9, 14, 9, 14);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UIStackView *FKVerticalStack(CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

static UIImage *FKQRCodeImage(NSString *string, CGFloat scale) {
    if (!string.length) return nil;
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:[string dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *image = filter.outputImage;
    if (!image) return nil;
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:image fromRect:image.extent];
    UIImage *result = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
    if (cgImage) CGImageRelease(cgImage);
    return result;
}

#pragma mark - Server

@interface FKServerViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, strong) UILabel *qrHint;
@property (nonatomic, strong) UIScrollView *scroll;
@end

@implementation FKServerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Network";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    self.scroll = scroll;
    [self.view addSubview:scroll];

    UIStackView *stack = FKVerticalStack(12);
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-28],
    ]];

    UIStackView *statusStack = FKVerticalStack(8);
    self.statusLabel = FKLabel(@"Stopped", [UIFont systemFontOfSize:24 weight:UIFontWeightBold],
                                [UIColor secondaryLabelColor]);
    self.urlLabel = FKLabel(@"", [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular],
                            [UIColor secondaryLabelColor]);
    self.toggleButton = FKActionButton(@"Start server", [UIColor systemGreenColor], self, @selector(toggleServer));
    [statusStack addArrangedSubview:self.statusLabel];
    [statusStack addArrangedSubview:self.urlLabel];
    [statusStack addArrangedSubview:self.toggleButton];
    [stack addArrangedSubview:FKCard(statusStack)];

    UIStackView *portStack = FKVerticalStack(6);
    [portStack addArrangedSubview:FKLabel(@"Port", [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
                                          [UIColor secondaryLabelColor])];
    self.portField = [[UITextField alloc] init];
    self.portField.keyboardType = UIKeyboardTypeNumberPad;
    self.portField.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
    self.portField.text = [NSString stringWithFormat:@"%ld", (long)[FKPrefs integerForKey:@"port" defaultValue:8787]];
    self.portField.backgroundColor = [UIColor tertiarySystemFillColor];
    self.portField.layer.cornerRadius = 8;
    self.portField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    self.portField.leftViewMode = UITextFieldViewModeAlways;
    [self.portField.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    [portStack addArrangedSubview:self.portField];
    [portStack addArrangedSubview:FKActionButton(@"Apply port", [UIColor systemIndigoColor], self, @selector(applyPort))];
    [stack addArrangedSubview:FKCard(portStack)];

    UIStackView *tokenStack = FKVerticalStack(8);
    [tokenStack addArrangedSubview:FKLabel(@"MCP token", [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
                                           [UIColor secondaryLabelColor])];
    self.tokenField = [[UITextField alloc] init];
    self.tokenField.text = [FKPrefs token];
    self.tokenField.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.tokenField.backgroundColor = [UIColor tertiarySystemFillColor];
    self.tokenField.layer.cornerRadius = 8;
    self.tokenField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    self.tokenField.leftViewMode = UITextFieldViewModeAlways;
    [self.tokenField.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    [tokenStack addArrangedSubview:self.tokenField];
    UIStackView *tokenButtons = [[UIStackView alloc] init];
    tokenButtons.axis = UILayoutConstraintAxisHorizontal;
    tokenButtons.spacing = 8;
    tokenButtons.distribution = UIStackViewDistributionFillEqually;
    [tokenButtons addArrangedSubview:FKActionButton(@"Copy", [UIColor systemBlueColor], self, @selector(copyToken))];
    [tokenButtons addArrangedSubview:FKActionButton(@"Regenerate", [UIColor systemOrangeColor], self, @selector(regenerateToken))];
    [tokenStack addArrangedSubview:tokenButtons];
    [stack addArrangedSubview:FKCard(tokenStack)];

    UIStackView *qrStack = FKVerticalStack(8);
    self.qrView = [[UIImageView alloc] init];
    self.qrView.contentMode = UIViewContentModeScaleAspectFit;
    self.qrView.backgroundColor = [UIColor whiteColor];
    self.qrView.layer.cornerRadius = 10;
    self.qrView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.qrView.heightAnchor constraintEqualToConstant:190].active = YES;
    [qrStack addArrangedSubview:FKLabel(@"Scan to connect", [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold],
                                        [UIColor secondaryLabelColor])];
    [qrStack addArrangedSubview:self.qrView];
    self.qrHint = FKLabel(@"", [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular],
                          [UIColor secondaryLabelColor]);
    [qrStack addArrangedSubview:self.qrHint];
    [stack addArrangedSubview:FKCard(qrStack)];

    UIStackView *actions = FKVerticalStack(8);
    [actions addArrangedSubview:FKActionButton(@"Open dashboard in Safari", [UIColor systemTealColor], self, @selector(openDashboard))];
    [actions addArrangedSubview:FKActionButton(@"Request log", [UIColor systemGrayColor], self, @selector(openLog))];
    [stack addArrangedSubview:actions];

    UILabel *hint = FKLabel(@"MCP transport: POST /mcp (JSON-RPC 2.0, Streamable HTTP). The server binds "
                            @"0.0.0.0 on the chosen port. Add NSLocalNetworkUsageDescription to the host "
                            @"app's Info.plist so iOS allows LAN clients to connect.",
                            [UIFont systemFontOfSize:10], [UIColor tertiaryLabelColor]);
    [stack addArrangedSubview:hint];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:FKServerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)keyboardChanged:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    self.scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scroll.scrollIndicatorInsets = self.scroll.contentInset;
}

- (void)refresh {
    if (![NSThread isMainThread]) { FKRunOnMain(^{ [self refresh]; }); return; }
    FKHTTPServer *server = [FKHTTPServer sharedServer];
    BOOL running = server.isRunning;
    self.statusLabel.text = running ? @"Running" : @"Stopped";
    self.statusLabel.textColor = running ? [UIColor systemGreenColor] : [UIColor secondaryLabelColor];
    [self.toggleButton setTitle:running ? @"Stop server" : @"Start server" forState:UIControlStateNormal];
    self.toggleButton.backgroundColor = running ? [UIColor systemRedColor] : [UIColor systemGreenColor];
    uint16_t port = running ? server.port : (uint16_t)[FKPrefs integerForKey:@"port" defaultValue:8787];
    self.urlLabel.text = running
        ? [NSString stringWithFormat:@"http://%@:%u/mcp\nMCP + REST + dashboard", FKLanAddress(), port]
        : @"Server not running";
    self.qrHint.text = running ? [NSString stringWithFormat:@"http://%@:%u/mcp", FKLanAddress(), port] : @"";
    NSString *dashboard = [NSString stringWithFormat:@"http://%@:%u/?token=%@", FKLanAddress(), port, [FKPrefs token]];
    self.qrView.image = running ? FKQRCodeImage(dashboard, 8) : nil;
    if (!self.portField.isFirstResponder)
        self.portField.text = [NSString stringWithFormat:@"%ld", (long)[FKPrefs integerForKey:@"port" defaultValue:8787]];
}

- (void)toggleServer {
    FKHTTPServer *server = [FKHTTPServer sharedServer];
    if (server.isRunning) {
        [server stop];
        [self refresh];
        return;
    }
    NSInteger requested = self.portField.text.integerValue;
    if (requested < 1 || requested > 65535) {
        FKPresentAlert(@"Invalid port", @"Pick a value between 1 and 65535.");
        return;
    }
    uint16_t port = (uint16_t)requested;
    NSError *error = nil;
    if (![server startOnPort:port error:&error]) {
        FKPresentAlert(@"Cannot start", error.localizedDescription ?: @"unknown error");
    } else {
        [FKPrefs setInteger:port forKey:@"port"];
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
    [self refresh];
}

- (void)applyPort {
    NSInteger port = self.portField.text.integerValue;
    if (port < 1 || port > 65535) { FKPresentAlert(@"Invalid port", @"Pick a value between 1 and 65535."); return; }
    [FKPrefs setInteger:port forKey:@"port"];
    FKHTTPServer *server = [FKHTTPServer sharedServer];
    if (server.isRunning) {
        [server stop];
        NSError *error = nil;
        if (![server startOnPort:(uint16_t)port error:&error]) FKPresentAlert(@"Cannot restart", error.localizedDescription);
    }
    [self refresh];
}

- (void)copyToken {
    [UIPasteboard generalPasteboard].string = self.tokenField.text ?: @"";
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    self.title = @"Network · copied";
}

- (void)regenerateToken {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Regenerate token?"
                                                                   message:@"Existing MCP clients will be disconnected."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Regenerate" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [FKPrefs regenerateToken];
        self.tokenField.text = [FKPrefs token];
        [self refresh];
        [self copyToken];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openDashboard {
    uint16_t port = [FKHTTPServer sharedServer].isRunning
        ? [FKHTTPServer sharedServer].port
        : (uint16_t)[FKPrefs integerForKey:@"port" defaultValue:8787];
    NSString *dashboard = [NSString stringWithFormat:@"http://%@:%u/?token=%@", FKLanAddress(), port, [FKPrefs token]];
    NSURL *url = [NSURL URLWithString:dashboard];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openLog {
    [self.navigationController pushViewController:[FKLogViewController logController] animated:YES];
}

@end

#pragma mark - Runtime console

@interface FKRuntimeViewController ()
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UITextView *input;
@end

@implementation FKRuntimeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"JavaScript";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];

    UIStackView *stack = FKVerticalStack(10);
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-28],
    ]];

    [stack addArrangedSubview:FKLabel(@"JSC context with fk.read, fk.write, fk.list, fk.stat, fk.info, fk.log, fk.sleep.",
                                      [UIFont systemFontOfSize:10], [UIColor secondaryLabelColor])];

    self.input = [[UITextView alloc] init];
    self.input.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.input.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.input.layer.cornerRadius = 10;
    self.input.text = @"fk.info()";
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    [self.input.heightAnchor constraintEqualToConstant:130].active = YES;
    [stack addArrangedSubview:self.input];

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 8;
    [buttons addArrangedSubview:FKActionButton(@"Run", [UIColor systemPurpleColor], self, @selector(run))];
    [buttons addArrangedSubview:FKActionButton(@"Clear", [UIColor systemGrayColor], self, @selector(clearOutput))];
    [stack addArrangedSubview:buttons];

    [stack addArrangedSubview:FKLabel(@"Output", [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold],
                                      [UIColor secondaryLabelColor])];

    self.output = [[UITextView alloc] init];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.output.layer.cornerRadius = 10;
    self.output.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    self.output.text = @"—";
    [self.output.heightAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
    [stack addArrangedSubview:self.output];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                                                                           target:self
                                                                                           action:@selector(run)];
}

- (void)run {
    NSString *source = self.input.text ?: @"";
    if (!source.length) return;
    self.output.text = @"running…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        NSDate *start = [NSDate date];
        id result = [FKRuntime evaluateScript:source error:&error];
        NSTimeInterval elapsed = -[start timeIntervalSinceNow];
        NSString *text = error.length ? [NSString stringWithFormat:@"Error: %@", error] : FKJSONString(result, YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.output.text = [NSString stringWithFormat:@"%@\n\n// %.1f ms", text, elapsed * 1000];
        });
    });
}

- (void)clearOutput { self.output.text = @"—"; }

@end
