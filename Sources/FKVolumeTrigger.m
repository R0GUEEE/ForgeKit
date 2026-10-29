//
//  FKVolumeTrigger.m — activation by pressing volume up, then volume down
//
//  Volume events are observed through the system's AVSystemController change
//  notification (string name, no private symbols) plus a KVO fallback on
//  AVAudioSession.outputVolume. The audio session uses the ambient + mixable
//  category, so starting the trigger never interrupts other audio.
//

#import "ForgeKit.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString * const FKVolumeDidChangeNotification = @"AVSystemController_SystemVolumeDidChangeNotification";
static NSString * const FKVolumeReasonKey = @"AVSystemController_AudioVolumeChangeReasonNotificationParameter";
static NSString * const FKVolumeValueKey = @"AVSystemController_AudioVolumeNotificationParameter";
static void *FKVolumeKVOContext = &FKVolumeKVOContext;

@interface FKVolumeTrigger ()
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, strong) AVAudioSession *session;
@property (nonatomic, assign) float lastVolume;
@property (nonatomic, assign) double pendingUpTime;
@property (nonatomic, assign) float pendingUpVolume;
@property (nonatomic, assign) double lastFireTime;
@property (nonatomic, assign) double suppressUntil;
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
    [self.session setCategory:AVAudioSessionCategoryAmbient
                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
                        error:&error];
    [self.session setActive:YES withOptions:0 error:&error];
    self.lastVolume = self.session.outputVolume;
    self.pendingUpTime = 0;
    self.lastFireTime = 0;
    self.running = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(volumeNotification:)
                                                 name:FKVolumeDidChangeNotification
                                               object:nil];
    [self.session addObserver:self forKeyPath:@"outputVolume"
                      options:NSKeyValueObservingOptionNew
                      context:FKVolumeKVOContext];
    FKLog(@"volume trigger armed (up then down within %.1fs)",
          [FKPrefs doubleForKey:@"volumeWindow" defaultValue:1.2]);
    [self normalizeIfNeeded];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:FKVolumeDidChangeNotification object:nil];
    @try {
        [self.session removeObserver:self forKeyPath:@"outputVolume" context:FKVolumeKVOContext];
    } @catch (NSException *exception) {
        (void)exception;
    }
    [self.session setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    self.session = nil;
    FKLog(@"volume trigger disarmed");
}

#pragma mark - Observations

- (void)volumeNotification:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSString *reason = info[FKVolumeReasonKey];
    if ([reason isKindOfClass:[NSString class]] && ![reason isEqualToString:@"ExplicitVolumeChange"]) return;
    NSNumber *value = info[FKVolumeValueKey];
    if (![value isKindOfClass:[NSNumber class]]) return;
    [self handleVolume:value.floatValue];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (context != FKVolumeKVOContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NSNumber *value = change[NSKeyValueChangeNewKey];
    if ([value isKindOfClass:[NSNumber class]]) [self handleVolume:value.floatValue];
}

- (void)handleVolume:(float)value {
    if (!self.running) return;
    FKRunOnMain(^{
        double now = [NSDate timeIntervalSinceReferenceDate];
        if (now < self.suppressUntil) { self.lastVolume = value; return; }
        float delta = value - self.lastVolume;
        self.lastVolume = value;
        if (fabsf(delta) < 0.001f) return;

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

// At 100% an "up" press produces no volume change, and at 0% a "down" press
// produces none either. When the trigger arms at an extreme, nudge the volume to
// the middle once so both directions can register. Best-effort: MPVolumeView's
// slider is the only public way to set system volume.
- (void)normalizeIfNeeded {
    if (![FKPrefs boolForKey:@"volumeNormalize" defaultValue:YES]) return;
    float volume = self.session.outputVolume;
    if (volume > 0.02f && volume < 0.98f) return;
    FKRunOnMain(^{
        UIWindow *window = FKKeyWindow();
        if (!window) return;
        MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-2000, -2000, 120, 30)];
        volumeView.hidden = NO;
        [window addSubview:volumeView];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (UIView *subview in volumeView.subviews) {
                if (![subview isKindOfClass:[UISlider class]]) continue;
                UISlider *slider = (UISlider *)subview;
                [slider setValue:0.5f animated:NO];
                [slider sendActionsForControlEvents:UIControlEventValueChanged];
                break;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [volumeView removeFromSuperview];
            });
        });
        double now = [NSDate timeIntervalSinceReferenceDate];
        self.suppressUntil = now + 1.0;
        FKLog(@"volume normalized from %.2f for sequence headroom", volume);
    });
}

@end
