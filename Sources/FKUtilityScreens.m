//
//  FKUtilityScreens.m — Utilities screen: WebKit inspector, FLEX, Frida
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKUtilities.h"

@implementation FKUtilitiesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.screenTitle = @"Utilities";
    self.title = @"Utilities";
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)rebuild {
    __weak typeof(self) weakSelf = self;
    NSDictionary *status = [FKUtilities status];
    NSDictionary *web = status[@"web_inspector"] ?: @{};
    NSDictionary *flex = status[@"flex"] ?: @{};
    NSDictionary *frida = status[@"frida"] ?: @{};

    NSMutableArray *sections = [NSMutableArray array];

    // WebKit inspector
    [sections addObject:@{ @"title": @"WebKit Inspector", @"rows": @[
        @{ @"title": @"Remote inspection",
           @"subtitle": web[@"note"] ?: @"",
           @"toggle": ^(BOOL on) {
               [FKUtilities setWebInspectorEnabled:on];
               [weakSelf rebuild];
           },
           @"toggleValue": web[@"enabled"] ?: @NO },
        @{ @"title": @"Apply to open web views",
           @"subtitle": @"Mark existing WKWebView instances inspectable",
           @"chevron": @YES,
           @"action": ^{
               [FKUtilities applyWebInspectorToOpenWebViews];
               [weakSelf rebuild];
           } },
        @{ @"title": @"State",
           @"subtitle": [NSString stringWithFormat:@"%@ web views · swizzle %@ · public API %@",
                         web[@"inspected_count"] ?: @0,
                         [web[@"swizzle_installed"] boolValue] ? @"installed" : @"off",
                         [web[@"public_api"] boolValue] ? @"yes" : @"fallback"] },
    ] }];

    // FLEX
    NSString *flexPath = [flex[@"search_path"] isKindOfClass:[NSString class]] ? flex[@"search_path"] : @"not found";
    NSString *loaderPath = [flex[@"loader_path"] isKindOfClass:[NSString class]] ? flex[@"loader_path"] : @"not found";
    BOOL loaderLoaded = [flex[@"loader_loaded"] boolValue];
    BOOL substrate = [flex[@"substrate"] boolValue];
    NSString *loaderDetail = loaderLoaded ? @"loaded (FLEXing gesture active)"
                            : (![loaderPath isEqualToString:@"not found"]
                               ? (substrate ? @"present, not loaded" : @"needs libsubstrate — using built-in gesture")
                               : @"not installed");
    [sections addObject:@{ @"title": @"FLEX", @"rows": @[
        @{ @"title": @"FLEXManager",
           @"subtitle": [flex[@"class_found"] boolValue] ? @"loaded" : @"not loaded" },
        @{ @"title": @"Core library", @"subtitle": flexPath },
        @{ @"title": @"Loader (FLEXing)", @"subtitle": [NSString stringWithFormat:@"%@\n%@", loaderPath, loaderDetail] },
        @{ @"title": @"Two-finger long press", @"subtitle": @"Open FLEX from anywhere (built-in; used when FLEXing cannot load)",
           @"toggle": ^(BOOL on) {
               [FKPrefs setBool:on forKey:@"flexGesture"];
               if (on) [FKUtilities installFLEXGesture];
           },
           @"toggleValue": @([FKPrefs boolForKey:@"flexGesture" defaultValue:YES]) },
        @{ @"title": @"Load and show explorer",
           @"subtitle": @"libFLEX.dylib + FLEXing.dylib from Frameworks or Documents",
           @"chevron": @YES,
           @"action": ^{
               NSDictionary *result = [FKUtilities loadFLEXAtPath:nil show:YES];
               FKPresentAlert(@"FLEX", [result[@"ok"] boolValue] ? @"Explorer presented."
                               : (result[@"error"] ?: @"failed to load"));
               [weakSelf rebuild];
           } },
        @{ @"title": @"Hide explorer", @"chevron": @YES,
           @"action": ^{ [FKUtilities hideFLEX]; [weakSelf rebuild]; } },
    ] }];

    // Frida
    NSArray *images = [frida[@"images"] isKindOfClass:[NSArray class]] ? frida[@"images"] : @[];
    NSString *gadgetPath = [frida[@"gadget"] isKindOfClass:[NSString class]] ? frida[@"gadget"] : @"not found";
    NSArray *configs = [frida[@"configs"] isKindOfClass:[NSArray class]] ? frida[@"configs"] : @[];
    NSString *configPath = configs.count ? configs.firstObject[@"path"] : @"not written";
    [sections addObject:@{ @"title": @"Frida", @"rows": @[
        @{ @"title": @"Gadget", @"subtitle": [frida[@"loaded"] boolValue]
               ? [NSString stringWithFormat:@"loaded (%lu images)", (unsigned long)images.count]
               : @"not loaded" },
        @{ @"title": @"Library", @"subtitle": gadgetPath },
        @{ @"title": @"Config", @"subtitle": configPath },
        @{ @"title": @"Load gadget",
           @"subtitle": @"Starts the Frida listener using FridaGadget.config",
           @"chevron": @YES,
           @"action": ^{
               NSDictionary *result = [FKUtilities loadFridaGadgetAtPath:nil config:nil];
               FKPresentAlert(@"Frida", [result[@"ok"] boolValue]
                               ? [NSString stringWithFormat:@"Loaded %@\nConfig: %@", result[@"path"],
                                  ([result[@"config"][@"written"] firstObject] ?: @{})[@"path"] ?: @"—"]
                               : (result[@"error"] ?: @"failed to load"));
               [weakSelf rebuild];
           } },
        @{ @"title": @"Write default config",
           @"subtitle": @"listen 127.0.0.1:27042 · resume",
           @"chevron": @YES,
           @"action": ^{
               NSDictionary *result = [FKUtilities writeFridaConfig:@{}];
               NSArray *written = result[@"written"];
               NSMutableArray *paths = [NSMutableArray array];
               for (NSDictionary *entry in written) if (entry[@"ok"]) [paths addObject:entry[@"path"]];
               FKPresentAlert(@"Frida config", paths.count ? [paths componentsJoinedByString:@"\n"]
                                                           : @"No writable location found.");
               [weakSelf rebuild];
           } },
    ] }];

    // Discovered libraries
    NSArray *discovered = [FKUtilities discoveredLibraries];
    if (discovered.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *entry in discovered) {
            [rows addObject:@{ @"title": entry[@"role"], @"subtitle": entry[@"path"],
                               @"chevron": @YES,
                               @"action": ^{
                                   [UIPasteboard generalPasteboard].string = entry[@"path"];
                                   FKPresentAlert(@"Path copied", entry[@"path"]);
                               } }];
        }
        [sections addObject:@{ @"title": @"Discovered", @"footer":
                                   @"Place helper dylibs in Frameworks/ or Documents/ForgeKit/dylibs. "
                                   @"They must be signed with the app to load on a jailed device.",
                               @"rows": rows }];
    }

    self.sections = sections;
    [self reloadSections];
}

@end
