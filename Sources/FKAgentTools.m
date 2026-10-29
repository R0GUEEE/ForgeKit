//
//  FKAgentTools.m — MCP surface for the agent and tweak scaffolding
//

#import "FKAgent.h"
#import "FKToolsPrivate.h"
#import <spawn.h>
#import <sys/wait.h>
#import <errno.h>
#import <string.h>

extern char **environ;

@implementation FKAgentTools

+ (NSArray<NSDictionary *> *)definitions {
    NSDictionary *(^str)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"string", @"description": description };
    };
    NSDictionary *(^boolean)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"boolean", @"description": description };
    };
    return @[
        @{ @"name": @"agent_ask", @"description":
               @"Ask the on-device build agent. It can inspect the app, edit files, hook methods "
               @"and scaffold tweak projects through ForgeKit tools.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"prompt": str(@"What to build or change."),
                                                @"timeout": @{ @"type": @"number", @"description": @"Seconds, default 120." } },
                              @"required": @[@"prompt"], @"additionalProperties": @NO } },
        @{ @"name": @"agent_config", @"description":
               @"Read or change agent settings (endpoint, model, API key, mutation policy).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"endpoint": str(@"Full chat-completions URL; bare hosts and /v1 are normalised."),
                                                @"model": str(@"Model name."),
                                                @"api_key": str(@"Stored in the keychain; empty string clears it."),
                                                @"allow_mutations": boolean(@"Permit write/patch/hook tools."),
                                                @"max_steps": @{ @"type": @"integer", @"description": @"1-24 tool rounds." },
                                                @"temperature": @{ @"type": @"number", @"description": @"0-2." },
                                                @"max_tokens": @{ @"type": @"integer", @"description": @"0 = provider default." },
                                                @"tool_mode": @{ @"type": @"string", @"enum": @[@"auto", @"none", @"required"] },
                                                @"tool_profile": @{ @"type": @"string", @"enum": @[@"all", @"safe", @"custom"] },
                                                @"enabled_tools": @{ @"type": @"array", @"items": @{ @"type": @"string" } },
                                                @"extra_headers": @{ @"type": @"object", @"description": @"Gateway headers, string values." },
                                                @"system_instructions": str(@"Extra operator instructions appended to the system prompt."),
                                                @"max_result_chars": @{ @"type": @"integer", @"description": @"Tool result truncation, 1000-200000." },
                                                @"context_messages": @{ @"type": @"integer", @"description": @"History messages kept per request." },
                                                @"timeout": @{ @"type": @"number", @"description": @"Request timeout in seconds." },
                                                @"theos_path": str(@"Theos install used by devkit_build.") },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"devkit_build", @"description":
               @"Scaffold a Theos dylib project from Objective-C source (Makefile, control, filter "
               @"plist) and compile it when a local toolchain is available.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"name": str(@"Project and dylib name."),
                                                @"source": str(@"Complete Objective-C source."),
                                                @"files": @{ @"type": @"object", @"description": @"Extra files: relative path -> text content." },
                                                @"filter": str(@"Bundle identifier for the filter plist."),
                                                @"compile": boolean(@"Try to build with Theos after writing.") },
                              @"required": @[@"name", @"source"], @"additionalProperties": @NO } },
        @{ @"name": @"agent_tools", @"description":
               @"List tools the agent can call, with read-only/mutating grouping and whether the current profile enables them.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"agent_stop", @"description": @"Cancel the agent request that is currently running.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"agent_transcript", @"description": @"Return the current agent conversation as JSON, or write it to a file.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"path": str(@"Optional destination file.") },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"devkit_projects", @"description": @"List scaffolded projects and their build state.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"devkit_project", @"description":
               @"Inspect or edit a scaffolded project: list files, read, write, delete.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"name": str(@"Project name."),
                                                @"action": @{ @"type": @"string", @"enum": @[@"list", @"read", @"write", @"delete"] },
                                                @"path": str(@"Path relative to the project root."),
                                                @"content": str(@"Content for write.") },
                              @"required": @[@"name", @"action"], @"additionalProperties": @NO } },
    ];
}

+ (NSString *)projectsDirectory {
    return [FKDocumentsPath() stringByAppendingPathComponent:@"ForgeKit/projects"];
}

+ (NSString *)sanitizedName:(NSString *)name {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
            [result appendFormat:@"%C", c];
        } else if (result.length && ![result hasSuffix:@"_"]) {
            [result appendString:@"_"];
        }
        if (result.length >= 48) break;
    }
    if (!result.length) result = [@"Tweak" mutableCopy];
    if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[result characterAtIndex:0]])
        [result insertString:@"T" atIndex:0];
    return result;
}

+ (NSDictionary *)writeProjectNamed:(NSString *)rawName source:(NSString *)source filter:(NSString *)filter {
    NSString *name = [self sanitizedName:rawName ?: @"Tweak"];
    NSString *root = [[self projectsDirectory] stringByAppendingPathComponent:name];
    NSString *sourcesDir = [root stringByAppendingPathComponent:@"Sources"];
    NSString *plistDir = [root stringByAppendingPathComponent:@"Layout/Library/MobileSubstrate/DynamicLibraries"];
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *directory in @[sourcesDir, plistDir]) {
        if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error])
            return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"cannot create project" };
    }

    NSString *makefile = [NSString stringWithFormat:
        @"# %@ — generated by ForgeKit\ntarget_arch := arm64\n"
        @"TARGET := iphone:clang:16.5:14.0\nARCHS = arm64\n\n"
        @"include $(THEOS)/makefiles/common.mk\n\n"
        @"LIBRARY_NAME = %@\n%@_FILES = Sources/%@.m\n"
        @"%@_CFLAGS = -fobjc-arc -fblocks\n"
        @"%@_FRAMEWORKS = Foundation UIKit\n"
        @"%@_LIBRARIES = \n"
        @"%@_INSTALL_PATH = /usr/lib\n\n"
        @"include $(THEOS_MAKE_PATH)/library.mk\n",
        name, name, name, name, name, name, name, name];

    NSString *control = [NSString stringWithFormat:
        @"Package: com.forgekit.%@\nName: %@\nVersion: 1.0.0\n"
        @"Architecture: iphoneos-arm64\nDescription: Generated by ForgeKit agent\n"
        @"Maintainer: ForgeKit\nAuthor: ForgeKit\nSection: Tweaks\nDepends: firmware (>= 14.0)\n",
        name.lowercaseString, name];

    NSString *plist = [NSString stringWithFormat:
        @"{\n    Filter = {\n        Bundles = (\n            \"%@\"\n        );\n    };\n}\n",
        filter.length ? filter : @"com.apple.springboard"];

    NSDictionary *files = @{
        [root stringByAppendingPathComponent:@"Makefile"]: makefile,
        [root stringByAppendingPathComponent:@"control"]: control,
        [plistDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]]: plist,
        [sourcesDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m"]]: source ?: @"",
    };
    for (NSString *path in files) {
        if (![files[path] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error])
            return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"cannot write project file",
                      @"path": path };
    }
    return @{ @"ok": @YES, @"name": name, @"project": root,
              @"source": [sourcesDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m"]],
              @"plist": [plistDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]] };
}

+ (NSDictionary *)buildProject:(NSString *)name source:(NSString *)source
                        filter:(NSString *)filter compile:(BOOL)compile {
    if (!source.length) return @{ @"ok": @NO, @"error": @"source required" };
    NSDictionary *written = [self writeProjectNamed:name source:source filter:filter];
    if (![written[@"ok"] boolValue]) return written;
    NSString *root = written[@"project"];

    if (!compile) {
        return [written mutableCopy] ?: written;
    }

    NSString *theos = [FKPrefs stringForKey:@"theosPath" defaultValue:@"/opt/theos"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:theos]) {
        NSMutableDictionary *result = [written mutableCopy];
        result[@"compiled"] = @NO;
        result[@"note"] = [NSString stringWithFormat:
                           @"Project written to %@. Set theosPath (agent_config or Settings) to a "
                           @"Theos install, then build with: THEOS=%@ make -C %@ TARGET=iphone:clang:16.5:14.0 ARCHS=arm64",
                           root, theos, root];
        return result;
    }

    NSString *command = [NSString stringWithFormat:
                         @"cd '%@' && THEOS='%@' PATH='%@/toolchain/linux/iphone/bin:/usr/bin:/bin:/usr/sbin:/sbin' "
                         @"make TARGET=iphone:clang:16.5:14.0 ARCHS=arm64 DEBUG=0 OPTFLAG=-O0 -j1 2>&1",
                         root, theos, theos];
    pid_t pid = 0;
    const char *argv[] = { "/bin/sh", "-c", command.UTF8String, NULL };
    int status = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)argv, environ);
    NSMutableDictionary *result = [written mutableCopy];
    if (status != 0) {
        result[@"compiled"] = @NO;
        result[@"error"] = [NSString stringWithFormat:@"cannot run the toolchain here (%s); project is at %@",
                            strerror(status), root];
        return result;
    }
    int waitStatus = 0;
    waitpid(pid, &waitStatus, 0);
    BOOL success = WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0;
    result[@"compiled"] = @(success);
    result[@"exit_status"] = @(WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1);
    NSString *dylib = [[root stringByAppendingPathComponent:@".theos/obj/arm64"]
                       stringByAppendingPathComponent:[written[@"name"] stringByAppendingPathExtension:@"dylib"]];
    if ([fm fileExistsAtPath:dylib]) result[@"dylib"] = dylib;
    if (!success) result[@"note"] = @"Build failed; check that the Theos toolchain is reachable from this process.";
    return result;
}

+ (BOOL)safeRelativePath:(NSString *)path {
    if (!path.length || [path hasPrefix:@"/"] || [path containsString:@".."]) return NO;
    return YES;
}

+ (NSDictionary *)writeFiles:(NSDictionary *)files intoRoot:(NSString *)root {
    if (![files isKindOfClass:[NSDictionary class]] || !files.count) return @{ @"ok": @YES, @"written": @[] };
    NSMutableArray *written = [NSMutableArray array];
    for (NSString *relative in files) {
        NSString *content = files[relative];
        if (![relative isKindOfClass:[NSString class]] || ![content isKindOfClass:[NSString class]]) continue;
        if (![self safeRelativePath:relative]) continue;
        NSString *destination = [root stringByAppendingPathComponent:relative];
        [[NSFileManager defaultManager] createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        if ([content writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:nil])
            [written addObject:relative];
    }
    return @{ @"ok": @YES, @"written": written };
}

+ (NSDictionary *)projectNamed:(NSString *)name action:(NSString *)action
                          path:(NSString *)path content:(NSString *)content {
    if (!name.length) return @{ @"ok": @NO, @"error": @"name required" };
    NSString *root = [[self projectsDirectory] stringByAppendingPathComponent:[self sanitizedName:name]];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory)
        return @{ @"ok": @NO, @"error": @"project not found", @"name": name };
    NSString *verb = [action lowercaseString] ?: @"list";
    if ([verb isEqualToString:@"list"]) {
        NSMutableArray *files = [NSMutableArray array];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:root];
        for (NSString *relative in enumerator) {
            if ([relative hasPrefix:@".theos"]) continue;
            [files addObject:relative];
            if (files.count >= 500) break;
        }
        return @{ @"ok": @YES, @"project": root, @"files": files };
    }
    if (![self safeRelativePath:path]) return @{ @"ok": @NO, @"error": @"invalid relative path" };
    NSString *destination = [root stringByAppendingPathComponent:path];
    if ([verb isEqualToString:@"read"]) {
        NSString *text = [NSString stringWithContentsOfFile:destination encoding:NSUTF8StringEncoding error:nil];
        if (!text) return @{ @"ok": @NO, @"error": @"cannot read file", @"path": destination };
        return @{ @"ok": @YES, @"path": destination, @"content": text };
    }
    if ([verb isEqualToString:@"write"]) {
        if (![content isKindOfClass:[NSString class]]) return @{ @"ok": @NO, @"error": @"content required" };
        [[NSFileManager defaultManager] createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL written = [content writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return @{ @"ok": @(written), @"path": destination, @"error": written ? [NSNull null] : @"write failed" };
    }
    if ([verb isEqualToString:@"delete"]) {
        NSError *error = nil;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:destination error:&error];
        return @{ @"ok": @(removed), @"path": destination,
                  @"error": removed ? [NSNull null] : (error.localizedDescription ?: @"delete failed") };
    }
    return @{ @"ok": @NO, @"error": @"unknown action" };
}

+ (NSArray<NSDictionary *> *)projects {
    NSMutableArray *projects = [NSMutableArray array];
    NSString *root = [self projectsDirectory];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) continue;
        NSString *dylib = [[path stringByAppendingPathComponent:@".theos/obj/arm64"]
                           stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"dylib"]];
        [projects addObject:@{ @"name": name, @"path": path,
                               @"built": @([[NSFileManager defaultManager] fileExistsAtPath:dylib]),
                               @"dylib": dylib }];
    }
    return projects;
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    if ([name isEqualToString:@"agent_ask"]) {
        NSString *prompt = args[@"prompt"];
        if (![prompt isKindOfClass:[NSString class]] || !prompt.length)
            return @{ @"ok": @NO, @"error": @"prompt required" };
        NSTimeInterval timeout = [args[@"timeout"] doubleValue] > 0 ? [args[@"timeout"] doubleValue] : 120;
        return [[FKAgent sharedAgent] runPromptSynchronously:prompt timeout:timeout];
    }
    if ([name isEqualToString:@"agent_config"]) {
        FKAgent *agent = [FKAgent sharedAgent];
        if ([args[@"endpoint"] isKindOfClass:[NSString class]]) agent.endpoint = args[@"endpoint"];
        if ([args[@"model"] isKindOfClass:[NSString class]]) agent.model = args[@"model"];
        if ([args[@"api_key"] isKindOfClass:[NSString class]]) [FKAgent setAPIKey:args[@"api_key"]];
        if ([args[@"allow_mutations"] respondsToSelector:@selector(boolValue)])
            agent.allowMutations = [args[@"allow_mutations"] boolValue];
        if ([args[@"max_steps"] respondsToSelector:@selector(integerValue)])
            agent.maxSteps = [args[@"max_steps"] integerValue];
        if ([args[@"temperature"] respondsToSelector:@selector(doubleValue)])
            agent.temperature = [args[@"temperature"] doubleValue];
        if ([args[@"max_tokens"] respondsToSelector:@selector(integerValue)])
            agent.maxTokens = [args[@"max_tokens"] integerValue];
        if ([args[@"tool_mode"] isKindOfClass:[NSString class]]) agent.toolMode = args[@"tool_mode"];
        if ([args[@"tool_profile"] isKindOfClass:[NSString class]]) agent.toolProfile = args[@"tool_profile"];
        if ([args[@"enabled_tools"] isKindOfClass:[NSArray class]]) agent.enabledTools = args[@"enabled_tools"];
        if ([args[@"extra_headers"] isKindOfClass:[NSDictionary class]]) agent.extraHeaders = args[@"extra_headers"];
        if ([args[@"system_instructions"] isKindOfClass:[NSString class]]) agent.systemInstructions = args[@"system_instructions"];
        if ([args[@"max_result_chars"] respondsToSelector:@selector(integerValue)])
            agent.maxToolResultChars = [args[@"max_result_chars"] integerValue];
        if ([args[@"context_messages"] respondsToSelector:@selector(integerValue)])
            agent.contextMessages = [args[@"context_messages"] integerValue];
        if ([args[@"timeout"] respondsToSelector:@selector(doubleValue)])
            agent.requestTimeout = [args[@"timeout"] doubleValue];
        if ([args[@"theos_path"] isKindOfClass:[NSString class]])
            [FKPrefs setString:args[@"theos_path"] forKey:@"theosPath"];
        NSString *key = [FKAgent apiKey];
        return @{ @"ok": @YES,
                  @"endpoint": agent.endpoint ?: @"",
                  @"model": agent.model ?: @"",
                  @"api_key_set": @(key.length > 0),
                  @"api_key_hint": key.length > 4 ? [NSString stringWithFormat:@"…%@", [key substringFromIndex:key.length - 4]] : @"",
                  @"allow_mutations": @(agent.allowMutations),
                  @"max_steps": @(agent.maxSteps),
                  @"temperature": @(agent.temperature),
                  @"max_tokens": @(agent.maxTokens),
                  @"tool_mode": agent.toolMode ?: @"auto",
                  @"tool_profile": agent.toolProfile ?: @"all",
                  @"enabled_tools": agent.enabledTools ?: @[],
                  @"extra_headers": agent.extraHeaders ?: @{},
                  @"system_instructions": agent.systemInstructions ?: @"",
                  @"max_result_chars": @(agent.maxToolResultChars),
                  @"context_messages": @(agent.contextMessages),
                  @"timeout": @(agent.requestTimeout),
                  @"last_usage": agent.lastUsage,
                  @"theos_path": [FKPrefs stringForKey:@"theosPath" defaultValue:@"/opt/theos"] };
    }
    if ([name isEqualToString:@"devkit_build"]) {
        NSMutableDictionary *result = [[self buildProject:args[@"name"] source:args[@"source"]
                                                   filter:args[@"filter"]
                                                  compile:[args[@"compile"] boolValue]] mutableCopy];
        if ([result[@"ok"] boolValue] && [args[@"files"] isKindOfClass:[NSDictionary class]]) {
            NSDictionary *extra = [self writeFiles:args[@"files"] intoRoot:result[@"project"]];
            result[@"extra_files"] = extra[@"written"] ?: @[];
        }
        return result;
    }
    if ([name isEqualToString:@"agent_tools"])
        return @{ @"ok": @YES, @"tools": [[FKAgent sharedAgent] availableTools] };
    if ([name isEqualToString:@"agent_stop"]) {
        [[FKAgent sharedAgent] stop];
        return @{ @"ok": @YES, @"stopped": @YES };
    }
    if ([name isEqualToString:@"agent_transcript"]) {
        NSArray *transcript = [[FKAgent sharedAgent] transcript];
        NSString *path = args[@"path"];
        if ([path isKindOfClass:[NSString class]] && path.length) {
            NSString *destination = FKExpandPath(path);
            NSData *data = [NSJSONSerialization dataWithJSONObject:transcript
                                                           options:NSJSONWritingPrettyPrinted error:nil];
            BOOL written = [data writeToFile:destination atomically:YES];
            return @{ @"ok": @(written), @"path": destination, @"messages": @(transcript.count),
                      @"error": written ? [NSNull null] : @"cannot write transcript" };
        }
        return @{ @"ok": @YES, @"messages": @(transcript.count), @"transcript": transcript };
    }
    if ([name isEqualToString:@"devkit_projects"])
        return @{ @"ok": @YES, @"projects": [self projects] };
    if ([name isEqualToString:@"devkit_project"])
        return [self projectNamed:args[@"name"] action:args[@"action"] path:args[@"path"] content:args[@"content"]];
    return nil;
}

@end
