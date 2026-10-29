//
//  FKShellScreens.m — terminal UI for the sandbox shell
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKShell.h"

@interface FKShellViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *output;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UILabel *promptLabel;
@property (nonatomic, strong) NSLayoutConstraint *inputBottom;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@property (nonatomic, assign) NSInteger historyIndex;
@end

@implementation FKShellViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Shell";
    self.view.backgroundColor = [UIColor blackColor];

    self.output = [[UITextView alloc] init];
    self.output.editable = NO;
    self.output.selectable = YES;
    self.output.backgroundColor = [UIColor blackColor];
    self.output.textColor = [UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1.0];
    self.output.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    self.output.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.output.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.output.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.output];

    UIView *bar = [[UIView alloc] init];
    bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    self.promptLabel = [[UILabel alloc] init];
    self.promptLabel.text = @"$";
    self.promptLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
    self.promptLabel.textColor = [UIColor systemGreenColor];
    self.promptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.promptLabel];

    self.input = [[UITextField alloc] init];
    self.input.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.input.textColor = [UIColor whiteColor];
    self.input.tintColor = [UIColor systemGreenColor];
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.returnKeyType = UIReturnKeyGo;
    self.input.delegate = self;
    self.input.placeholder = @"command";
    self.input.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.input];

    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    [send setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    send.tintColor = [UIColor systemGreenColor];
    [send addTarget:self action:@selector(runCurrent) forControlEvents:UIControlEventTouchUpInside];
    send.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:send];

    UIStackView *shortcuts = [[UIStackView alloc] init];
    shortcuts.axis = UILayoutConstraintAxisHorizontal;
    shortcuts.spacing = 10;
    shortcuts.distribution = UIStackViewDistributionEqualSpacing;
    shortcuts.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *labels = @[@"help", @"ls -l", @"sandbox", @"containers", @"sysinfo", @"clear"];
    for (NSUInteger i = 0; i < labels.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:labels[i] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
        [button setTitleColor:[UIColor colorWithWhite:0.7 alpha:1.0] forState:UIControlStateNormal];
        button.tag = (NSInteger)i;
        [button addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
        [shortcuts addArrangedSubview:button];
    }
    [bar addSubview:shortcuts];

    self.inputBottom = [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.output.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.output.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.output.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.output.bottomAnchor constraintEqualToAnchor:bar.topAnchor],

        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottom,
        [bar.heightAnchor constraintEqualToConstant:84],

        [self.promptLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [self.promptLabel.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [self.promptLabel.widthAnchor constraintEqualToConstant:12],

        [self.input.leadingAnchor constraintEqualToAnchor:self.promptLabel.trailingAnchor constant:4],
        [self.input.topAnchor constraintEqualToAnchor:bar.topAnchor constant:6],
        [self.input.heightAnchor constraintEqualToConstant:34],

        [send.leadingAnchor constraintEqualToAnchor:self.input.trailingAnchor constant:6],
        [send.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [send.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
        [send.widthAnchor constraintEqualToConstant:30],
        [send.heightAnchor constraintEqualToConstant:30],

        [shortcuts.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [shortcuts.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [shortcuts.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-6],
        [shortcuts.heightAnchor constraintEqualToConstant:26],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"network"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(serverMenu)];

    self.history = [NSMutableArray array];
    self.historyIndex = 0;
    [self appendLine:[NSString stringWithFormat:@"ForgeKit shell %@ — %@", FKVersionString, FKAppIdentifier()]];
    [self appendLine:@"Type 'help'. Commands run in-process; no popen, no exec."];
    [self appendLine:[NSString stringWithFormat:@"cwd: %@", [FKShell sharedShell].currentDirectory]];
    [self appendLine:@""];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)keyboardChanged:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    self.inputBottom.constant = -(MAX(0, overlap - safeBottom));
    [self.view layoutIfNeeded];
}

- (void)appendLine:(NSString *)line {
    self.output.text = [self.output.text stringByAppendingFormat:@"%@\n", line ?: @""];
    if (self.output.text.length > 400000)
        self.output.text = [self.output.text substringFromIndex:self.output.text.length - 300000];
    [self.output scrollRangeToVisible:NSMakeRange(self.output.text.length, 0)];
}

- (void)runCurrent {
    NSString *command = [self.input.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.input.text = @"";
    if (!command.length) return;
    [self.history addObject:command];
    self.historyIndex = (NSInteger)self.history.count;
    [self appendLine:[NSString stringWithFormat:@"$ %@", command]];
    NSString *outputText = [[FKShell sharedShell] execute:command];
    if (outputText.length) [self appendLine:outputText];
    self.title = [NSString stringWithFormat:@"Shell · %@", [FKShell sharedShell].currentDirectory.lastPathComponent];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self runCurrent]; return YES; }

- (void)shortcutTapped:(UIButton *)sender {
    NSArray *commands = @[@"help", @"ls -l", @"sandbox", @"containers", @"sysinfo", @""];
    NSString *command = commands[(NSUInteger)sender.tag];
    if (!command.length) { self.output.text = @""; return; }
    self.input.text = command;
    [self runCurrent];
}

- (void)serverMenu {
    FKShellServer *server = [FKShellServer sharedServer];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"TCP shell"
                                                                    message:[NSString stringWithFormat:
                                        @"127.0.0.1:%u · %@\nclient.py \"help\" --port %u",
                                        server.port, server.isRunning ? @"running" : @"stopped", server.port]
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:server.isRunning ? @"Stop server" : @"Start server"
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (server.isRunning) {
            [server stop];
        } else {
            NSError *error = nil;
            if (![server startOnPort:8080 error:&error])
                FKPresentAlert(@"Cannot start", error.localizedDescription ?: @"bind failed");
        }
        [self appendLine:server.isRunning ? @"TCP shell started on 127.0.0.1:8080" : @"TCP shell stopped"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy endpoint" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = @"iproxy 8080 8080  # then: python3 client.py \"help\"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Toggle LAN bind" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        BOOL lan = [FKPrefs boolForKey:@"shellBindLAN" defaultValue:NO];
        [FKPrefs setBool:!lan forKey:@"shellBindLAN"];
        [self appendLine:!lan ? @"LAN bind enabled — restart the server to apply" : @"Loopback-only mode"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
