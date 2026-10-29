//
//  FKAgentScreens.m — agent chat and settings
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKAgent.h"
#import "FKToolsPrivate.h"

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
