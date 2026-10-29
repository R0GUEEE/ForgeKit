//
//  FKToolsApp.m — application, runtime, UI and server tools (category)
//

#import "ForgeKit.h"
#import "FKToolsPrivate.h"
#import "FKIL2CPP.h"
#import "FKShell.h"
#import <dlfcn.h>

static NSDictionary *FKOk(NSDictionary *payload) {
    NSMutableDictionary *result = [@{ @"ok": @YES } mutableCopy];
    if (payload) [result addEntriesFromDictionary:payload];
    return result;
}

static NSDictionary *FKFail(NSString *message) {
    return @{ @"ok": @NO, @"error": message ?: @"failed" };
}

static NSString *FKStringArg(NSDictionary *args, NSString *key) {
    id value = args[key];
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

static BOOL FKBoolArg(NSDictionary *args, NSString *key, BOOL fallback) {
    id value = args[key];
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return fallback;
}

static NSInteger FKIntArg(NSDictionary *args, NSString *key, NSInteger fallback) {
    id value = args[key];
    if ([value respondsToSelector:@selector(integerValue)]) return [value integerValue];
    return fallback;
}


static id FKObjectAtKeyPath(NSDictionary *dictionary, NSString *keyPath) {
    id current = dictionary;
    for (NSString *part in [keyPath componentsSeparatedByString:@"."]) {
        if (![current isKindOfClass:[NSDictionary class]]) return nil;
        current = ((NSDictionary *)current)[part];
        if (!current) return nil;
    }
    return current;
}

static BOOL FKSetObjectAtKeyPath(NSMutableDictionary *dictionary, NSString *keyPath, id value) {
    NSArray *parts = [keyPath componentsSeparatedByString:@"."];
    if (!parts.count) return NO;
    NSMutableDictionary *current = dictionary;
    for (NSUInteger i = 0; i < parts.count - 1; i++) {
        id next = current[parts[i]];
        if (![next isKindOfClass:[NSMutableDictionary class]]) {
            next = [NSMutableDictionary dictionary];
            current[parts[i]] = next;
        }
        current = next;
    }
    current[parts.lastObject] = value ?: [NSNull null];
    return YES;
}

static id FKCoerceValue(id value, NSString *type) {
    if (!type.length) return value;
    if ([type isEqualToString:@"string"]) return [value description] ?: @"";
    if ([type isEqualToString:@"bool"]) return @([value boolValue]);
    if ([type isEqualToString:@"int"] || [type isEqualToString:@"number"]) return @([value longLongValue]);
    if ([type isEqualToString:@"float"]) return @([value doubleValue]);
    if ([type isEqualToString:@"data"] && [value isKindOfClass:[NSString class]])
        return [[NSData alloc] initWithBase64EncodedString:value options:0] ?: [NSData data];
    return value;
}

@implementation FKTools (Application)

#pragma mark - Application introspection

+ (NSDictionary *)appInfo {
    NSDictionary *info = FKInfoPlist();
    NSMutableDictionary *identity = [NSMutableDictionary dictionary];
    identity[@"name"] = FKAppName();
    identity[@"bundle_id"] = FKAppIdentifier();
    identity[@"version"] = FKAppVersion();
    identity[@"short_version"] = info[@"CFBundleShortVersionString"] ?: @"";
    identity[@"build"] = info[@"CFBundleVersion"] ?: @"";
    identity[@"minimum_os"] = info[@"MinimumOSVersion"] ?: @"";
    identity[@"platform"] = info[@"DTPlatformName"] ?: @"";
    identity[@"sdk"] = info[@"DTSDKName"] ?: @"";
    identity[@"executable"] = info[@"CFBundleExecutable"] ?: @"";
    identity[@"url_schemes"] = [info[@"CFBundleURLTypes"] valueForKey:@"CFBundleURLSchemes"] ?: @[];

    NSDictionary *device = @{
        @"model": FKDeviceModelIdentifier(),
        @"name": [UIDevice currentDevice].name ?: @"",
        @"system": [UIDevice currentDevice].systemName ?: @"iOS",
        @"ios": FKOSVersionString(),
    };
    NSDictionary *process = @{
        @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
        @"resident_memory": @(FKResidentMemory()),
        @"resident_memory_text": FKHumanSize(FKResidentMemory()),
        @"uptime": @([[NSProcessInfo processInfo] systemUptime]),
    };
    NSDictionary *sandbox = @{
        @"jailbroken": @(FKIsJailbroken()),
        @"container_writable": @([[NSFileManager defaultManager] isWritableFileAtPath:FKContainerPath()]),
        @"bundle_writable": @([[NSFileManager defaultManager] isWritableFileAtPath:FKBundlePath()]),
        @"root_readable": @([[NSFileManager defaultManager] isReadableFileAtPath:@"/"]),
    };
    return FKOk(@{ @"app": identity, @"device": device, @"process": process,
                   @"sandbox": sandbox, @"paths": FKApplicationPaths(),
                   @"signing": @{ @"entitlements": FKEntitlements() } });
}

+ (NSDictionary *)infoPlist:(NSDictionary *)args {
    NSString *key = FKStringArg(args, @"key");
    NSDictionary *info = FKInfoPlist();
    if (key.length) {
        id value = FKObjectAtKeyPath(info, key);
        return value ? FKOk(@{ @"key": key, @"value": FKJSONSafe(value) }) : FKFail(@"key not found");
    }
    return FKOk(@{ @"plist": FKJSONSafe(info) });
}

+ (NSDictionary *)plistGet:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data) return FKFail(error.localizedDescription ?: @"cannot read");
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (!plist) return FKFail(error.localizedDescription ?: @"not a plist");
    NSString *key = FKStringArg(args, @"key");
    if (key.length) {
        id value = [plist isKindOfClass:[NSDictionary class]] ? FKObjectAtKeyPath(plist, key) : nil;
        return value ? FKOk(@{ @"key": key, @"value": FKJSONSafe(value) }) : FKFail(@"key not found");
    }
    return FKOk(@{ @"path": path, @"plist": FKJSONSafe(plist) });
}

+ (NSDictionary *)plistSet:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    NSString *key = FKStringArg(args, @"key");
    if (!path.length || !key.length) return FKFail(@"path and key required");
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error] : nil;
    if (![plist isKindOfClass:[NSMutableDictionary class]]) return FKFail(@"plist missing or not a dictionary");
    id value = FKCoerceValue(args[@"value"], FKStringArg(args, @"value_type"));
    if (!FKSetObjectAtKeyPath(plist, key, value)) return FKFail(@"cannot set key");
    NSData *output = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                format:NSPropertyListXMLFormat_v1_0
                                                               options:0
                                                                 error:&error];
    if (!output) return FKFail(error.localizedDescription ?: @"encode failed");
    if (!FKWriteDataAtomically(output, path, &error)) return FKFail(error.localizedDescription ?: @"write failed");
    return FKOk(@{ @"path": path, @"key": key, @"value": FKJSONSafe(value) });
}

+ (NSDictionary *)defaultsList {
    NSString *preferences = [FKLibraryPath() stringByAppendingPathComponent:@"Preferences"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:preferences error:nil] ?: @[];
    NSMutableArray *domains = [NSMutableArray array];
    for (NSString *file in files) {
        if (![file.pathExtension isEqualToString:@"plist"]) continue;
        NSString *path = [preferences stringByAppendingPathComponent:file];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        [domains addObject:@{
            @"domain": [file stringByDeletingPathExtension],
            @"path": path,
            @"keys": @(plist.count),
            @"bytes": @([[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]),
        }];
    }
    [domains sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"domain"] compare:b[@"domain"]];
    }];
    return FKOk(@{ @"preferences": preferences, @"domains": domains });
}

+ (NSDictionary *)defaultsGet:(NSDictionary *)args {
    NSString *domain = FKStringArg(args, @"domain");
    if (!domain.length) return FKFail(@"domain required");
    NSDictionary *values = [[NSUserDefaults standardUserDefaults] persistentDomainForName:domain];
    if (!values) {
        NSString *path = [FKLibraryPath() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"Preferences/%@.plist", domain]];
        values = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    if (!values) return FKFail(@"domain not found");
    NSString *key = FKStringArg(args, @"key");
    if (key.length) {
        id value = values[key];
        return value ? FKOk(@{ @"domain": domain, @"key": key, @"value": FKJSONSafe(value) }) : FKFail(@"key not found");
    }
    return FKOk(@{ @"domain": domain, @"values": FKJSONSafe(values) });
}

+ (NSDictionary *)defaultsSet:(NSDictionary *)args {
    NSString *domain = FKStringArg(args, @"domain");
    NSString *key = FKStringArg(args, @"key");
    if (!domain.length || !key.length) return FKFail(@"domain and key required");
    id value = args[@"value"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([domain isEqualToString:FKAppIdentifier()]) {
        [defaults setObject:value forKey:key];
        [defaults synchronize];
        return FKOk(@{ @"domain": domain, @"key": key, @"value": FKJSONSafe(value), @"scope": @"runtime" });
    }
    NSString *path = [FKLibraryPath() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"Preferences/%@.plist", domain]];
    NSMutableDictionary *plist = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
    plist[key] = value;
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || !FKWriteDataAtomically(data, path, &error)) return FKFail(error.localizedDescription ?: @"write failed");
    return FKOk(@{ @"domain": domain, @"key": key, @"path": path, @"scope": @"file" });
}

+ (NSDictionary *)urlSchemes {
    NSArray *types = FKInfoPlist()[@"CFBundleURLTypes"];
    NSMutableArray *result = [NSMutableArray array];
    if ([types isKindOfClass:[NSArray class]]) {
        for (NSDictionary *type in types) {
            id schemes = type[@"CFBundleURLSchemes"];
            if ([schemes isKindOfClass:[NSArray class]]) [result addObjectsFromArray:schemes];
        }
    }
    return FKOk(@{ @"schemes": result });
}

+ (NSDictionary *)binaries {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *binaries = [NSMutableArray array];
    NSMutableArray *candidates = [NSMutableArray array];
    if (NSBundle.mainBundle.executablePath) [candidates addObject:NSBundle.mainBundle.executablePath];
    NSString *frameworks = [FKBundlePath() stringByAppendingPathComponent:@"Frameworks"];
    for (NSString *name in [fm contentsOfDirectoryAtPath:frameworks error:nil]) {
        NSString *path = [frameworks stringByAppendingPathComponent:name];
        NSString *binary = [path stringByAppendingPathComponent:name.stringByDeletingPathExtension];
        if ([fm fileExistsAtPath:binary]) [candidates addObject:binary];
    }
    NSString *plugins = [FKBundlePath() stringByAppendingPathComponent:@"PlugIns"];
    for (NSString *name in [fm contentsOfDirectoryAtPath:plugins error:nil]) {
        NSString *path = [plugins stringByAppendingPathComponent:name];
        NSString *binary = [path stringByAppendingPathComponent:name.stringByDeletingPathExtension];
        if ([fm fileExistsAtPath:binary]) [candidates addObject:binary];
    }
    for (NSString *path in candidates) {
        unsigned long long size = [[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
        [binaries addObject:@{ @"path": path, @"size": @(size),
                               @"dependencies": FKMachODependencies(path) }];
    }
    return FKOk(@{ @"binaries": binaries });
}

+ (NSDictionary *)keychain:(NSDictionary *)args {
    NSString *itemClass = FKStringArg(args, @"item_class") ?: @"generic";
    NSArray *items = FKKeychainItems(itemClass);
    return FKOk(@{ @"class": itemClass, @"count": @(items.count), @"items": items });
}

+ (NSDictionary *)dylibLoad:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return FKFail(@"file does not exist");
    dlerror();
    void *handle = dlopen(path.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        const char *message = dlerror();
        return FKFail(message ? [NSString stringWithUTF8String:message] : @"dlopen failed");
    }
    return FKOk(@{ @"path": path, @"handle": [NSString stringWithFormat:@"%p", handle] });
}

#pragma mark - Runtime

+ (NSDictionary *)runtimeEval:(NSDictionary *)args {
    NSString *source = FKStringArg(args, @"source");
    if (!source.length) return FKFail(@"source required");
    NSString *error = nil;
    id result = [FKRuntime evaluateScript:source error:&error];
    if (error) return FKFail(error);
    return FKOk(@{ @"result": result ?: @"null" });
}

+ (NSDictionary *)runtimeClasses:(NSDictionary *)args {
    NSString *prefix = FKStringArg(args, @"prefix") ?: @"";
    NSInteger limit = FKIntArg(args, @"limit", 500);
    return FKOk(@{ @"classes": [FKRuntime classesWithPrefix:prefix limit:limit] });
}

+ (NSDictionary *)runtimeClassInfo:(NSDictionary *)args {
    NSString *name = FKStringArg(args, @"class");
    if (!name.length) return FKFail(@"class required");
    return FKOk([FKRuntime classInfo:name]);
}

+ (NSDictionary *)runtimeMemory {
    uint64_t resident = FKResidentMemory();
    return FKOk(@{ @"resident": @(resident), @"resident_text": FKHumanSize(resident),
                   @"threads": @([[NSThread currentThread] isMainThread] ? 1 : 0) });
}

#pragma mark - UI automation

+ (NSDictionary *)uiTree:(NSDictionary *)args {
    NSInteger depth = FKIntArg(args, @"depth", 8);
    NSInteger maxNodes = FKIntArg(args, @"max_nodes", 1500);
    return FKOk([FKRuntime viewTreeWithDepth:depth maxNodes:maxNodes]);
}

+ (NSDictionary *)uiTap:(NSDictionary *)args {
    NSString *label = FKStringArg(args, @"label");
    if (label.length) return FKOk([FKRuntime tapElementWithLabel:label]);
    NSNumber *x = args[@"x"];
    NSNumber *y = args[@"y"];
    if (![x isKindOfClass:[NSNumber class]] || ![y isKindOfClass:[NSNumber class]])
        return FKFail(@"provide x and y, or label");
    return FKOk([FKRuntime tapAtPoint:CGPointMake(x.doubleValue, y.doubleValue)]);
}

+ (NSDictionary *)uiType:(NSDictionary *)args {
    NSString *text = FKStringArg(args, @"text");
    if (text == nil) return FKFail(@"text required");
    return FKOk([FKRuntime typeText:text intoElementWithLabel:FKStringArg(args, @"label")]);
}

+ (NSDictionary *)uiScreenshot:(NSDictionary *)args {
    CGFloat quality = 0.8;
    NSNumber *value = args[@"quality"];
    if ([value isKindOfClass:[NSNumber class]]) quality = value.doubleValue;
    return FKOk([FKRuntime screenshotJPEGQuality:quality]);
}

+ (NSDictionary *)uiAlert:(NSDictionary *)args {
    NSString *title = FKStringArg(args, @"title") ?: @"ForgeKit";
    NSString *message = FKStringArg(args, @"message") ?: @"";
    FKPresentAlert(title, message);
    return FKOk(@{ @"presented": @YES });
}

+ (NSDictionary *)uiOpenURL:(NSDictionary *)args {
    NSString *string = FKStringArg(args, @"url");
    NSURL *url = string.length ? [NSURL URLWithString:string] : nil;
    if (!url) return FKFail(@"invalid url");
    __block BOOL opened = NO;
    FKRunOnMain(^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            (void)success;
        }];
        opened = YES;
    });
    return FKOk(@{ @"url": url.absoluteString, @"requested": @(opened) });
}

#pragma mark - Server / status

+ (NSDictionary *)status {
    FKHTTPServer *server = [FKHTTPServer sharedServer];
    NSString *token = [FKPrefs token];
    NSString *masked = token.length > 8 ? [NSString stringWithFormat:@"%@…%@", [token substringToIndex:4], [token substringFromIndex:token.length - 4]] : @"";
    return FKOk(@{
        @"version": FKVersionString,
        @"app": @{ @"name": FKAppName(), @"bundle": FKAppIdentifier(), @"version": FKAppVersion() },
        @"device": @{ @"model": FKDeviceModelIdentifier(), @"ios": FKOSVersionString() },
        @"sandbox": @{ @"jailbroken": @(FKIsJailbroken()), @"container": FKContainerPath() },
        @"server": @{ @"running": @(server.isRunning), @"port": @(server.port),
                      @"url": [NSString stringWithFormat:@"http://%@:%u/mcp", FKLanAddress(), server.port],
                      @"token_masked": masked, @"requires_token": @([FKPrefs boolForKey:@"requireToken" defaultValue:YES]) },
        @"panel": @{ @"visible": @([[FKPanel sharedPanel] isVisible]),
                     @"gesture": @"long-press status bar clock",
                     @"alt_gesture": @"volume up then down",
                     @"volume_trigger": @([[FKVolumeTrigger sharedTrigger] isRunning]) },
        @"il2cpp": @{ @"available": @([FKIL2CPP available]), @"detail": [FKIL2CPP statusText] },
        @"shell": @{ @"cwd": [FKShell sharedShell].currentDirectory,
                     @"commands": @([[FKShell sharedShell] commandNames].count),
                     @"tcp": @{ @"running": @([[FKShellServer sharedServer] isRunning]),
                                @"port": @([[FKShellServer sharedServer] port]) } },
        @"tools": @([FKTools toolDefinitions].count),
        @"memory": FKHumanSize(FKResidentMemory()),
    });
}

+ (NSDictionary *)logWithArgs:(NSDictionary *)args {
    NSInteger limit = MAX(1, MIN(FKIntArg(args, @"limit", 200), 2000));
    NSArray *lines = FKLogLines();
    NSUInteger start = lines.count > (NSUInteger)limit ? lines.count - (NSUInteger)limit : 0;
    return FKOk(@{ @"lines": [lines subarrayWithRange:NSMakeRange(start, lines.count - start)] });
}

+ (NSDictionary *)serverStart:(NSDictionary *)args {
    uint16_t port = (uint16_t)MAX(1, MIN(FKIntArg(args, @"port", [FKPrefs integerForKey:@"port" defaultValue:8787]), 65535));
    NSError *error = nil;
    if (![[FKHTTPServer sharedServer] startOnPort:port error:&error])
        return FKFail(error.localizedDescription ?: @"cannot start server");
    [FKPrefs setInteger:port forKey:@"port"];
    return FKOk(@{
        @"running": @YES,
        @"port": @(port),
        @"url": [NSString stringWithFormat:@"http://%@:%u/mcp", FKLanAddress(), port],
        @"token": [FKPrefs token],
    });
}

+ (NSDictionary *)serverLog:(NSDictionary *)args {
    NSInteger limit = MAX(1, MIN(FKIntArg(args, @"limit", 50), 500));
    return FKOk(@{ @"requests": [[FKHTTPServer sharedServer] recentRequestsWithLimit:limit] });
}

#pragma mark - Containers and self test

+ (NSDictionary *)appContainers {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *containers = [NSMutableArray array];
    NSArray *pairs = @[
        @[ @"/var/mobile/Containers/Data/Application", @"data" ],
        @[ @"/var/containers/Bundle/Application", @"bundle" ],
        @[ @"/var/mobile/Containers/Shared/AppGroup", @"group" ],
    ];
    for (NSArray *pair in pairs) {
        NSString *root = pair[0];
        NSString *kind = pair[1];
        NSArray *entries = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *uuid in entries) {
            NSString *path = [root stringByAppendingPathComponent:uuid];
            NSString *identifier = nil;
            NSArray *candidates = kind == nil ? @[] : @[
                [path stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"],
                [path stringByAppendingPathComponent:@"PluginKitPlugin/.com.apple.mobile_container_manager.metadata.plist"],
            ];
            for (NSString *plistPath in candidates) {
                NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                if ([metadata[@"MCMMetadataIdentifier"] isKindOfClass:[NSString class]]) {
                    identifier = metadata[@"MCMMetadataIdentifier"];
                }
                if (identifier) break;
            }
            [containers addObject:@{ @"kind": kind, @"uuid": uuid, @"path": path,
                                     @"identifier": identifier ?: @"unknown" }];
        }
    }
    BOOL denied = (containers.count == 0);
    return FKOk(@{ @"count": @(containers.count), @"containers": containers,
                   @"note": denied ? @"No containers visible: the sandbox only exposes this app's own container." : @"" });
}

+ (NSDictionary *)selfTest {
    NSMutableArray *checks = [NSMutableArray array];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"forgekit-selftest"];
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];

    void (^check)(NSString *, BOOL, NSString *) = ^(NSString *name, BOOL passed, NSString *detail) {
        [checks addObject:@{ @"check": name, @"passed": @(passed), @"detail": detail ?: @"" }];
    };

    NSString *file = [root stringByAppendingPathComponent:@"sample.txt"];
    NSString *payload = @"forgekit self test\nsecond line";
    BOOL wrote = FKWriteDataAtomically([payload dataUsingEncoding:NSUTF8StringEncoding], file, NULL);
    NSString *readBack = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    check(@"write+read", wrote && [readBack isEqualToString:payload], file);

    NSArray *listing = FKDirectoryList(root, YES, NULL);
    check(@"list", listing.count >= 1, [NSString stringWithFormat:@"%lu entries", (unsigned long)listing.count]);

    NSString *zip = [root stringByAppendingPathComponent:@"bundle.zip"];
    NSError *zipError = nil;
    BOOL zipped = [FKZip createArchiveAtPath:zip fromPaths:@[file] error:&zipError];
    check(@"zip.create", zipped, zipError.localizedDescription ?: zip);

    NSString *unzipped = [root stringByAppendingPathComponent:@"out"];
    NSError *unzipError = nil;
    BOOL unzippedOK = [FKZip extractArchiveAtPath:zip toDirectory:unzipped error:&unzipError];
    NSString *extracted = [NSString stringWithContentsOfFile:[unzipped stringByAppendingPathComponent:@"sample.txt"]
                                                    encoding:NSUTF8StringEncoding error:nil];
    check(@"zip.extract", unzippedOK && [extracted isEqualToString:payload], unzipError.localizedDescription ?: unzipped);

    NSString *jsError = nil;
    id jsResult = [FKRuntime evaluateScript:@"1 + 2" error:&jsError];
    check(@"javascript", [jsResult respondsToSelector:@selector(intValue)] && [jsResult intValue] == 3, jsError ?: [jsResult description]);

    NSArray *keychain = FKKeychainItems(@"generic");
    check(@"keychain", YES, [NSString stringWithFormat:@"%lu generic items", (unsigned long)keychain.count]);

    NSDictionary *tree = [FKRuntime viewTreeWithDepth:4 maxNodes:500];
    check(@"ui.tree", [tree[@"tree"] isKindOfClass:[NSDictionary class]],
          [NSString stringWithFormat:@"%@ nodes", tree[@"nodes"] ?: @"?"]);

    NSDictionary *status = [self status];
    check(@"server", YES, [NSString stringWithFormat:@"running=%@", status[@"server"][@"running"]]);

    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];

    NSInteger failed = 0;
    for (NSDictionary *entry in checks) if (![entry[@"passed"] boolValue]) failed++;
    return FKOk(@{ @"passed": @(checks.count - failed), @"failed": @(failed), @"checks": checks });
}

@end
