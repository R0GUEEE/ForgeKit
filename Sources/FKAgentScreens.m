//
//  FKAgentScreens.m — agent chat and settings
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKAgent.h"
#import "FKToolsPrivate.h"

#pragma mark - Chat

@interface FKAgentChatViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *transcriptView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, assign) BOOL running;
@end

@implementation FKAgentChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Agent";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(newConversation)],
    ];

    self.transcriptView = [[UITextView alloc] init];
    self.transcriptView.editable = NO;
    self.transcriptView.alwaysBounceVertical = YES;
    self.transcriptView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.transcriptView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.transcriptView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.transcriptView];

    UIStackView *presets = [[UIStackView alloc] init];
    presets.axis = UILayoutConstraintAxisHorizontal;
    presets.spacing = 8;
    presets.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *titles = @[@"Inspect app", @"Build tweak", @"Patch a value"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        button.backgroundColor = [UIColor secondarySystemBackgroundColor];
        button.layer.cornerRadius = 12;
        button.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
        button.tag = 400 + (NSInteger)i;
        [button addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [presets addArrangedSubview:button];
    }
    [self.view addSubview:presets];

    UIView *bar = [[UIView alloc] init];
    bar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    self.inputField = [[UITextField alloc] init];
    self.inputField.placeholder = @"Ask the agent to build or change something…";
    self.inputField.font = [UIFont systemFontOfSize:13];
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.inputField];

    UIButton *send = [UIButton buttonWithType:UIButtonTypeSystem];
    [send setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    send.tintColor = [UIColor systemBlueColor];
    [send addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    send.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:send];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    self.bottomConstraint = [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.transcriptView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.transcriptView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.transcriptView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.transcriptView.bottomAnchor constraintEqualToAnchor:presets.topAnchor constant:-4],

        [presets.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [presets.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12],
        [presets.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-6],
        [presets.heightAnchor constraintEqualToConstant:30],

        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.bottomConstraint,
        [bar.heightAnchor constraintEqualToConstant:46],

        [self.inputField.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [self.inputField.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [send.leadingAnchor constraintEqualToAnchor:self.inputField.trailingAnchor constant:8],
        [send.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [send.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [send.widthAnchor constraintEqualToConstant:30],
        [send.heightAnchor constraintEqualToConstant:30],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshConfigBanner)
                                                 name:UITextFieldTextDidEndEditingNotification object:nil];

    if (![FKAgent apiKey].length) {
        [self append:@"No API key configured. Open ⚙︎ to add an OpenAI-compatible key, or set it with agent_config over MCP." system:YES];
    } else {
        [self append:[NSString stringWithFormat:@"Agent ready · %@ · mutations %@",
                      [FKAgent sharedAgent].model ?: @"?",
                      [FKAgent sharedAgent].allowMutations ? @"on" : @"off"] system:YES];
    }
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)keyboardChanged:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    self.bottomConstraint.constant = -MAX(0, overlap - self.view.safeAreaInsets.bottom);
    [self.view layoutIfNeeded];
}

- (void)refreshConfigBanner {}

- (void)append:(NSString *)text system:(BOOL)system {
    if (!text.length) return;
    NSString *prefix = system ? @"· " : @"";
    NSString *line = [NSString stringWithFormat:@"%@%@\n\n", prefix, text];
    NSMutableAttributedString *existing = [[NSMutableAttributedString alloc] initWithAttributedString:self.transcriptView.attributedText ?: [[NSAttributedString alloc] initWithString:@""]];
    UIColor *color = system ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    NSAttributedString *addition = [[NSAttributedString alloc] initWithString:line
                                                                  attributes:@{ NSForegroundColorAttributeName: color,
                                                                                NSFontAttributeName: self.transcriptView.font }];
    [existing appendAttributedString:addition];
    if (existing.length > 400000) {
        existing = [[NSMutableAttributedString alloc] initWithAttributedString:
                    [existing attributedSubstringFromRange:NSMakeRange(existing.length - 300000, 300000)]];
    }
    self.transcriptView.attributedText = existing;
    [self.transcriptView scrollRangeToVisible:NSMakeRange(self.transcriptView.attributedText.length, 0)];
}

- (void)send {
    NSString *prompt = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!prompt.length || self.running) return;
    self.inputField.text = @"";
    self.running = YES;
    [self.spinner startAnimating];
    [self append:[NSString stringWithFormat:@"you: %@", prompt] system:NO];

    __weak typeof(self) weakSelf = self;
    [[FKAgent sharedAgent] runPrompt:prompt completion:^(NSString *answer, NSArray<NSDictionary *> *activity, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.running = NO;
            [self.spinner stopAnimating];
            for (NSDictionary *entry in activity) {
                NSString *tool = entry[@"tool"] ?: @"?";
                BOOL ok = [entry[@"ok"] boolValue];
                [self append:[NSString stringWithFormat:@"→ %@ %@", tool, ok ? @"ok" : @"failed"] system:YES];
            }
            if (error) {
                [self append:[NSString stringWithFormat:@"error: %@", error.localizedDescription] system:YES];
            } else {
                [self append:[NSString stringWithFormat:@"agent: %@", answer ?: @""] system:NO];
            }
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [self send]; return YES; }

- (void)presetTapped:(UIButton *)sender {
    NSArray *prompts = @[
        @"Inspect this app: bundle identity, entitlements, container contents and the top-level classes. Summarise what it does and suggest three useful modifications.",
        @"Build a tweak dylib for this app. Ask me what behaviour to change if it is unclear, then call devkit_build with complete Objective-C source and a filter for this bundle id.",
        @"Find a value in memory or in the Objective-C runtime that I might want to change, show me its current value, and propose the smallest safe patch. Do not mutate anything until I confirm.",
    ];
    NSInteger index = sender.tag - 400;
    if (index < 0 || index >= (NSInteger)prompts.count) return;
    self.inputField.text = prompts[(NSUInteger)index];
    [self.inputField becomeFirstResponder];
}

- (void)newConversation {
    [[FKAgent sharedAgent] resetConversation];
    self.transcriptView.text = @"";
    [self append:@"New conversation." system:YES];
}

- (void)openSettings {
    [self.navigationController pushViewController:[[FKAgentSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
                                         animated:YES];
}

@end

#pragma mark - Settings

@implementation FKAgentSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Agent settings";
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self rebuild]; }

- (void)promptFor:(NSString *)title value:(NSString *)value secure:(BOOL)secure handler:(void (^)(NSString *))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = value;
        field.secureTextEntry = secure;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        handler(alert.textFields.firstObject.text ?: @"");
        [self rebuild];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)rebuild {
    __weak typeof(self) weakSelf = self;
    FKAgent *agent = [FKAgent sharedAgent];
    NSString *key = [FKAgent apiKey];
    self.sections = @[
        @{ @"title": @"Model", @"rows": @[
            @{ @"title": @"Endpoint", @"subtitle": agent.endpoint ?: @"", @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Endpoint" value:agent.endpoint ?: @"" secure:NO handler:^(NSString *value) {
                   agent.endpoint = value;
               }]; } },
            @{ @"title": @"Model", @"subtitle": agent.model ?: @"", @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Model" value:agent.model ?: @"" secure:NO handler:^(NSString *value) {
                   agent.model = value;
               }]; } },
            @{ @"title": @"API key",
               @"subtitle": key.length ? [NSString stringWithFormat:@"set (…%@)", [key substringFromIndex:MAX(0, (NSInteger)key.length - 4)]] : @"not set",
               @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"API key" value:@"" secure:YES handler:^(NSString *value) {
                   [FKAgent setAPIKey:value];
               }]; } },
        ] },
        @{ @"title": @"Execution", @"rows": @[
            @{ @"title": @"Allow mutations",
               @"subtitle": @"Permit writes, patches, hooks and shell commands",
               @"toggle": ^(BOOL on) { agent.allowMutations = on; [weakSelf rebuild]; },
               @"toggleValue": @(agent.allowMutations) },
            @{ @"title": @"Max tool steps", @"subtitle": [NSString stringWithFormat:@"%ld", (long)agent.maxSteps], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Max tool steps" value:[NSString stringWithFormat:@"%ld", (long)agent.maxSteps]
                                        secure:NO handler:^(NSString *value) {
                   NSInteger steps = value.integerValue;
                   if (steps > 0) agent.maxSteps = MIN(steps, 24);
               }]; } },
            @{ @"title": @"Theos path",
               @"subtitle": [FKPrefs stringForKey:@"theosPath" defaultValue:@"/opt/theos"], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Theos path"
                                           value:[FKPrefs stringForKey:@"theosPath" defaultValue:@"/opt/theos"]
                                          secure:NO handler:^(NSString *value) {
                   [FKPrefs setString:value forKey:@"theosPath"];
               }]; } },
        ] },
        @{ @"title": @"Projects", @"rows": @[
            @{ @"title": @"Scaffolded projects",
               @"subtitle": [NSString stringWithFormat:@"%lu", (unsigned long)[FKAgentTools projects].count], @"chevron": @YES,
               @"action": ^{
                   NSMutableArray *rows = [NSMutableArray array];
                   for (NSDictionary *project in [FKAgentTools projects]) {
                       [rows addObject:@{ @"title": project[@"name"] ?: @"?",
                                          @"subtitle": project[@"path"] ?: @"",
                                          @"chevron": @YES,
                                          @"action": ^{
                                              [UIPasteboard generalPasteboard].string = project[@"path"];
                                              FKPresentAlert(project[@"name"] ?: @"Project",
                                                             [NSString stringWithFormat:@"%@\n\nBuilt: %@",
                                                              project[@"path"], [project[@"built"] boolValue] ? @"yes" : @"no"]);
                                          } }];
                   }
                   if (!rows.count) [rows addObject:@{ @"title": @"No projects yet", @"subtitle": @"Ask the agent to build one" }];
                   [weakSelf.navigationController pushViewController:
                       [FKListViewController listWithTitle:@"Projects"
                                                  sections:@[ @{ @"title": @"Projects", @"rows": rows } ]]
                                                           animated:YES];
               } },
            @{ @"title": @"Clear conversation", @"chevron": @YES,
               @"action": ^{ [[FKAgent sharedAgent] resetConversation]; FKPresentAlert(@"Agent", @"Conversation cleared."); } },
            @{ @"title": @"Remove API key", @"destructive": @YES, @"chevron": @YES,
               @"action": ^{ [FKAgent setAPIKey:nil]; [weakSelf rebuild]; } },
        ] },
    ];
    [self reloadSections];
}

@end
