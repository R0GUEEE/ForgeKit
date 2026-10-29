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
#import "FKRuntimeKit.h"
#import "FKToolsPrivate.h"
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

static Class FKWebViewClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY);
        cls = NSClassFromString(@"WKWebView");
    });
    return cls;
}

static void FKMakeWebViewInspectable(id webView) {
    if (!webView) return;
    if (![FKPrefs boolForKey:@"webInspector" defaultValue:NO]) return;
    Class webViewClass = FKWebViewClass();
    if (webViewClass && ![webView isKindOfClass:webViewClass]) return;
    if (@available(iOS 16.4, *)) {
        SEL setter = NSSelectorFromString(@"setInspectable:");
        if ([webView respondsToSelector:setter]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(webView, setter, YES);
            gWebViewsInspectable++;
            return;
        }
    }
    // Pre-16.4 fallback: private WebKit preferences toggle. Best effort.
    @try {
        id preferences = [webView valueForKeyPath:@"configuration.preferences"];
        SEL selector = NSSelectorFromString(@"_setDeveloperExtrasEnabled:");
        if (preferences && [preferences respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(preferences, selector, YES);
            gWebViewsInspectable++;
        }
    } @catch (NSException *exception) {
        FKLog(@"webinspector: %@", exception.reason ?: @"preference toggle failed");
    }
}

// The WKWebView class is resolved at runtime, so these IMPs use id and the
// Objective-C message ABI instead of a compile-time WKWebView type.
static void FKWebViewLoadRequest(id self, SEL _cmd, id request) {
    FKMakeWebViewInspectable(self);
    ((id (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"fk_loadRequest:"), request);
}

static void FKWebViewLoadHTML(id self, SEL _cmd, id string, id baseURL) {
    FKMakeWebViewInspectable(self);
    ((id (*)(id, SEL, id, id))objc_msgSend)(self, NSSelectorFromString(@"fk_loadHTMLString:baseURL:"), string, baseURL);
}

static void FKWebViewLoadFile(id self, SEL _cmd, id URL, id accessURL) {
    FKMakeWebViewInspectable(self);
    ((id (*)(id, SEL, id, id))objc_msgSend)(self, NSSelectorFromString(@"fk_loadFileURL:allowingReadAccessToURL:"), URL, accessURL);
}

static void FKSwizzleWKWebViewMethod(Class cls, SEL original, SEL replacement, IMP implementation) {
    Method method = class_getInstanceMethod(cls, original);
    if (!method) return;
    class_addMethod(cls, replacement, implementation, method_getTypeEncoding(method));
    Method added = class_getInstanceMethod(cls, replacement);
    if (added) method_exchangeImplementations(method, added);
}

#pragma mark - Utilities

@interface FKUtilities ()
+ (NSDictionary *)flexStatusInternal;
+ (void)visitWebViews:(UIView *)view;
+ (void)installFLEXGesture;
+ (void)attachFLEXGestureToWindow:(UIWindow *)window;
@end

#pragma mark - FLEX gesture

@interface FKFLEXGestureTarget : NSObject <UIGestureRecognizerDelegate>
@end

static NSHashTable<UIWindow *> *gFLEXGestureWindows = nil;
static BOOL gFLEXGestureInstalled = NO;
static BOOL gFLEXLoaderLoaded = NO;
static FKFLEXGestureTarget *gFLEXGestureTarget = nil;

@implementation FKFLEXGestureTarget
- (void)handleFLEXPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    if (![FKPrefs boolForKey:@"flexGesture" defaultValue:YES]) return;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    [FKUtilities showFLEX];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

#pragma mark FLEX

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
        Class webViewClass = FKWebViewClass();
        supported = webViewClass && [webViewClass instancesRespondToSelector:NSSelectorFromString(@"setInspectable:")];
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
    Class webViewClass = FKWebViewClass();
    if (webViewClass && [view isKindOfClass:webViewClass]) FKMakeWebViewInspectable(view);
    for (UIView *child in view.subviews) [self visitWebViews:child];
}

#pragma mark FLEX

+ (NSDictionary *)flexStatusInternal {
    Class managerClass = NSClassFromString(@"FLEXManager");
    NSString *path = FKUtilityFirstExisting(@[@"libFLEX.dylib", @"AllFLEXing.dylib", @"FLEX.dylib"]);
    NSString *loader = FKUtilityFirstExisting(@[@"FLEXing.dylib"]);
    NSMutableDictionary *status = [@{ @"class_found": @(managerClass != nil),
                                      @"search_path": path ?: [NSNull null],
                                      @"loader_path": loader ?: [NSNull null],
                                      @"loader_loaded": @(gFLEXLoaderLoaded),
                                      @"substrate": @(dlsym(RTLD_DEFAULT, "MSHookMessageEx") != NULL),
                                      @"gesture_installed": @(gFLEXGestureInstalled),
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
    NSString *core = path.length ? FKExpandPath(path)
                                 : FKUtilityFirstExisting(@[@"libFLEX.dylib", @"AllFLEXing.dylib", @"FLEX.dylib"]);
    if (!core) {
        return @{ @"ok": @NO, @"error": @"libFLEX.dylib not found",
                  @"searched": FKUtilitySearchPaths(@[@"libFLEX.dylib", @"AllFLEXing.dylib", @"FLEX.dylib"]) };
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:core])
        return @{ @"ok": @NO, @"error": @"libFLEX is not readable", @"path": core };

    void *coreHandle = dlopen(core.UTF8String, RTLD_NOW | RTLD_LOCAL);
    if (!coreHandle) {
        const char *error = dlerror();
        return @{ @"ok": @NO, @"path": core,
                  @"error": error ? [NSString stringWithUTF8String:error] : @"dlopen failed" };
    }
    Class managerClass = NSClassFromString(@"FLEXManager");

    // FLEXing adds the status-bar gesture. It needs libsubstrate; skip it cleanly
    // when the host has no hooking runtime, and provide our own gesture instead.
    NSString *loaderPath = FKUtilityFirstExisting(@[@"FLEXing.dylib"]);
    BOOL substrateAvailable = dlsym(RTLD_DEFAULT, "MSHookMessageEx") != NULL;
    NSString *loaderError = nil;
    if (loaderPath && substrateAvailable) {
        void *loaderHandle = dlopen(loaderPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (loaderHandle) {
            gFLEXLoaderLoaded = YES;
        } else {
            const char *error = dlerror();
            loaderError = error ? [NSString stringWithUTF8String:error] : @"dlopen failed";
        }
    } else if (loaderPath && !substrateAvailable) {
        loaderError = @"libsubstrate not present (jailed host); using the built-in gesture";
    }

    if (!gFLEXLoaderLoaded && [FKPrefs boolForKey:@"flexGesture" defaultValue:YES])
        [self installFLEXGesture];

    NSDictionary *shown = nil;
    if (show && managerClass) shown = [self showFLEX];
    FKLog(@"FLEX core=%@ class=%@ loader=%@", core, managerClass ? @"yes" : @"no",
          gFLEXLoaderLoaded ? @"loaded" : @"built-in gesture");

    return @{ @"ok": @(managerClass != nil), @"path": core,
              @"handle": [NSString stringWithFormat:@"%p", coreHandle],
              @"class_found": @(managerClass != nil),
              @"loader": @{ @"path": loaderPath ?: [NSNull null],
                            @"loaded": @(gFLEXLoaderLoaded),
                            @"substrate": @(substrateAvailable),
                            @"error": loaderError ?: [NSNull null] },
              @"gesture_installed": @(gFLEXGestureInstalled),
              @"shown": shown ?: @{ @"ok": @NO, @"error": @"not requested" } };
}

#pragma mark FLEX gesture install

+ (void)installFLEXGesture {
    if (gFLEXGestureInstalled) return;
    gFLEXGestureInstalled = YES;
    gFLEXGestureWindows = [NSHashTable weakObjectsHashTable];
    gFLEXGestureTarget = [[FKFLEXGestureTarget alloc] init];
    FKRunOnMain(^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:[UIWindow class]]) [self attachFLEXGestureToWindow:note.object];
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) [self attachFLEXGestureToWindow:window];
            }
        }];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) [self attachFLEXGestureToWindow:window];
        }
        FKLog(@"FLEX gesture installed (two-finger long press)");
    });
}

+ (void)attachFLEXGestureToWindow:(UIWindow *)window {
    if (!window || window.windowLevel > UIWindowLevelAlert) return;
    @synchronized(gFLEXGestureWindows) {
        if ([gFLEXGestureWindows containsObject:window]) return;
        [gFLEXGestureWindows addObject:window];
    }
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:gFLEXGestureTarget
                                                      action:@selector(handleFLEXPress:)];
    press.numberOfTouchesRequired = 2;
    press.minimumPressDuration = 0.8;
    press.allowableMovement = 24;
    press.cancelsTouchesInView = NO;
    press.delegate = gFLEXGestureTarget;
    [window addGestureRecognizer:press];
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
        @"flex": @[@"libFLEX.dylib", @"AllFLEXing.dylib", @"FLEX.dylib"],
        @"flex_loader": @[@"FLEXing.dylib"],
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
               @"Status of the native runtime toolkit and the WebKit inspector.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"web_inspector", @"description":
               @"Enable or disable WebKit remote inspection for WKWebView instances (iOS 16.4+ public API, private fallback below).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"enabled": @{ @"type": @"boolean", @"description": @"Target state; omit to read." },
                                                @"apply": @{ @"type": @"boolean", @"description": @"Also apply to already-open web views." } },
                              @"required": @[], @"additionalProperties": @NO } },
    ];
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    if ([name isEqualToString:@"utilities_status"]) {
        return @{ @"ok": @YES,
                  @"web_inspector": [FKUtilities webInspectorStatus],
                  @"hooks": [FKRuntimeKit activeHooks],
                  @"modules": @([FKRuntimeKit modules].count),
                  @"traffic": [FKRuntimeKit networkHistory:1],
                  @"native": @YES };
    }
    if ([name isEqualToString:@"web_inspector"]) {
        if ([args[@"enabled"] respondsToSelector:@selector(boolValue)]) {
            [FKUtilities setWebInspectorEnabled:[args[@"enabled"] boolValue]];
            if ([args[@"apply"] boolValue]) [FKUtilities applyWebInspectorToOpenWebViews];
        }
        return @{ @"ok": @YES, @"status": [FKUtilities webInspectorStatus] };
    }
    return nil;
}

@end
