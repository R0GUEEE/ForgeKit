//
//  FKVolumeTrigger.m — activation by pressing volume up, then volume down
//
//  Three independent sources feed one state machine:
//    1. AVSystemController volume-change notification (string name)
//    2. KVO on AVAudioSession.outputVolume
//    3. KVO on a hidden MPVolumeView's UISlider — this one keeps working when the
//       audio session is deactivated by the system, which is the usual reason a
//       notification-only listener goes dead.
//
//  The session uses Playback + MixWithOthers so hardware presses adjust media
//  volume even with the ring switch silenced. No audio is played.
//

#import "ForgeKit.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

static NSString * const FKVolumeDidChangeNotification = @"AVSystemController_SystemVolumeDidChangeNotification";
static NSString * const FKVolumeReasonKey = @"AVSystemController_AudioVolumeChangeReasonNotificationParameter";
static NSString * const FKVolumeValueKey = @"AVSystemController_AudioVolumeNotificationParameter";
static void *FKVolumeSessionContext = &FKVolumeSessionContext;
static void *FKVolumeSliderContext = &FKVolumeSliderContext;

@interface FKVolumeTrigger ()
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, strong) AVAudioSession *session;
@property (nonatomic, strong) UIView *volumeView;
@property (nonatomic, weak) UISlider *volumeSlider;
@property (nonatomic, assign) float lastVolume;
@property (nonatomic, assign) double pendingUpTime;
@property (nonatomic, assign) float pendingUpVolume;
@property (nonatomic, assign) double lastEventTime;
@property (nonatomic, assign) double lastFireTime;
@property (nonatomic, assign) double suppressUntil;
@property (nonatomic, assign) NSInteger eventCount;
@property (nonatomic, assign) NSInteger lastDirection;
@property (nonatomic, assign) double lastDirectionTime;
@end

@implementation FKVolumeTrigger

+ (instancetype)sharedTrigger {
    static FKVolumeTrigger *trigger;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ trigger = [[FKVolumeTrigger alloc] init]; });
    return trigger;
}

- (void)start {
    if (self.running) return;
    self.session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [self.session setCategory:AVAudioSessionCategoryPlayback
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:&error];
    [self.session setActive:YES withOptions:0 error:&error];
    self.lastVolume = self.session.outputVolume;
    self.pendingUpTime = 0;
    self.lastFireTime = 0;
    self.eventCount = 0;
    self.running = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(volumeNotification:)
                                                 name:FKVolumeDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    // The volume-up + volume-down chord is consumed by iOS as the screenshot
    // gesture; the screenshot notification is the only public signal for it.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenshotTaken:)
                                                 name:UIApplicationUserDidTakeScreenshotNotification
                                               object:nil];
    [self.session addObserver:self forKeyPath:@"outputVolume"
                      options:NSKeyValueObservingOptionNew
                      context:FKVolumeSessionContext];
    [self installVolumeView];
    FKLog(@"volume trigger armed (up then down within %.1fs)", [FKPrefs doubleForKey:@"volumeWindow" defaultValue:1.2]);
    [self normalizeIfNeeded];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    @try {
        [self.session removeObserver:self forKeyPath:@"outputVolume" context:FKVolumeSessionContext];
    } @catch (NSException *exception) {
        (void)exception;
    }
    [self detachVolumeView];
    [self.session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    self.session = nil;
    FKLog(@"volume trigger disarmed after %ld events", (long)self.eventCount);
}

#pragma mark - Volume view

- (void)installVolumeView {
    FKRunOnMain(^{
        if (self.volumeView.superview) {
            [self bindVolumeSlider];
            return;
        }
        UIWindow *window = FKKeyWindow();
        if (!window) {
            // Try again once the app has a window.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.running && !self.volumeView.superview) [self installVolumeView];
            });
            return;
        }
        Class volumeClass = NSClassFromString(@"MPVolumeView");
        if (!volumeClass) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{ dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_LAZY); });
            volumeClass = NSClassFromString(@"MPVolumeView");
        }
        if (!volumeClass) {
            FKLog(@"volume trigger: MPVolumeView unavailable on this system");
            return;
        }
        UIView *view = [[volumeClass alloc] initWithFrame:CGRectMake(-3000, -3000, 120, 32)];
        view.userInteractionEnabled = NO;
        view.alpha = 0.011;      // must stay visible for the slider to update
        view.hidden = NO;
        [window addSubview:view];
        self.volumeView = view;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self bindVolumeSlider];
        });
    });
}

- (UISlider *)findSliderInView:(UIView *)view {
    if ([view isKindOfClass:[UISlider class]]) return (UISlider *)view;
    for (UIView *child in view.subviews) {
        UISlider *slider = [self findSliderInView:child];
        if (slider) return slider;
    }
    return nil;
}

- (void)bindVolumeSlider {
    if (!self.running) return;
    UISlider *slider = [self findSliderInView:self.volumeView];
    if (!slider) {
        FKLog(@"volume trigger: MPVolumeView slider not ready");
        return;
    }
    if (self.volumeSlider == slider) return;
    if (self.volumeSlider) {
        @try {
            [self.volumeSlider removeObserver:self forKeyPath:@"value" context:FKVolumeSliderContext];
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    self.volumeSlider = slider;
    [slider addObserver:self forKeyPath:@"value"
                options:NSKeyValueObservingOptionNew
                context:FKVolumeSliderContext];
    self.lastVolume = slider.value;
    FKLog(@"volume trigger: MPVolumeView slider bound (%.2f)", slider.value);
}

- (void)detachVolumeView {
    FKRunOnMain(^{
        if (self.volumeSlider) {
            @try {
                [self.volumeSlider removeObserver:self forKeyPath:@"value" context:FKVolumeSliderContext];
            } @catch (NSException *exception) {
                (void)exception;
            }
            self.volumeSlider = nil;
        }
        [self.volumeView removeFromSuperview];
        self.volumeView = nil;
    });
}

#pragma mark - Events

- (void)applicationBecameActive:(NSNotification *)notification {
    if (!self.running) return;
    NSError *error = nil;
    [self.session setActive:YES withOptions:0 error:&error];
    [self installVolumeView];
    self.lastVolume = self.session.outputVolume;
    FKLog(@"volume trigger re-armed on foreground (%.2f)", self.lastVolume);
}

- (void)volumeNotification:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *reason = info[FKVolumeReasonKey];
    if ([reason isKindOfClass:[NSString class]] && ![reason isEqualToString:@"ExplicitVolumeChange"]) return;
    NSNumber *value = info[FKVolumeValueKey];
    if ([value isKindOfClass:[NSNumber class]]) [self handleVolume:value.floatValue];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (context == FKVolumeSessionContext || context == FKVolumeSliderContext) {
        NSNumber *value = change[NSKeyValueChangeNewKey];
        if ([value isKindOfClass:[NSNumber class]]) [self handleVolume:value.floatValue];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)handleVolume:(float)value {
    if (!self.running) return;
    FKRunOnMain(^{
        double now = [NSDate timeIntervalSinceReferenceDate];
        if (now < self.suppressUntil) {
            self.lastVolume = value;
            return;
        }
        // Notification + KVO + slider can deliver the same change; collapse duplicates.
        if (now - self.lastEventTime < 0.06 && fabsf(value - self.lastVolume) < 0.001) return;
        float delta = value - self.lastVolume;
        if (fabsf(delta) < 0.001) return;
        self.lastEventTime = now;
        self.lastVolume = value;
        self.eventCount++;

        NSInteger direction = delta > 0 ? 1 : -1;
        if ([FKPrefs boolForKey:@"volumeChordTrigger" defaultValue:YES] &&
            self.lastDirection != 0 && direction != self.lastDirection &&
            now - self.lastDirectionTime <= 0.20) {
            // Two opposing presses inside one gesture window: treat as the chord.
            self.lastDirection = 0;
            self.pendingUpTime = 0;
            [self fire];
            return;
        }
        self.lastDirection = direction;
        self.lastDirectionTime = now;

        if (delta > 0) {
            self.pendingUpTime = now;
            self.pendingUpVolume = value;
            return;
        }
        double window = [FKPrefs doubleForKey:@"volumeWindow" defaultValue:1.2];
        if (self.pendingUpTime > 0 && now - self.pendingUpTime <= window && value < self.pendingUpVolume) {
            self.pendingUpTime = 0;
            [self fire];
        }
    });
}

- (void)screenshotTaken:(NSNotification *)notification {
    if (!self.running) return;
    if (![FKPrefs boolForKey:@"volumeChordTrigger" defaultValue:YES]) return;
    FKLog(@"volume chord detected via screenshot notification");
    [self fire];
}

- (void)fire {
    double now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastFireTime < 1.5) return;
    self.lastFireTime = now;
    if ([FKPrefs boolForKey:@"haptics" defaultValue:YES]) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator impactOccurred];
    }
    FKLog(@"volume sequence detected — toggling panel");
    [[FKPanel sharedPanel] toggle];
}

#pragma mark - Headroom

- (void)normalizeIfNeeded {
    if (![FKPrefs boolForKey:@"volumeNormalize" defaultValue:YES]) return;
    float volume = self.volumeSlider ? self.volumeSlider.value : self.session.outputVolume;
    if (volume > 0.02f && volume < 0.98f) return;
    FKRunOnMain(^{
        UISlider *slider = self.volumeSlider;
        if (!slider) return;
        [slider setValue:0.5f animated:NO];
        [slider sendActionsForControlEvents:UIControlEventValueChanged];
        self.suppressUntil = [NSDate timeIntervalSinceReferenceDate] + 1.0;
        self.pendingUpTime = 0;
        FKLog(@"volume normalized from %.2f for sequence headroom", volume);
    });
}

@end
