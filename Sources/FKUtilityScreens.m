//
//  FKUtilityScreens.m — native runtime utilities (WebKit inspector, heap, traffic, hooks)
//

#import "ForgeKit.h"
#import "FKPanelScreens.h"
#import "FKUtilities.h"
#import "FKRuntimeKit.h"
#import <stdlib.h>

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
    NSDictionary *web = [FKUtilities webInspectorStatus];
    NSArray *hooks = [FKRuntimeKit activeHooks];
    NSArray *modules = [FKRuntimeKit modules];

    NSMutableArray *sections = [NSMutableArray array];

    [sections addObject:@{ @"title": @"WebKit Inspector", @"rows": @[
        @{ @"title": @"Remote inspection",
           @"subtitle": web[@"note"] ?: @"",
           @"toggle": ^(BOOL on) { [FKUtilities setWebInspectorEnabled:on]; [weakSelf rebuild]; },
           @"toggleValue": web[@"enabled"] ?: @NO },
        @{ @"title": @"Apply to open web views",
           @"subtitle": @"Mark existing WKWebView instances inspectable",
           @"chevron": @YES,
           @"action": ^{ [FKUtilities applyWebInspectorToOpenWebViews]; [weakSelf rebuild]; } },
        @{ @"title": @"State",
           @"subtitle": [NSString stringWithFormat:@"%@ web views · swizzle %@ · public API %@",
                         web[@"inspected_count"] ?: @0,
                         [web[@"swizzle_installed"] boolValue] ? @"installed" : @"off",
                         [web[@"public_api"] boolValue] ? @"yes" : @"fallback"] },
    ] }];

    [sections addObject:@{ @"title": @"Runtime", @"rows": @[
        @{ @"title": @"Traffic capture",
           @"subtitle": @"Record NSURLSession requests, responses and previews",
           @"toggle": ^(BOOL on) {
               [FKPrefs setBool:on forKey:@"netCapture"];
               [weakSelf rebuild];
           },
           @"toggleValue": @([FKPrefs boolForKey:@"netCapture" defaultValue:YES]) },
        @{ @"title": @"Heap objects",
           @"subtitle": @"Enumerate live objects (all classes or one class)",
           @"chevron": @YES,
           @"action": ^{ [weakSelf promptHeap]; } },
        @{ @"title": @"Network traffic",
           @"subtitle": @"Captured requests and responses",
           @"chevron": @YES,
           @"action": ^{ [weakSelf showTraffic]; } },
        @{ @"title": @"Function hooks",
           @"subtitle": [NSString stringWithFormat:@"%lu active", (unsigned long)hooks.count],
           @"chevron": @YES,
           @"action": ^{ [weakSelf showHooks]; } },
        @{ @"title": @"Loaded modules",
           @"subtitle": [NSString stringWithFormat:@"%lu Mach-O images", (unsigned long)modules.count],
           @"chevron": @YES,
           @"action": ^{ [weakSelf showModules]; } },
    ] }];

    [sections addObject:@{ @"title": @"About", @"footer":
                               @"Native implementations of FLEX's runtime explorer and Frida's "
                               @"memory/hook tools. No helper dylib is loaded.",
                           @"rows": @[
        @{ @"title": @"ObjC explorer", @"subtitle": @"Heap scan, object/ivar inspection, method invocation" },
        @{ @"title": @"Memory", @"subtitle": @"Read, write, scan, module exports" },
        @{ @"title": @"Hooks", @"subtitle": @"Restorable 16-byte inline redirect" },
    ] }];

    self.sections = sections;
    [self reloadSections];
}

#pragma mark - Actions

- (void)promptHeap {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Heap objects"
                                                                   message:@"Class name (empty = all classes)"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"UIView";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Scan" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *className = alert.textFields.firstObject.text;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *result = [FKRuntimeKit heapObjectsOfClass:className.length ? className : nil limit:200];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![result[@"ok"] boolValue]) {
                    FKPresentAlert(@"Heap scan", result[@"error"] ?: @"failed");
                    return;
                }
                NSMutableArray *rows = [NSMutableArray array];
                for (NSDictionary *object in result[@"objects"]) {
                    [rows addObject:@{ @"title": object[@"class"] ?: @"?",
                                       @"subtitle": object[@"ptr"] ?: @"",
                                       @"chevron": @YES,
                                       @"action": ^{ [self showObject:object[@"ptr"]]; } }];
                }
                if (!rows.count) [rows addObject:@{ @"title": @"No objects", @"subtitle": result[@"error"] ?: @"" }];
                FKListViewController *list = [FKListViewController listWithTitle:@"Heap"
                                                                        sections:@[ @{ @"title": [NSString stringWithFormat:@"%@ objects", result[@"count"]],
                                                                                       @"rows": rows } ]];
                [self.navigationController pushViewController:list animated:YES];
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showObject:(NSString *)pointerString {
    unsigned long long pointer = strtoull(pointerString.UTF8String, NULL, 0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *info = [FKRuntimeKit objectInfo:pointer depth:4];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![info[@"ok"] boolValue]) { FKPresentAlert(@"Object", info[@"error"] ?: @"failed"); return; }
            NSMutableArray *rows = [NSMutableArray array];
            [rows addObject:@{ @"title": @"Class", @"subtitle": info[@"class"] ?: @"" }];
            [rows addObject:@{ @"title": @"Chain", @"subtitle": [info[@"chain"] componentsJoinedByString:@" → "] }];
            [rows addObject:@{ @"title": @"Size", @"subtitle": [NSString stringWithFormat:@"%@ bytes", info[@"size"]] }];
            [rows addObject:@{ @"title": @"Description", @"subtitle": info[@"description"] ?: @"" }];
            for (NSDictionary *ivar in info[@"ivars"] ?: @[]) {
                id value = ivar[@"value"];
                NSString *text = [value isKindOfClass:[NSDictionary class]]
                    ? ([value[@"value"] description] ?: [value description])
                    : [value description];
                [rows addObject:@{ @"title": ivar[@"name"] ?: @"?",
                                   @"subtitle": [NSString stringWithFormat:@"%@ = %@", ivar[@"type"] ?: @"?", text ?: @""] }];
            }
            FKListViewController *list = [FKListViewController listWithTitle:pointerString
                                                                    sections:@[ @{ @"title": @"Object", @"rows": rows } ]];
            [self.navigationController pushViewController:list animated:YES];
        });
    });
}

- (void)showTraffic {
    NSDictionary *history = [FKRuntimeKit networkHistory:200];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *record in history[@"records"] ?: @[]) {
        NSString *subtitle = [NSString stringWithFormat:@"%@ %@ · %@ · %@ ms",
                              record[@"method"] ?: @"?", record[@"status"] ?: @"—",
                              record[@"bytes"] ?: @0, record[@"duration_ms"] ?: @0];
        [rows addObject:@{ @"title": record[@"url"] ?: @"?",
                           @"subtitle": subtitle,
                           @"chevron": @YES,
                           @"action": ^{
                               FKListViewController *detail = [FKListViewController listWithTitle:@"Request"
                                   sections:@[ @{ @"title": @"Record", @"rows": @[
                                       @{ @"title": @"URL", @"subtitle": record[@"url"] ?: @"" },
                                       @{ @"title": @"Status", @"subtitle": [NSString stringWithFormat:@"%@", record[@"status"] ?: @"—"] },
                                       @{ @"title": @"Request headers", @"subtitle": FKJSONString(record[@"request_headers"] ?: @{}, YES) },
                                       @{ @"title": @"Response headers", @"subtitle": FKJSONString(record[@"response_headers"] ?: @{}, YES) },
                                       @{ @"title": @"Preview", @"subtitle": record[@"preview"] ?: @"" },
                                   ] } ]];
                               [self.navigationController pushViewController:detail animated:YES];
                           } }];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No traffic recorded", @"subtitle": @"Capture is enabled by default" }];
    FKListViewController *list = [FKListViewController listWithTitle:@"Traffic"
                                                            sections:@[ @{ @"title": [NSString stringWithFormat:@"%@ requests", history[@"total"] ?: @0],
                                                                           @"rows": rows } ]];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)showHooks {
    NSArray *hooks = [FKRuntimeKit activeHooks];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *hook in hooks) {
        [rows addObject:@{ @"title": hook[@"source"] ?: @"?",
                           @"subtitle": [NSString stringWithFormat:@"→ %@ · %@", hook[@"destination"] ?: @"?", hook[@"address"] ?: @""],
                           @"destructive": @YES,
                           @"action": ^{
                               [FKRuntimeKit restoreSymbol:hook[@"source"] ?: @""];
                               [self rebuild];
                           } }];
    }
    if (!rows.count) [rows addObject:@{ @"title": @"No active hooks", @"subtitle": @"Use hook_redirect over MCP" }];
    FKListViewController *list = [FKListViewController listWithTitle:@"Hooks"
                                                            sections:@[ @{ @"title": @"Active", @"rows": rows } ]];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)showModules {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *module in [FKRuntimeKit modules]) {
        [rows addObject:@{ @"title": module[@"name"] ?: @"?",
                           @"subtitle": [NSString stringWithFormat:@"%@ · %@ bytes · slide %@",
                                         module[@"base"] ?: @"", module[@"size"] ?: @0, module[@"slide"] ?: @""] }];
    }
    FKListViewController *list = [FKListViewController listWithTitle:@"Modules"
                                                            sections:@[ @{ @"title": @"Mach-O images", @"rows": rows } ]];
    [self.navigationController pushViewController:list animated:YES];
}

@end
