//
//  FKHooks.m — dylib entry point, window hooks and gesture installation
//

#import "ForgeKit.h"
#import <objc/runtime.h>

static void FKInstallGesturesOnAllWindows(void) {
    UIApplication *application = [UIApplication sharedApplication];
    if (!application) return;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.windowLevel > UIWindowLevelAlert) continue;
            [[FKPanel sharedPanel] installGestureOnWindow:window];
        }
    }
}

@interface UIWindow (FKForgeKit)
- (void)fk_makeKeyAndVisible;
- (void)fk_didMoveToWindow;
@end

@implementation UIWindow (FKForgeKit)

- (void)fk_makeKeyAndVisible {
    [self fk_makeKeyAndVisible];
    if (self.windowLevel <= UIWindowLevelAlert) [[FKPanel sharedPanel] installGestureOnWindow:self];
}

- (void)fk_didMoveToWindow {
    [self fk_didMoveToWindow];
    if (self.window && self.windowLevel <= UIWindowLevelAlert)
        [[FKPanel sharedPanel] installGestureOnWindow:self];
}

@end

__attribute__((constructor))
static void FKForgeKitInitialize(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            FKSwizzleInstance([UIWindow class], @selector(makeKeyAndVisible), @selector(fk_makeKeyAndVisible));
            FKSwizzleInstance([UIWindow class], @selector(didMoveToWindow), @selector(fk_didMoveToWindow));

            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                FKInstallGesturesOnAllWindows();
            }];
            [center addObserverForName:UIWindowDidBecomeKeyNotification
                                object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                UIWindow *window = note.object;
                if ([window isKindOfClass:[UIWindow class]] && window.windowLevel <= UIWindowLevelAlert)
                    [[FKPanel sharedPanel] installGestureOnWindow:window];
            }];
            [center addObserverForName:UISceneDidActivateNotification
                                object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                FKInstallGesturesOnAllWindows();
            }];

            FKInstallGesturesOnAllWindows();
            FKLog(@"ForgeKit %@ loaded into %@ (%@)", FKVersionString, FKAppIdentifier(), FKDeviceModelIdentifier());

            if ([FKPrefs boolForKey:@"volumeTrigger" defaultValue:YES]) {
                [[FKVolumeTrigger sharedTrigger] start];
            }

            if ([FKPrefs boolForKey:@"autoStart" defaultValue:NO]) {
                NSError *error = nil;
                uint16_t port = (uint16_t)[FKPrefs integerForKey:@"port" defaultValue:8787];
                if (![[FKHTTPServer sharedServer] startOnPort:port error:&error])
                    FKLog(@"autoStart failed: %@", error.localizedDescription);
            }
        });
    }
}
