#pragma mark - Defaults

@interface FKDefaultsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *domains;
@end

@implementation FKDefaultsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Preferences";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(load)];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self load];
}

- (void)load {
    NSDictionary *result = [FKTools callTool:@"app_defaults_list" arguments:@{}];
    self.domains = result[@"domains"] ?: @[];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%lu domains", (unsigned long)self.domains.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.domains.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"domain";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *domain = self.domains[(NSUInteger)indexPath.row];
    cell.textLabel.text = domain[@"domain"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ keys · %@", domain[@"keys"], FKHumanSize([domain[@"bytes"] unsignedLongLongValue])];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *domain = self.domains[(NSUInteger)indexPath.row];
    NSString *name = domain[@"domain"];
    NSString *path = domain[@"path"];
    NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id value = values[key];
        NSString *subtitle = [value isKindOfClass:[NSString class]] ? value : FKJSONString(value, NO);
        [rows addObject:@{
            @"title": key,
            @"subtitle": subtitle,
            @"chevron": @YES,
            @"action": ^{
                [self editKey:key domain:name path:path current:value];
            },
        }];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No keys", @"subtitle": @"" }];
    FKListViewController *detail = [FKListViewController listWithTitle:name
                                                              sections:@[ @{ @"title": @"Values", @"rows": rows } ]];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)editKey:(NSString *)key domain:(NSString *)domain path:(NSString *)path current:(id)current {
    NSString *initial = [current isKindOfClass:[NSString class]] ? current : FKJSONString(current, NO);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:key
                                                                   message:domain
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = initial;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        NSDictionary *result = [FKTools callTool:@"app_plist_set"
                                       arguments:@{ @"path": path, @"key": key, @"value": text, @"value_type": @"string" }];
        if (![result[@"ok"] boolValue]) FKPresentAlert(@"Write failed", result[@"error"]);
        [self load];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Keychain

@interface FKKeychainViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@end

@implementation FKKeychainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Keychain";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 54;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(load)];
    [self load];
}

- (void)load {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *generic = FKKeychainItems(@"generic");
        NSArray *internet = FKKeychainItems(@"internet");
        NSArray *certificates = FKKeychainItems(@"certificate");
        NSMutableArray *sections = [NSMutableArray array];
        if (generic.count) [sections addObject:@{ @"title": [NSString stringWithFormat:@"Generic (%lu)", (unsigned long)generic.count], @"rows": [self rowsFor:generic] }];
        if (internet.count) [sections addObject:@{ @"title": [NSString stringWithFormat:@"Internet (%lu)", (unsigned long)internet.count], @"rows": [self rowsFor:internet] }];
        if (certificates.count) [sections addObject:@{ @"title": [NSString stringWithFormat:@"Certificates (%lu)", (unsigned long)certificates.count], @"rows": [self rowsFor:certificates] }];
        if (!sections.count) [sections addObject:@{ @"title": @"Keychain", @"rows": @[ @{ @"title": @"No items visible", @"subtitle": @"The app has no keychain items in its access groups." } ] }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.sections = sections;
            [self.tableView reloadData];
        });
    });
}

- (NSArray *)rowsFor:(NSArray *)items {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *service = item[@"service"] ?: item[@"account"] ?: @"(unnamed)";
        NSString *account = item[@"account"] ?: @"";
        NSString *subtitle = account.length ? account : (item[@"access_group"] ?: @"");
        id secret = item[@"text"] ?: item[@"data"];
        [rows addObject:@{
            @"title": service,
            @"subtitle": subtitle,
            @"chevron": @YES,
            @"action": ^{
                NSString *body = FKJSONString(item, YES);
                UIViewController *controller = [FKTextViewController viewerWithTitle:service text:body];
                [FKTopViewController().navigationController pushViewController:controller animated:YES];
            },
            @"_secret": secret ?: @"",
        }];
    }
    return rows;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.sections.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section][@"title"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
    return (NSInteger)rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"keychain";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = row[@"subtitle"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = row[@"chevron"] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    void (^action)(void) = row[@"action"];
    if (action) action();
}

@end

#pragma mark - Settings

@interface FKSettingsViewController ()
@property (nonatomic, strong) FKListViewController *list;
@end

@implementation FKSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.list = [FKListViewController listWithTitle:@"" sections:@[]];
    [self addChildViewController:self.list];
    self.list.view.frame = self.view.bounds;
    self.list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.list.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.list.view];
    [self.list didMoveToParentViewController:self];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Rebuild"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(rebuild)];
    [self rebuild];
}

- (void)rebuild {
    __weak typeof(self) weakSelf = self;
    void (^save)(NSString *, BOOL) = ^(NSString *key, BOOL value) {
        [FKPrefs setBool:value forKey:key];
        [weakSelf rebuild];
    };
    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:@{ @"title": @"Trigger", @"rows": @[
        @{ @"title": @"Haptic feedback", @"subtitle": @"Vibrate when the panel opens",
           @"toggle": ^(BOOL on) { save(@"haptics", on); },
           @"toggleValue": @([FKPrefs boolForKey:@"haptics" defaultValue:YES]) },
        @{ @"title": @"Left-edge fallback", @"subtitle": @"Also open from the left screen edge when the status bar is hidden",
           @"toggle": ^(BOOL on) { save(@"edgeFallback", on); },
           @"toggleValue": @([FKPrefs boolForKey:@"edgeFallback" defaultValue:YES]) },
        @{ @"title": @"Hold duration", @"subtitle": [NSString stringWithFormat:@"%.1f s", [FKPrefs doubleForKey:@"gestureDuration" defaultValue:0.7]],
           @"chevron": @YES,
           @"action": ^{ [weakSelf chooseDuration]; } },
    ] }];

    [sections addObject:@{ @"title": @"Server", @"rows": @[
        @{ @"title": @"Require bearer token", @"subtitle": @"Reject MCP/REST calls without the token",
           @"toggle": ^(BOOL on) { save(@"requireToken", on); },
           @"toggleValue": @([FKPrefs boolForKey:@"requireToken" defaultValue:YES]) },
        @{ @"title": @"Start on launch", @"subtitle": @"Bring the HTTP server up when the app loads",
           @"toggle": ^(BOOL on) { save(@"autoStart", on); },
           @"toggleValue": @([FKPrefs boolForKey:@"autoStart" defaultValue:NO]) },
        @{ @"title": @"Port", @"subtitle": [NSString stringWithFormat:@"%ld", (long)[FKPrefs integerForKey:@"port" defaultValue:8787]],
           @"chevron": @YES,
           @"action": ^{ [weakSelf choosePort]; } },
    ] }];

    [sections addObject:@{ @"title": @"Data", @"rows": @[
        @{ @"title": @"Regenerate token", @"subtitle": @"Invalidates existing clients",
           @"destructive": @YES,
           @"action": ^{
               [FKPrefs regenerateToken];
               FKPresentAlert(@"Token regenerated", [FKPrefs token]);
           } },
        @{ @"title": @"Clear log", @"subtitle": @"Empty the in-memory log buffer",
           @"action": ^{ FKLogClear(); [[FKHTTPServer sharedServer] clearRequestLog]; } },
        @{ @"title": @"Clear request log", @"subtitle": @"Reset the HTTP request history",
           @"action": ^{ [[FKHTTPServer sharedServer] clearRequestLog]; } },
    ] }];

    [sections addObject:@{ @"title": @"About", @"rows": @[
        @{ @"title": @"ForgeKit", @"subtitle": [NSString stringWithFormat:@"version %@", FKVersionString] },
        @{ @"title": @"Host app", @"subtitle": [NSString stringWithFormat:@"%@ · %@", FKAppIdentifier(), FKAppVersion()] },
        @{ @"title": @"Sandbox", @"subtitle": FKIsJailbroken() ? @"jailbroken filesystem visible" : @"app container only" },
        @{ @"title": @"MCP endpoint", @"subtitle": [NSString stringWithFormat:@"http://%@:%ld/mcp", FKLanAddress(), (long)[FKPrefs integerForKey:@"port" defaultValue:8787]] },
        @{ @"title": @"Tool count", @"subtitle": [NSString stringWithFormat:@"%lu tools", (unsigned long)[FKTools toolDefinitions].count] },
    ] }];

    self.list.sections = sections;
    [self.list reloadSections];
}

- (void)chooseDuration {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Hold duration" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *value in @[@0.4, @0.7, @1.2]) {
        NSString *title = [NSString stringWithFormat:@"%.1f s", value.doubleValue];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [FKPrefs setDouble:value.doubleValue forKey:@"gestureDuration"];
            [self rebuild];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)choosePort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"HTTP port" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%ld", (long)[FKPrefs integerForKey:@"port" defaultValue:8787]];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSInteger port = alert.textFields.firstObject.text.integerValue;
        if (port < 1 || port > 65535) return;
        [FKPrefs setInteger:port forKey:@"port"];
        FKHTTPServer *server = [FKHTTPServer sharedServer];
        if (server.isRunning) {
            [server stop];
            NSError *error = nil;
            [server startOnPort:(uint16_t)port error:&error];
        }
        [self rebuild];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Log

@interface FKLogViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *requests;
@property (nonatomic, strong) NSArray<NSString *> *lines;
@end

@implementation FKLogViewController

+ (instancetype)logController {
    return [[FKLogViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Log";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                           target:self
                                                                                           action:@selector(clearAll)];
    [self reload];
}

- (void)reload {
    self.requests = [[[FKHTTPServer sharedServer] recentRequestsWithLimit:120] reverseObjectEnumerator].allObjects;
    self.lines = [[FKLogLines() reverseObjectEnumerator] allObjects];
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}

- (void)clearAll {
    FKLogClear();
    [[FKHTTPServer sharedServer] clearRequestLog];
    [self reload];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:@"HTTP requests (%lu)", (unsigned long)self.requests.count]
                        : [NSString stringWithFormat:@"ForgeKit log (%lu)", (unsigned long)self.lines.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.requests.count : (NSInteger)self.lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"log";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    if (indexPath.section == 0) {
        NSDictionary *request = self.requests[(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", request[@"method"], request[@"path"]];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
        NSInteger status = [request[@"status"] integerValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld · %@ ms · %@",
                                     (long)status, request[@"ms"],
                                     FKFormatDate([NSDate dateWithTimeIntervalSince1970:[request[@"time"] doubleValue]])];
        cell.detailTextLabel.textColor = status >= 400 ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    } else {
        cell.textLabel.text = self.lines[(NSUInteger)indexPath.row];
        cell.textLabel.numberOfLines = 4;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = nil;
    }
    return cell;
}

@end
