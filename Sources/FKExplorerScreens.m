//
//  FKExplorerScreens.m — native FLEX-style explorer (hierarchy, heap, classes,
//  libraries, traffic, cookies), built on FKRuntimeKit.
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKRuntimeKit.h"
#import <objc/runtime.h>
#import <stdlib.h>

@interface FKHierarchyViewController : UITableViewController
+ (instancetype)controllerWithView:(UIView *)view;
@end
@interface FKObjCClassListViewController : UITableViewController
@end
@interface FKObjCClassDetailViewController : UITableViewController
+ (instancetype)controllerForClass:(NSString *)name;
@end
@interface FKObjCObjectViewController : FKListViewController
+ (instancetype)controllerWithPointer:(NSString *)pointerString;
@end
@interface FKLibrariesViewController : UITableViewController
@end
@interface FKLibraryExportsViewController : UITableViewController
+ (instancetype)controllerWithModule:(NSString *)moduleName;
@end
@interface FKTrafficViewController : UITableViewController
@end
@interface FKCookiesViewController : FKListViewController
@end


#pragma mark - Explorer home

@implementation FKExplorerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    self.screenTitle = @"Explorer";
    self.title = @"Explorer";
    self.sections = @[
        @{ @"title": @"Runtime", @"rows": @[
            @{ @"title": @"View hierarchy", @"subtitle": @"Walk the live window tree", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[FKHierarchyViewController controllerWithView:FKKeyWindow()]]; } },
            @{ @"title": @"Classes", @"subtitle": @"Every Objective-C class, methods and ivars", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKObjCClassListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
            @{ @"title": @"Libraries", @"subtitle": @"Loaded Mach-O images and exports", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKLibrariesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
            @{ @"title": @"Network traffic", @"subtitle": @"Captured NSURLSession requests", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKTrafficViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        ] },
        @{ @"title": @"Data", @"rows": @[
            @{ @"title": @"Files", @"subtitle": FKContainerPath(), @"chevron": @YES,
               @"action": ^{ [weakSelf push:[FKFileBrowserViewController browserAtPath:FKContainerPath()]]; } },
            @{ @"title": @"Preferences", @"subtitle": @"Library/Preferences plists", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKDefaultsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
            @{ @"title": @"Keychain", @"subtitle": @"Items visible to this app", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKKeychainViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
            @{ @"title": @"Cookies", @"subtitle": @"NSHTTPCookieStorage", @"chevron": @YES,
               @"action": ^{ [weakSelf push:[[FKCookiesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        ] },
        @{ @"title": @"App", @"rows": @[
            @{ @"title": @"Application info", @"subtitle": FKAppIdentifier(), @"chevron": @YES,
               @"action": ^{ [weakSelf push:[weakSelf applicationInfoController]]; } },
        ] },
    ];
    [self reloadSections];
}

- (UIViewController *)applicationInfoController {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{ @"title": @"Name", @"subtitle": FKAppName() }];
    [rows addObject:@{ @"title": @"Bundle identifier", @"subtitle": FKAppIdentifier() }];
    [rows addObject:@{ @"title": @"Version", @"subtitle": FKAppVersion() }];
    [rows addObject:@{ @"title": @"Bundle", @"subtitle": FKBundlePath() }];
    [rows addObject:@{ @"title": @"Container", @"subtitle": FKContainerPath() }];
    [rows addObject:@{ @"title": @"Documents", @"subtitle": FKDocumentsPath() }];
    [rows addObject:@{ @"title": @"Device", @"subtitle": [NSString stringWithFormat:@"%@ · iOS %@",
                                                          FKDeviceModelIdentifier(), FKOSVersionString()] }];
    [rows addObject:@{ @"title": @"Jailbroken", @"subtitle": FKIsJailbroken() ? @"yes" : @"no" }];
    return [FKListViewController listWithTitle:@"Application" sections:@[ @{ @"title": @"Identity", @"rows": rows } ]];
}

- (void)push:(UIViewController *)controller {
    [self.navigationController pushViewController:controller animated:YES];
}

@end

#pragma mark - Hierarchy

@interface FKHierarchyViewController ()
@property (nonatomic, strong) UIView *node;
@end

@implementation FKHierarchyViewController

+ (instancetype)controllerWithView:(UIView *)view {
    FKHierarchyViewController *controller = [[FKHierarchyViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.node = view;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = NSStringFromClass([self.node class]);
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Highlight" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(highlightNode)],
        [[UIBarButtonItem alloc] initWithTitle:@"Inspect" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(inspectNode)],
    ];
}

- (void)highlightNode {
    UIView *window = self.node.window;
    CGRect rect = [self.node convertRect:self.node.bounds toView:window];
    [FKRuntimeKit highlightRect:rect duration:2.0];
}

- (void)inspectNode {
    NSDictionary *info = [FKRuntimeKit objectInfo:(unsigned long long)(uintptr_t)(__bridge void *)self.node depth:4];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *ivar in info[@"ivars"] ?: @[]) {
        [rows addObject:@{ @"title": ivar[@"name"] ?: @"?",
                           @"subtitle": [NSString stringWithFormat:@"%@ = %@", ivar[@"type"] ?: @"?",
                                         ivar[@"value"] ?: @""] }];
    }
    if (!rows.count) [rows addObject:@{ @"title": info[@"error"] ?: @"No ivars", @"subtitle": @"" }];
    FKListViewController *list = [FKListViewController listWithTitle:NSStringFromClass([self.node class])
                                                            sections:@[ @{ @"title": @"Instance", @"rows": rows } ]];
    [self.navigationController pushViewController:list animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%lu subviews", (unsigned long)self.node.subviews.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(1, self.node.subviews.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"hierarchy";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if (!self.node.subviews.count) {
        cell.textLabel.text = @"No subviews";
        cell.detailTextLabel.text = @"";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    UIView *child = self.node.subviews[(NSUInteger)indexPath.row];
    cell.textLabel.text = NSStringFromClass([child class]);
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", NSStringFromCGRect(child.frame),
                                 child.isHidden ? @" · hidden" : @""];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.node.subviews.count) return;
    UIView *child = self.node.subviews[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[FKHierarchyViewController controllerWithView:child] animated:YES];
}

@end

#pragma mark - Classes

@interface FKObjCClassListViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSString *> *allClasses;
@property (nonatomic, strong) NSArray<NSString *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation FKObjCClassListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Classes";
    self.tableView.rowHeight = 44;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter classes";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    NSMutableArray *names = [NSMutableArray array];
    int count = objc_getClassList(NULL, 0);
    if (count > 0) {
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * (size_t)count);
        count = objc_getClassList(classes, count);
        for (int i = 0; i < count; i++) {
            const char *name = class_getName(classes[i]);
            if (name) [names addObject:[NSString stringWithUTF8String:name] ?: @""];
        }
        free(classes);
    }
    self.allClasses = [names sortedArrayUsingSelector:@selector(compare:)];
    self.filtered = self.allClasses;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *needle = searchController.searchBar.text;
    if (!needle.length) self.filtered = self.allClasses;
    else self.filtered = [self.allClasses filteredArrayUsingPredicate:
                          [NSPredicate predicateWithFormat:@"self CONTAINS[cd] %@", needle]];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.filtered.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"objc-class";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    cell.textLabel.text = self.filtered[(NSUInteger)indexPath.row];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.filtered[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[FKObjCClassDetailViewController controllerForClass:name] animated:YES];
}

@end

@interface FKObjCClassDetailViewController ()
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) NSArray<NSDictionary *> *instanceMethods;
@property (nonatomic, strong) NSArray<NSDictionary *> *classMethods;
@property (nonatomic, strong) NSArray<NSDictionary *> *ivars;
@property (nonatomic, strong) NSArray<NSDictionary *> *properties;
@end

@implementation FKObjCClassDetailViewController

+ (instancetype)controllerForClass:(NSString *)name {
    FKObjCClassDetailViewController *controller = [[FKObjCClassDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.className = name;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Instances"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(showInstances)];

    Class cls = NSClassFromString(self.className);
    NSMutableArray *instanceMethods = [NSMutableArray array];
    NSMutableArray *classMethods = [NSMutableArray array];
    NSMutableArray *ivars = [NSMutableArray array];
    NSMutableArray *properties = [NSMutableArray array];

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        [instanceMethods addObject:@{ @"name": NSStringFromSelector(method_getName(methods[i])),
                                      @"types": [NSString stringWithUTF8String:method_getTypeEncoding(methods[i])] ?: @"" }];
    }
    free(methods);

    methods = class_copyMethodList(object_getClass(cls), &count);
    for (unsigned i = 0; i < count; i++) {
        [classMethods addObject:@{ @"name": NSStringFromSelector(method_getName(methods[i])),
                                   @"types": [NSString stringWithUTF8String:method_getTypeEncoding(methods[i])] ?: @"" }];
    }
    free(methods);

    Ivar *ivarList = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        [ivars addObject:@{ @"name": [NSString stringWithUTF8String:ivar_getName(ivarList[i])] ?: @"?",
                            @"types": [NSString stringWithUTF8String:ivar_getTypeEncoding(ivarList[i])] ?: @"" }];
    }
    free(ivarList);

    objc_property_t *propertyList = class_copyPropertyList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        [properties addObject:@{ @"name": [NSString stringWithUTF8String:property_getName(propertyList[i])] ?: @"?",
                                 @"types": [NSString stringWithUTF8String:property_getAttributes(propertyList[i])] ?: @"" }];
    }
    free(propertyList);

    self.instanceMethods = instanceMethods;
    self.classMethods = classMethods;
    self.ivars = ivars;
    self.properties = properties;
}

- (void)showInstances {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = [FKRuntimeKit heapObjectsOfClass:self.className limit:100];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *rows = [NSMutableArray array];
            for (NSDictionary *object in result[@"objects"] ?: @[]) {
                [rows addObject:@{ @"title": object[@"class"] ?: @"?",
                                   @"subtitle": object[@"ptr"] ?: @"",
                                   @"chevron": @YES,
                                   @"action": ^{
                                       [self.navigationController pushViewController:
                                           [FKObjCObjectViewController controllerWithPointer:object[@"ptr"]]
                                                                            animated:YES];
                                   } }];
            }
            if (!rows.count) [rows addObject:@{ @"title": @"No live instances", @"subtitle": result[@"error"] ?: @"" }];
            FKListViewController *list = [FKListViewController listWithTitle:@"Instances"
                                                                    sections:@[ @{ @"title": @"Heap", @"rows": rows } ]];
            [self.navigationController pushViewController:list animated:YES];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return [NSString stringWithFormat:@"Instance methods (%lu)", (unsigned long)self.instanceMethods.count];
        case 1: return [NSString stringWithFormat:@"Class methods (%lu)", (unsigned long)self.classMethods.count];
        case 2: return [NSString stringWithFormat:@"Ivars (%lu)", (unsigned long)self.ivars.count];
        default: return [NSString stringWithFormat:@"Properties (%lu)", (unsigned long)self.properties.count];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return (NSInteger)self.instanceMethods.count;
        case 1: return (NSInteger)self.classMethods.count;
        case 2: return (NSInteger)self.ivars.count;
        default: return (NSInteger)self.properties.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"objc-member";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *entry = nil;
    switch (indexPath.section) {
        case 0: entry = self.instanceMethods[(NSUInteger)indexPath.row]; break;
        case 1: entry = self.classMethods[(NSUInteger)indexPath.row]; break;
        case 2: entry = self.ivars[(NSUInteger)indexPath.row]; break;
        default: entry = self.properties[(NSUInteger)indexPath.row]; break;
    }
    cell.textLabel.text = entry[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = entry[@"types"];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = (indexPath.section < 2) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section > 1) return;
    NSDictionary *entry = indexPath.section == 0 ? self.instanceMethods[(NSUInteger)indexPath.row]
                                                 : self.classMethods[(NSUInteger)indexPath.row];
    NSString *signature = [NSString stringWithFormat:@"%@ %@ %@",
                           indexPath.section == 0 ? @"-" : @"+", self.className, entry[@"name"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:entry[@"name"]
                                                                   message:[NSString stringWithFormat:@"%@\n%@",
                                                                            signature, entry[@"types"]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy selector" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = entry[@"name"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Object

@interface FKObjCObjectViewController ()
@property (nonatomic, copy) NSString *pointerString;
@end

@implementation FKObjCObjectViewController

+ (instancetype)controllerWithPointer:(NSString *)pointerString {
    FKObjCObjectViewController *controller = [[FKObjCObjectViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.pointerString = pointerString;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pointerString;
    unsigned long long pointer = strtoull(self.pointerString.UTF8String, NULL, 0);
    NSDictionary *info = [FKRuntimeKit objectInfo:pointer depth:4];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{ @"title": @"Class", @"subtitle": info[@"class"] ?: @"" }];
    [rows addObject:@{ @"title": @"Chain", @"subtitle": [info[@"chain"] componentsJoinedByString:@" → "] ?: @"" }];
    [rows addObject:@{ @"title": @"Description", @"subtitle": info[@"description"] ?: @"" }];
    for (NSDictionary *ivar in info[@"ivars"] ?: @[]) {
        NSDictionary *value = ivar[@"value"];
        NSString *detail = [value isKindOfClass:[NSDictionary class]]
            ? [NSString stringWithFormat:@"%@ = %@", ivar[@"type"] ?: @"?", value[@"value"] ?: value]
            : [NSString stringWithFormat:@"%@ = %@", ivar[@"type"] ?: @"?", value ?: @""];
        NSMutableDictionary *row = [@{ @"title": ivar[@"name"] ?: @"?", @"subtitle": detail } mutableCopy];
        if ([value isKindOfClass:[NSDictionary class]] && value[@"ptr"]) {
            row[@"chevron"] = @YES;
            NSString *childPointer = [value[@"ptr"] description];
            row[@"action"] = ^{
                [self.navigationController pushViewController:
                    [FKObjCObjectViewController controllerWithPointer:childPointer] animated:YES];
            };
        }
        [rows addObject:row];
    }
    self.sections = @[ @{ @"title": @"Object", @"rows": rows } ];
    [self reloadSections];
}

@end

#pragma mark - Libraries

@interface FKLibrariesViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *modules;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation FKLibrariesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Libraries";
    self.tableView.rowHeight = 54;
    self.modules = [FKRuntimeKit modules];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.modules.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"library";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *module = self.modules[(NSUInteger)indexPath.row];
    cell.textLabel.text = [module[@"name"] lastPathComponent];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ bytes", module[@"base"], module[@"size"]];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *module = self.modules[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:
        [FKLibraryExportsViewController controllerWithModule:module[@"name"]] animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {}

@end

@interface FKLibraryExportsViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *moduleName;
@property (nonatomic, strong) NSArray<NSDictionary *> *exports;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation FKLibraryExportsViewController

+ (instancetype)controllerWithModule:(NSString *)moduleName {
    FKLibraryExportsViewController *controller = [[FKLibraryExportsViewController alloc] initWithStyle:UITableViewStylePlain];
    controller.moduleName = moduleName;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.moduleName lastPathComponent];
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Export filter";
    self.navigationItem.searchController = self.search;
    [self reload];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }

- (void)reload {
    NSString *filter = self.search.searchBar.text;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *exports = [FKRuntimeKit exportsOfModule:self.moduleName filter:filter limit:300];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.exports = exports;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.exports.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"export";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *entry = self.exports[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = entry[@"address"];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    return cell;
}

@end

#pragma mark - Traffic

@interface FKTrafficViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *records;
@end

@implementation FKTrafficViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Traffic";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(clear)];
    [self reload];
}

- (void)reload {
    self.records = [FKRuntimeKit networkHistory:200][@"records"] ?: @[];
    [self.tableView reloadData];
}

- (void)clear {
    [FKRuntimeKit clearNetworkHistory];
    [self reload];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)MAX(1, self.records.count); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"traffic";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if (!self.records.count) {
        cell.textLabel.text = @"No traffic captured";
        cell.detailTextLabel.text = @"Capture is enabled by default";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    cell.textLabel.text = record[@"url"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@ · %@ ms · %@ bytes",
                                 record[@"method"], record[@"status"] ?: @"—",
                                 record[@"duration_ms"], record[@"bytes"]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.records.count) return;
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    FKListViewController *detail = [FKListViewController listWithTitle:@"Request"
        sections:@[ @{ @"title": @"Record", @"rows": @[
            @{ @"title": @"URL", @"subtitle": record[@"url"] ?: @"" },
            @{ @"title": @"Status", @"subtitle": [NSString stringWithFormat:@"%@", record[@"status"] ?: @"—"] },
            @{ @"title": @"Request headers", @"subtitle": FKJSONString(record[@"request_headers"] ?: @{}, YES) },
            @{ @"title": @"Response headers", @"subtitle": FKJSONString(record[@"response_headers"] ?: @{}, YES) },
            @{ @"title": @"Preview", @"subtitle": record[@"preview"] ?: @"" },
        ] } ]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end

#pragma mark - Cookies

@implementation FKCookiesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cookies";
    NSArray *cookies = FKHTTPCookies();
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *cookie in cookies) {
        [rows addObject:@{ @"title": cookie[@"name"] ?: @"?",
                           @"subtitle": [NSString stringWithFormat:@"%@ · %@ · %@", cookie[@"domain"],
                                         cookie[@"path"], cookie[@"value"]] }];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No cookies", @"subtitle": @"NSHTTPCookieStorage is empty" }];
    self.sections = @[ @{ @"title": [NSString stringWithFormat:@"%lu cookies", (unsigned long)cookies.count],
                          @"rows": rows } ];
    [self reloadSections];
}

@end
