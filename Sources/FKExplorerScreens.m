//
//  FKExplorerScreens.m — native FLEX-style explorer (hierarchy, heap, classes,
//  libraries, traffic, cookies), built on FKRuntimeKit.
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKRuntimeKit.h"
#import <objc/runtime.h>
#import <stdlib.h>
#import "FKUtilities.h"

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
        [[UIBarButtonItem alloc] initWithTitle:@"Frames" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(showFrames)],
    ];
}

- (void)highlightNode {
    UIView *window = self.node.window;
    CGRect rect = [self.node convertRect:self.node.bounds toView:window];
    [FKRuntimeKit highlightRect:rect duration:2.0];
}

- (void)showFrames {
    [FKRuntimeKit highlightAllViewsInWindow:self.node.window duration:2.5];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"Invoke" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptInvoke:entry[@"name"] classMethod:(indexPath.section == 1)];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptInvoke:(NSString *)selector classMethod:(BOOL)classMethod {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:selector
                                                                   message:@"Object pointer (empty for class methods) and comma-separated arguments"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = classMethod ? @"class method" : @"object pointer";
        field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"args, e.g. 42, hello";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Run" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *pointerText = alert.textFields.firstObject.text ?: @"";
        NSString *argsText = alert.textFields.lastObject.text ?: @"";
        NSMutableArray *args = [NSMutableArray array];
        for (NSString *piece in [argsText componentsSeparatedByString:@","]) {
            NSString *trimmed = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!trimmed.length) continue;
            NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
            NSNumber *number = [formatter numberFromString:trimmed];
            [args addObject:number ?: trimmed];
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *result = [FKRuntimeKit callClass:self.className selector:selector
                                                    object:strtoull(pointerText.UTF8String, NULL, 0)
                                               classMethod:classMethod args:args];
            dispatch_async(dispatch_get_main_queue(), ^{
                FKPresentAlert(selector, FKJSONString(result, YES));
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
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
    [rows addObject:@{ @"title": @"References", @"subtitle": @"Objects whose ivars point to this one", @"chevron": @YES,
                       @"action": ^{ [self showReferences:pointer]; } }];
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

- (void)showReferences:(unsigned long long)pointer {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = [FKRuntimeKit referencesTo:pointer limit:50];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *rows = [NSMutableArray array];
            for (NSDictionary *reference in result[@"references"] ?: @[]) {
                [rows addObject:@{ @"title": reference[@"class"] ?: @"?",
                                   @"subtitle": [NSString stringWithFormat:@"%@ · %@", reference[@"ivar"], reference[@"ptr"]],
                                   @"chevron": @YES,
                                   @"action": ^{
                                       [self.navigationController pushViewController:
                                           [FKObjCObjectViewController controllerWithPointer:reference[@"ptr"]] animated:YES];
                                   } }];
            }
            if (!rows.count) [rows addObject:@{ @"title": @"No references found", @"subtitle": result[@"error"] ?: @"" }];
            FKListViewController *list = [FKListViewController listWithTitle:@"References"
                                                                    sections:@[ @{ @"title": @"Referrers", @"rows": rows } ]];
            [self.navigationController pushViewController:list animated:YES];
        });
    });
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

#pragma mark - FLEX home

@interface FKFlexModuleButton : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configureTitle:(NSString *)title symbol:(NSString *)symbol selected:(BOOL)selected;
@end

@implementation FKFlexModuleButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.7;
        [self addSubview:_titleLabel];
        self.layer.cornerRadius = 12;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    return self;
}
- (void)configureTitle:(NSString *)title symbol:(NSString *)symbol selected:(BOOL)selected {
    UIColor *accent = [UIColor colorWithRed:1.0 green:0.55 blue:0.2 alpha:1.0];
    self.iconView.image = [UIImage systemImageNamed:symbol];
    self.iconView.tintColor = selected ? accent : [UIColor colorWithWhite:0.7 alpha:1.0];
    self.titleLabel.text = title;
    self.titleLabel.textColor = selected ? accent : [UIColor colorWithWhite:0.7 alpha:1.0];
    self.backgroundColor = selected ? [accent colorWithAlphaComponent:0.15] : [UIColor clearColor];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.iconView.frame = CGRectMake((self.bounds.size.width - 22) / 2, 8, 22, 22);
    self.titleLabel.frame = CGRectMake(1, 33, self.bounds.size.width - 2, self.bounds.size.height - 35);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}
@end

@interface FKFlexViewController ()
@property (nonatomic, strong) UINavigationController *moduleNav;
@property (nonatomic, strong) NSArray<NSDictionary *> *modules;
@property (nonatomic, strong) NSMutableArray<FKFlexModuleButton *> *moduleButtons;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, assign) NSInteger selectedIndex;
@end

@implementation FKFlexViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.035 blue:0.045 alpha:1.0];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:topBar];

    UILabel *logo = [[UILabel alloc] init];
    logo.text = @"FLEX";
    logo.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    logo.textColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.2 alpha:1.0];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:logo];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"runtime explorer";
    subtitle.font = [UIFont monospacedSystemFontOfSize:8.5 weight:UIFontWeightRegular];
    subtitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:subtitle];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    [done setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [done addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:done];

    UIScrollView *toolbar = [[UIScrollView alloc] init];
    toolbar.showsHorizontalScrollIndicator = NO;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toolbar];

    UIStackView *toolbarStack = [[UIStackView alloc] init];
    toolbarStack.axis = UILayoutConstraintAxisHorizontal;
    toolbarStack.spacing = 4;
    toolbarStack.alignment = UIStackViewAlignmentCenter;
    toolbarStack.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:toolbarStack];

    self.moduleNav = [[UINavigationController alloc] init];
    self.moduleNav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.moduleNav.view.translatesAutoresizingMaskIntoConstraints = NO;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName: [UIColor whiteColor] };
    self.moduleNav.navigationBar.standardAppearance = appearance;
    self.moduleNav.navigationBar.scrollEdgeAppearance = appearance;
    self.moduleNav.navigationBar.tintColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.2 alpha:1.0];
    [self addChildViewController:self.moduleNav];
    [self.view addSubview:self.moduleNav.view];
    [self.moduleNav didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [topBar.heightAnchor constraintEqualToConstant:44],

        [logo.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:14],
        [logo.topAnchor constraintEqualToAnchor:topBar.topAnchor constant:2],
        [subtitle.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:7],
        [subtitle.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],

        [done.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-14],
        [done.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],

        [toolbar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [toolbar.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:64],

        [toolbarStack.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:10],
        [toolbarStack.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-10],
        [toolbarStack.topAnchor constraintEqualToAnchor:toolbar.topAnchor],
        [toolbarStack.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [toolbarStack.heightAnchor constraintEqualToAnchor:toolbar.heightAnchor],

        [self.moduleNav.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.moduleNav.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.moduleNav.view.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.moduleNav.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.entries = @[
        @{ @"title": @"Hierarchy", @"symbol": @"square.stack.3d.up.fill", @"make": ^{ return [FKHierarchyViewController controllerWithView:FKKeyWindow()]; } },
        @{ @"title": @"Heap", @"symbol": @"memorychip.fill", @"make": ^{ return [[FKHeapClassesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"Classes", @"symbol": @"cube.box.fill", @"make": ^{ return [[FKObjCClassListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"Network", @"symbol": @"network", @"make": ^{ return [[FKTrafficViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"Libraries", @"symbol": @"books.vertical.fill", @"make": ^{ return [[FKLibrariesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"Globals", @"symbol": @"globe", @"make": ^{ return [[FKGlobalsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"Files", @"symbol": @"folder.fill", @"make": ^{ return [FKFileBrowserViewController browserAtPath:FKContainerPath()]; } },
        @{ @"title": @"SQLite", @"symbol": @"cylinder.split.1x2.fill", @"make": ^{ return [[FKSQLiteListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
        @{ @"title": @"System", @"symbol": @"gearshape.2.fill", @"make": ^{ return [[FKSystemViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; } },
    ];

    self.moduleButtons = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.entries.count; i++) {
        NSDictionary *entry = self.entries[i];
        FKFlexModuleButton *button = [[FKFlexModuleButton alloc] initWithFrame:CGRectZero];
        button.tag = 700 + (NSInteger)i;
        [button configureTitle:entry[@"title"] symbol:entry[@"symbol"] selected:NO];
        [button.widthAnchor constraintEqualToConstant:58].active = YES;
        [button.heightAnchor constraintEqualToConstant:58].active = YES;
        [button addTarget:self action:@selector(moduleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [toolbarStack addArrangedSubview:button];
        [self.moduleButtons addObject:button];
    }
    [self selectIndex:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBarHidden = NO;
}

- (void)done {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)moduleTapped:(FKFlexModuleButton *)sender {
    [self selectIndex:sender.tag - 700];
}

- (void)selectIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.entries.count) return;
    self.selectedIndex = index;
    for (NSUInteger i = 0; i < self.moduleButtons.count; i++) {
        NSDictionary *entry = self.entries[i];
        [self.moduleButtons[i] configureTitle:entry[@"title"] symbol:entry[@"symbol"] selected:(NSInteger)i == index];
    }
    id makeObject = self.entries[(NSUInteger)index][@"make"];
    UIViewController *(^make)(void) = (UIViewController *(^)(void))makeObject;
    UIViewController *root = make ? make() : nil;
    if (root) [self.moduleNav setViewControllers:@[root] animated:NO];
}

@end

#pragma mark - Heap

@interface FKHeapClassesViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *classes;
@property (nonatomic, assign) BOOL loading;
@end

@implementation FKHeapClassesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Heap";
    self.tableView.rowHeight = 48;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self action:@selector(reload)];
    [self reload];
}

- (void)reload {
    if (self.loading) return;
    self.loading = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = [FKRuntimeKit heapClassCounts:300];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.classes = result[@"classes"] ?: @[];
            self.loading = NO;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(1, self.classes.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"heap-class";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if (!self.classes.count) {
        cell.textLabel.text = self.loading ? @"Scanning heap…" : @"No objects found";
        cell.detailTextLabel.text = @"";
        return cell;
    }
    NSDictionary *entry = self.classes[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"class"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ objects", entry[@"count"]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.classes.count) return;
    NSString *className = self.classes[(NSUInteger)indexPath.row][@"class"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = [FKRuntimeKit heapObjectsOfClass:className limit:100];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableArray *rows = [NSMutableArray array];
            for (NSDictionary *object in result[@"objects"] ?: @[]) {
                [rows addObject:@{ @"title": object[@"class"] ?: className,
                                   @"subtitle": object[@"ptr"] ?: @"",
                                   @"chevron": @YES,
                                   @"action": ^{
                                       [self.navigationController pushViewController:
                                           [FKObjCObjectViewController controllerWithPointer:object[@"ptr"]] animated:YES];
                                   } }];
            }
            if (!rows.count) [rows addObject:@{ @"title": @"No live objects", @"subtitle": result[@"error"] ?: @"" }];
            FKListViewController *list = [FKListViewController listWithTitle:className
                                                                    sections:@[ @{ @"title": @"Objects", @"rows": rows } ]];
            [self.navigationController pushViewController:list animated:YES];
        });
    });
}

@end

#pragma mark - Globals

@implementation FKGlobalsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    self.screenTitle = @"Globals";
    self.title = @"Globals";
    self.sections = @[ @{ @"title": @"Globals", @"rows": @[
        @{ @"title": @"User Defaults", @"chevron": @YES,
           @"action": ^{ [weakSelf push:[[FKDefaultsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        @{ @"title": @"Cookies", @"chevron": @YES,
           @"action": ^{ [weakSelf push:[[FKCookiesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        @{ @"title": @"Keychain", @"chevron": @YES,
           @"action": ^{ [weakSelf push:[[FKKeychainViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        @{ @"title": @"Notifications", @"subtitle": @"Recorded posts", @"chevron": @YES,
           @"action": ^{ [weakSelf push:[[FKNotificationsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
        @{ @"title": @"Web views", @"subtitle": @"Make WKWebView inspectable", @"chevron": @YES,
           @"action": ^{ [weakSelf push:[[FKWebViewsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; } },
    ] } ];
    [self reloadSections];
}

- (void)push:(UIViewController *)controller {
    [self.navigationController pushViewController:controller animated:YES];
}

@end

#pragma mark - Notifications

@interface FKNotificationsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *records;
@end

@implementation FKNotificationsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Notifications";
    self.tableView.rowHeight = 50;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(clear)];
    [self reload];
}

- (void)reload {
    self.records = [FKRuntimeKit notificationHistory:300][@"records"] ?: @[];
    [self.tableView reloadData];
}

- (void)clear { [FKRuntimeKit clearNotificationHistory]; [self reload]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)MAX(1, self.records.count); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"notification";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if (!self.records.count) {
        cell.textLabel.text = @"No notifications recorded";
        cell.detailTextLabel.text = @"Posts are captured after launch";
        return cell;
    }
    NSDictionary *record = self.records[(NSUInteger)indexPath.row];
    cell.textLabel.text = record[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", record[@"object"],
                                 FKFormatDate([NSDate dateWithTimeIntervalSince1970:[record[@"time"] doubleValue]])];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    return cell;
}

@end

#pragma mark - Web views

@implementation FKWebViewsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Web views";
    self.tableView.rowHeight = 54;
}

- (NSArray<UIView *> *)webViews {
    NSMutableArray *webViews = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            [self collect:window into:webViews];
        }
    }
    return webViews;
}

- (void)collect:(UIView *)view into:(NSMutableArray *)webViews {
    if ([view isKindOfClass:NSClassFromString(@"WKWebView")]) [webViews addObject:view];
    for (UIView *child in view.subviews) [self collect:child into:webViews];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(1, [self webViews].count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"webview";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSArray *views = [self webViews];
    if (!views.count) {
        cell.textLabel.text = @"No WKWebView instances";
        cell.detailTextLabel.text = @"Open a web view first";
        return cell;
    }
    UIView *view = views[(NSUInteger)indexPath.row];
    cell.textLabel.text = NSStringFromClass([view class]);
    cell.detailTextLabel.text = NSStringFromCGRect(view.frame);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *views = [self webViews];
    if (!views.count) return;
    [FKUtilities setWebInspectorEnabled:YES];
    [FKUtilities applyWebInspectorToOpenWebViews];
    FKPresentAlert(@"Web inspector", @"Inspectable enabled for all web views. Attach Safari's Web Inspector to this device.");
}

@end

#pragma mark - SQLite

@interface FKSQLiteListViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *files;
@end

@implementation FKSQLiteListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SQLite";
    self.tableView.rowHeight = 54;
    self.files = [FKRuntimeKit sqliteFiles];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(1, self.files.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"sqlite-file";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    if (!self.files.count) {
        cell.textLabel.text = @"No databases found";
        cell.detailTextLabel.text = @"Looked in Documents and Library";
        return cell;
    }
    NSDictionary *entry = self.files[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", entry[@"path"], FKHumanSize([entry[@"bytes"] unsignedLongLongValue])];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:8.5 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.files.count) return;
    NSDictionary *entry = self.files[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:
        [FKSQLiteTablesViewController controllerWithPath:entry[@"path"]] animated:YES];
}

@end

@interface FKSQLiteTablesViewController ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSArray<NSString *> *tables;
@end

@implementation FKSQLiteTablesViewController

+ (instancetype)controllerWithPath:(NSString *)path {
    FKSQLiteTablesViewController *controller = [[FKSQLiteTablesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.path = path;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.path.lastPathComponent;
    self.tableView.rowHeight = 46;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Query"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(promptQuery)];
    NSDictionary *result = [FKRuntimeKit sqliteTablesAtPath:self.path];
    self.tables = result[@"tables"] ?: @[];
    if (![result[@"ok"] boolValue]) FKPresentAlert(@"SQLite", result[@"error"] ?: @"cannot open");
}

- (void)promptQuery {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SQL query"
                                                                   message:self.path.lastPathComponent
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = @"SELECT * FROM sqlite_master LIMIT 50";
        field.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Run" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *sql = alert.textFields.firstObject.text ?: @"";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *result = [FKRuntimeKit sqliteQuery:sql atPath:self.path];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![result[@"ok"] boolValue]) { FKPresentAlert(@"SQLite", result[@"error"] ?: @"failed"); return; }
                NSMutableString *text = [NSMutableString string];
                [text appendFormat:@"%@\n\n", [result[@"columns"] componentsJoinedByString:@" | "]];
                for (NSDictionary *row in result[@"rows"]) {
                    NSMutableArray *values = [NSMutableArray array];
                    for (NSString *column in result[@"columns"]) [values addObject:[row[column] description] ?: @"NULL"];
                    [text appendFormat:@"%@\n", [values componentsJoinedByString:@" | "]];
                }
                [text appendFormat:@"\n%lu rows", (unsigned long)[result[@"rows"] count]];
                [self.navigationController pushViewController:
                    [FKTextViewController viewerWithTitle:@"Query" text:text] animated:YES];
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)MAX(1, self.tables.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"sqlite-table";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    cell.textLabel.text = self.tables.count ? self.tables[(NSUInteger)indexPath.row] : @"No tables";
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.accessoryType = self.tables.count ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.tables.count) return;
    NSString *table = [self.tables[(NSUInteger)indexPath.row] stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM \"%@\" LIMIT 100", table];
    NSDictionary *result = [FKRuntimeKit sqliteQuery:sql atPath:self.path];
    if (![result[@"ok"] boolValue]) { FKPresentAlert(@"SQLite", result[@"error"] ?: @"failed"); return; }
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"%@\n\n", [result[@"columns"] componentsJoinedByString:@" | "]];
    for (NSDictionary *row in result[@"rows"]) {
        NSMutableArray *values = [NSMutableArray array];
        for (NSString *column in result[@"columns"]) [values addObject:[row[column] description] ?: @"NULL"];
        [text appendFormat:@"%@\n", [values componentsJoinedByString:@" | "]];
    }
    [text appendFormat:@"\n%lu rows", (unsigned long)[result[@"rows"] count]];
    [self.navigationController pushViewController:[FKTextViewController viewerWithTitle:table text:text] animated:YES];
}

@end

#pragma mark - System

@implementation FKSystemViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{ @"title": @"Device", @"subtitle": FKDeviceModelIdentifier() }];
    [rows addObject:@{ @"title": @"iOS", @"subtitle": FKOSVersionString() }];
    [rows addObject:@{ @"title": @"App", @"subtitle": [NSString stringWithFormat:@"%@ · %@", FKAppName(), FKAppVersion()] }];
    [rows addObject:@{ @"title": @"Bundle", @"subtitle": FKAppIdentifier() }];
    [rows addObject:@{ @"title": @"Container", @"subtitle": FKContainerPath() }];
    [rows addObject:@{ @"title": @"Resident memory", @"subtitle": FKHumanSize(FKResidentMemory()) }];
    [rows addObject:@{ @"title": @"Cores", @"subtitle": [NSString stringWithFormat:@"%lu", (unsigned long)[[NSProcessInfo processInfo] processorCount]] }];
    [rows addObject:@{ @"title": @"Uptime", @"subtitle": [NSString stringWithFormat:@"%.0f s", [[NSProcessInfo processInfo] systemUptime]] }];
    [rows addObject:@{ @"title": @"Modules", @"subtitle": [NSString stringWithFormat:@"%lu", (unsigned long)[FKRuntimeKit modules].count] }];
    [rows addObject:@{ @"title": @"Classes", @"subtitle": [NSString stringWithFormat:@"%d", objc_getClassList(NULL, 0)] }];
    [rows addObject:@{ @"title": @"Network", @"subtitle": [FKLanAddresses() componentsJoinedByString:@", "] }];
    self.sections = @[ @{ @"title": @"Process", @"rows": rows } ];
    [self reloadSections];
}

@end
