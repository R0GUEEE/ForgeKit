//
//  FKUnityTools.m — IL2CPP tool surface (libtool-compatible names), script engine
//

#import "ForgeKit.h"
#import "FKIL2CPP.h"
#import <JavaScriptCore/JavaScriptCore.h>

#pragma mark - Script engine

@interface FKScriptEngine : NSObject
+ (instancetype)sharedEngine;
- (NSDictionary *)runSource:(NSString *)source name:(NSString *)name;
- (NSDictionary *)startUIScript:(NSString *)source name:(NSString *)name;
- (void)stopUIScript;
- (NSDictionary *)uiStatus;
- (NSArray<NSDictionary *> *)listScripts;
- (BOOL)saveScript:(NSString *)name code:(NSString *)code error:(NSString **)error;
- (NSString *)loadScript:(NSString *)name;
+ (NSString *)helpText;
@end

static NSString *FKScriptsDirectory(void) {
    return [FKDocumentsPath() stringByAppendingPathComponent:@"ForgeKit/scripts"];
}

static NSString *FKSanitizedScriptName(NSString *name) {
    NSString *base = name.lastPathComponent.stringByDeletingPathExtension;
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    base = [[base componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    if (!base.length) base = @"script";
    return [base stringByAppendingPathExtension:@"js"];
}

#pragma mark - Overlay

@interface FKScriptOverlay : NSObject
+ (instancetype)sharedOverlay;
- (void)showWithText:(NSString *)text;
- (void)hide;
@end

@implementation FKScriptOverlay {
    UIWindow *_window;
    UILabel *_label;
}

+ (instancetype)sharedOverlay {
    static FKScriptOverlay *overlay;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ overlay = [[FKScriptOverlay alloc] init]; });
    return overlay;
}

- (void)showWithText:(NSString *)text {
    FKRunOnMain(^{
        if (!self->_window) {
            UIWindowScene *scene = FKActiveWindowScene();
            UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                                     : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            window.windowLevel = UIWindowLevelAlert + 90;
            window.backgroundColor = [UIColor clearColor];
            window.userInteractionEnabled = NO;
            UIViewController *controller = [[UIViewController alloc] init];
            controller.view.backgroundColor = [UIColor clearColor];
            UILabel *label = [[UILabel alloc] init];
            label.numberOfLines = 0;
            label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
            label.textColor = [UIColor whiteColor];
            label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
            label.layer.cornerRadius = 8;
            label.layer.cornerCurve = kCACornerCurveContinuous;
            label.clipsToBounds = YES;
            label.frame = CGRectMake(12, 64, 280, 0);
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
            [controller.view addSubview:label];
            window.rootViewController = controller;
            window.hidden = NO;
            self->_window = window;
            self->_label = label;
        }
        self->_window.hidden = NO;
        self->_label.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
        [self->_label sizeToFit];
        CGRect frame = self->_label.frame;
        frame.origin = CGPointMake(12, 64);
        frame.size.width = MIN(CGRectGetWidth(self->_window.bounds) - 24, MAX(frame.size.width + 16, 160));
        frame.size.height += 10;
        self->_label.frame = frame;
    });
}

- (void)hide {
    FKRunOnMain(^{
        self->_window.hidden = YES;
        self->_window = nil;
        self->_label = nil;
    });
}

@end

#pragma mark - Engine

@implementation FKScriptEngine {
    NSTimer *_timer;
    NSString *_source;
    NSString *_name;
    NSInteger _ticks;
    NSString *_lastError;
}

+ (instancetype)sharedEngine {
    static FKScriptEngine *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [[FKScriptEngine alloc] init]; });
    return engine;
}

+ (NSString *)helpText {
    return @"ForgeKit scripting uses JavaScript (JavaScriptCore), not Lua. "
           @"The Class bridge mirrors libtool's Lua API:\n"
           "  var cls = Class.fromName(\"Namespace.ClassName\");\n"
           "  cls.findObjects(10)            -> [{ptr, class}]\n"
           "  cls.read(\"field\", 0)          -> value (0 = static)\n"
           "  cls.write(\"field\", 42, 0)     -> bool\n"
           "  cls.invoke(\"Method\", 0, [args]) -> result\n"
           "  cls.info()                     -> class metadata\n"
           "  Class.search(\"Coins\", 20)      -> [names]\n"
           "  log(value), json(value), sleep(seconds), uiText = \"...\"\n"
           "Scripts are stored in Documents/ForgeKit/scripts/*.js.";
}

- (JSContext *)newContext {
    JSContext *context = [[JSContext alloc] init];
    __weak typeof(self) weakSelf = self;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        (void)ctx;
        FKScriptEngine *strongSelf = weakSelf;
        strongSelf->_lastError = [exception toString] ?: @"script error";
        FKLog(@"script exception: %@", strongSelf->_lastError);
    };
    context[@"log"] = ^(id value) { FKLog(@"script: %@", value); };
    context[@"json"] = ^NSString *(id value) { return FKJSONString(value, YES); };
    context[@"sleep"] = ^(double seconds) { [NSThread sleepForTimeInterval:MIN(MAX(seconds, 0), 5.0)]; };
    context[@"uiText"] = @"";

    __weak JSContext *weakContext = context;
    context[@"Class"] = @{
        @"fromName": ^JSValue *(NSString *className) {
            JSContext *ctx = weakContext;
            if (!ctx || !className.length) return [JSValue valueWithUndefinedInContext:weakContext];
            JSValue *handle = [JSValue valueWithNewObjectInContext:ctx];
            handle[@"name"] = className;
            handle[@"info"] = ^NSDictionary *{
                return [FKIL2CPP classInfoFor:className];
            };
            handle[@"findObjects"] = ^NSArray *(NSNumber *limit) {
                NSDictionary *result = [FKIL2CPP findObjectsOfClass:className
                                                               limit:limit ? limit.integerValue : 32];
                return result[@"objects"] ?: @[];
            };
            handle[@"read"] = ^id(NSString *field, NSNumber *objectPointer) {
                NSDictionary *result = [FKIL2CPP readField:field ofClass:className
                                                    object:objectPointer.unsignedLongLongValue];
                return result[@"value"] ?: result;
            };
            handle[@"write"] = ^BOOL(NSString *field, id value, NSNumber *objectPointer) {
                NSDictionary *result = [FKIL2CPP writeField:field ofClass:className
                                                     object:objectPointer.unsignedLongLongValue value:value];
                return [result[@"ok"] boolValue];
            };
            handle[@"invoke"] = ^id(NSString *method, NSNumber *objectPointer, NSArray *arguments) {
                NSDictionary *result = [FKIL2CPP invokeMethod:method ofClass:className
                                                       object:objectPointer.unsignedLongLongValue
                                                         args:arguments ?: @[] overload:0];
                return result[@"result"] ?: result;
            };
            return handle;
        },
        @"search": ^NSArray *(NSString *pattern, NSNumber *limit) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSDictionary *entry in [FKIL2CPP classesMatching:pattern limit:limit ? limit.integerValue : 50])
                [names addObject:entry[@"name"]];
            return names;
        },
    };
    return context;
}

- (NSDictionary *)runSource:(NSString *)source name:(NSString *)name {
    if (!source.length) return @{ @"ok": @NO, @"error": @"empty script" };
    if (![FKIL2CPP available] && [source rangeOfString:@"Class."].location != NSNotFound)
        return @{ @"ok": @NO, @"error": [FKIL2CPP statusText] };
    JSContext *context = [self newContext];
    NSDate *start = [NSDate date];
    JSValue *value = [context evaluateScript:source];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    if (context.exception && !context.exception.isUndefined) {
        return @{ @"ok": @NO, @"error": [context.exception toString] ?: @"script error",
                  @"name": name ?: @"inline", @"ms": @((NSInteger)(elapsed * 1000)) };
    }
    id result = value.isUndefined ? @"undefined" : [value toObject];
    return @{ @"ok": @YES, @"name": name ?: @"inline",
              @"result": FKJSONSafe(result ?: @"null"),
              @"uiText": [context[@"uiText"] toString] ?: @"",
              @"ms": @((NSInteger)(elapsed * 1000)) };
}

- (BOOL)saveScript:(NSString *)name code:(NSString *)code error:(NSString **)error {
    NSString *file = [FKScriptsDirectory() stringByAppendingPathComponent:FKSanitizedScriptName(name)];
    NSError *writeError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:FKScriptsDirectory()
                                  withIntermediateDirectories:YES attributes:nil error:&writeError]) {
        if (error) *error = writeError.localizedDescription;
        return NO;
    }
    BOOL ok = [code writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!ok && error) *error = writeError.localizedDescription;
    return ok;
}

- (NSString *)loadScript:(NSString *)name {
    NSString *file = [FKScriptsDirectory() stringByAppendingPathComponent:FKSanitizedScriptName(name)];
    return [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
}

- (NSArray<NSDictionary *> *)listScripts {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:FKScriptsDirectory() error:nil] ?: @[];
    NSMutableArray *scripts = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file.pathExtension isEqualToString:@"js"]) continue;
        NSString *path = [FKScriptsDirectory() stringByAppendingPathComponent:file];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        [scripts addObject:@{ @"name": file.stringByDeletingPathExtension,
                              @"bytes": attributes[NSFileSize] ?: @0,
                              @"modified": @([attributes[NSFileModificationDate] timeIntervalSince1970]) }];
    }
    return scripts;
}

- (NSDictionary *)startUIScript:(NSString *)source name:(NSString *)name {
    if (!source.length) return @{ @"ok": @NO, @"error": @"empty script" };
    [self stopUIScript];
    _source = [source copy];
    _name = [name copy] ?: @"ui";
    _ticks = 0;
    _lastError = nil;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        FKScriptEngine *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            [weakSelf tick];
        }];
        [weakSelf tick];
    });
    return @{ @"ok": @YES, @"running": @YES, @"name": _name };
}

- (void)tick {
    NSString *source = _source;
    if (!source) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        JSContext *context = [self newContext];
        JSValue *value = [context evaluateScript:source];
        NSString *text = [context[@"uiText"] toString] ?: @"";
        BOOL failed = context.exception && !context.exception.isUndefined;
        if (failed) text = [context.exception toString] ?: @"error";
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_ticks++;
            if (failed) self->_lastError = text;
            [[FKScriptOverlay sharedOverlay] showWithText:text.length ? text : @"(script produced no uiText)"];
        });
        (void)value;
    });
}

- (void)stopUIScript {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_timer invalidate];
        self->_timer = nil;
        self->_source = nil;
        [[FKScriptOverlay sharedOverlay] hide];
    });
}

- (NSDictionary *)uiStatus {
    return @{ @"running": @(_timer != nil), @"name": _name ?: @"",
              @"ticks": @(_ticks), @"lastError": _lastError ?: @"",
              @"renderer": @"UIKit overlay (1 Hz)" };
}

@end

#pragma mark - Tool surface

@implementation FKUnityTools

+ (NSArray<NSDictionary *> *)definitions {
    NSMutableArray *tools = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSDictionary *, NSArray *) = ^(NSString *name, NSString *description,
                                                                     NSDictionary *properties, NSArray *required) {
        [tools addObject:@{ @"name": name, @"description": description,
                            @"inputSchema": @{ @"type": @"object", @"properties": properties ?: @{},
                                               @"required": required ?: @[], @"additionalProperties": @NO } }];
    };
    NSDictionary *(^s)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"string", @"description": description };
    };
    NSDictionary *(^i)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"integer", @"description": description };
    };

    add(@"ping", @"Liveness check for the IL2CPP tool bridge.", @{}, @[]);
    add(@"runtime_info", @"IL2CPP backend status: assemblies, classes, patch capacity.", @{}, @[]);
    add(@"list_images", @"List loaded IL2CPP images (assemblies).",
        @{ @"filter": s(@"Name substring.") }, @[]);
    add(@"list_classes", @"Search classes by name substring.",
        @{ @"filter": s(@"Case-insensitive class name substring."), @"limit": i(@"Default 200.") }, @[]);
    add(@"class_info", @"Fields, methods, parent and interfaces of a class.",
        @{ @"class": s(@"Full class name, e.g. Namespace.Type.") }, @[@"class"]);
    add(@"find_field_owners", @"Every class with a field of the given type.",
        @{ @"type": s(@"Type substring, e.g. List<Item> or Int32."), @"limit": i(@"Default 200.") }, @[@"type"]);
    add(@"find_methods_by_pattern", @"Cross-class method search by name and/or return type.",
        @{ @"pattern": s(@"Method name substring."), @"return_type": s(@"Return type substring."),
           @"limit": i(@"Default 200.") }, @[]);
    add(@"find_classes_inheriting_from", @"Classes whose ancestor chain matches a base class.",
        @{ @"base": s(@"Base class name substring."), @"limit": i(@"Default 500.") }, @[@"base"]);
    add(@"find_classes_implementing", @"Classes implementing an interface (substring match).",
        @{ @"interface": s(@"Interface name substring."), @"limit": i(@"Default 500.") }, @[@"interface"]);
    add(@"find_objects", @"Live instances of a class (Unity object lookup, then static-field scan).",
        @{ @"class": s(@"Full class name."), @"limit": i(@"Default 50.") }, @[@"class"]);
    add(@"inspect_object", @"Read every field of a live instance, including inherited fields.",
        @{ @"class": s(@"Class of the object."), @"object": s(@"Object pointer from find_objects."),
           @"limit": i(@"Default 120.") }, @[@"class", @"object"]);
    add(@"inspect_collection", @"Read array and List<T> elements from a collection pointer.",
        @{ @"object": s(@"Collection pointer."), @"limit": i(@"Default 200.") }, @[@"object"]);
    add(@"read_field", @"Read one field (static when object is 0 or omitted).",
        @{ @"class": s(@"Declaring class."), @"field": s(@"Field name."),
           @"object": s(@"Instance pointer, or 0 for static.") }, @[@"class", @"field"]);
    add(@"write_field", @"Write one field (static or instance).",
        @{ @"class": s(@"Declaring class."), @"field": s(@"Field name."),
           @"object": s(@"Instance pointer, or 0 for static."), @"value": @{ @"description": @"New value." } },
        @[@"class", @"field", @"value"]);
    add(@"invoke_method", @"Invoke a method and return its result.",
        @{ @"class": s(@"Declaring class."), @"method": s(@"Method name."),
           @"object": s(@"Instance pointer, or 0 for static."),
           @"args": @{ @"type": @"array", @"description": @"Arguments." },
           @"overload": i(@"Nth overload with this name, default 0.") }, @[@"class", @"method"]);
    add(@"patch_method", @"Patch a method: constant return, nop, or redirect to another method.",
        @{ @"class": s(@"Declaring class."), @"method": s(@"Method name."),
           @"mode": @{ @"type": @"string", @"enum": @[@"return", @"nop", @"redirect"] },
           @"value": @{ @"description": @"Return value, or TargetClass.TargetMethod for redirect." },
           @"overload": i(@"Nth overload, default 0.") }, @[@"class", @"method"]);
    add(@"restore_patch", @"Undo one patch.", @{ @"class": s(@"Class."), @"method": s(@"Method.") },
        @[@"class", @"method"]);
    add(@"restore_all", @"Undo every active patch and redirect.", @{}, @[]);
    add(@"patch_status", @"Active patch slots and details.", @{}, @[]);
    add(@"watch_field", @"Sample a field repeatedly to tell live data from stale mirrors.",
        @{ @"class": s(@"Class."), @"field": s(@"Field."), @"object": s(@"Instance pointer, or 0 for static."),
           @"samples": i(@"Default 5."), @"interval_ms": i(@"Default 250.") },
        @[@"class", @"field"]);
    add(@"scan_ui_for_value", @"Search rendered UnityEngine.UI.Text / TMP text for a substring.",
        @{ @"needle": s(@"Text to find."), @"limit": i(@"Default 100.") }, @[@"needle"]);
    add(@"find_singletons", @"Static Instance/_instance fields that hold live objects.",
        @{ @"image": s(@"Optional image filter."), @"limit": i(@"Default 50.") }, @[]);
    add(@"scene_roots", @"Root GameObjects of the active scene.",
        @{ @"limit": i(@"Default 50.") }, @[]);
    add(@"read_player_prefs", @"Read a UnityEngine.PlayerPrefs value.",
        @{ @"key": s(@"Preference key."), @"type": @{ @"type": @"string", @"enum": @[@"int", @"float", @"string"] } },
        @[@"key"]);
    add(@"write_player_prefs", @"Write or delete a UnityEngine.PlayerPrefs value.",
        @{ @"key": s(@"Preference key."), @"type": @{ @"type": @"string", @"enum": @[@"int", @"float", @"string"] },
           @"value": @{ @"description": @"New value." }, @"delete": @{ @"type": @"boolean" } }, @[@"key"]);
    add(@"compare_instances", @"Batch compare up to 5 classes: instance counts and first-instance fields.",
        @{ @"classes": @{ @"type": @"array", @"items": @{ @"type": @"string" } },
           @"fields": @{ @"type": @"array", @"items": @{ @"type": @"string" } } }, @[@"classes"]);
    add(@"dump", @"Static dump of classes, fields and methods to a text file.",
        @{ @"filter": s(@"Optional class name substring."), @"path": s(@"Output path.") }, @[]);
    add(@"run_lua", @"Run a script with the Class bridge (JavaScript, not Lua).",
        @{ @"code": s(@"Source."), @"script": s(@"Saved script name.") }, @[]);
    add(@"save_script", @"Persist a script under Documents/ForgeKit/scripts.",
        @{ @"name": s(@"Script name."), @"code": s(@"Source.") }, @[@"name", @"code"]);
    add(@"list_scripts", @"List saved scripts.", @{}, @[]);
    add(@"lua_help", @"Scripting API help (Class bridge).", @{}, @[]);
    add(@"run_ui_lua", @"Run a script once per second and render uiText in an overlay.",
        @{ @"code": s(@"Source."), @"name": s(@"Optional name.") }, @[@"code"]);
    add(@"stop_ui_lua", @"Stop the persistent UI script.", @{}, @[]);
    add(@"ui_lua_status", @"Status of the persistent UI script.", @{}, @[]);
    add(@"toggle_menu", @"Open or close the ForgeKit panel.",
        @{ @"visible": @{ @"type": @"boolean" } }, @[]);
    return tools;
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    NSDictionary *a = [args isKindOfClass:[NSDictionary class]] ? args : @{};
    NSString *className = a[@"class"];
    if ([name isEqualToString:@"ping"]) {
        return @{ @"ok": @YES, @"pong": @YES, @"time": @([[NSDate date] timeIntervalSince1970]),
                  @"bridge": [FKIL2CPP available] ? @"il2cpp" : @"none" };
    }
    if ([name isEqualToString:@"runtime_info"]) return [FKIL2CPP runtimeInfo];
    if ([name isEqualToString:@"list_images"]) {
        NSArray *images = [FKIL2CPP images];
        NSString *filter = [a[@"filter"] lowercaseString];
        if (filter.length) {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", a[@"filter"]];
            images = [images filteredArrayUsingPredicate:predicate];
        }
        return @{ @"ok": @YES, @"count": @(images.count), @"images": images };
    }
    if ([name isEqualToString:@"list_classes"]) {
        NSArray *classes = [FKIL2CPP classesMatching:a[@"filter"] ?: @""
                                               limit:[a[@"limit"] integerValue] ?: 200];
        return @{ @"ok": @YES, @"count": @(classes.count), @"classes": classes };
    }
    if ([name isEqualToString:@"class_info"]) return [FKIL2CPP classInfoFor:className ?: @""];
    if ([name isEqualToString:@"find_field_owners"])
        return [FKIL2CPP findFieldOwners:a[@"type"] ?: @"" limit:[a[@"limit"] integerValue] ?: 200];
    if ([name isEqualToString:@"find_methods_by_pattern"])
        return [FKIL2CPP findMethodsByPattern:a[@"pattern"] returnType:a[@"return_type"]
                                        limit:[a[@"limit"] integerValue] ?: 200];
    if ([name isEqualToString:@"find_classes_inheriting_from"])
        return [FKIL2CPP findClassesInheritingFrom:a[@"base"] ?: @"" limit:[a[@"limit"] integerValue] ?: 500];
    if ([name isEqualToString:@"find_classes_implementing"])
        return [FKIL2CPP findClassesImplementing:a[@"interface"] ?: @"" limit:[a[@"limit"] integerValue] ?: 500];
    if ([name isEqualToString:@"find_objects"])
        return [FKIL2CPP findObjectsOfClass:className ?: @"" limit:[a[@"limit"] integerValue] ?: 50];
    if ([name isEqualToString:@"inspect_object"]) {
        unsigned long long pointer = [a[@"object"] unsignedLongLongValue];
        return [FKIL2CPP inspectObjectOfClass:className ?: @"" pointer:pointer
                                        limit:[a[@"limit"] integerValue] ?: 120];
    }
    if ([name isEqualToString:@"inspect_collection"])
        return [FKIL2CPP inspectCollection:[a[@"object"] unsignedLongLongValue]
                                     limit:[a[@"limit"] integerValue] ?: 200];
    if ([name isEqualToString:@"read_field"])
        return [FKIL2CPP readField:a[@"field"] ?: @"" ofClass:className ?: @""
                            object:[a[@"object"] unsignedLongLongValue]];
    if ([name isEqualToString:@"write_field"])
        return [FKIL2CPP writeField:a[@"field"] ?: @"" ofClass:className ?: @""
                             object:[a[@"object"] unsignedLongLongValue] value:a[@"value"]];
    if ([name isEqualToString:@"invoke_method"])
        return [FKIL2CPP invokeMethod:a[@"method"] ?: @"" ofClass:className ?: @""
                               object:[a[@"object"] unsignedLongLongValue]
                                 args:a[@"args"] ?: @[] overload:[a[@"overload"] integerValue] ?: 0];
    if ([name isEqualToString:@"patch_method"])
        return [FKIL2CPP patchMethod:a[@"method"] ?: @"" ofClass:className ?: @""
                                mode:a[@"mode"] ?: @"return" value:a[@"value"]
                            overload:[a[@"overload"] integerValue] ?: 0];
    if ([name isEqualToString:@"restore_patch"])
        return [FKIL2CPP restorePatchOfClass:className ?: @"" method:a[@"method"] ?: @""];
    if ([name isEqualToString:@"restore_all"]) return [FKIL2CPP restoreAllPatches];
    if ([name isEqualToString:@"patch_status"]) return [FKIL2CPP patchStatus];
    if ([name isEqualToString:@"watch_field"])
        return [FKIL2CPP watchField:className ?: @"" field:a[@"field"] ?: @""
                             object:[a[@"object"] unsignedLongLongValue]
                            samples:[a[@"samples"] integerValue] ?: 5
                         intervalMs:[a[@"interval_ms"] integerValue] ?: 250];
    if ([name isEqualToString:@"scan_ui_for_value"])
        return [FKIL2CPP scanUIText:a[@"needle"] ?: @"" limit:[a[@"limit"] integerValue] ?: 100];
    if ([name isEqualToString:@"find_singletons"])
        return [FKIL2CPP findSingletonsWithImage:a[@"image"] limit:[a[@"limit"] integerValue] ?: 50];
    if ([name isEqualToString:@"scene_roots"])
        return [FKIL2CPP sceneRootsWithLimit:[a[@"limit"] integerValue] ?: 50];
    if ([name isEqualToString:@"read_player_prefs"])
        return [FKIL2CPP playerPrefsRead:a[@"key"] ?: @"" type:a[@"type"] ?: @"int"];
    if ([name isEqualToString:@"write_player_prefs"])
        return [FKIL2CPP playerPrefsWrite:a[@"key"] ?: @"" type:a[@"type"] ?: @"int"
                                    value:a[@"value"] delete:[a[@"delete"] boolValue]];
    if ([name isEqualToString:@"compare_instances"])
        return [FKIL2CPP compareInstances:a[@"classes"] ?: @[] fields:a[@"fields"] ?: @[]];
    if ([name isEqualToString:@"dump"])
        return [FKIL2CPP dumpWithFilter:a[@"filter"] path:a[@"path"]];
    if ([name isEqualToString:@"toggle_menu"]) {
        id requested = a[@"visible"];
        FKRunOnMain(^{
            if ([requested respondsToSelector:@selector(boolValue)]) {
                if ([requested boolValue]) [[FKPanel sharedPanel] show];
                else [[FKPanel sharedPanel] hide];
            } else {
                [[FKPanel sharedPanel] toggle];
            }
        });
        return @{ @"ok": @YES, @"visible": @([[FKPanel sharedPanel] isVisible]) };
    }

    FKScriptEngine *engine = [FKScriptEngine sharedEngine];
    if ([name isEqualToString:@"run_lua"]) {
        NSString *source = a[@"code"];
        NSString *scriptName = a[@"script"];
        if (!source.length && scriptName.length) source = [engine loadScript:scriptName];
        if (!source.length) return @{ @"ok": @NO, @"error": @"provide code or a saved script name" };
        return [engine runSource:source name:scriptName ?: @"inline"];
    }
    if ([name isEqualToString:@"save_script"]) {
        NSString *error = nil;
        BOOL saved = [engine saveScript:a[@"name"] ?: @"" code:a[@"code"] ?: @"" error:&error];
        return @{ @"ok": @(saved), @"name": a[@"name"] ?: @"",
                  @"path": [FKScriptsDirectory() stringByAppendingPathComponent:
                            FKSanitizedScriptName(a[@"name"] ?: @"")],
                  @"error": saved ? [NSNull null] : (error ?: @"save failed") };
    }
    if ([name isEqualToString:@"list_scripts"])
        return @{ @"ok": @YES, @"directory": FKScriptsDirectory(), @"scripts": [engine listScripts] };
    if ([name isEqualToString:@"lua_help"])
        return @{ @"ok": @YES, @"engine": @"JavaScriptCore", @"api": [FKScriptEngine helpText] };
    if ([name isEqualToString:@"run_ui_lua"]) {
        NSString *source = a[@"code"];
        if (!source.length && [a[@"script"] isKindOfClass:[NSString class]]) source = [engine loadScript:a[@"script"]];
        if (!source.length) return @{ @"ok": @NO, @"error": @"code required" };
        return [engine startUIScript:source name:a[@"name"] ?: @"ui"];
    }
    if ([name isEqualToString:@"stop_ui_lua"]) { [engine stopUIScript]; return @{ @"ok": @YES, @"running": @NO }; }
    if ([name isEqualToString:@"ui_lua_status"]) return [engine uiStatus];
    return nil;
}

@end
