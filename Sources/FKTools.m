//
//  FKTools.m — tool catalogue, dispatch and filesystem tools
//

#import "ForgeKit.h"
#import "FKToolsPrivate.h"
#import <sys/stat.h>

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

@implementation FKTools

+ (NSDictionary *)inputSchemaForProperties:(NSDictionary *)properties required:(NSArray *)required {
    return @{ @"type": @"object",
              @"properties": properties ?: @{},
              @"required": required ?: @[],
              @"additionalProperties": @NO };
}

+ (NSArray *)toolDefinitions {
    NSMutableArray *tools = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSDictionary *, NSArray *) = ^(NSString *name, NSString *description,
                                                                     NSDictionary *properties, NSArray *required) {
        [tools addObject:@{ @"name": name,
                            @"description": description,
                            @"inputSchema": [self inputSchemaForProperties:properties required:required] }];
    };

    add(@"fs_roots", @"List candidate filesystem roots with read/write access flags.", @{}, @[]);
    add(@"fs_list", @"List a directory. Returns name, path, size, mtime and directory flag per entry.",
        @{ @"path": @{ @"type": @"string", @"description": @"Directory path (defaults to app container)." },
           @"include_hidden": @{ @"type": @"boolean", @"description": @"Include dotfiles." } },
        @[]);
    add(@"fs_stat", @"Stat a path: type, size, POSIX mode, owner, timestamps and access flags.",
        @{ @"path": @{ @"type": @"string" } }, @[@"path"]);
    add(@"fs_read", @"Read a file. Returns utf8 text by default; use encoding=base64 for binary.",
        @{ @"path": @{ @"type": @"string" },
           @"encoding": @{ @"type": @"string", @"enum": @[@"utf8", @"base64"] },
           @"offset": @{ @"type": @"integer", @"description": @"Byte offset." },
           @"length": @{ @"type": @"integer", @"description": @"Maximum bytes to return (default 1 MiB)." } },
        @[@"path"]);
    add(@"fs_write", @"Write (replace) a file, creating parent directories.",
        @{ @"path": @{ @"type": @"string" },
           @"content": @{ @"type": @"string", @"description": @"Text or base64 payload." },
           @"encoding": @{ @"type": @"string", @"enum": @[@"utf8", @"base64"] },
           @"append": @{ @"type": @"boolean" } },
        @[@"path", @"content"]);
    add(@"fs_mkdir", @"Create a directory (intermediate directories by default).",
        @{ @"path": @{ @"type": @"string" },
           @"intermediates": @{ @"type": @"boolean" } }, @[@"path"]);
    add(@"fs_delete", @"Delete a file or directory. Non-empty directories require recursive=true.",
        @{ @"path": @{ @"type": @"string" },
           @"recursive": @{ @"type": @"boolean" } }, @[@"path"]);
    add(@"fs_move", @"Move or rename a path.",
        @{ @"from": @{ @"type": @"string" }, @"to": @{ @"type": @"string" },
           @"overwrite": @{ @"type": @"boolean" } }, @[@"from", @"to"]);
    add(@"fs_copy", @"Copy a file or directory tree.",
        @{ @"from": @{ @"type": @"string" }, @"to": @{ @"type": @"string" },
           @"overwrite": @{ @"type": @"boolean" } }, @[@"from", @"to"]);
    add(@"fs_search", @"Recursively search a directory by name substring and/or text content.",
        @{ @"path": @{ @"type": @"string" },
           @"name": @{ @"type": @"string", @"description": @"Case-insensitive filename substring." },
           @"contains": @{ @"type": @"string", @"description": @"Text content to find in files < 2 MiB." },
           @"max_results": @{ @"type": @"integer" } },
        @[@"path"]);
    add(@"fs_chmod", @"Change POSIX permissions, e.g. mode=755.",
        @{ @"path": @{ @"type": @"string" },
           @"mode": @{ @"type": @"string" } }, @[@"path", @"mode"]);
    add(@"fs_zip", @"Create a zip archive from one or more paths.",
        @{ @"destination": @{ @"type": @"string" },
           @"sources": @{ @"type": @"array", @"items": @{ @"type": @"string" } } },
        @[@"destination", @"sources"]);
    add(@"fs_unzip", @"Extract a zip archive into a directory (path traversal is filtered).",
        @{ @"archive": @{ @"type": @"string" },
           @"destination": @{ @"type": @"string" } }, @[@"archive", @"destination"]);
    add(@"fs_zip_list", @"List entries in a zip archive.",
        @{ @"archive": @{ @"type": @"string" } }, @[@"archive"]);

    add(@"app_info", @"Application identity: bundle id, name, version, device, sandbox state, paths.",
        @{}, @[]);
    add(@"app_paths", @"Resolved application paths (bundle, container, documents, library, groups).",
        @{}, @[]);
    add(@"app_info_plist", @"Read Info.plist (whole dictionary, or a single dot-separated key).",
        @{ @"key": @{ @"type": @"string" } }, @[]);
    add(@"app_plist_get", @"Read any plist file, optionally one dot-separated key.",
        @{ @"path": @{ @"type": @"string" },
           @"key": @{ @"type": @"string" } }, @[@"path"]);
    add(@"app_plist_set", @"Write a key in a plist file atomically.",
        @{ @"path": @{ @"type": @"string" },
           @"key": @{ @"type": @"string" },
           @"value": @{ @"description": @"New value." },
           @"value_type": @{ @"type": @"string", @"enum": @[@"string", @"bool", @"int", @"float", @"data", @"raw"] } },
        @[@"path", @"key", @"value"]);
    add(@"app_defaults_list", @"List preference domains (plists) inside the app container.",
        @{}, @[]);
    add(@"app_defaults_get", @"Read a preference domain, optionally a single key.",
        @{ @"domain": @{ @"type": @"string" }, @"key": @{ @"type": @"string" } }, @[@"domain"]);
    add(@"app_defaults_set", @"Write a key in a preference domain.",
        @{ @"domain": @{ @"type": @"string" }, @"key": @{ @"type": @"string" },
           @"value": @{ } }, @[@"domain", @"key", @"value"]);
    add(@"app_entitlements", @"Entitlements parsed from the code signature and provisioning profile.",
        @{}, @[]);
    add(@"app_url_schemes", @"URL schemes and document types declared by the app.",
        @{}, @[]);
    add(@"app_binaries", @"Mach-O dependencies, rpaths and slices for the app and bundled frameworks.",
        @{}, @[]);
    add(@"app_loaded_images", @"Every image currently loaded in the process.",
        @{}, @[]);
    add(@"app_keychain", @"Dump keychain items visible to this app (generic/internet/certificate).",
        @{ @"item_class": @{ @"type": @"string", @"enum": @[@"generic", @"internet", @"certificate"] } }, @[]);
    add(@"app_cookies", @"List HTTP cookies held by NSHTTPCookieStorage.",
        @{}, @[]);
    add(@"app_dylib_load", @"dlopen a dylib inside the process (needs a valid signature or jailbreak).",
        @{ @"path": @{ @"type": @"string" } }, @[@"path"]);
    add(@"app_containers", @"Enumerate app data/bundle containers with their bundle identifiers (jailbroken or entitled processes).",
        @{}, @[]);

    add(@"runtime_eval", @"Evaluate JavaScript in a JSC context with the fk.* filesystem bridge.",
        @{ @"source": @{ @"type": @"string" } }, @[@"source"]);
    add(@"runtime_classes", @"List Objective-C classes by prefix.",
        @{ @"prefix": @{ @"type": @"string" }, @"limit": @{ @"type": @"integer" } }, @[]);
    add(@"runtime_class_info", @"Methods, ivars and protocols of a class.",
        @{ @"class": @{ @"type": @"string" } }, @[@"class"]);
    add(@"runtime_memory", @"Process memory statistics.",
        @{}, @[]);

    add(@"ui_tree", @"Dump the key window's view tree with frames, text and accessibility labels.",
        @{ @"depth": @{ @"type": @"integer" }, @"max_nodes": @{ @"type": @"integer" } }, @[]);
    add(@"ui_tap", @"Tap by point (screen points) or by accessibility label / button title.",
        @{ @"x": @{ @"type": @"number" }, @"y": @{ @"type": @"number" },
           @"label": @{ @"type": @"string" } }, @[]);
    add(@"ui_type", @"Type into the focused text field, or the field matching a label.",
        @{ @"text": @{ @"type": @"string" }, @"label": @{ @"type": @"string" } }, @[@"text"]);
    add(@"ui_screenshot", @"Screenshot the key window as base64 JPEG.",
        @{ @"quality": @{ @"type": @"number", @"description": @"0.1 - 1.0, default 0.8" } }, @[]);
    add(@"ui_alert", @"Present a native alert inside the host app.",
        @{ @"title": @{ @"type": @"string" }, @"message": @{ @"type": @"string" } }, @[]);
    add(@"ui_open_url", @"Open a URL with the host app's UIApplication.",
        @{ @"url": @{ @"type": @"string" } }, @[@"url"]);

    add(@"devkit_status", @"ForgeKit status: version, server, panel, sandbox, memory.",
        @{}, @[]);
    add(@"devkit_log", @"Recent ForgeKit log lines.",
        @{ @"limit": @{ @"type": @"integer" } }, @[]);
    add(@"panel_open", @"Open the in-app toolkit panel.", @{}, @[]);
    add(@"panel_close", @"Close the in-app toolkit panel.", @{}, @[]);
    add(@"server_start", @"Start the HTTP/MCP server.",
        @{ @"port": @{ @"type": @"integer" } }, @[]);
    add(@"server_stop", @"Stop the HTTP/MCP server.", @{}, @[]);
    add(@"server_log", @"Recent HTTP requests.",
        @{ @"limit": @{ @"type": @"integer" } }, @[]);
    add(@"devkit_selftest", @"Exercise filesystem, zip, JavaScript, keychain and UI paths; returns per-check results.",
        @{}, @[]);

    [tools addObjectsFromArray:[FKUnityTools definitions]];
    [tools addObjectsFromArray:[FKShellTools definitions]];
    return tools;
}

#pragma mark - Dispatch

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)arguments {
    NSDictionary *args = [arguments isKindOfClass:[NSDictionary class]] ? arguments : @{};
    @try {
        if ([name isEqualToString:@"fs_roots"]) return [self fsRoots];
        if ([name isEqualToString:@"fs_list"]) return [self fsList:args];
        if ([name isEqualToString:@"fs_stat"]) return [self fsStat:args];
        if ([name isEqualToString:@"fs_read"]) return [self fsRead:args];
        if ([name isEqualToString:@"fs_write"]) return [self fsWrite:args];
        if ([name isEqualToString:@"fs_mkdir"]) return [self fsMkdir:args];
        if ([name isEqualToString:@"fs_delete"]) return [self fsDelete:args];
        if ([name isEqualToString:@"fs_move"]) return [self fsMove:args copy:NO];
        if ([name isEqualToString:@"fs_copy"]) return [self fsMove:args copy:YES];
        if ([name isEqualToString:@"fs_search"]) return [self fsSearch:args];
        if ([name isEqualToString:@"fs_chmod"]) return [self fsChmod:args];
        if ([name isEqualToString:@"fs_zip"]) return [self fsZip:args];
        if ([name isEqualToString:@"fs_unzip"]) return [self fsUnzip:args];
        if ([name isEqualToString:@"fs_zip_list"]) return [self fsZipList:args];

        if ([name isEqualToString:@"app_info"]) return [self appInfo];
        if ([name isEqualToString:@"app_paths"]) return FKOk(@{ @"paths": FKApplicationPaths() });
        if ([name isEqualToString:@"app_info_plist"]) return [self infoPlist:args];
        if ([name isEqualToString:@"app_plist_get"]) return [self plistGet:args];
        if ([name isEqualToString:@"app_plist_set"]) return [self plistSet:args];
        if ([name isEqualToString:@"app_defaults_list"]) return [self defaultsList];
        if ([name isEqualToString:@"app_defaults_get"]) return [self defaultsGet:args];
        if ([name isEqualToString:@"app_defaults_set"]) return [self defaultsSet:args];
        if ([name isEqualToString:@"app_entitlements"]) return FKOk(@{ @"entitlements": FKEntitlements() });
        if ([name isEqualToString:@"app_url_schemes"]) return [self urlSchemes];
        if ([name isEqualToString:@"app_binaries"]) return [self binaries];
        if ([name isEqualToString:@"app_loaded_images"]) return FKOk(@{ @"images": FKLoadedImages() });
        if ([name isEqualToString:@"app_keychain"]) return [self keychain:args];
        if ([name isEqualToString:@"app_cookies"]) return FKOk(@{ @"cookies": FKHTTPCookies() });
        if ([name isEqualToString:@"app_dylib_load"]) return [self dylibLoad:args];
        if ([name isEqualToString:@"app_containers"]) return [self appContainers];

        if ([name isEqualToString:@"runtime_eval"]) return [self runtimeEval:args];
        if ([name isEqualToString:@"runtime_classes"]) return [self runtimeClasses:args];
        if ([name isEqualToString:@"runtime_class_info"]) return [self runtimeClassInfo:args];
        if ([name isEqualToString:@"runtime_memory"]) return [self runtimeMemory];

        if ([name isEqualToString:@"ui_tree"]) return [self uiTree:args];
        if ([name isEqualToString:@"ui_tap"]) return [self uiTap:args];
        if ([name isEqualToString:@"ui_type"]) return [self uiType:args];
        if ([name isEqualToString:@"ui_screenshot"]) return [self uiScreenshot:args];
        if ([name isEqualToString:@"ui_alert"]) return [self uiAlert:args];
        if ([name isEqualToString:@"ui_open_url"]) return [self uiOpenURL:args];

        if ([name isEqualToString:@"devkit_status"]) return [self status];
        if ([name isEqualToString:@"devkit_log"]) return [self logWithArgs:args];
        if ([name isEqualToString:@"panel_open"]) { FKRunOnMain(^{ [[FKPanel sharedPanel] show]; }); return FKOk(@{ @"panel": @"open" }); }
        if ([name isEqualToString:@"panel_close"]) { FKRunOnMain(^{ [[FKPanel sharedPanel] hide]; }); return FKOk(@{ @"panel": @"closed" }); }
        if ([name isEqualToString:@"server_start"]) return [self serverStart:args];
        if ([name isEqualToString:@"server_stop"]) { [[FKHTTPServer sharedServer] stop]; return FKOk(@{ @"running": @NO }); }
        if ([name isEqualToString:@"server_log"]) return [self serverLog:args];
        if ([name isEqualToString:@"devkit_selftest"]) return [self selfTest];

        NSDictionary *unityResult = [FKUnityTools callTool:name arguments:args];
        if (unityResult) return unityResult;
        NSDictionary *shellResult = [FKShellTools callTool:name arguments:args];
        if (shellResult) return shellResult;

        return FKFail([NSString stringWithFormat:@"unknown tool %@", name]);
    } @catch (NSException *exception) {
        FKLog(@"tool %@ threw %@: %@", name, exception.name, exception.reason);
        return FKFail([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]);
    }
}

#pragma mark - Filesystem

+ (NSDictionary *)fsRoots { return FKOk(@{ @"roots": FKRoots() }); }

+ (NSDictionary *)fsList:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path") ?: FKContainerPath());
    NSError *error = nil;
    NSArray *entries = FKDirectoryList(path, FKBoolArg(args, @"include_hidden", NO), &error);
    if (error) return FKFail(error.localizedDescription);
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    return FKOk(@{ @"path": path, @"count": @(entries.count), @"entries": entries,
                   @"writable": @([[NSFileManager defaultManager] isWritableFileAtPath:path]),
                   @"exists": @(exists) });
}

+ (NSDictionary *)fsStat:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    return FKOk(@{ @"stat": FKFileAttributes(path) });
}

+ (NSDictionary *)fsRead:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    NSError *error = nil;
    NSData *data = FKReadData(path, &error);
    if (!data) return FKFail(error.localizedDescription ?: @"cannot read");
    NSUInteger offset = (NSUInteger)MAX(0, FKIntArg(args, @"offset", 0));
    NSUInteger length = (NSUInteger)MAX(0, FKIntArg(args, @"length", 1024 * 1024));
    if (offset > data.length) offset = data.length;
    length = MIN(length, data.length - offset);
    NSData *slice = [data subdataWithRange:NSMakeRange(offset, length)];
    BOOL base64 = [[FKStringArg(args, @"encoding") lowercaseString] isEqualToString:@"base64"];
    NSMutableDictionary *result = [@{
        @"path": path, @"size": @(data.length), @"offset": @(offset), @"returned": @(slice.length),
        @"truncated": @(offset + length < data.length), @"encoding": base64 ? @"base64" : @"utf8",
    } mutableCopy];
    if (base64) {
        result[@"content"] = [slice base64EncodedStringWithOptions:0];
    } else {
        NSString *text = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
        if (!text) {
            result[@"encoding"] = @"base64";
            result[@"content"] = [slice base64EncodedStringWithOptions:0];
            result[@"note"] = @"not valid UTF-8; returned base64";
        } else {
            result[@"content"] = text;
        }
    }
    return FKOk(result);
}

+ (NSDictionary *)fsWrite:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    NSString *content = FKStringArg(args, @"content");
    if (!path.length) return FKFail(@"path required");
    if (content == nil) return FKFail(@"content required");
    BOOL base64 = [[FKStringArg(args, @"encoding") lowercaseString] isEqualToString:@"base64"];
    NSData *payload = base64 ? [[NSData alloc] initWithBase64EncodedString:content options:0]
                             : [content dataUsingEncoding:NSUTF8StringEncoding];
    if (!payload) return FKFail(@"invalid payload");
    BOOL append = FKBoolArg(args, @"append", NO);
    BOOL success = NO;
    NSError *error = nil;
    if (append && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            @try {
                [handle seekToEndOfFile];
                [handle writeData:payload];
                [handle closeFile];
                success = YES;
            } @catch (NSException *exception) {
                return FKFail(exception.reason ?: @"append failed");
            }
        }
    } else {
        success = FKWriteDataAtomically(payload, path, &error);
    }
    if (!success) return FKFail(error.localizedDescription ?: @"write failed");
    return FKOk(@{ @"path": path, @"bytes": @(payload.length), @"appended": @(append) });
}

+ (NSDictionary *)fsMkdir:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                   withIntermediateDirectories:FKBoolArg(args, @"intermediates", YES)
                                                    attributes:nil
                                                         error:&error]) {
        return FKFail(error.localizedDescription ?: @"mkdir failed");
    }
    return FKOk(@{ @"path": path });
}

+ (NSDictionary *)fsDelete:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    if (!path.length) return FKFail(@"path required");
    BOOL directory = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path isDirectory:&directory]) return FKFail(@"path does not exist");
    if (directory && !FKBoolArg(args, @"recursive", NO)) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:path error:nil];
        if (contents.count) return FKFail(@"directory not empty; pass recursive=true");
    }
    NSError *error = nil;
    if (![fm removeItemAtPath:path error:&error]) return FKFail(error.localizedDescription ?: @"delete failed");
    return FKOk(@{ @"path": path, @"deleted": @YES });
}

+ (NSDictionary *)fsMove:(NSDictionary *)args copy:(BOOL)copy {
    NSString *from = FKExpandPath(FKStringArg(args, @"from"));
    NSString *to = FKExpandPath(FKStringArg(args, @"to"));
    if (!from.length || !to.length) return FKFail(@"from and to are required");
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:from]) return FKFail(@"source does not exist");
    if (!FKBoolArg(args, @"overwrite", NO) && [fm fileExistsAtPath:to]) return FKFail(@"destination exists");
    NSError *error = nil;
    [fm createDirectoryAtPath:[to stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = copy ? [fm copyItemAtPath:from toPath:to error:&error] : [fm moveItemAtPath:from toPath:to error:&error];
    if (!ok) return FKFail(error.localizedDescription ?: @"operation failed");
    return FKOk(@{ @"from": from, @"to": to, @"operation": copy ? @"copy" : @"move" });
}

+ (NSDictionary *)fsSearch:(NSDictionary *)args {
    NSString *root = FKExpandPath(FKStringArg(args, @"path"));
    if (!root.length) return FKFail(@"path required");
    NSString *namePattern = [FKStringArg(args, @"name") lowercaseString];
    NSString *contains = FKStringArg(args, @"contains");
    NSInteger maxResults = MAX(1, MIN(FKIntArg(args, @"max_results", 200), 2000));
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSString *> *enumerator = [fm enumeratorAtPath:root];
    NSMutableArray *results = [NSMutableArray array];
    for (NSString *relative in enumerator) {
        if (results.count >= (NSUInteger)maxResults) break;
        NSString *full = [root stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        [fm fileExistsAtPath:full isDirectory:&isDirectory];
        NSString *name = full.lastPathComponent;
        BOOL nameMatch = !namePattern.length || [name.lowercaseString rangeOfString:namePattern].location != NSNotFound;
        BOOL contentMatch = NO;
        if (contains.length && !isDirectory) {
            NSDictionary *attributes = [fm attributesOfItemAtPath:full error:nil];
            if ([attributes[NSFileSize] unsignedLongLongValue] < 2 * 1024 * 1024) {
                NSData *data = [NSData dataWithContentsOfFile:full];
                NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                contentMatch = text && [text rangeOfString:contains options:NSCaseInsensitiveSearch].location != NSNotFound;
            }
        }
        if ((nameMatch && (!contains.length || contentMatch)) || (contains.length && contentMatch)) {
            [results addObject:@{ @"path": full, @"name": name, @"directory": @(isDirectory),
                                  @"match": contentMatch ? @"content" : @"name" }];
        }
    }
    return FKOk(@{ @"root": root, @"count": @(results.count), @"results": results });
}

+ (NSDictionary *)fsChmod:(NSDictionary *)args {
    NSString *path = FKExpandPath(FKStringArg(args, @"path"));
    NSString *modeString = FKStringArg(args, @"mode");
    if (!path.length || !modeString.length) return FKFail(@"path and mode required");
    unsigned long mode = strtoul(modeString.UTF8String, NULL, 8);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(mode) }
                                         ofItemAtPath:path error:&error])
        return FKFail(error.localizedDescription ?: @"chmod failed");
    return FKOk(@{ @"path": path, @"mode": modeString });
}

+ (NSDictionary *)fsZip:(NSDictionary *)args {
    NSString *destination = FKExpandPath(FKStringArg(args, @"destination"));
    id sources = args[@"sources"];
    if (!destination.length || ![sources isKindOfClass:[NSArray class]]) return FKFail(@"destination and sources required");
    NSError *error = nil;
    if (![FKZip createArchiveAtPath:destination fromPaths:sources error:&error])
        return FKFail(error.localizedDescription ?: @"zip failed");
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:destination error:nil][NSFileSize] unsignedLongLongValue];
    return FKOk(@{ @"archive": destination, @"bytes": @(size) });
}

+ (NSDictionary *)fsUnzip:(NSDictionary *)args {
    NSString *archive = FKExpandPath(FKStringArg(args, @"archive"));
    NSString *destination = FKExpandPath(FKStringArg(args, @"destination"));
    if (!archive.length || !destination.length) return FKFail(@"archive and destination required");
    NSError *error = nil;
    if (![FKZip extractArchiveAtPath:archive toDirectory:destination error:&error])
        return FKFail(error.localizedDescription ?: @"unzip failed");
    return FKOk(@{ @"archive": archive, @"destination": destination });
}

+ (NSDictionary *)fsZipList:(NSDictionary *)args {
    NSString *archive = FKExpandPath(FKStringArg(args, @"archive"));
    if (!archive.length) return FKFail(@"archive required");
    NSError *error = nil;
    NSArray *entries = [FKZip listArchiveAtPath:archive error:&error];
    if (!entries.count && error) return FKFail(error.localizedDescription);
    return FKOk(@{ @"archive": archive, @"entries": entries });
}

@end
