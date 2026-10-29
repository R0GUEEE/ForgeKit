//
//  FKUI.m — shared UIKit building blocks
//

#import "ForgeKit.h"

#pragma mark - FKListViewController

@implementation FKListViewController

+ (instancetype)listWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections {
    FKListViewController *controller = [[FKListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.screenTitle = title ?: @"";
    controller.sections = sections ?: @[];
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.screenTitle;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
}

- (void)reloadSections {
    if ([NSThread isMainThread]) [self.tableView reloadData];
    else FKRunOnMain(^{ [self.tableView reloadData]; });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.sections.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.sections[(NSUInteger)section][@"footer"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
    return (NSInteger)rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *section = self.sections[(NSUInteger)indexPath.section];
    NSArray *rows = section[@"rows"];
    NSDictionary *row = rows[(NSUInteger)indexPath.row];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.text = row[@"subtitle"] ?: row[@"value"];
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.textColor = [row[@"destructive"] boolValue] ? [UIColor systemRedColor] : [UIColor labelColor];
    cell.selectionStyle = row[@"action"] || row[@"toggle"] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;

    if (row[@"toggle"]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [row[@"toggleValue"] boolValue];
        toggle.tag = indexPath.section * 1000 + indexPath.row;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (row[@"chevron"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (row[@"check"] && [row[@"check"] boolValue]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;
    if (section >= (NSInteger)self.sections.count) return;
    NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
    if (row >= (NSInteger)rows.count) return;
    void (^block)(BOOL) = rows[(NSUInteger)row][@"toggle"];
    if (block) block(sender.isOn);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *rows = self.sections[(NSUInteger)indexPath.section][@"rows"];
    NSDictionary *row = rows[(NSUInteger)indexPath.row];
    void (^action)(void) = row[@"action"];
    if (action) action();
}

@end

#pragma mark - FKTextViewController

@interface FKTextViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, assign) BOOL dirty;
@end

@implementation FKTextViewController

+ (instancetype)viewerWithTitle:(NSString *)title text:(NSString *)text {
    FKTextViewController *controller = [[FKTextViewController alloc] init];
    controller.title = title;
    controller.text = text ?: @"";
    controller.readOnly = YES;
    return controller;
}

+ (instancetype)viewerWithPath:(NSString *)path {
    FKTextViewController *controller = [[FKTextViewController alloc] init];
    controller.filePath = path;
    controller.title = path.lastPathComponent;
    controller.readOnly = YES;
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    controller.text = text ?: [NSString stringWithFormat:@"Cannot decode %@ as UTF-8 (%llu bytes).",
                               path.lastPathComponent, (unsigned long long)data.length];
    if (!text) controller.readOnly = YES;
    return controller;
}

+ (instancetype)editorWithPath:(NSString *)path {
    FKTextViewController *controller = [self viewerWithPath:path];
    controller.readOnly = NO;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.text = self.text ?: @"";
    self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.textView.editable = !self.readOnly;
    self.textView.alwaysBounceVertical = YES;
    self.textView.delegate = self;
    [self.view addSubview:self.textView];
    if (@available(iOS 13.0, *)) {
        self.textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.textView.textColor = [UIColor labelColor];
    }

    NSMutableArray<UIBarButtonItem *> *rightItems = [NSMutableArray array];
    if (!self.readOnly && self.filePath.length) {
        [rightItems addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                            target:self
                                                                            action:@selector(save)]];
    }
    [rightItems addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                         target:self
                                                                         action:@selector(share)]];
    // Keep the automatic back button: actions live on the right.
    self.navigationItem.rightBarButtonItems = rightItems;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)keyboardChanged:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.textView.contentInset = insets;
    self.textView.scrollIndicatorInsets = insets;
}

- (void)textViewDidChange:(UITextView *)textView { self.dirty = YES; }

- (void)save {
    NSError *error = nil;
    NSData *data = [self.textView.text dataUsingEncoding:NSUTF8StringEncoding];
    if (!self.filePath.length || !FKWriteDataAtomically(data, self.filePath, &error)) {
        FKPresentAlert(@"Save failed", error.localizedDescription ?: @"no path");
        return;
    }
    self.dirty = NO;
    self.text = self.textView.text;
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    self.title = [NSString stringWithFormat:@"%@ · saved", self.filePath.lastPathComponent];
}

- (void)share {
    NSArray *items = self.filePath.length ? @[[NSURL fileURLWithPath:self.filePath]] : @[self.textView.text ?: @""];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:activity animated:YES completion:nil];
}

@end

#pragma mark - FKHexViewController

@interface FKHexViewController ()
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, assign) NSUInteger loaded;
@end

@implementation FKHexViewController

+ (instancetype)viewerWithPath:(NSString *)path {
    FKHexViewController *controller = [[FKHexViewController alloc] init];
    controller.filePath = path;
    controller.title = path.lastPathComponent;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.data = [NSData dataWithContentsOfFile:self.filePath options:NSDataReadingMappedIfSafe error:nil] ?: [NSData data];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.view addSubview:self.textView];

    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithTitle:@"More"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(loadMore)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                            target:self
                                                                            action:@selector(share)];
    self.navigationItem.rightBarButtonItems = @[more, share];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self renderFrom:0];
}

- (void)renderFrom:(NSUInteger)offset {
    NSUInteger chunk = 128 * 1024;
    if (offset >= self.data.length) return;
    NSUInteger length = MIN(chunk, self.data.length - offset);
    NSData *slice = [self.data subdataWithRange:NSMakeRange(offset, length)];
    NSString *dump = FKHexDump(slice, offset, length);
    self.textView.text = offset == 0 ? dump : [self.textView.text stringByAppendingString:dump];
    self.loaded = offset + length;
    self.title = [NSString stringWithFormat:@"%@ · %@", self.filePath.lastPathComponent, FKHumanSize(self.data.length)];
}

- (void)loadMore { [self renderFrom:self.loaded]; }

- (void)share {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:self.filePath]]
                                                                          applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:activity animated:YES completion:nil];
}

@end

#pragma mark - FKImageViewController

@interface FKImageViewController () <UIScrollViewDelegate>
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation FKImageViewController

+ (instancetype)viewerWithPath:(NSString *)path {
    FKImageViewController *controller = [[FKImageViewController alloc] init];
    controller.filePath = path;
    controller.title = path.lastPathComponent;
    return controller;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIImage *image = [UIImage imageWithContentsOfFile:self.filePath];
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 6.0;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithImage:image];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = self.scrollView.bounds;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scrollView addSubview:self.imageView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self
                                                                                           action:@selector(share)];
    if (!image) {
        UILabel *label = [[UILabel alloc] init];
        label.text = @"Cannot decode image";
        label.textColor = [UIColor whiteColor];
        [label sizeToFit];
        label.center = self.view.center;
        [self.view addSubview:label];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }

- (void)share {
    NSArray *items = @[[NSURL fileURLWithPath:self.filePath]];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
}

@end
