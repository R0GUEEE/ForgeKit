//
//  FKRuntimeTools.m — MCP surface for the native ObjC/memory/hook toolkit
//

#import "ForgeKit.h"
#import "FKRuntimeKit.h"
#import "FKToolsPrivate.h"

@implementation FKRuntimeTools

+ (NSArray<NSDictionary *> *)definitions {
    NSDictionary *(^str)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"string", @"description": description };
    };
    NSDictionary *(^num)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"integer", @"description": description };
    };
    return @[
        @{ @"name": @"objc_heap", @"description":
               @"Enumerate live Objective-C objects from the malloc heap (FLEX-style), optionally filtered by class.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"class": str(@"Optional exact class name (subclasses included)."),
                                                @"limit": num(@"Default 200.") },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"objc_object", @"description":
               @"Inspect an object by pointer: class chain, size, description and every ivar in the chain.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"object": str(@"Object pointer (decimal or 0x...)."),
                                                @"depth": num(@"Superclass levels to walk, default 4.") },
                              @"required": @[@"object"], @"additionalProperties": @NO } },
        @{ @"name": @"objc_call", @"description":
               @"Invoke an Objective-C method with primitive/string/object arguments and return its result.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"class": str(@"Class name."),
                                                @"selector": str(@"Selector, e.g. setHidden:."),
                                                @"object": str(@"Instance pointer, or omit for class methods."),
                                                @"class_method": @{ @"type": @"boolean" },
                                                @"args": @{ @"type": @"array", @"items": @{} } },
                              @"required": @[@"class", @"selector"], @"additionalProperties": @NO } },
        @{ @"name": @"objc_ivar_get", @"description": @"Read one ivar from a live object.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"object": str(@"Object pointer."), @"name": str(@"Ivar name.") },
                              @"required": @[@"object", @"name"], @"additionalProperties": @NO } },
        @{ @"name": @"objc_ivar_set", @"description": @"Write one ivar on a live object.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"object": str(@"Object pointer."), @"name": str(@"Ivar name."),
                                                @"value": @{ @"description": @"New value." } },
                              @"required": @[@"object", @"name", @"value"], @"additionalProperties": @NO } },
        @{ @"name": @"view_highlight", @"description": @"Flash a red outline over a screen rectangle.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"x": @{ @"type": @"number" }, @"y": @{ @"type": @"number" },
                                                @"width": @{ @"type": @"number" }, @"height": @{ @"type": @"number" },
                                                @"seconds": @{ @"type": @"number", @"description": @"Default 2." } },
                              @"required": @[@"x", @"y", @"width", @"height"], @"additionalProperties": @NO } },
        @{ @"name": @"mem_modules", @"description": @"List loaded Mach-O images with base, slide and size.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"mem_read", @"description": @"Read process memory (base64 + hex dump).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"address": str(@"Decimal or 0x hex."), @"length": num(@"Default 64, max 1 MiB.") },
                              @"required": @[@"address"], @"additionalProperties": @NO } },
        @{ @"name": @"mem_write", @"description": @"Write base64 bytes to process memory.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"address": str(@"Decimal or 0x hex."), @"base64": str(@"Payload.") },
                              @"required": @[@"address", @"base64"], @"additionalProperties": @NO } },
        @{ @"name": @"mem_scan", @"description":
               @"Scan a module (or all modules) for a UTF-8 string or hex byte pattern with ?? wildcards.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"pattern": str(@"Text or hex, e.g. 48 65 6c ?? 6f."),
                                                @"module": str(@"Optional module name substring."),
                                                @"limit": num(@"Default 50.") },
                              @"required": @[@"pattern"], @"additionalProperties": @NO } },
        @{ @"name": @"mem_exports", @"description": @"List exported symbols of a module.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"module": str(@"Module name substring."),
                                                @"filter": str(@"Optional symbol substring."),
                                                @"limit": num(@"Default 200.") },
                              @"required": @[@"module"], @"additionalProperties": @NO } },
        @{ @"name": @"hook_redirect", @"description":
               @"Patch a function's entry to jump to another function (saved and restorable).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"source": str(@"Symbol name or 0x address."),
                                                @"destination": str(@"Symbol name or 0x address.") },
                              @"required": @[@"source", @"destination"], @"additionalProperties": @NO } },
        @{ @"name": @"hook_restore", @"description": @"Restore a redirected function to its original bytes.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"source": str(@"Original symbol name.") },
                              @"required": @[@"source"], @"additionalProperties": @NO } },
        @{ @"name": @"hook_list", @"description": @"List active function hooks.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"net_history", @"description":
               @"Captured NSURLSession traffic (URL, status, timing, headers, body preview).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"limit": num(@"Default 100.") },
                              @"required": @[], @"additionalProperties": @NO } },
        @{ @"name": @"net_clear", @"description": @"Clear captured traffic.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"net_capture", @"description": @"Enable/disable traffic capture.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"enabled": @{ @"type": @"boolean" } },
                              @"required": @[], @"additionalProperties": @NO } },
    ];
}

static unsigned long long FKPointerArg(NSDictionary *args, NSString *key) {
    id value = args[key];
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return 0;
    return strtoull([[value description] UTF8String], NULL, 0);
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    if ([name isEqualToString:@"objc_heap"])
        return [FKRuntimeKit heapObjectsOfClass:args[@"class"] limit:[args[@"limit"] integerValue] ?: 200];
    if ([name isEqualToString:@"objc_object"])
        return [FKRuntimeKit objectInfo:FKPointerArg(args, @"object")
                                 depth:[args[@"depth"] integerValue] ?: 4];
    if ([name isEqualToString:@"objc_call"])
        return [FKRuntimeKit callClass:args[@"class"] ?: @"" selector:args[@"selector"] ?: @""
                                object:FKPointerArg(args, @"object")
                           classMethod:[args[@"class_method"] boolValue]
                                  args:args[@"args"] ?: @[]];
    if ([name isEqualToString:@"objc_ivar_get"])
        return [FKRuntimeKit getIvar:args[@"name"] ?: @"" object:FKPointerArg(args, @"object")];
    if ([name isEqualToString:@"objc_ivar_set"])
        return [FKRuntimeKit setIvar:args[@"name"] ?: @"" object:FKPointerArg(args, @"object")
                               value:args[@"value"]];
    if ([name isEqualToString:@"view_highlight"]) {
        CGRect rect = CGRectMake([args[@"x"] doubleValue], [args[@"y"] doubleValue],
                                 [args[@"width"] doubleValue], [args[@"height"] doubleValue]);
        return [FKRuntimeKit highlightRect:rect duration:[args[@"seconds"] doubleValue] ?: 2.0];
    }
    if ([name isEqualToString:@"mem_modules"])
        return @{ @"ok": @YES, @"modules": [FKRuntimeKit modules] };
    if ([name isEqualToString:@"mem_read"])
        return [FKRuntimeKit readMemory:FKPointerArg(args, @"address")
                                 length:[args[@"length"] integerValue] ?: 64];
    if ([name isEqualToString:@"mem_write"])
        return [FKRuntimeKit writeMemory:FKPointerArg(args, @"address") base64:args[@"base64"] ?: @""];
    if ([name isEqualToString:@"mem_scan"])
        return [FKRuntimeKit scanMemory:args[@"pattern"] ?: @"" module:args[@"module"]
                                  limit:[args[@"limit"] integerValue] ?: 50];
    if ([name isEqualToString:@"mem_exports"])
        return @{ @"ok": @YES, @"exports": [FKRuntimeKit exportsOfModule:args[@"module"] ?: @""
                                                                  filter:args[@"filter"]
                                                                   limit:[args[@"limit"] integerValue] ?: 200] };
    if ([name isEqualToString:@"hook_redirect"])
        return [FKRuntimeKit redirectSymbol:args[@"source"] ?: @"" to:args[@"destination"] ?: @""];
    if ([name isEqualToString:@"hook_restore"])
        return [FKRuntimeKit restoreSymbol:args[@"source"] ?: @""];
    if ([name isEqualToString:@"hook_list"])
        return @{ @"ok": @YES, @"hooks": [FKRuntimeKit activeHooks] };
    if ([name isEqualToString:@"net_history"])
        return [FKRuntimeKit networkHistory:[args[@"limit"] integerValue] ?: 100];
    if ([name isEqualToString:@"net_clear"]) {
        [FKRuntimeKit clearNetworkHistory];
        return @{ @"ok": @YES, @"cleared": @YES };
    }
    if ([name isEqualToString:@"net_capture"]) {
        if ([args[@"enabled"] respondsToSelector:@selector(boolValue)])
            [FKPrefs setBool:[args[@"enabled"] boolValue] forKey:@"netCapture"];
        return @{ @"ok": @YES, @"enabled": @([FKPrefs boolForKey:@"netCapture" defaultValue:YES]) };
    }
    return nil;
}

@end
