//
//  FKMCP.m — MCP (Model Context Protocol) JSON-RPC 2.0 endpoint
//

#import "ForgeKit.h"

static NSDictionary *FKJSONRPCError(id identifier, NSInteger code, NSString *message) {
    return @{ @"jsonrpc": @"2.0",
              @"id": identifier ?: [NSNull null],
              @"error": @{ @"code": @(code), @"message": message ?: @"error" } };
}

static NSDictionary *FKJSONRPCResult(id identifier, id result) {
    return @{ @"jsonrpc": @"2.0",
              @"id": identifier ?: [NSNull null],
              @"result": result ?: @{} };
}

@implementation FKMCP

+ (NSString *)protocolVersion { return @"2025-06-18"; }

+ (NSArray<NSDictionary *> *)toolDefinitions { return [FKTools toolDefinitions]; }

+ (id)handleJSONRPC:(id)payload authorized:(BOOL)authorized {
    if ([payload isKindOfClass:[NSArray class]]) {
        NSMutableArray *responses = [NSMutableArray array];
        for (id item in (NSArray *)payload) {
            NSDictionary *response = [self handleSingle:item authorized:authorized];
            if (response.count) [responses addObject:response];
        }
        return responses;
    }
    return [self handleSingle:payload authorized:authorized] ?: @{};
}

+ (NSDictionary *)handleSingle:(id)payload authorized:(BOOL)authorized {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return FKJSONRPCError(nil, -32600, @"invalid request");
    }
    NSDictionary *request = payload;
    id identifier = request[@"id"];
    BOOL isNotification = (identifier == nil || identifier == [NSNull null]);
    NSString *method = request[@"method"];
    if (![method isKindOfClass:[NSString class]]) {
        return isNotification ? @{} : FKJSONRPCError(identifier, -32600, @"missing method");
    }
    NSDictionary *params = [request[@"params"] isKindOfClass:[NSDictionary class]] ? request[@"params"] : @{};

    if (!authorized) {
        return isNotification ? @{} : FKJSONRPCError(identifier, -32001, @"unauthorized: bearer token required");
    }

    if ([method isEqualToString:@"initialize"]) {
        NSString *requested = params[@"protocolVersion"];
        NSArray *supported = @[ @"2025-06-18", @"2025-03-26", @"2024-11-05" ];
        NSString *version = [supported containsObject:requested] ? requested : [self protocolVersion];
        return FKJSONRPCResult(identifier, @{
            @"protocolVersion": version,
            @"capabilities": @{
                @"tools": @{ @"listChanged": @NO },
                @"logging": @{},
            },
            @"serverInfo": @{ @"name": @"ForgeKit", @"version": FKVersionString,
                              @"title": @"ForgeKit application development toolkit" },
            @"instructions": @"ForgeKit controls the host iOS application it is injected into. "
                             @"Start with devkit_status, then app_info and fs_roots. File paths accept "
                             @"~, $APP, $CONTAINER, $DOCS, $LIB, $TMP. ui_tree + ui_tap + ui_type drive "
                             @"the host UI; ui_screenshot returns base64 JPEG.",
        });
    }
    if ([method isEqualToString:@"notifications/initialized"] ||
        [method isEqualToString:@"notifications/cancelled"] ||
        [method hasPrefix:@"notifications/"]) {
        return @{};
    }
    if ([method isEqualToString:@"ping"]) return FKJSONRPCResult(identifier, @{});
    if ([method isEqualToString:@"tools/list"]) {
        return FKJSONRPCResult(identifier, @{ @"tools": [FKTools toolDefinitions] });
    }
    if ([method isEqualToString:@"tools/call"]) {
        NSString *name = params[@"name"];
        NSDictionary *arguments = [params[@"arguments"] isKindOfClass:[NSDictionary class]] ? params[@"arguments"] : @{};
        if (![name isKindOfClass:[NSString class]] || !name.length) {
            return FKJSONRPCError(identifier, -32602, @"tools/call requires params.name");
        }
        NSDictionary *result = [FKTools callTool:name arguments:arguments];
        BOOL failed = [result[@"ok"] isKindOfClass:[NSNumber class]] && ![result[@"ok"] boolValue];
        NSString *text = FKJSONString(result, YES);
        NSMutableDictionary *payloadResult = [@{
            @"content": @[ @{ @"type": @"text", @"text": text } ],
            @"isError": @(failed),
        } mutableCopy];
        payloadResult[@"structuredContent"] = FKJSONSafe(result);
        return FKJSONRPCResult(identifier, payloadResult);
    }
    if ([method isEqualToString:@"resources/list"]) {
        return FKJSONRPCResult(identifier, @{ @"resources": @[] });
    }
    if ([method isEqualToString:@"resources/templates/list"]) {
        return FKJSONRPCResult(identifier, @{ @"resourceTemplates": @[] });
    }
    if ([method isEqualToString:@"prompts/list"]) {
        return FKJSONRPCResult(identifier, @{ @"prompts": @[] });
    }
    if ([method isEqualToString:@"logging/setLevel"]) {
        return FKJSONRPCResult(identifier, @{});
    }
    if ([method isEqualToString:@"server/discover"]) {
        return FKJSONRPCResult(identifier, @{ @"serverInfo": @{ @"name": @"ForgeKit", @"version": FKVersionString },
                                              @"protocolVersion": [self protocolVersion] });
    }
    return isNotification ? @{} : FKJSONRPCError(identifier, -32601,
                                                 [NSString stringWithFormat:@"method not found: %@", method]);
}

@end
