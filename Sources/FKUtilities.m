//
//  FKUtilities.m — FLEX, Frida gadget and WebKit inspector integration
//
//  The three helpers are loaded at runtime instead of being linked:
//    • AllFLEXing.dylib / libFLEX.dylib — in-app explorer (FLEXManager)
//    • frida-gadget — dynamic instrumentation (config-driven listener)
//    • WebKit inspector — implemented natively here (same technique as
//      WebInspectEnabler: force `inspectable` on WKWebView before loads)
//
//  A jailed app can only dlopen images that are signed into its bundle, so the
//  search path order is: Frameworks/, bundle root, Documents/ForgeKit/dylibs,
//  /usr/lib, /var/jb/usr/lib.
//

#import "FKUtilities.h"
#import "FKToolsPrivate.h"
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>

static NSInteger gWebViewsInspectable = 0;
static BOOL gWebInspectorInstalled = NO;

#pragma mark - Discovery

static NSArray<NSString *> *FKUtilitySearchDirectories(void) {
    NSMutableArray *directories = [NSMutableArray array];
    NSString *bundle = FKBundlePath();
    [directories addObject:[bundle stringByAppendingPathComponent:@"Frameworks"]];
    [directories addObject:bundle];
    [directories addObject:[FKDocumentsPath() stringByAppendingPathComponent:@"ForgeKit/dylibs"]];
    [directories addObject:@"/usr/lib"];
    [directories addObject:@"/var/jb/usr/lib"];
    return directories;
}

static NSArray<NSString *> *FKUtilitySearchPaths(NSArray<NSString *> *names) {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *directory in FKUtilitySearchDirectories()) {
        for (NSString *name in names) [paths addObject:[directory stringByAppendingPathComponent:name]];
    }
    return paths;
}

static NSString *FKUtilityFirstExisting(NSArray<NSString *> *names) {
    for (NSString *path in FKUtilitySearchPaths(names)) {
        if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) return path;
    }
    return nil;
}

static NSDictionary *FKUtilityWriteJSON(NSDictionary *json, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) return @{ @"path": path, @"ok": @NO, @"error": error.localizedDescription ?: @"encode failed" };
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    return @{ @"path": path, @"ok": @(ok),
              @"error": ok ? [NSNull null] : (error.localizedDescription ?: @"write failed") };
}

#pragma mark - Web inspector

static void FKMakeWebViewInspectable(WKWebView *webView) {
    if (![FKPrefs boolForKey:@"webInspector" defaultValue:NO]) return;
    if (!webView) return;
    if (@available(iOS 16.4, *)) {
        if ([webView respondsToSelector:@selector(setInspectable:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(webView, @selector(setInspectable:), YES);
            gWebViewsInspectable++;
            return;
        }
    }
    // Pre-16.4 fallback: private WebKit preferences toggle. Best effort.
    @try {
        id preferences = [webView valueForKeyPath:@"configuration.preferences"];
        SEL selector = NSSelectorFromString(@"_setDeveloperExtrasEnabled:");
        if ([preferences respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(preferences, selector, YES);
            gWebViewsInspectable++;
        }
    } @catch (NSException *exception) {
        FKLog(@"webinspector: %@", exception.reason ?: @"preference toggle failed");
    }
}

@interface WKWebView (FKForgeKit)
@end

@implementation WKWebView (FKForgeKit)

- (WKNavigation *)fk_loadRequest:(NSURLRequest *)request {
    FKMakeWebViewInspectable(self);
    return [self fk_loadRequest:request];
}

- (WKNavigation *)fk_loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    FKMakeWebViewInspectable(self);
    return [self fk_loadHTMLString:string baseURL:baseURL];
}

- (WKNavigation *)fk_loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL {
    FKMakeWebViewInspectable(self);
    return [self fk_loadFileURL:URL allowingReadAccessToURL:readAccessURL];
}

@end

#pragma mark - Utilities

@interface FKUtilities ()
+ (NSDictionary *)flexStatusInternal;
+ (void)visitWebViews:(UIView *)view;
@end

@implementation FKUtilities

+ (void)installWebInspectorSwizzle {
    if (gWebInspectorInstalled) return;
    Class webViewClass = NSClassFromString(@"WKWebView");
    if (!webViewClass) {
        FKLog(@"webinspector: WKWebView not present yet");
        return;
    }
    FKSwizzleInstance(webViewClass, @selector(loadRequest:), @selector(fk_loadRequest:));
    FKSwizzleInstance(webViewClass, @selector(loadHTMLString:baseURL:), @selector(fk_loadHTMLString:baseURL:));
    FKSwizzleInstance(webViewClass, @selector(loadFileURL:allowingReadAccessToURL:),
                      @selector(fk_loadFileURL:allowingReadAccessToURL:));
    gWebInspectorInstalled = YES;
    FKLog(@"webinspector: WKWebView load swizzles installed");
}

+ (NSDictionary *)webInspectorStatus {
    BOOL supported = NO;
    if (@available(iOS 16.4, *)) {
        supported = [NSClassFromString(@"WKWebView") instancesRespondToSelector:@selector(setInspectable:)];
    }
    return @{ @"enabled": @([FKPrefs boolForKey:@"webInspector" defaultValue:NO]),
              @"swizzle_installed": @(gWebInspectorInstalled),
              @"public_api": @(supported),
              @"inspected_count": @(gWebViewsInspectable),
              @"note": supported ? @"WKWebView.inspectable" : @"private _setDeveloperExtrasEnabled fallback" };
}

+ (void)setWebInspectorEnabled:(BOOL)enabled {
    [FKPrefs setBool:enabled forKey:@"webInspector"];
    [self installWebInspectorSwizzle];
    if (enabled) [self applyWebInspectorToOpenWebViews];
    FKLog(@"webinspector: %@", enabled ? @"enabled" : @"disabled");
}

+ (void)applyWebInspectorToOpenWebViews {
    FKRunOnMain(^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) [self visitWebViews:window];
        }
    });
}

+ (void)visitWebViews:(UIView *)view {
    if ([view isKindOfClass:[WKWebView class]]) FKMakeWebViewInspectable((WKWebView *)view);
    for (UIView *child in view.subviews) [self visitWebViews:child];
}

#pragma mark FLEX

+ (NSDictionary *)flexStatusInternal {
    Class managerClass = NSClassFromString(@"FLEXManager");
    NSString *path = FKUtilityFirstExisting(@[@"AllFLEXing.dylib", @"libFLEX.dylib", @"FLEX.dylib"]);
    NSMutableDictionary *status = [@{ @"class_found": @(managerClass != nil),
                                      @"search_path": path ?: [NSNull null],
                                      @"loaded": @(managerClass != nil) } mutableCopy];
    if (managerClass) {
        __block BOOL hidden = YES;
        FKRunOnMain(^{
            id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedManager));
            SEL selector = NSSelectorFromString(@"isHidden");
            if ([manager respondsToSelector:selector])
                hidden = ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector);
        });
        status[@"hidden"] = @(hidden);
    }
    return status;
}

+ (NSDictionary *)showFLEX {
    Class managerClass = NSClassFromString(@"FLEXManager");
    if (!managerClass) return @{ @"ok": @NO, @"error": @"FLEXManager not loaded" };
    __block BOOL shown = NO;
    FKRunOnMain(^{
        id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedManager));
        SEL selector = NSSelectorFromString(@"showExplorer");
        if ([manager respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(manager, selector);
            shown = YES;
        }
    });
    return @{ @"ok": @(shown), @"shown": @(shown),
              @"error": shown ? [NSNull null] : @"showExplorer unavailable" };
}

+ (NSDictionary *)hideFLEX {
    Class managerClass = NSClassFromString(@"FLEXManager");
    if (!managerClass) return @{ @"ok": @NO, @"error": @"FLEXManager not loaded" };
    FKRunOnMain(^{
        id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedManager));
        SEL selector = NSSelectorFromString(@"hideExplorer");
        if ([manager respondsToSelector:selector])
            ((void (*)(id, SEL))objc_msgSend)(manager, selector);
    });
    return @{ @"ok": @YES };
}

+ (NSDictionary *)loadFLEXAtPath:(NSString *)path show:(BOOL)show {
    NSString *resolved = path.length ? FKExpandPath(path)
                                     : FKUtilityFirstExisting(@[@"AllFLEXing.dylib", @"libFLEX.dylib", @"FLEX.dylib"]);
    if (!resolved) {
        return @{ @"ok": @NO, @"error": @"FLEX dylib not found",
                  @"searched": FKUtilitySearchPaths(@[@"AllFLEXing.dylib", @"libFLEX.dylib", @"FLEX.dylib"]) };
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:resolved])
        return @{ @"ok": @NO, @"error": @"FLEX dylib is not readable", @"path": resolved };
    void *handle = dlopen(resolved.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *error = dlerror();
        return @{ @"ok": @NO, @"path": resolved,
                  @"error": error ? [NSString stringWithUTF8String:error] : @"dlopen failed" };
    }
    Class managerClass = NSClassFromString(@"FLEXManager");
    NSDictionary *shown = nil;
    if (show && managerClass) shown = [self showFLEX];
    FKLog(@"FLEX loaded from %@ (class=%@)", resolved, managerClass ? @"yes" : @"no");
    return @{ @"ok": @YES, @"path": resolved,
              @"handle": [NSString stringWithFormat:@"%p", handle],
              @"class_found": @(managerClass != nil),
              @"shown": shown ?: @{ @"ok": @NO, @"error": @"not requested" } };
}

#pragma mark Frida

+ (NSDictionary *)defaultFridaConfig {
    return @{
        @"interaction": @{ @"type": @"listen", @"address": @"127.0.0.1",
                           @"port": @27042, @"on_load": @"resume" },
        @"runtime": @"qjs",
        @"code_signing": @"required",
    };
}

+ (NSDictionary *)writeFridaConfig:(NSDictionary *)config {
    NSDictionary *payload = config.count ? config : [self defaultFridaConfig];
    NSMutableArray *written = [NSMutableArray array];
    NSMutableArray *paths = [NSMutableArray array];
    [paths addObject:[FKDocumentsPath() stringByAppendingPathComponent:@"FridaGadget.config"]];
    NSString *gadget = FKUtilityFirstExisting(@[@"FridaGadget.dylib", @"frida-gadget.dylib",
                                                @"libFridaGadget.dylib",
                                                @"frida-gadget-17.24.3-ios-universal.dylib"]);
    // Never write inside the app bundle: that breaks the code signature seal.
    if (gadget && [gadget hasPrefix:FKDocumentsPath()])
        [paths addObject:[[gadget stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent:@"FridaGadget.config"]];
    for (NSString *path in paths) {
        if (![[NSFileManager defaultManager] isWritableFileAtPath:[path stringByDeletingLastPathComponent]]) continue;
        [written addObject:FKUtilityWriteJSON(payload, path)];
    }
    return @{ @"ok": @(written.count > 0), @"candidates": paths, @"written": written,
              @"config": payload };
}

+ (NSDictionary *)loadFridaGadgetAtPath:(NSString *)path config:(NSDictionary *)config {
    NSString *resolved = path.length ? FKExpandPath(path)
                                     : FKUtilityFirstExisting(@[@"FridaGadget.dylib", @"frida-gadget.dylib",
                                                                @"libFridaGadget.dylib",
                                                                @"frida-gadget-17.24.3-ios-universal.dylib"]);
    if (!resolved) {
        return @{ @"ok": @NO, @"error": @"Frida gadget dylib not found",
                  @"searched": FKUtilitySearchPaths(@[@"FridaGadget.dylib", @"frida-gadget.dylib",
                                                      @"libFridaGadget.dylib",
                                                      @"frida-gadget-17.24.3-ios-universal.dylib"]) };
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:resolved])
        return @{ @"ok": @NO, @"error": @"gadget is not readable", @"path": resolved };
    NSDictionary *configResult = [self writeFridaConfig:config ?: [self defaultFridaConfig]];
    void *handle = dlopen(resolved.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *error = dlerror();
        return @{ @"ok": @NO, @"path": resolved, @"config": configResult,
                  @"error": error ? [NSString stringWithUTF8String:error] : @"dlopen failed" };
    }
    FKLog(@"Frida gadget loaded from %@", resolved);
    return @{ @"ok": @YES, @"path": resolved,
              @"handle": [NSString stringWithFormat:@"%p", handle],
              @"config": configResult,
              @"status": [self fridaStatus] };
}

+ (NSDictionary *)fridaStatus {
    NSMutableArray *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name] ?: @"";
        if ([path.lowercaseString rangeOfString:@"frida"].location != NSNotFound) [images addObject:path];
    }
    NSMutableArray *configs = [NSMutableArray array];
    NSArray *configPaths = @[
        [FKDocumentsPath() stringByAppendingPathComponent:@"FridaGadget.config"],
        [FKBundlePath() stringByAppendingPathComponent:@"FridaGadget.config"],
    ];
    for (NSString *path in configPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] ?: [NSData data]
                                                                options:0 error:nil];
            [configs addObject:@{ @"path": path, @"config": json ?: @{} }];
        }
    }
    return @{ @"loaded": @(images.count > 0), @"images": images, @"configs": configs,
              @"gadget": FKUtilityFirstExisting(@[@"FridaGadget.dylib", @"frida-gadget.dylib",
                                                  @"libFridaGadget.dylib",
                                                  @"frida-gadget-17.24.3-ios-universal.dylib"]) ?: [NSNull null] };
}

#pragma mark Status

+ (NSDictionary *)status {
    return @{ @"web_inspector": [self webInspectorStatus],
              @"flex": [self flexStatusInternal],
              @"frida": [self fridaStatus] };
}

+ (NSArray<NSDictionary *> *)discoveredLibraries {
    NSMutableArray *found = [NSMutableArray array];
    NSDictionary *groups = @{
        @"flex": @[@"AllFLEXing.dylib", @"libFLEX.dylib", @"FLEX.dylib"],
        @"frida": @[@"FridaGadget.dylib", @"frida-gadget.dylib", @"libFridaGadget.dylib",
                    @"frida-gadget-17.24.3-ios-universal.dylib"],
    };
    for (NSString *role in groups) {
        for (NSString *path in FKUtilitySearchPaths(groups[role])) {
            if ([[NSFileManager defaultManager] isReadableFileAtPath:path]) {
                [found addObject:@{ @"role": role, @"path": path }];
                break;
            }
        }
    }
    return found;
}

@end

#pragma mark - Tools

@implementation FKUtilityTools

+ (NSArray<NSDictionary *> *)definitions {
    NSDictionary *(^str)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"string", @"description": description };
    };
    return @[
        @{ @"name": @"utilities_status", @"description":
               @"Status of bundled utilities: FLEX, Frida gadget, WebKit inspector.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"web_inspector", @"description":
               @"Enable or disable WebKit remote inspection for WKWebView instances (iOS 16.4+ public API, private fallback below).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"enabled": @{ @"type": @"boolean", @"description": @"Target state; omit to read." },
                                                @"apply": @{ @"type": @"boolean", @"description": @"Also apply to already-open web views." } },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"flex", @"description":
               @"Load and control the FLEX/AllFLEXing in-app explorer. action = status | load | show | hide.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"action": @{ @"type": @"string", @"enum": @[@"status", @"load", @"show", @"hide"] },
                                                @"path": str(@"Optional dylib path.") },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"frida", @"description":
               @"Load and inspect the Frida gadget. action = status | load | config.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"action": @{ @"type": @"string", @"enum": @[@"status", @"load", @"config"] },
                                                @"path": str(@"Optional gadget dylib path."),
                                                @"config": @{ @"type": @"object", @"description": @"FridaGadget.config contents; omit for listen 127.0.0.1:27042." } },
                              @"required": @[], @"additionalProperties": @NO } },
    ];
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    if ([name isEqualToString:@"utilities_status"]) {
        NSMutableDictionary *status = [[FKUtilities status] mutableCopy];
        status[@"ok"] = @YES;
        status[@"discovered"] = [FKUtilities discoveredLibraries];
        return status;
    }
    if ([name isEqualToString:@"web_inspector"]) {
        if ([args[@"enabled"] respondsToSelector:@selector(boolValue)]) {
            [FKUtilities setWebInspectorEnabled:[args[@"enabled"] boolValue]];
            if ([args[@"apply"] boolValue]) [FKUtilities applyWebInspectorToOpenWebViews];
        }
        return @{ @"ok": @YES, @"status": [FKUtilities webInspectorStatus] };
    }
    if ([name isEqualToString:@"flex"]) {
        NSString *action = args[@"action"] ?: @"status";
        if ([action isEqualToString:@"load"]) return [FKUtilities loadFLEXAtPath:args[@"path"] show:YES];
        if ([action isEqualToString:@"show"]) return [FKUtilities showFLEX];
        if ([action isEqualToString:@"hide"]) return [FKUtilities hideFLEX];
        return @{ @"ok": @YES, @"status": [FKUtilities status][@"flex"] };
    }
    if ([name isEqualToString:@"frida"]) {
        NSString *action = args[@"action"] ?: @"status";
        if ([action isEqualToString:@"load"])
            return [FKUtilities loadFridaGadgetAtPath:args[@"path"] config:args[@"config"]];
        if ([action isEqualToString:@"config"])
            return [FKUtilities writeFridaConfig:args[@"config"] ?: @{}];
        return @{ @"ok": @YES, @"status": [FKUtilities fridaStatus] };
    }
    return nil;
}

@end
