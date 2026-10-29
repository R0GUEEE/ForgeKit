//
//  FKRuntime.m — JavaScriptCore evaluation, ObjC introspection, UI automation
//

#import "ForgeKit.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>

static NSMutableArray *FKRuntimeHistory(void) {
    static NSMutableArray *history;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ history = [NSMutableArray array]; });
    return history;
}

static NSString *FKViewText(UIView *view) {
    NSMutableArray *parts = [NSMutableArray array];
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length) [parts addObject:text];
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        if (field.text.length) [parts addObject:field.text];
        if (field.placeholder.length) [parts addObject:[NSString stringWithFormat:@"placeholder:%@", field.placeholder]];
    } else if ([view isKindOfClass:[UITextView class]]) {
        NSString *text = ((UITextView *)view).text;
        if (text.length) [parts addObject:[text substringToIndex:MIN(text.length, (NSUInteger)120)]];
    } else if ([view isKindOfClass:[UIButton class]]) {
        NSString *title = [((UIButton *)view) titleForState:UIControlStateNormal];
        if (title.length) [parts addObject:title];
    } else if ([view isKindOfClass:[UISearchBar class]]) {
        NSString *text = ((UISearchBar *)view).text;
        if (text.length) [parts addObject:text];
    }
    if (view.accessibilityLabel.length) [parts addObject:[NSString stringWithFormat:@"a11y:%@", view.accessibilityLabel]];
    if (view.accessibilityIdentifier.length) [parts addObject:[NSString stringWithFormat:@"id:%@", view.accessibilityIdentifier]];
    return [parts componentsJoinedByString:@" | "];
}

static NSDictionary *FKDescribeView(UIView *view, NSInteger depth, NSInteger maxDepth, NSInteger *budget) {
    if (*budget <= 0) return @{};
    *budget -= 1;
    NSMutableDictionary *node = [NSMutableDictionary dictionary];
    node[@"class"] = NSStringFromClass([view class]);
    node[@"frame"] = NSStringFromCGRect(view.frame);
    node[@"text"] = FKViewText(view);
    node[@"hidden"] = @(view.hidden || view.alpha < 0.02);
    node[@"interactive"] = @([view isKindOfClass:[UIControl class]] || view.isUserInteractionEnabled);
    node[@"tag"] = @(view.tag);
    if ([view isKindOfClass:[UIControl class]]) node[@"enabled"] = @(((UIControl *)view).enabled);
    node[@"a11y"] = @(view.isAccessibilityElement);
    if (view.accessibilityTraits) node[@"traits"] = @(view.accessibilityTraits);
    if (depth < maxDepth) {
        NSMutableArray *children = [NSMutableArray array];
        for (UIView *child in view.subviews) {
            if (*budget <= 0) break;
            NSDictionary *description = FKDescribeView(child, depth + 1, maxDepth, budget);
            if (description.count) [children addObject:description];
        }
        if (children.count) node[@"children"] = children;
    }
    return node;
}

static void FKCollectViews(UIView *view, NSMutableArray<UIView *> *output) {
    [output addObject:view];
    for (UIView *child in view.subviews) FKCollectViews(child, output);
}

static NSString *FKElementLabel(UIView *view) {
    if (view.accessibilityLabel.length) return view.accessibilityLabel;
    if (view.accessibilityIdentifier.length) return view.accessibilityIdentifier;
    if ([view isKindOfClass:[UILabel class]]) return ((UILabel *)view).text;
    if ([view isKindOfClass:[UIButton class]]) return [((UIButton *)view) titleForState:UIControlStateNormal];
    if ([view isKindOfClass:[UITextField class]]) return ((UITextField *)view).placeholder ?: ((UITextField *)view).text;
    if ([view isKindOfClass:[UINavigationBar class]]) return nil;
    return nil;
}

static UIView *FKFindViewByLabel(NSString *label) {
    UIWindow *window = FKKeyWindow();
    if (!window) return nil;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    FKCollectViews(window, views);
    UIView *partial = nil;
    for (UIView *view in views) {
        NSString *candidate = FKElementLabel(view);
        if (!candidate.length) continue;
        if ([candidate isEqualToString:label]) return view;
        if (!partial && [candidate rangeOfString:label options:NSCaseInsensitiveSearch].location != NSNotFound)
            partial = view;
    }
    return partial;
}

static BOOL FKActivateView(UIView *view) {
    if (!view) return NO;
    UIView *control = view;
    while (control && ![control isKindOfClass:[UIControl class]]) control = control.superview;
    if (control) {
        UIControl *candidate = (UIControl *)control;
        [candidate sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([view respondsToSelector:@selector(accessibilityActivate)]) {
        return [view accessibilityActivate];
    }
    if ([view.gestureRecognizers count] > 0) {
        return NO;
    }
    return NO;
}

static BOOL FKActivateAtPoint(CGPoint point, NSDictionary **detail) {
    UIWindow *window = FKKeyWindow();
    if (!window) return NO;
    UIView *hit = [window hitTest:point withEvent:nil];
    if (!hit) return NO;
    if (detail) {
        *detail = @{ @"class": NSStringFromClass([hit class]),
                     @"frame": NSStringFromCGRect([hit convertRect:hit.bounds toView:window]),
                     @"label": FKElementLabel(hit) ?: @"" };
    }
    return FKActivateView(hit);
}

@implementation FKRuntime

+ (id)evaluateScript:(NSString *)source error:(NSString **)error {
    if (!source.length) {
        if (error) *error = @"empty script";
        return nil;
    }
    JSContext *context = [[JSContext alloc] init];
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        (void)ctx;
        FKLog(@"JS exception: %@", exception);
    };

    context[@"fk"] = @{
        @"read": ^NSString *(NSString *path) {
            NSData *data = [NSData dataWithContentsOfFile:FKExpandPath(path)];
            if (!data) return @"";
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        },
        @"write": ^BOOL (NSString *path, NSString *content) {
            NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
            return FKWriteDataAtomically(data, FKExpandPath(path), NULL);
        },
        @"list": ^NSArray *(NSString *path) {
            return FKDirectoryList(FKExpandPath(path), YES, NULL);
        },
        @"stat": ^NSDictionary *(NSString *path) {
            return FKFileAttributes(FKExpandPath(path));
        },
        @"info": ^NSDictionary *{
            return @{ @"app": FKAppName(), @"bundle": FKAppIdentifier(), @"version": FKAppVersion(),
                      @"device": FKDeviceModelIdentifier(), @"ios": FKOSVersionString(),
                      @"container": FKContainerPath(), @"jailed": @(!FKIsJailbroken()) };
        },
        @"log": ^(NSString *message) {
            FKLog(@"js: %@", message);
        },
        @"sleep": ^(double seconds) {
            [NSThread sleepForTimeInterval:MIN(seconds, 5.0)];
        },
    };

    JSValue *value = [context evaluateScript:source];
    if (context.exception && !context.exception.isUndefined) {
        NSString *message = [context.exception toString] ?: @"error";
        if (error) *error = message;
        [FKRuntimeHistory() addObject:@{ @"source": source, @"error": message }];
        return nil;
    }
    id result = value.isUndefined ? @"undefined" : [value toObject];
    if (!result) result = [value description];
    [FKRuntimeHistory() addObject:@{ @"source": source, @"result": FKJSONSafe(result) }];
    return FKJSONSafe(result);
}

+ (NSDictionary *)viewTreeWithDepth:(NSInteger)depth maxNodes:(NSInteger)maxNodes {
    __block NSDictionary *result = nil;
    FKRunOnMain(^{
        UIWindow *window = FKKeyWindow();
        if (!window) { result = @{ @"error": @"no key window" }; return; }
        NSInteger budget = MAX(50, MIN(maxNodes, 5000));
        NSDictionary *tree = FKDescribeView(window, 0, MAX(1, MIN(depth, 20)), &budget);
        result = @{
            @"window": @{ @"class": NSStringFromClass([window class]),
                          @"size": NSStringFromCGSize(window.bounds.size),
                          @"level": @(window.windowLevel) },
            @"tree": tree,
            @"nodes": @(MAX(0, MIN(maxNodes, 5000)) - budget),
        };
    });
    return result ?: @{ @"error": @"unavailable" };
}

+ (NSDictionary *)tapAtPoint:(CGPoint)point {
    __block NSDictionary *result = nil;
    FKRunOnMain(^{
        NSDictionary *detail = nil;
        BOOL activated = FKActivateAtPoint(point, &detail);
        result = @{ @"point": NSStringFromCGPoint(point), @"activated": @(activated), @"hit": detail ?: @{} };
    });
    return result ?: @{ @"error": @"unavailable" };
}

+ (NSDictionary *)tapElementWithLabel:(NSString *)label {
    __block NSDictionary *result = nil;
    FKRunOnMain(^{
        UIView *view = FKFindViewByLabel(label);
        if (!view) {
            result = @{ @"error": @"element not found", @"label": label ?: @"" };
            return;
        }
        BOOL activated = FKActivateView(view);
        if (!activated) {
            CGPoint center = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds))
                                         toView:FKKeyWindow()];
            NSDictionary *detail = nil;
            activated = FKActivateAtPoint(center, &detail);
        }
        result = @{
            @"label": label,
            @"class": NSStringFromClass([view class]),
            @"frame": NSStringFromCGRect(view.frame),
            @"activated": @(activated),
        };
    });
    return result ?: @{ @"error": @"unavailable" };
}

+ (NSDictionary *)typeText:(NSString *)text intoElementWithLabel:(NSString *)label {
    __block NSDictionary *result = nil;
    FKRunOnMain(^{
        UIView *target = nil;
        if (label.length) target = FKFindViewByLabel(label);
        if (!target) {
            NSMutableArray<UIView *> *views = [NSMutableArray array];
            UIWindow *window = FKKeyWindow();
            if (window) FKCollectViews(window, views);
            for (UIView *view in views) {
                if (view.isFirstResponder &&
                    ([view isKindOfClass:[UITextField class]] || [view isKindOfClass:[UITextView class]] ||
                     [view isKindOfClass:[UISearchBar class]])) {
                    target = view;
                    break;
                }
            }
        }
        if (!target) { result = @{ @"error": @"no text field found" }; return; }

        if ([target isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *)target;
            if (!field.isFirstResponder) [field becomeFirstResponder];
            field.text = text;
            [field sendActionsForControlEvents:UIControlEventEditingChanged];
        } else if ([target isKindOfClass:[UITextView class]]) {
            UITextView *view = (UITextView *)target;
            if (!view.isFirstResponder) [view becomeFirstResponder];
            view.text = text;
            [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:view];
        } else if ([target isKindOfClass:[UISearchBar class]]) {
            ((UISearchBar *)target).text = text;
        } else {
            result = @{ @"error": [NSString stringWithFormat:@"unsupported field %@", NSStringFromClass([target class])] };
            return;
        }
        result = @{ @"target": NSStringFromClass([target class]), @"length": @(text.length), @"typed": @YES };
    });
    return result ?: @{ @"error": @"unavailable" };
}

+ (NSDictionary *)screenshotJPEGQuality:(CGFloat)quality {
    __block NSDictionary *result = nil;
    FKRunOnMain(^{
        UIImage *image = FKSnapshotKeyWindow();
        if (!image) { result = @{ @"error": @"no window" }; return; }
        NSData *jpeg = UIImageJPEGRepresentation(image, MAX(0.1, MIN(quality, 1.0)));
        if (!jpeg) { result = @{ @"error": @"encode failed" }; return; }
        result = @{
            @"width": @(image.size.width * image.scale),
            @"height": @(image.size.height * image.scale),
            @"format": @"jpeg",
            @"bytes": @(jpeg.length),
            @"base64": [jpeg base64EncodedStringWithOptions:0],
        };
    });
    return result ?: @{ @"error": @"unavailable" };
}

+ (NSArray<NSDictionary *> *)classesWithPrefix:(NSString *)prefix limit:(NSInteger)limit {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)malloc(sizeof(Class) * (NSUInteger)count);
    if (!classes) return @[];
    count = objc_getClassList(classes, count);
    NSMutableArray *matches = [NSMutableArray array];
    NSInteger cap = MAX(1, MIN(limit, 2000));
    for (int i = 0; i < count && (NSInteger)matches.count < cap; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        NSString *className = [NSString stringWithUTF8String:name];
        if (!className) continue;
        if (prefix.length && ![className hasPrefix:prefix]) continue;
        [matches addObject:@{ @"name": className,
                              @"superclass": NSStringFromClass(class_getSuperclass(classes[i]) ?: [NSObject class]) }];
    }
    free(classes);
    [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
    return matches;
}

+ (NSDictionary *)classInfo:(NSString *)className {
    Class cls = NSClassFromString(className);
    if (!cls) return @{ @"error": @"class not found" };
    NSMutableArray *instanceMethods = [NSMutableArray array];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        [instanceMethods addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);

    NSMutableArray *classMethods = [NSMutableArray array];
    Method *metaMethods = class_copyMethodList(object_getClass(cls), &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        [classMethods addObject:NSStringFromSelector(method_getName(metaMethods[i]))];
    }
    free(metaMethods);

    NSMutableArray *ivars = [NSMutableArray array];
    unsigned int ivarCount = 0;
    Ivar *ivarList = class_copyIvarList(cls, &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
        const char *name = ivar_getName(ivarList[i]);
        const char *type = ivar_getTypeEncoding(ivarList[i]);
        if (name) [ivars addObject:[NSString stringWithFormat:@"%s %s", type ?: "?", name]];
    }
    free(ivarList);

    NSMutableArray *protocols = [NSMutableArray array];
    unsigned int protocolCount = 0;
    Protocol *__unsafe_unretained *protocolList = class_copyProtocolList(cls, &protocolCount);
    for (unsigned int i = 0; i < protocolCount; i++) {
        const char *name = protocol_getName(protocolList[i]);
        if (name) [protocols addObject:[NSString stringWithUTF8String:name]];
    }
    free(protocolList);

    [instanceMethods sortUsingSelector:@selector(compare:)];
    [classMethods sortUsingSelector:@selector(compare:)];
    return @{
        @"name": className,
        @"superclass": NSStringFromClass(class_getSuperclass(cls) ?: [NSObject class]),
        @"instance_methods": instanceMethods,
        @"class_methods": classMethods,
        @"ivars": ivars,
        @"protocols": protocols,
    };
}

@end
