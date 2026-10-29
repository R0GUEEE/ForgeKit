//
//  FKUnityScreens.m — Unity/IL2CPP browser, inspector and patch manager UI
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKIL2CPP.h"

#pragma mark - Class detail

@interface FKUnityClassViewController : UITableViewController
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) NSDictionary *info;
@end

@implementation FKUnityClassViewController

+ (instancetype)controllerForClass:(NSString *)className {
    FKUnityClassViewController *controller = [[FKUnityClassViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.className = className;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className.lastPathComponent;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Instances" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(showInstances)];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *info = [FKIL2CPP classInfoFor:self.className];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.info = info;
            [self.tableView reloadData];
        });
    });
}

- (void)showInstances {
    NSDictionary *found = [FKIL2CPP findObjectsOfClass:self.className limit:50];
    NSArray *objects = found[@"objects"] ?: @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *object in objects) {
        unsigned long long pointer = [object[@"ptr"] unsignedLongLongValue];
        [rows addObject:@{
            @"title": [NSString stringWithFormat:@"0x%llx", pointer],
            @"subtitle": [NSString stringWithFormat:@"%@ · %@", object[@"class"] ?: self.className,
                          found[@"strategy"] ?: @""],
            @"chevron": @YES,
            @"action": ^{
                UIViewController *details =
                    [self objectControllerForClass:object[@"class"] ?: self.className pointer:pointer];
                [self.navigationController pushViewController:details animated:YES];
            },
        }];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No live instances", @"subtitle": found[@"strategy"] ?: @"" }];
    FKListViewController *list = [FKListViewController listWithTitle:@"Instances"
                                                            sections:@[ @{ @"title": found[@"strategy"] ?: @"objects",
                                                                           @"rows": rows } ]];
    [self.navigationController pushViewController:list animated:YES];
}

- (UIViewController *)objectControllerForClass:(NSString *)className pointer:(unsigned long long)pointer {
    NSDictionary *inspection = [FKIL2CPP inspectObjectOfClass:className pointer:pointer limit:120];
    NSArray *fields = inspection[@"fields"] ?: @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *field in fields) {
        NSString *value = field[@"value"] ? FKJSONString(field[@"value"], NO) : @"";
        NSMutableDictionary *row = [@{
            @"title": field[@"name"] ?: @"?",
            @"subtitle": [NSString stringWithFormat:@"%@ · %@", field[@"type"] ?: @"?", value],
            @"action": ^{
                if (!field[@"navigable"]) return;
                NSDictionary *child = field[@"value"];
                unsigned long long childPointer = [child[@"ptr"] unsignedLongLongValue];
                if (!childPointer) return;
                UIViewController *next = [self objectControllerForClass:child[@"class"] ?: @""
                                                                    pointer:childPointer];
                [self.navigationController pushViewController:next animated:YES];
            },
        } mutableCopy];
        if (field[@"navigable"]) row[@"chevron"] = @YES;
        [rows addObject:row];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No readable fields", @"subtitle": inspection[@"error"] ?: @"" }];
    return [FKListViewController listWithTitle:[NSString stringWithFormat:@"0x%llx", pointer]
                                      sections:@[ @{ @"title": className, @"rows": rows } ]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Identity";
    return [NSString stringWithFormat:@"Members (%lu)", (unsigned long)([self.info[@"fields"] count] + [self.info[@"methods"] count])];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.info) return 1;
    return section == 0 ? 4 : (NSInteger)([self.info[@"fields"] count] + [self.info[@"methods"] count]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"unity-class";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (!self.info) {
        cell.textLabel.text = [self.info[@"error"] description] ?: @"Loading…";
        cell.detailTextLabel.text = @"";
        return cell;
    }
    if (indexPath.section == 0) {
        NSArray *titles = @[@"Class", @"Parent", @"Image", @"Interfaces"];
        NSArray *values = @[self.info[@"name"] ?: @"", self.info[@"parent"] ?: @"",
                            self.info[@"image"] ?: @"", [self.info[@"interfaces"] componentsJoinedByString:@", "] ?: @""];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = values[(NSUInteger)indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        return cell;
    }
    NSArray *fields = self.info[@"fields"] ?: @[];
    if (indexPath.row < (NSInteger)fields.count) {
        NSDictionary *field = fields[(NSUInteger)indexPath.row];
        cell.textLabel.text = field[@"name"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@ · offset %@",
                                     [field[@"static"] boolValue] ? @"static " : @"",
                                     field[@"type"] ?: @"?", field[@"offset"] ?: @0];
    } else {
        NSUInteger index = (NSUInteger)indexPath.row - fields.count;
        NSArray *methods = self.info[@"methods"] ?: @[];
        if (index < methods.count) {
            NSDictionary *method = methods[index];
            cell.textLabel.text = method[@"name"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@(%@)", method[@"return"] ?: @"?",
                                         method[@"name"] ?: @"?",
                                         [method[@"params"] componentsJoinedByString:@", "] ?: @""];
        }
    }
    return cell;
}

@end

#pragma mark - Unity browser

@interface FKUnityViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *classes;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSDictionary *info;
@end

@implementation FKUnityViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Unity";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class name filter";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Scripts" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(openScripts)];
    [self refresh];
}

- (void)refresh {
    self.info = [FKIL2CPP runtimeInfo];
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *classes = [FKIL2CPP classesMatching:self.searchController.searchBar.text ?: @"" limit:400];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.classes = classes;
            [self.tableView reloadData];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self refresh]; }

- (void)openScripts {
    [self.navigationController pushViewController:[[FKScriptConsoleViewController alloc] init] animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Backend";
    return [NSString stringWithFormat:@"Classes (%lu)", (unsigned long)self.classes.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.info ? 6 : 1;
    return (NSInteger)self.classes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"unity";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        NSArray *titles = @[@"Backend", @"Class cache", @"Images", @"Active patches", @"Dump", @"Restore all"];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        if (!self.info) { cell.detailTextLabel.text = @"unavailable"; return cell; }
        NSArray *values = @[
            self.info[@"backend"] ?: @"none",
            [NSString stringWithFormat:@"%@ classes", self.info[@"class_count"] ?: @0],
            [NSString stringWithFormat:@"%@ images", self.info[@"image_count"] ?: @0],
            [NSString stringWithFormat:@"%@ / %@", self.info[@"active_patches"] ?: @0, self.info[@"patch_capacity"] ?: @0],
            @"write to Documents", @"undo every patch",
        ];
        cell.detailTextLabel.text = values[(NSUInteger)indexPath.row];
        if (indexPath.row == 4 || indexPath.row == 5) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSDictionary *entry = self.classes[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = entry[@"image"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSDictionary *entry = self.classes[(NSUInteger)indexPath.row];
        [self.navigationController pushViewController:
            [FKUnityClassViewController controllerForClass:entry[@"name"]] animated:YES];
        return;
    }
    if (indexPath.row == 4) {
        self.title = @"Dumping…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *result = [FKIL2CPP dumpWithFilter:nil path:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.title = @"Unity";
                FKPresentAlert(@"Dump complete",
                               [NSString stringWithFormat:@"%@ classes · %@ fields · %@ methods\n%@",
                                result[@"classes"], result[@"fields"], result[@"methods"], result[@"path"] ?: @""]);
            });
        });
    } else if (indexPath.row == 5) {
        [FKIL2CPP restoreAllPatches];
        [self refresh];
        FKPresentAlert(@"Patches restored", @"All active patches were removed.");
    } else if (indexPath.row == 3) {
        NSDictionary *status = [FKIL2CPP patchStatus];
        NSArray *patches = status[@"patches"] ?: @[];
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *patch in patches) {
            [rows addObject:@{
                @"title": [NSString stringWithFormat:@"%@.%@", patch[@"class"], patch[@"method"]],
                @"subtitle": [NSString stringWithFormat:@"%@ · %@", patch[@"mode"], patch[@"address"]],
                @"destructive": @YES,
                @"action": ^{
                    [FKIL2CPP restorePatchOfClass:patch[@"class"] method:patch[@"method"]];
                    [self refresh];
                },
            }];
        }
        if (!rows.count) [rows addObject:@{ @"title": @"No active patches", @"subtitle": @"capacity 64" }];
        FKListViewController *list = [FKListViewController listWithTitle:@"Patches"
                                                                sections:@[ @{ @"title": @"Active", @"rows": rows } ]];
        [self.navigationController pushViewController:list animated:YES];
    }
}

@end

#pragma mark - Script console

@interface FKScriptConsoleViewController ()
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UITextView *output;
@end

@implementation FKScriptConsoleViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Scripts";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-28],
    ]];

    UILabel *hint = [[UILabel alloc] init];
    hint.numberOfLines = 0;
    hint.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.text = @"Class.fromName(\"App.Model\").findObjects(5)  ·  .read(\"coins\", 0)  ·  .write(\"coins\", 999, 0)";
    [stack addArrangedSubview:hint];

    self.input = [[UITextView alloc] init];
    self.input.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.input.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.input.layer.cornerRadius = 10;
    self.input.text = @"var c = Class.fromName(\"UnityEngine.QualitySettings\");\njson(c.info());";
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    [self.input.heightAnchor constraintEqualToConstant:150].active = YES;
    [stack addArrangedSubview:self.input];

    UIButton *run = [UIButton buttonWithType:UIButtonTypeSystem];
    [run setTitle:@"Run" forState:UIControlStateNormal];
    [run setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    run.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    run.backgroundColor = [UIColor systemPurpleColor];
    run.layer.cornerRadius = 10;
    [run.heightAnchor constraintEqualToConstant:42].active = YES;
    [run addTarget:self action:@selector(runScript) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:run];

    self.output = [[UITextView alloc] init];
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    self.output.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.output.layer.cornerRadius = 10;
    self.output.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    self.output.text = @"—";
    [self.output.heightAnchor constraintGreaterThanOrEqualToConstant:220].active = YES;
    [stack addArrangedSubview:self.output];
}

- (void)runScript {
    NSString *source = self.input.text ?: @"";
    NSDictionary *result = [FKTools callTool:@"run_lua" arguments:@{ @"code": source }];
    self.output.text = FKJSONString(result, YES);
}

@end
