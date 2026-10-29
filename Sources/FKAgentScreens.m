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
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
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

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    self.sendButton.tintColor = [UIColor systemBlueColor];
    [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.sendButton];

    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setImage:[UIImage systemImageNamed:@"stop.circle.fill"] forState:UIControlStateNormal];
    self.stopButton.tintColor = [UIColor systemRedColor];
    self.stopButton.hidden = YES;
    [self.stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:self.stopButton];

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
        [self.sendButton.leadingAnchor constraintEqualToAnchor:self.inputField.trailingAnchor constant:8],
        [self.sendButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:30],
        [self.sendButton.heightAnchor constraintEqualToConstant:30],

        [self.stopButton.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.stopButton.widthAnchor constraintEqualToConstant:30],
        [self.stopButton.heightAnchor constraintEqualToConstant:30],

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
        [self append:[NSString stringWithFormat:@"Agent ready · %@ · %@ · mutations %@",
                      [FKAgent sharedAgent].model ?: @"?",
                      [FKAgent sharedAgent].provider ?: @"custom",
                      [FKAgent sharedAgent].allowMutations ? @"on" : @"off"] system:YES];
    }
    [self renderPersistedHistory];
}

- (void)renderPersistedHistory {
    NSArray<NSDictionary *> *history = [[FKAgent sharedAgent] transcript];
    if (!history.count) return;
    NSInteger start = MAX(0, (NSInteger)history.count - 60);
    [self append:[NSString stringWithFormat:@"· restored %lu earlier messages", (unsigned long)history.count] system:YES];
    for (NSInteger index = start; index < (NSInteger)history.count; index++) {
        NSDictionary *message = history[(NSUInteger)index];
        NSString *role = message[@"role"];
        id content = message[@"content"];
        if ([role isEqualToString:@"user"] && [content isKindOfClass:[NSString class]] && [content length]) {
            [self append:[NSString stringWithFormat:@"you: %@", content] system:NO];
        } else if ([role isEqualToString:@"assistant"]) {
            if ([content isKindOfClass:[NSString class]] && [content length])
                [self append:[NSString stringWithFormat:@"agent: %@", content] system:NO];
            else if ([message[@"tool_calls"] isKindOfClass:[NSArray class]])
                [self append:@"· planned tool calls" system:YES];
        }
    }
    [self append:@"" system:YES];
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
    self.sendButton.hidden = YES;
    self.stopButton.hidden = NO;
    [self.spinner startAnimating];
    [self append:[NSString stringWithFormat:@"you: %@", prompt] system:NO];

    __weak typeof(self) weakSelf = self;
    [[FKAgent sharedAgent] runPrompt:prompt completion:^(NSString *answer, NSArray<NSDictionary *> *activity, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.running = NO;
            self.sendButton.hidden = NO;
            self.stopButton.hidden = YES;
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
                NSDictionary *usage = [FKAgent sharedAgent].lastUsage;
                if ([usage[@"total_tokens"] respondsToSelector:@selector(integerValue)]) {
                    [self append:[NSString stringWithFormat:@"· %@ prompt + %@ completion = %@ tokens",
                                  usage[@"prompt_tokens"] ?: @0, usage[@"completion_tokens"] ?: @0,
                                  usage[@"total_tokens"]] system:YES];
                }
            }
        });
    }];
}

- (void)stop {
    [[FKAgent sharedAgent] stop];
    [self append:@"· stop requested" system:YES];
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

- (NSString *)providerName {
    NSDictionary *provider = [FKAgent providerWithIdentifier:[FKAgent sharedAgent].provider];
    return provider[@"name"] ?: @"Custom endpoint";
}

- (void)chooseProvider {
    NSArray *providers = [FKAgent providers];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Provider"
                                                                   message:@"Endpoint and default model are filled from the provider's official API."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *provider in providers) {
        NSString *identifier = provider[@"id"];
        NSString *title = [identifier isEqualToString:[FKAgent sharedAgent].provider]
            ? [NSString stringWithFormat:@"✓ %@", provider[@"name"]] : provider[@"name"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[FKAgent sharedAgent] applyProvider:identifier];
            [self rebuild];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseModel {
    FKAgent *agent = [FKAgent sharedAgent];
    if (![FKAgent apiKey].length) {
        FKPresentAlert(@"Model list", @"Add an API key first; local providers (Ollama, LM Studio) can be listed without one.");
    }
    __weak typeof(self) weakSelf = self;
    void (^show)(NSArray *) = ^(NSArray *models) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *model in models) {
            [rows addObject:@{ @"title": model,
                               @"subtitle": [model isEqualToString:agent.model] ? @"current" : @"",
                               @"check": @([model isEqualToString:agent.model]),
                               @"action": ^{
                                   agent.model = model;
                                   [weakSelf.navigationController popViewControllerAnimated:YES];
                                   [weakSelf rebuild];
                               } }];
            if (rows.count >= 300) break;
        }
        if (!rows.count) [rows addObject:@{ @"title": @"No models returned", @"subtitle": @"Enter a model name manually" }];
        FKListViewController *list = [FKListViewController listWithTitle:@"Models"
                                                                sections:@[ @{ @"title": [NSString stringWithFormat:@"%lu available", (unsigned long)models.count],
                                                                               @"rows": rows } ]];
        [weakSelf.navigationController pushViewController:list animated:YES];
    };
    [[FKAgent sharedAgent] fetchModelsWithCompletion:^(NSArray<NSString *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                FKPresentAlert(@"Model list", error.localizedDescription);
                return;
            }
            show(models ?: @[]);
        });
    }];
}

- (void)chooseFrom:(NSArray<NSString *> *)options title:(NSString *)title
           current:(NSString *)current handler:(void (^)(NSString *))handler {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *option in options) {
        NSString *label = [option isEqualToString:current] ? [NSString stringWithFormat:@"✓ %@", option] : option;
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            handler(option);
            [self rebuild];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)rebuild {
    __weak typeof(self) weakSelf = self;
    FKAgent *agent = [FKAgent sharedAgent];
    NSString *key = [FKAgent apiKey];
    self.sections = @[
        @{ @"title": @"Model", @"rows": @[
            @{ @"title": @"Provider", @"subtitle": [weakSelf providerName], @"chevron": @YES,
               @"action": ^{ [weakSelf chooseProvider]; } },
            @{ @"title": @"Endpoint", @"subtitle": agent.endpoint ?: @"", @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Endpoint" value:agent.endpoint ?: @"" secure:NO handler:^(NSString *value) {
                   agent.endpoint = value;
               }]; } },
            @{ @"title": @"Model", @"subtitle": agent.model ?: @"", @"chevron": @YES,
               @"action": ^{ [weakSelf chooseModel]; } },
            @{ @"title": @"Enter model manually", @"chevron": @YES,
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
        @{ @"title": @"Sampling", @"rows": @[
            @{ @"title": @"Temperature", @"subtitle": [NSString stringWithFormat:@"%.2f", agent.temperature], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Temperature (0-2)"
                                           value:[NSString stringWithFormat:@"%.2f", agent.temperature]
                                          secure:NO handler:^(NSString *value) {
                   double number = value.doubleValue;
                   if (number >= 0 && number <= 2) agent.temperature = number;
               }]; } },
            @{ @"title": @"Max tokens", @"subtitle": agent.maxTokens ? [NSString stringWithFormat:@"%ld", (long)agent.maxTokens] : @"provider default",
               @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Max tokens (0 = default)"
                                           value:[NSString stringWithFormat:@"%ld", (long)agent.maxTokens]
                                          secure:NO handler:^(NSString *value) {
                   agent.maxTokens = value.integerValue;
               }]; } },
            @{ @"title": @"Request timeout", @"subtitle": [NSString stringWithFormat:@"%.0f s", agent.requestTimeout], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Timeout (seconds)"
                                           value:[NSString stringWithFormat:@"%.0f", agent.requestTimeout]
                                          secure:NO handler:^(NSString *value) {
                   agent.requestTimeout = value.doubleValue;
               }]; } },
        ] },
        @{ @"title": @"Tools", @"rows": @[
            @{ @"title": @"Tool profile", @"subtitle": agent.toolProfile ?: @"all", @"chevron": @YES,
               @"action": ^{ [weakSelf chooseFrom:@[@"all", @"safe", @"custom"] title:@"Tool profile"
                                          current:agent.toolProfile handler:^(NSString *value) {
                   agent.toolProfile = value;
               }]; } },
            @{ @"title": @"Tool mode", @"subtitle": agent.toolMode ?: @"auto", @"chevron": @YES,
               @"action": ^{ [weakSelf chooseFrom:@[@"auto", @"none", @"required"] title:@"Tool mode"
                                          current:agent.toolMode handler:^(NSString *value) {
                   agent.toolMode = value;
               }]; } },
            @{ @"title": @"Custom tool list",
               @"subtitle": agent.enabledTools.count ? [agent.enabledTools componentsJoinedByString:@", "] : @"empty",
               @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Tools, comma separated"
                                           value:[agent.enabledTools componentsJoinedByString:@","]
                                          secure:NO handler:^(NSString *value) {
                   NSMutableArray *names = [NSMutableArray array];
                   for (NSString *piece in [value componentsSeparatedByString:@","]) {
                       NSString *trimmed = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                       if (trimmed.length) [names addObject:trimmed];
                   }
                   agent.enabledTools = names;
               }]; } },
            @{ @"title": @"Max tool result", @"subtitle": [NSString stringWithFormat:@"%ld chars", (long)agent.maxToolResultChars], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Max tool result characters"
                                           value:[NSString stringWithFormat:@"%ld", (long)agent.maxToolResultChars]
                                          secure:NO handler:^(NSString *value) {
                   agent.maxToolResultChars = value.integerValue;
               }]; } },
            @{ @"title": @"Context messages", @"subtitle": [NSString stringWithFormat:@"%ld", (long)agent.contextMessages], @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"History messages per request"
                                           value:[NSString stringWithFormat:@"%ld", (long)agent.contextMessages]
                                          secure:NO handler:^(NSString *value) {
                   agent.contextMessages = value.integerValue;
               }]; } },
        ] },
        @{ @"title": @"Prompt", @"rows": @[
            @{ @"title": @"Extra instructions",
               @"subtitle": agent.systemInstructions.length ? agent.systemInstructions : @"none", @"chevron": @YES,
               @"action": ^{ [weakSelf promptFor:@"Extra system instructions" value:agent.systemInstructions ?: @""
                                          secure:NO handler:^(NSString *value) {
                   agent.systemInstructions = value;
               }]; } },
            @{ @"title": @"Extra headers",
               @"subtitle": agent.extraHeaders.count ? [NSString stringWithFormat:@"%lu header(s)", (unsigned long)agent.extraHeaders.count] : @"none",
               @"chevron": @YES,
               @"action": ^{
                   NSData *data = [NSJSONSerialization dataWithJSONObject:agent.extraHeaders ?: @{} options:0 error:nil];
                   NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
                   [weakSelf promptFor:@"Headers JSON" value:json secure:NO handler:^(NSString *value) {
                       NSData *input = [value dataUsingEncoding:NSUTF8StringEncoding];
                       id object = input.length ? [NSJSONSerialization JSONObjectWithData:input options:0 error:nil] : nil;
                       if ([object isKindOfClass:[NSDictionary class]]) agent.extraHeaders = object;
                   }];
               } },
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
