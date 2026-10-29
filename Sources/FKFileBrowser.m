//
//  FKFileBrowser.m — full-featured in-app file browser (RWFileManager-class utility)
//

#import "ForgeKit.h"

@interface FKFileBrowserViewController () <UISearchResultsUpdating, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *visibleEntries;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL showHidden;
@property (nonatomic, copy) NSString *sortKey;
@property (nonatomic, assign) BOOL sortAscending;
@end

@implementation FKFileBrowserViewController

+ (instancetype)browserAtPath:(NSString *)path {
    FKFileBrowserViewController *controller = [[FKFileBrowserViewController alloc] initWithStyle:UITableViewStylePlain];
    controller.path = FKExpandPath(path ?: FKContainerPath());
    controller.sortKey = @"name";
    controller.sortAscending = YES;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 56;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter this folder";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(showCreateMenu:)];
    [self buildToolbar];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)buildToolbar {
    self.navigationController.toolbarHidden = NO;
    UIBarButtonItem *(^item)(NSString *, SEL) = ^UIBarButtonItem *(NSString *image, SEL action) {
        return [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:image]
                                                style:UIBarButtonItemStylePlain
                                               target:self
                                               action:action];
    };
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil action:nil];
    self.toolbarItems = @[ item(@"externaldrive", @selector(showRoots:)),
                           flex,
                           item(@"arrow.up.doc", @selector(goToPath:)),
                           flex,
                           item(@"eye", @selector(toggleHidden:)),
                           flex,
                           item(@"arrow.up.arrow.down", @selector(showSortMenu:)) ];
}

#pragma mark - Data

- (void)reload {
    NSError *error = nil;
    NSArray *entries = FKDirectoryList(self.path, self.showHidden, &error);
    if (error && !self.entries.count) {
        FKLog(@"list %@ failed: %@", self.path, error.localizedDescription);
    }
    NSArray *sorted = [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aDir = [a[@"directory"] boolValue], bDir = [b[@"directory"] boolValue];
        if (aDir != bDir) return aDir ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult result;
        if ([self.sortKey isEqualToString:@"size"]) {
            result = [a[@"size"] compare:b[@"size"]];
        } else if ([self.sortKey isEqualToString:@"date"]) {
            result = [a[@"modified"] compare:b[@"modified"]];
        } else {
            result = [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }
        return self.sortAscending ? result : -result;
    }];
    self.entries = sorted;
    self.title = self.path.length > 1 ? self.path.lastPathComponent : @"Root";
    [self applyFilter];
    [self updateFooter];
}

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text;
    if (!query.length) {
        self.visibleEntries = self.entries;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", query];
        self.visibleEntries = [self.entries filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (void)updateFooter {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:self.path error:nil];
    unsigned long long free = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 46)];
    label.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.text = [NSString stringWithFormat:@"%@\n%@ free", self.path, FKHumanSize(free)];
    self.tableView.tableFooterView = label;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.visibleEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"FKFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    BOOL directory = [entry[@"directory"] boolValue];
    NSString *extension = [entry[@"name"] pathExtension].lowercaseString;
    NSString *symbol = directory ? @"folder.fill" : @"doc.text";
    if ([@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic"] containsObject:extension]) symbol = @"photo";
    else if ([extension isEqualToString:@"plist"]) symbol = @"list.bullet.rectangle";
    else if ([@[@"dylib", @"framework"] containsObject:extension]) symbol = @"shippingbox";
    else if ([@[@"zip", @"gz", @"tar", @"deb"] containsObject:extension]) symbol = @"archivebox";
    else if ([@[@"sqlite", @"db"] containsObject:extension]) symbol = @"cylinder.split.1x2";

    cell.imageView.image = [UIImage systemImageNamed:symbol];
    cell.imageView.tintColor = directory ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    cell.textLabel.text = entry[@"name"];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:directory ? UIFontWeightSemibold : UIFontWeightRegular];
    NSString *detail = directory ? @"folder" : entry[@"size_text"];
    NSString *date = entry[@"modified"] ? FKFormatDate([NSDate dateWithTimeIntervalSince1970:[entry[@"modified"] doubleValue]]) : nil;
    if (date.length && !directory) detail = [NSString stringWithFormat:@"%@ · %@", detail, date];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.accessoryType = directory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openEntry:self.visibleEntries[(NSUInteger)indexPath.row]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self confirmDelete:entry completion:completion];
    }];
    UIContextualAction *shareAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                              title:@"Share"
                                                                            handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self shareEntry:entry sender:nil];
        completion(YES);
    }];
    shareAction.backgroundColor = [UIColor systemTealColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, shareAction]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                        title:@"Rename"
                                                                      handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self promptRename:entry completion:completion];
    }];
    rename.backgroundColor = [UIColor systemOrangeColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[rename]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSDictionary *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    NSString *path = entry[@"path"];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        NSMutableArray *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"Open" image:[UIImage systemImageNamed:@"arrow.up.right.square"] identifier:nil handler:^(UIAction *a) {
            [self openEntry:entry];
        }]];
        if ([entry[@"directory"] boolValue]) {
            [actions addObject:[UIAction actionWithTitle:@"Open in new window" image:[UIImage systemImageNamed:@"rectangle.stack"] identifier:nil handler:^(UIAction *a) {
                FKFileBrowserViewController *browser = [FKFileBrowserViewController browserAtPath:path];
                [self.navigationController pushViewController:browser animated:YES];
            }]];
        }
        [actions addObject:[UIAction actionWithTitle:@"Rename" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *a) {
            [self promptRename:entry completion:nil];
        }]];
        [actions addObject:[UIAction actionWithTitle:@"Duplicate" image:[UIImage systemImageNamed:@"plus.square.on.square"] identifier:nil handler:^(UIAction *a) {
            [self duplicate:entry];
        }]];
        [actions addObject:[UIAction actionWithTitle:@"Compress" image:[UIImage systemImageNamed:@"archivebox"] identifier:nil handler:^(UIAction *a) {
            [self compress:entry];
        }]];
        [actions addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) {
            [self shareEntry:entry sender:nil];
        }]];
        [actions addObject:[UIAction actionWithTitle:@"Info" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(UIAction *a) {
            [self showInfo:entry];
        }]];
        UIMenu *destructive = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *a) {
                [self confirmDelete:entry completion:nil];
            }]
        ]];
        return [UIMenu menuWithTitle:entry[@"name"] image:nil identifier:nil options:0 children:[actions arrayByAddingObject:destructive]];
    }];
}

#pragma mark - Open / preview

- (void)openEntry:(NSDictionary *)entry {
    NSString *path = entry[@"path"];
    if ([entry[@"directory"] boolValue]) {
        [self.navigationController pushViewController:[FKFileBrowserViewController browserAtPath:path] animated:YES];
        return;
    }
    NSString *extension = path.pathExtension.lowercaseString;
    if ([@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"heic", @"bmp", @"tiff"] containsObject:extension]) {
        [self.navigationController pushViewController:[FKImageViewController viewerWithPath:path] animated:YES];
    } else if ([extension isEqualToString:@"plist"]) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (plist) {
            NSError *error = nil;
            NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
            NSString *text = xml ? [[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] : error.localizedDescription;
            [self.navigationController pushViewController:[FKTextViewController viewerWithTitle:path.lastPathComponent text:text] animated:YES];
        } else {
            [self.navigationController pushViewController:[FKHexViewController viewerWithPath:path] animated:YES];
        }
    } else if ([@[@"txt", @"md", @"json", @"xml", @"log", @"swift", @"m", @"mm", @"h", @"c", @"cpp", @"js", @"ts", @"html",
                  @"css", @"sh", @"strings", @"conf", @"yml", @"yaml", @"ini", @"plistx", @"pbxproj", @"entitlements"] containsObject:extension]) {
        [self.navigationController pushViewController:[FKTextViewController editorWithPath:path] animated:YES];
    } else {
        [self.navigationController pushViewController:[FKHexViewController viewerWithPath:path] animated:YES];
    }
}

#pragma mark - Actions

- (void)showCreateMenu:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptCreateDirectory];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New text file" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self promptCreateFile];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Paste copied path" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self pastePath];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptCreateDirectory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New folder" message:self.path
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"name"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = alert.textFields.firstObject.text;
        if (!name.length) return;
        NSString *target = [self.path stringByAppendingPathComponent:name];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:NO attributes:nil error:&error])
            FKPresentAlert(@"Create failed", error.localizedDescription);
        [self reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptCreateFile {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New file" message:self.path
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"name.txt"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = alert.textFields.firstObject.text;
        if (!name.length) return;
        NSString *target = [self.path stringByAppendingPathComponent:name];
        NSError *error = nil;
        if (!FKWriteDataAtomically([NSData data], target, &error)) FKPresentAlert(@"Create failed", error.localizedDescription);
        [self reload];
        [self.navigationController pushViewController:[FKTextViewController editorWithPath:target] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pastePath {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *string = pasteboard.string;
    if (!string.length) { FKPresentAlert(@"Clipboard empty", @"Copy a path or file name first."); return; }
    NSString *target = [string isAbsolutePath] ? string : [self.path stringByAppendingPathComponent:string];
    BOOL directory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&directory]) {
        if (directory) [self.navigationController pushViewController:[FKFileBrowserViewController browserAtPath:target] animated:YES];
        else [self openEntry:@{ @"path": target, @"directory": @NO, @"name": target.lastPathComponent, @"size": @0 }];
    } else {
        FKPresentAlert(@"Not found", target);
    }
}

- (void)promptRename:(NSDictionary *)entry completion:(void (^)(BOOL))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:entry[@"name"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = entry[@"name"]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = alert.textFields.firstObject.text;
        if (!name.length) { if (completion) completion(NO); return; }
        NSString *target = [[entry[@"path"] stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
        NSError *error = nil;
        BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:entry[@"path"] toPath:target error:&error];
        if (!ok) FKPresentAlert(@"Rename failed", error.localizedDescription);
        if (completion) completion(ok);
        [self reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        if (completion) completion(NO);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)duplicate:(NSDictionary *)entry {
    NSString *path = entry[@"path"];
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *base = path.lastPathComponent.stringByDeletingPathExtension;
    NSString *extension = path.pathExtension;
    NSString *name = extension.length ? [NSString stringWithFormat:@"%@ copy.%@", base, extension]
                                      : [NSString stringWithFormat:@"%@ copy", base];
    NSString *target = [directory stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:target error:&error]) {
        FKPresentAlert(@"Duplicate failed", error.localizedDescription);
        return;
    }
    [self reload];
}

- (void)confirmDelete:(NSDictionary *)entry completion:(void (^)(BOOL))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete"
                                                                   message:entry[@"name"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        NSError *error = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:entry[@"path"] error:&error];
        if (!ok) FKPresentAlert(@"Delete failed", error.localizedDescription);
        if (completion) completion(ok);
        [self reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        if (completion) completion(NO);
    }]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareEntry:(NSDictionary *)entry sender:(id)sender {
    NSURL *url = [NSURL fileURLWithPath:entry[@"path"]];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)showInfo:(NSDictionary *)entry {
    NSDictionary *attributes = FKFileAttributes(entry[@"path"]);
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *key in [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [rows addObject:@{ @"title": key, @"value": [attributes[key] description],
                           @"subtitle": [attributes[key] description] }];
    }
    FKListViewController *info = [FKListViewController listWithTitle:entry[@"name"] sections:@[ @{ @"title": @"Attributes", @"rows": rows } ]];
    [self.navigationController pushViewController:info animated:YES];
}

- (void)compress:(NSDictionary *)entry {
    NSString *source = entry[@"path"];
    NSString *target = [source stringByAppendingPathExtension:@"zip"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:target]) {
        target = [[source stringByDeletingPathExtension] stringByAppendingString:
                  [NSString stringWithFormat:@"-%@.zip", @((NSInteger)[[NSDate date] timeIntervalSince1970])]];
    }
    NSError *error = nil;
    if (![FKZip createArchiveAtPath:target fromPaths:@[source] error:&error]) {
        FKPresentAlert(@"Compress failed", error.localizedDescription);
        return;
    }
    [self reload];
}

- (void)showRoots:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Jump to" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *root in FKRoots()) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@%@", root[@"name"], root[@"path"],
                           [root[@"readable"] boolValue] ? @"" : @" (denied)"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            FKFileBrowserViewController *browser = [FKFileBrowserViewController browserAtPath:root[@"path"]];
            [self.navigationController pushViewController:browser animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.toolbarItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)goToPath:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Go to path" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.path;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *path = alert.textFields.firstObject.text;
        if (!path.length) return;
        [self.navigationController pushViewController:[FKFileBrowserViewController browserAtPath:path] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleHidden:(id)sender {
    self.showHidden = !self.showHidden;
    [self reload];
    UIBarButtonItem *item = (UIBarButtonItem *)sender;
    item.image = [UIImage systemImageNamed:self.showHidden ? @"eye.fill" : @"eye"];
}

- (void)showSortMenu:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Sort" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *key in @[@"name", @"size", @"date"]) {
        NSString *title = [NSString stringWithFormat:@"%@ %@", key, [self.sortKey isEqualToString:key] ? @"✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if ([self.sortKey isEqualToString:key]) self.sortAscending = !self.sortAscending;
            else { self.sortKey = key; self.sortAscending = YES; }
            [self reload];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = (UIBarButtonItem *)sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
