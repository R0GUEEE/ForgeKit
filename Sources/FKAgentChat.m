//
//  FKAgentChat.m — agent chat interface
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKAgent.h"

#pragma mark - Markdown

static NSAttributedString *FKChatMarkdown(NSString *text, UIFont *baseFont, UIColor *color) {
    NSMutableAttributedString *output = [[NSMutableAttributedString alloc] init];
    if (!text.length) return output;
    UIFont *bold = [UIFont systemFontOfSize:baseFont.pointSize weight:UIFontWeightSemibold];
    UIFont *italic = [UIFont italicSystemFontOfSize:baseFont.pointSize];
    UIFont *mono = [UIFont monospacedSystemFontOfSize:baseFont.pointSize - 0.5 weight:UIFontWeightRegular];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    NSDictionary *base = @{ NSFontAttributeName: baseFont,
                            NSForegroundColorAttributeName: color,
                            NSParagraphStyleAttributeName: paragraph };

    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    BOOL inCode = NO;
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *line = lines[index];
        BOOL last = index == lines.count - 1;
        if ([line hasPrefix:@"```"]) {
            inCode = !inCode;
            continue;
        }
        if (inCode) {
            [output appendAttributedString:[[NSAttributedString alloc]
                initWithString:[line stringByAppendingString:@"\n"]
                    attributes:@{ NSFontAttributeName: mono,
                                  NSForegroundColorAttributeName: [color colorWithAlphaComponent:0.92],
                                  NSBackgroundColorAttributeName: [UIColor colorWithWhite:0.5 alpha:0.12],
                                  NSParagraphStyleAttributeName: paragraph }]];
            continue;
        }
        NSMutableAttributedString *row = [[NSMutableAttributedString alloc] initWithString:line attributes:base];
        // **bold**
        NSRegularExpression *boldRegex = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*(.+?)\\*\\*" options:0 error:nil];
        for (NSTextCheckingResult *match in [[boldRegex matchesInString:line options:0 range:NSMakeRange(0, line.length)] reverseObjectEnumerator]) {
            NSString *inner = [line substringWithRange:[match rangeAtIndex:1]];
            [row replaceCharactersInRange:match.range withString:inner];
            [row addAttribute:NSFontAttributeName value:bold
                        range:NSMakeRange(match.range.location, inner.length)];
        }
        // `code`
        NSRegularExpression *codeRegex = [NSRegularExpression regularExpressionWithPattern:@"`([^`]+)`" options:0 error:nil];
        NSString *plain = row.string;
        for (NSTextCheckingResult *match in [[codeRegex matchesInString:plain options:0 range:NSMakeRange(0, plain.length)] reverseObjectEnumerator]) {
            NSString *inner = [plain substringWithRange:[match rangeAtIndex:1]];
            [row replaceCharactersInRange:match.range withString:inner];
            [row addAttribute:NSFontAttributeName value:mono
                        range:NSMakeRange(match.range.location, inner.length)];
            [row addAttribute:NSBackgroundColorAttributeName value:[UIColor colorWithWhite:0.5 alpha:0.14]
                        range:NSMakeRange(match.range.location, inner.length)];
        }
        // *italic*
        NSRegularExpression *italicRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<![*])\\*([^*]+)\\*" options:0 error:nil];
        plain = row.string;
        for (NSTextCheckingResult *match in [[italicRegex matchesInString:plain options:0 range:NSMakeRange(0, plain.length)] reverseObjectEnumerator]) {
            NSString *inner = [plain substringWithRange:[match rangeAtIndex:1]];
            [row replaceCharactersInRange:match.range withString:inner];
            [row addAttribute:NSFontAttributeName value:italic
                        range:NSMakeRange(match.range.location, inner.length)];
        }
        if (!last) [row appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:base]];
        [output appendAttributedString:row];
    }
    return output;
}

#pragma mark - Entry

typedef NS_ENUM(NSInteger, FKChatKind) {
    FKChatKindUser,
    FKChatKindAssistant,
    FKChatKindSystem,
    FKChatKindTool,
};

@interface FKChatEntry : NSObject
@property (nonatomic, assign) FKChatKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, assign) BOOL toolOK;
@property (nonatomic, assign) BOOL toolPending;
@property (nonatomic, copy) NSString *toolDetail;
@property (nonatomic, strong) NSDictionary *toolResult;
@property (nonatomic, strong) NSDate *date;
@end

@implementation FKChatEntry
+ (instancetype)user:(NSString *)text {
    FKChatEntry *entry = [[FKChatEntry alloc] init];
    entry.kind = FKChatKindUser; entry.text = text ?: @""; entry.date = [NSDate date];
    return entry;
}
+ (instancetype)assistant:(NSString *)text {
    FKChatEntry *entry = [[FKChatEntry alloc] init];
    entry.kind = FKChatKindAssistant; entry.text = text ?: @""; entry.date = [NSDate date];
    return entry;
}
+ (instancetype)system:(NSString *)text {
    FKChatEntry *entry = [[FKChatEntry alloc] init];
    entry.kind = FKChatKindSystem; entry.text = text ?: @""; entry.date = [NSDate date];
    return entry;
}
+ (instancetype)tool:(NSString *)name arguments:(NSDictionary *)arguments {
    FKChatEntry *entry = [[FKChatEntry alloc] init];
    entry.kind = FKChatKindTool;
    entry.toolName = name ?: @"?";
    entry.toolPending = YES;
    entry.date = [NSDate date];
    NSString *summary = FKJSONString(arguments ?: @{}, NO);
    if (summary.length > 120) summary = [[summary substringToIndex:120] stringByAppendingString:@"…"];
    entry.toolDetail = summary;
    return entry;
}
@end

#pragma mark - Cells

@interface FKChatBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSLayoutConstraint *leading;
@property (nonatomic, strong) NSLayoutConstraint *trailing;
- (void)configureWithEntry:(FKChatEntry *)entry;
@end

@implementation FKChatBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [[UIView alloc] init];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = 16;
        _bubble.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:_bubble];

        _label = [[UILabel alloc] init];
        _label.numberOfLines = 0;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [_bubble addSubview:_label];

        _leading = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12];
        _trailing = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12];
        [NSLayoutConstraint activateConstraints:@[
            [_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.84],
            [_label.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:12],
            [_label.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-12],
            [_label.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:9],
            [_label.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-9],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(FKChatEntry *)entry {
    BOOL isUser = entry.kind == FKChatKindUser;
    self.leading.active = !isUser;
    self.trailing.active = isUser;
    self.bubble.backgroundColor = isUser ? [UIColor systemBlueColor]
                                         : [UIColor secondarySystemGroupedBackgroundColor];
    UIColor *textColor = isUser ? [UIColor whiteColor] : [UIColor labelColor];
    UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.label.attributedText = isUser ? [[NSAttributedString alloc] initWithString:entry.text ?: @""
                                                                        attributes:@{ NSFontAttributeName: font,
                                                                                      NSForegroundColorAttributeName: textColor }]
                                       : FKChatMarkdown(entry.text, font, textColor);
    self.bubble.layer.borderWidth = isUser ? 0 : 0.5;
    self.bubble.layer.borderColor = [UIColor separatorColor].CGColor;
}

@end

@interface FKChatSystemCell : UITableViewCell
@property (nonatomic, strong) UILabel *pill;
@end

@implementation FKChatSystemCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _pill = [[UILabel alloc] init];
        _pill.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _pill.textColor = [UIColor secondaryLabelColor];
        _pill.textAlignment = NSTextAlignmentCenter;
        _pill.numberOfLines = 0;
        _pill.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
        _pill.layer.cornerRadius = 10;
        _pill.layer.cornerCurve = kCACornerCurveContinuous;
        _pill.clipsToBounds = YES;
        _pill.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_pill];
        [NSLayoutConstraint activateConstraints:@[
            [_pill.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_pill.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.86],
            [_pill.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_pill.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        ]];
    }
    return self;
}
- (void)configureText:(NSString *)text {
    self.pill.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
}
@end

@interface FKChatToolCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UILabel *detail;
@end

@implementation FKChatToolCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [[UIView alloc] init];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _card.layer.cornerRadius = 12;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 0.5;
        _card.layer.borderColor = [UIColor separatorColor].CGColor;
        [self.contentView addSubview:_card];

        _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"wrench.and.screwdriver.fill"]];
        _icon.tintColor = [UIColor systemOrangeColor];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_icon];

        _title = [[UILabel alloc] init];
        _title.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_title];

        _status = [[UILabel alloc] init];
        _status.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _status.textAlignment = NSTextAlignmentRight;
        _status.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_status];

        _detail = [[UILabel alloc] init];
        _detail.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
        _detail.textColor = [UIColor secondaryLabelColor];
        _detail.numberOfLines = 2;
        _detail.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_detail];

        [NSLayoutConstraint activateConstraints:@[
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

            [_icon.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_icon.topAnchor constraintEqualToAnchor:_card.topAnchor constant:10],
            [_icon.widthAnchor constraintEqualToConstant:15],
            [_icon.heightAnchor constraintEqualToConstant:15],

            [_title.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:7],
            [_title.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_status.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
            [_status.centerYAnchor constraintEqualToAnchor:_icon.centerYAnchor],
            [_status.leadingAnchor constraintGreaterThanOrEqualToAnchor:_title.trailingAnchor constant:6],

            [_detail.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:10],
            [_detail.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
            [_detail.topAnchor constraintEqualToAnchor:_icon.bottomAnchor constant:5],
            [_detail.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-9],
        ]];
    }
    return self;
}
- (void)configureWithEntry:(FKChatEntry *)entry {
    self.title.text = entry.toolName;
    if (entry.toolPending) {
        self.status.text = @"running";
        self.status.textColor = [UIColor systemOrangeColor];
    } else if (entry.toolOK) {
        self.status.text = @"done";
        self.status.textColor = [UIColor systemGreenColor];
    } else {
        self.status.text = @"failed";
        self.status.textColor = [UIColor systemRedColor];
    }
    self.detail.text = entry.toolDetail ?: @"";
}
@end

#pragma mark - Chat

@interface FKAgentChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<FKChatEntry *> *entries;
@property (nonatomic, strong) UIView *headerBar;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UILabel *usageLabel;
@property (nonatomic, strong) UIView *composer;
@property (nonatomic, strong) UITextView *inputView;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *presetButton;
@property (nonatomic, strong) UIView *emptyState;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic, strong) NSLayoutConstraint *inputHeight;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL hasRestored;
@end

@implementation FKAgentChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Agent";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.entries = [NSMutableArray array];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                                         style:UIBarButtonItemStylePlain target:self action:@selector(newConversation)],
    ];

    [self buildHeader];
    [self buildTable];
    [self buildComposer];
    [self buildEmptyState];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification object:nil];

    [self restoreHistory];
    [self refreshHeader];
    [self updateEmptyState];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark Build

- (void)buildHeader {
    self.headerBar = [[UIView alloc] init];
    self.headerBar.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.headerBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerBar];

    self.modelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.modelButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.modelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.headerBar addSubview:self.modelButton];

    self.usageLabel = [[UILabel alloc] init];
    self.usageLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.usageLabel.textColor = [UIColor secondaryLabelColor];
    self.usageLabel.textAlignment = NSTextAlignmentRight;
    self.usageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerBar addSubview:self.usageLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.headerBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerBar.heightAnchor constraintEqualToConstant:36],

        [self.modelButton.leadingAnchor constraintEqualToAnchor:self.headerBar.leadingAnchor constant:14],
        [self.modelButton.centerYAnchor constraintEqualToAnchor:self.headerBar.centerYAnchor],
        [self.modelButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.usageLabel.leadingAnchor constant:-8],
        [self.usageLabel.trailingAnchor constraintEqualToAnchor:self.headerBar.trailingAnchor constant:-14],
        [self.usageLabel.centerYAnchor constraintEqualToAnchor:self.headerBar.centerYAnchor],
    ]];
}

- (void)buildTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 12, 0);
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:[FKChatBubbleCell class] forCellReuseIdentifier:@"bubble"];
    [self.tableView registerClass:[FKChatSystemCell class] forCellReuseIdentifier:@"system"];
    [self.tableView registerClass:[FKChatToolCell class] forCellReuseIdentifier:@"tool"];
    [self.view addSubview:self.tableView];
}

- (void)buildComposer {
    self.composer = [[UIView alloc] init];
    self.composer.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.composer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.composer];

    UIView *field = [[UIView alloc] init];
    field.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
    field.layer.cornerRadius = 18;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composer addSubview:field];

    self.inputView = [[UITextView alloc] init];
    self.inputView.font = [UIFont systemFontOfSize:14];
    self.inputView.backgroundColor = [UIColor clearColor];
    self.inputView.delegate = self;
    self.inputView.scrollEnabled = NO;
    self.inputView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.inputView.translatesAutoresizingMaskIntoConstraints = NO;
    [field addSubview:self.inputView];

    self.placeholder = [[UILabel alloc] init];
    self.placeholder.text = @"Ask the agent to build or change something…";
    self.placeholder.font = [UIFont systemFontOfSize:14];
    self.placeholder.textColor = [UIColor placeholderTextColor];
    self.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [field addSubview:self.placeholder];

    self.presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.presetButton setImage:[UIImage systemImageNamed:@"wand.and.stars"] forState:UIControlStateNormal];
    self.presetButton.tintColor = [UIColor systemPurpleColor];
    [self.presetButton addTarget:self action:@selector(showPresets) forControlEvents:UIControlEventTouchUpInside];
    self.presetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composer addSubview:self.presetButton];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    self.sendButton.tintColor = [UIColor systemBlueColor];
    [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composer addSubview:self.sendButton];

    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setImage:[UIImage systemImageNamed:@"stop.circle.fill"] forState:UIControlStateNormal];
    self.stopButton.tintColor = [UIColor systemRedColor];
    self.stopButton.hidden = YES;
    [self.stopButton addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.composer addSubview:self.stopButton];

    self.inputHeight = [self.inputView.heightAnchor constraintEqualToConstant:36];
    self.composerBottom = [self.composer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.headerBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.composer.topAnchor],

        [self.composer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.composer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.composerBottom,

        [field.leadingAnchor constraintEqualToAnchor:self.composer.leadingAnchor constant:10],
        [field.topAnchor constraintEqualToAnchor:self.composer.topAnchor constant:8],
        [field.bottomAnchor constraintEqualToAnchor:self.composer.bottomAnchor constant:-8],
        [field.trailingAnchor constraintEqualToAnchor:self.presetButton.leadingAnchor constant:-6],

        [self.inputView.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:2],
        [self.inputView.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-2],
        [self.inputView.topAnchor constraintEqualToAnchor:field.topAnchor constant:2],
        [self.inputView.bottomAnchor constraintEqualToAnchor:field.bottomAnchor constant:-2],
        [self.placeholder.leadingAnchor constraintEqualToAnchor:self.inputView.leadingAnchor constant:13],
        [self.placeholder.topAnchor constraintEqualToAnchor:self.inputView.topAnchor constant:8],
        self.inputHeight,

        [self.presetButton.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-2],
        [self.presetButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.presetButton.widthAnchor constraintEqualToConstant:26],
        [self.presetButton.heightAnchor constraintEqualToConstant:26],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.composer.trailingAnchor constant:-12],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:32],
        [self.sendButton.heightAnchor constraintEqualToConstant:32],

        [self.stopButton.centerXAnchor constraintEqualToAnchor:self.sendButton.centerXAnchor],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
        [self.stopButton.widthAnchor constraintEqualToConstant:32],
        [self.stopButton.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)buildEmptyState {
    self.emptyState = [[UIView alloc] init];
    self.emptyState.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:self.emptyState aboveSubview:self.tableView];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
    icon.tintColor = [UIColor systemBlueColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyState addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"What should we build?";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyState addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.text = @"Inspect this app, patch it, or scaffold a tweak dylib.";
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyState addSubview:subtitle];

    UIStackView *suggestions = [[UIStackView alloc] init];
    suggestions.axis = UILayoutConstraintAxisVertical;
    suggestions.spacing = 8;
    suggestions.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *prompts = @[@"Inspect this app and suggest three tweaks",
                         @"Build a tweak that removes ads",
                         @"Find a value I can patch safely"];
    NSArray *symbols = @[@"magnifyingglass", @"hammer.fill", @"slider.horizontal.3"];
    for (NSUInteger i = 0; i < prompts.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *configuration = [UIButtonConfiguration grayButtonConfiguration];
            configuration.title = prompts[i];
            configuration.image = [UIImage systemImageNamed:symbols[i]];
            configuration.imagePadding = 8;
            configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
            configuration.baseForegroundColor = [UIColor labelColor];
            button.configuration = configuration;
        } else {
            [button setTitle:prompts[i] forState:UIControlStateNormal];
            [button setImage:[UIImage systemImageNamed:symbols[i]] forState:UIControlStateNormal];
            button.backgroundColor = [UIColor tertiarySystemGroupedBackgroundColor];
            button.layer.cornerRadius = 10;
            button.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 8, 10);
        }
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        button.tag = 500 + (NSInteger)i;
        [button addTarget:self action:@selector(suggestionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [suggestions addArrangedSubview:button];
    }
    [self.emptyState addSubview:suggestions];

    [NSLayoutConstraint activateConstraints:@[
        [self.emptyState.topAnchor constraintEqualToAnchor:self.headerBar.bottomAnchor],
        [self.emptyState.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.emptyState.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.emptyState.bottomAnchor constraintEqualToAnchor:self.composer.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:self.emptyState.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:self.emptyState.centerYAnchor constant:-90],
        [icon.widthAnchor constraintEqualToConstant:34],
        [icon.heightAnchor constraintEqualToConstant:34],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:self.emptyState.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:self.emptyState.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [subtitle.leadingAnchor constraintEqualToAnchor:self.emptyState.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:self.emptyState.trailingAnchor],
        [suggestions.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:18],
        [suggestions.leadingAnchor constraintEqualToAnchor:self.emptyState.leadingAnchor],
        [suggestions.trailingAnchor constraintEqualToAnchor:self.emptyState.trailingAnchor],
    ]];
}

#pragma mark State

- (void)restoreHistory {
    if (self.hasRestored) return;
    self.hasRestored = YES;
    NSArray<NSDictionary *> *history = [[FKAgent sharedAgent] transcript];
    if (!history.count) return;
    [self.entries addObject:[FKChatEntry system:[NSString stringWithFormat:@"restored %lu messages", (unsigned long)history.count]]];
    for (NSDictionary *message in history) {
        NSString *role = message[@"role"];
        id content = message[@"content"];
        if ([role isEqualToString:@"user"] && [content isKindOfClass:[NSString class]] && [content length])
            [self.entries addObject:[FKChatEntry user:content]];
        else if ([role isEqualToString:@"assistant"] && [content isKindOfClass:[NSString class]] && [content length])
            [self.entries addObject:[FKChatEntry assistant:content]];
    }
    [self.tableView reloadData];
    [self scrollToBottom];
}

- (void)refreshHeader {
    FKAgent *agent = [FKAgent sharedAgent];
    NSDictionary *provider = [FKAgent providerWithIdentifier:agent.provider];
    NSString *providerName = provider[@"name"] ?: @"Custom";
    [self.modelButton setTitle:[NSString stringWithFormat:@"%@ · %@  ⌄", providerName, agent.model ?: @"?"]
                      forState:UIControlStateNormal];
    NSDictionary *usage = agent.lastUsage;
    if ([usage[@"total_tokens"] respondsToSelector:@selector(integerValue)])
        self.usageLabel.text = [NSString stringWithFormat:@"%@ tok", usage[@"total_tokens"]];
    else
        self.usageLabel.text = agent.allowMutations ? @"mutations on" : @"read-only";
}

- (void)updateEmptyState {
    self.emptyState.hidden = self.entries.count > 0;
}

- (void)scrollToBottom {
    if (!self.entries.count) return;
    [self.tableView layoutIfNeeded];
    NSInteger row = (NSInteger)self.entries.count - 1;
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}

- (void)appendEntry:(FKChatEntry *)entry {
    [self.entries addObject:entry];
    [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)self.entries.count - 1 inSection:0]]
                          withRowAnimation:UITableViewRowAnimationFade];
    [self updateEmptyState];
    [self scrollToBottom];
}

#pragma mark Actions

- (void)send {
    NSString *text = [self.inputView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || self.running) return;
    self.inputView.text = @"";
    [self textViewDidChange:self.inputView];
    self.running = YES;
    self.sendButton.hidden = YES;
    self.stopButton.hidden = NO;
    [self appendEntry:[FKChatEntry user:text]];
    [self appendEntry:[FKChatEntry system:@"thinking…"]];

    __weak typeof(self) weakSelf = self;
    [FKAgent sharedAgent].eventHandler = ^(NSDictionary *event) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *type = event[@"type"];
        if ([type isEqualToString:@"tool_start"]) {
            [self.entries addObject:[FKChatEntry tool:event[@"tool"] arguments:event[@"arguments"]]];
            [self.tableView reloadData];
            [self scrollToBottom];
        } else if ([type isEqualToString:@"tool_end"]) {
            for (FKChatEntry *entry in [self.entries reverseObjectEnumerator]) {
                if (entry.kind == FKChatKindTool && entry.toolPending && [entry.toolName isEqualToString:event[@"tool"]]) {
                    entry.toolPending = NO;
                    entry.toolOK = [event[@"ok"] boolValue];
                    NSDictionary *result = event[@"result"];
                    NSString *summary = result[@"output"] ?: result[@"error"] ?: result[@"answer"] ?: FKJSONString(result, NO);
                    if (summary.length > 160) summary = [[summary substringToIndex:160] stringByAppendingString:@"…"];
                    entry.toolDetail = summary;
                    entry.toolResult = result;
                    break;
                }
            }
            [self.tableView reloadData];
        }
    };

    [[FKAgent sharedAgent] runPrompt:text completion:^(NSString *answer, NSArray<NSDictionary *> *activity, NSError *error) {
        [FKAgent sharedAgent].eventHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.running = NO;
            self.sendButton.hidden = NO;
            self.stopButton.hidden = YES;
            // Drop the thinking placeholder (collect first; never mutate while enumerating).
            FKChatEntry *thinking = nil;
            for (FKChatEntry *entry in [self.entries reverseObjectEnumerator]) {
                if (entry.kind == FKChatKindSystem && [entry.text isEqualToString:@"thinking…"]) {
                    thinking = entry;
                    break;
                }
            }
            if (thinking) [self.entries removeObject:thinking];
            if (error) {
                [self appendEntry:[FKChatEntry system:error.localizedDescription ?: @"request failed"]];
            } else {
                [self appendEntry:[FKChatEntry assistant:answer ?: @"(no content)"]];
            }
            [self.tableView reloadData];
            [self scrollToBottom];
            [self refreshHeader];
        });
    }];
}

- (void)stop {
    [[FKAgent sharedAgent] stop];
    [self appendEntry:[FKChatEntry system:@"stopped"]];
}

- (void)showPresets {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Quick tasks" message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *prompts = @[@"Inspect this app: bundle identity, entitlements, container contents and top-level classes. Suggest three useful modifications.",
                         @"Build a tweak for this app. Ask what behaviour to change if unclear, then call devkit_build with complete source and a filter for this bundle id.",
                         @"Find values worth patching in the runtime, show current values, and propose the smallest safe change."];
    NSArray *titles = @[@"Inspect app", @"Build tweak", @"Find a patch"];
    for (NSUInteger i = 0; i < prompts.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.inputView.text = prompts[i];
            [self textViewDidChange:self.inputView];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.presetButton;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)suggestionTapped:(UIButton *)sender {
    NSArray *prompts = @[@"Inspect this app and suggest three tweaks",
                         @"Build a tweak that removes ads",
                         @"Find a value I can patch safely"];
    NSInteger index = sender.tag - 500;
    if (index < 0 || index >= (NSInteger)prompts.count) return;
    self.inputView.text = prompts[(NSUInteger)index];
    [self textViewDidChange:self.inputView];
    [self.inputView becomeFirstResponder];
}

- (void)newConversation {
    [[FKAgent sharedAgent] resetConversation];
    [self.entries removeAllObjects];
    [self.tableView reloadData];
    [self updateEmptyState];
    [self refreshHeader];
}

- (void)openSettings {
    [self.navigationController pushViewController:[[FKAgentSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
                                         animated:YES];
}

#pragma mark Keyboard

- (void)keyboardChanged:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - converted.origin.y);
    self.composerBottom.constant = -MAX(0, overlap - self.view.safeAreaInsets.bottom);
    [UIView animateWithDuration:0.2 animations:^{ [self.view layoutIfNeeded]; }];
    [self scrollToBottom];
}

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholder.hidden = textView.text.length > 0;
    CGFloat width = MAX(80, textView.bounds.size.width);
    CGSize size = [textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat height = MAX(36, MIN(120, ceil(size.height)));
    if (fabs(height - self.inputHeight.constant) > 0.5) {
        self.inputHeight.constant = height;
        textView.scrollEnabled = height >= 120;
        [self.view layoutIfNeeded];
    }
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    FKChatEntry *entry = self.entries[(NSUInteger)indexPath.row];
    if (entry.kind == FKChatKindTool) {
        FKChatToolCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tool" forIndexPath:indexPath];
        [cell configureWithEntry:entry];
        return cell;
    }
    if (entry.kind == FKChatKindSystem) {
        FKChatSystemCell *cell = [tableView dequeueReusableCellWithIdentifier:@"system" forIndexPath:indexPath];
        [cell configureText:entry.text];
        return cell;
    }
    FKChatBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
    [cell configureWithEntry:entry];
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    FKChatEntry *entry = self.entries[(NSUInteger)indexPath.row];
    if (!entry.text.length) return nil;
    UIContextualAction *copy = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                       title:@"Copy"
                                                                     handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [UIPasteboard generalPasteboard].string = entry.text;
        UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
        completion(YES);
    }];
    copy.backgroundColor = [UIColor systemGrayColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[copy]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FKChatEntry *entry = self.entries[(NSUInteger)indexPath.row];
    if (entry.kind != FKChatKindTool || !entry.toolResult.count) return;
    FKListViewController *detail = [FKListViewController listWithTitle:entry.toolName
        sections:@[ @{ @"title": entry.toolOK ? @"Result" : @"Error",
                       @"rows": @[ @{ @"title": @"JSON",
                                      @"subtitle": [FKJSONString(entry.toolResult, YES) substringToIndex:
                                                    MIN((NSUInteger)4000, FKJSONString(entry.toolResult, YES).length)] } ] } ]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
