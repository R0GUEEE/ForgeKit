//
//  FKAgent.m — OpenAI-compatible chat loop with ForgeKit tools
//

#import "FKAgent.h"
#import <Security/Security.h>

static NSString * const FKAgentKeychainService = @"com.r0guee.forgekit.agent";
static NSString * const FKAgentKeychainAccount = @"api-key";

static id FKAgentJSONValue(NSData *data) {
    if (!data.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSString *FKAgentNormalizedEndpoint(NSString *raw) {
    NSString *value = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!value.length) value = @"https://api.openai.com/v1/chat/completions";
    if (![value.lowercaseString hasPrefix:@"http://"] && ![value.lowercaseString hasPrefix:@"https://"])
        value = [@"https://" stringByAppendingString:value];
    while ([value hasSuffix:@"/"]) value = [value substringToIndex:value.length - 1];
    if ([value rangeOfString:@"chat/completions"].location == NSNotFound) {
        if ([value hasSuffix:@"/v1"]) value = [value stringByAppendingString:@"/chat/completions"];
        else if ([value rangeOfString:@"/v1/"].location != NSNotFound)
            value = [value stringByAppendingString:@"chat/completions"];
        else value = [value stringByAppendingString:@"/v1/chat/completions"];
    }
    return value;
}

static BOOL FKAgentToolMutates(NSString *name) {
    static NSSet *exact;
    static NSArray *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = [NSSet setWithArray:@[@"shell", @"hook_redirect", @"hook_restore",
                                      @"mem_write", @"write_field", @"invoke_method",
                                      @"patch_method", @"restore_patch", @"restore_all",
                                      @"write_player_prefs", @"objc_ivar_set", @"objc_call",
                                      @"panel_open", @"panel_close", @"server_start", @"server_stop",
                                      @"net_clear", @"net_capture", @"web_inspector", @"devkit_build"]];
        prefixes = @[@"fs_write", @"fs_delete", @"fs_move", @"fs_copy", @"fs_mkdir", @"fs_chmod",
                     @"fs_zip", @"fs_unzip", @"ui_", @"net_"];
    });
    if ([exact containsObject:name]) return YES;
    for (NSString *prefix in prefixes) {
        if ([name hasPrefix:prefix]) return YES;
    }
    return NO;
}

@implementation FKAgent {
    NSMutableArray<NSDictionary *> *_history;
    BOOL _toolsDisabled;
    NSLock *_runLock;
    NSMutableArray<NSDictionary *> *_activity;
}

+ (instancetype)sharedAgent {
    static FKAgent *agent;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ agent = [[FKAgent alloc] init]; });
    return agent;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _history = [NSMutableArray array];
        _activity = [NSMutableArray array];
        _runLock = [[NSLock alloc] init];
        _maxSteps = 8;
        _endpoint = FKAgentNormalizedEndpoint([FKPrefs stringForKey:@"agentEndpoint"
                                                            defaultValue:@"https://api.openai.com/v1/chat/completions"]);
        _model = [FKPrefs stringForKey:@"agentModel" defaultValue:@"gpt-4o-mini"];
        _allowMutations = [FKPrefs boolForKey:@"agentAllowMutations" defaultValue:NO];
    }
    return self;
}

#pragma mark - Settings

+ (NSString *)apiKey {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: FKAgentKeychainService,
        (__bridge id)kSecAttrAccount: FKAgentKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return @"";
    NSData *data = CFBridgingRelease(result);
    if (![data isKindOfClass:[NSData class]]) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

+ (void)setAPIKey:(NSString *)key {
    NSString *value = key ?: @"";
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: FKAgentKeychainService,
        (__bridge id)kSecAttrAccount: FKAgentKeychainAccount,
    };
    if (!value.length) {
        SecItemDelete((__bridge CFDictionaryRef)query);
        return;
    }
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *attributes = @{ (__bridge id)kSecValueData: data };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *insert = [query mutableCopy];
        insert[(__bridge id)kSecValueData] = data;
        insert[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        SecItemAdd((__bridge CFDictionaryRef)insert, NULL);
    }
}

- (void)setEndpoint:(NSString *)endpoint {
    _endpoint = FKAgentNormalizedEndpoint(endpoint);
    [FKPrefs setString:_endpoint forKey:@"agentEndpoint"];
}

- (void)setModel:(NSString *)model {
    _model = [model copy];
    [FKPrefs setString:_model forKey:@"agentModel"];
}

- (void)setAllowMutations:(BOOL)allowMutations {
    _allowMutations = allowMutations;
    [FKPrefs setBool:allowMutations forKey:@"agentAllowMutations"];
}

#pragma mark - Conversation

- (void)resetConversation {
    [_runLock lock];
    [_history removeAllObjects];
    [_activity removeAllObjects];
    [_runLock unlock];
}

- (NSArray<NSDictionary *> *)transcript {
    [_runLock lock];
    NSArray *copy = [_history copy];
    [_runLock unlock];
    return copy;
}

- (NSString *)systemPrompt {
    return [NSString stringWithFormat:
            @"You are ForgeKit's on-device build agent running inside %@ (%@) on iOS %@, %@.\n"
            @"You control the host app through tools: filesystem, sandbox shell, Objective-C runtime "
            @"(objc_heap, objc_object, objc_call, objc_ivar_get/set), memory, hooks, HTTP traffic "
            @"capture, Unity/IL2CPP, and the MCP server.\n"
            @"When the user asks for a tweak or a modification:\n"
            @"1. Inspect first (app_info, fs_list, objc_* or shell).\n"
            @"2. Make the smallest change that satisfies the request.\n"
            @"3. For a reusable tweak, call devkit_build with a complete Objective-C source that "
            @"compiles as a dylib (constructor-based, no substrate headers).\n"
            @"4. Verify with a read-back tool call and state exactly what changed.\n"
            @"Mutating tools are %@. If a tool is blocked, explain what setting must be enabled "
            @"instead of retrying.\n"
            @"Keep answers short: what you did, where it is, and how to test it.",
            FKAppName(), FKAppIdentifier(), FKOSVersionString(), FKDeviceModelIdentifier(),
            self.allowMutations ? @"enabled" : @"disabled (read-only mode)"];
}

#pragma mark - HTTP

- (NSArray<NSDictionary *> *)toolDefinitionsForAPI {
    static NSSet *excluded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        excluded = [NSSet setWithArray:@[@"agent_ask", @"agent_config", @"devkit_projects",
                                         @"panel_open", @"panel_close", @"server_start",
                                         @"server_stop", @"server_log", @"devkit_selftest",
                                         @"devkit_log"]];
    });
    NSMutableArray *tools = [NSMutableArray array];
    for (NSDictionary *definition in [FKTools toolDefinitions]) {
        NSString *name = definition[@"name"];
        if (!name.length || [excluded containsObject:name]) continue;
        [tools addObject:@{
            @"type": @"function",
            @"function": @{ @"name": name,
                            @"description": definition[@"description"] ?: @"",
                            @"parameters": definition[@"inputSchema"] ?: @{ @"type": @"object", @"properties": @{} } },
        }];
    }
    return tools;
}

- (NSURLRequest *)requestForMessages:(NSArray *)messages tools:(NSArray *)tools {
    NSMutableDictionary *payload = [@{
        @"model": self.model ?: @"gpt-4o-mini",
        @"messages": messages,
        @"temperature": @0.2,
        @"stream": @NO,
    } mutableCopy];
    if (tools.count && !_toolsDisabled) {
        payload[@"tools"] = tools;
        payload[@"tool_choice"] = @"auto";
    }
    NSError *error = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!body) return nil;
    NSURL *url = [NSURL URLWithString:FKAgentNormalizedEndpoint(self.endpoint)];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 90;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"ForgeKit/2.3.1" forHTTPHeaderField:@"User-Agent"];
    NSString *key = [[FKAgent apiKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = body;
    return request;
}

- (void)step:(NSInteger)step
  completion:(void (^)(NSString *, NSArray<NSDictionary *> *, NSError *))completion {
    if (step >= MAX(1, self.maxSteps)) {
        completion(nil, _activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:1
                                                   userInfo:@{ NSLocalizedDescriptionKey: @"step limit reached" }]);
        return;
    }
    if (![FKAgent apiKey].length) {
        completion(nil, _activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:2
                                                   userInfo:@{ NSLocalizedDescriptionKey:
                                                                   @"No API key. Open Agent → settings and add an OpenAI-compatible key." }]);
        return;
    }

    NSMutableArray *messages = [NSMutableArray array];
    [messages addObject:@{ @"role": @"system", @"content": [self systemPrompt] }];
    [_runLock lock];
    [messages addObjectsFromArray:_history];
    [_runLock unlock];

    NSURLRequest *request = [self requestForMessages:messages tools:[self toolDefinitionsForAPI]];
    if (!request) {
        completion(nil, _activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:3
                                                   userInfo:@{ NSLocalizedDescriptionKey: @"invalid endpoint" }]);
        return;
    }
    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, self->_activity, error); return; }
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSString *host = response.URL.host ?: @"?";
        FKLog(@"agent: POST %@ -> HTTP %ld, %lu bytes", response.URL.path ?: @"/", (long)status,
              (unsigned long)(data.length));
        if (!data.length && status >= 200 && status < 300 && !self->_toolsDisabled &&
            [[FKTools toolDefinitions] count] > 0) {
            // Some OpenAI-compatible gateways return an empty 200 for requests that carry
            // tool schemas. Retry once without tools so the user still gets an answer.
            self->_toolsDisabled = YES;
            FKLog(@"agent: empty 200 with tools, retrying without tool schemas");
            [self step:step completion:completion];
            return;
        }
        if (!data.length) {
            NSString *message = [NSString stringWithFormat:
                                 @"empty response from HTTP %ld at %@ (check the endpoint URL, API key and provider status)",
                                 (long)status, host];
            completion(nil, self->_activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:status
                                                           userInfo:@{ NSLocalizedDescriptionKey: message }]);
            return;
        }
        id json = FKAgentJSONValue(data);
        if (![json isKindOfClass:[NSDictionary class]]) {
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            if (text.length > 600) text = [[text substringToIndex:600] stringByAppendingString:@"…"];
            NSString *message = text.length
                ? [NSString stringWithFormat:@"HTTP %ld from %@: %@", (long)status, host, text]
                : [NSString stringWithFormat:@"unreadable response: HTTP %ld from %@", (long)status, host];
            completion(nil, self->_activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:status
                                                           userInfo:@{ NSLocalizedDescriptionKey: message }]);
            return;
        }
        if (status >= 400) {
            id errorObject = json[@"error"];
            NSString *message = nil;
            if ([errorObject isKindOfClass:[NSDictionary class]]) message = errorObject[@"message"];
            else if ([errorObject isKindOfClass:[NSString class]]) message = errorObject;
            if (!message.length) message = [NSString stringWithFormat:@"HTTP %ld from %@", (long)status, host];
            completion(nil, self->_activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:status
                                                           userInfo:@{ NSLocalizedDescriptionKey: message }]);
            return;
        }
        NSDictionary *choice = [json[@"choices"] firstObject];
        NSDictionary *message = choice[@"message"];
        if (![message isKindOfClass:[NSDictionary class]]) {
            completion(nil, self->_activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:4
                                                           userInfo:@{ NSLocalizedDescriptionKey: @"malformed response" }]);
            return;
        }
        NSArray *toolCalls = message[@"tool_calls"];
        if ([toolCalls isKindOfClass:[NSArray class]] && toolCalls.count) {
            [self->_runLock lock];
            [self->_history addObject:@{ @"role": @"assistant",
                                         @"content": message[@"content"] ?: [NSNull null],
                                         @"tool_calls": toolCalls }];
            [self->_runLock unlock];
            for (NSDictionary *call in toolCalls) {
                NSDictionary *function = call[@"function"];
                NSString *name = function[@"name"];
                NSString *arguments = function[@"arguments"];
                if (![name isKindOfClass:[NSString class]]) continue;
                NSDictionary *args = FKAgentJSONValue([arguments dataUsingEncoding:NSUTF8StringEncoding]) ?: @{};
                NSDictionary *result = [self executeTool:name arguments:args];
                NSString *encoded = FKJSONString(result, YES);
                if (encoded.length > 24000) encoded = [[encoded substringToIndex:24000] stringByAppendingString:@"…"];
                [self->_runLock lock];
                [self->_history addObject:@{ @"role": @"tool",
                                             @"tool_call_id": call[@"id"] ?: @"",
                                             @"content": encoded ?: @"{}" }];
                [self->_runLock unlock];
            }
            [self step:step + 1 completion:completion];
            return;
        }
        NSString *content = [message[@"content"] isKindOfClass:[NSString class]] ? message[@"content"] : @"";
        [self->_runLock lock];
        [self->_history addObject:@{ @"role": @"assistant", @"content": content ?: @"" }];
        [self->_runLock unlock];
        completion(content, self->_activity, nil);
    }];
    [task resume];
}

- (NSDictionary *)executeTool:(NSString *)name arguments:(NSDictionary *)arguments {
    if (FKAgentToolMutates(name) && !self.allowMutations) {
        NSDictionary *blocked = @{ @"ok": @NO,
                                   @"error": @"mutating tools are disabled; enable 'Allow mutations' in Agent settings" };
        [self recordActivity:name arguments:arguments result:blocked];
        return blocked;
    }
    NSDictionary *result = nil;
    @try {
        result = [FKTools callTool:name arguments:arguments] ?: @{ @"ok": @NO, @"error": @"unknown tool" };
    } @catch (NSException *exception) {
        result = @{ @"ok": @NO, @"error": exception.reason ?: @"tool threw" };
    }
    [self recordActivity:name arguments:arguments result:result];
    return result;
}

- (void)recordActivity:(NSString *)name arguments:(NSDictionary *)arguments result:(NSDictionary *)result {
    [_runLock lock];
    [_activity addObject:@{ @"tool": name ?: @"?",
                            @"arguments": arguments ?: @{},
                            @"ok": result[@"ok"] ?: @NO,
                            @"result": result ?: @{} }];
    [_runLock unlock];
}

#pragma mark - Public runs

- (void)runPrompt:(NSString *)prompt
       completion:(void (^)(NSString *, NSArray<NSDictionary *> *, NSError *))completion {
    if (!prompt.length) {
        completion(nil, @[], [NSError errorWithDomain:@"ForgeKit.Agent" code:5
                                             userInfo:@{ NSLocalizedDescriptionKey: @"empty prompt" }]);
        return;
    }
    if (![_runLock tryLock]) {
        completion(nil, @[], [NSError errorWithDomain:@"ForgeKit.Agent" code:6
                                             userInfo:@{ NSLocalizedDescriptionKey: @"the agent is already running" }]);
        return;
    }
    _toolsDisabled = NO;
    [_history addObject:@{ @"role": @"user", @"content": prompt }];
    [_activity removeAllObjects];
    [_runLock unlock];
    [self step:0 completion:completion];
}

- (NSDictionary *)runPromptSynchronously:(NSString *)prompt timeout:(NSTimeInterval)timeout {
    __block NSDictionary *output = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self runPrompt:prompt completion:^(NSString *answer, NSArray<NSDictionary *> *activity, NSError *error) {
        output = @{ @"ok": @(error == nil),
                    @"answer": answer ?: @"",
                    @"error": error.localizedDescription ?: @"",
                    @"activity": activity ?: @[] };
        dispatch_semaphore_signal(semaphore);
    }];
    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        return @{ @"ok": @NO, @"error": @"agent timed out" };
    }
    return output ?: @{ @"ok": @NO, @"error": @"agent returned nothing" };
}

@end
