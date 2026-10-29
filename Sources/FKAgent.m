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


static NSArray<NSDictionary *> *FKAgentProviderList(void) {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @{ @"id": @"openai", @"name": @"OpenAI",
               @"endpoint": @"https://api.openai.com/v1/chat/completions",
               @"default_model": @"gpt-4o-mini",
               @"fallback_models": @[@"gpt-4o", @"gpt-4o-mini", @"gpt-4.1", @"gpt-4.1-mini", @"o4-mini"] },
            @{ @"id": @"anthropic", @"name": @"Anthropic (Claude)",
               @"endpoint": @"https://api.anthropic.com/v1/chat/completions",
               @"default_model": @"claude-sonnet-4-5",
               @"headers": @{ @"anthropic-version": @"2023-06-01" },
               @"fallback_models": @[@"claude-sonnet-4-5", @"claude-opus-4-1", @"claude-haiku-4-5"] },
            @{ @"id": @"gemini", @"name": @"Google Gemini",
               @"endpoint": @"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
               @"default_model": @"gemini-2.5-flash",
               @"fallback_models": @[@"gemini-2.5-pro", @"gemini-2.5-flash", @"gemini-2.0-flash"] },
            @{ @"id": @"groq", @"name": @"Groq",
               @"endpoint": @"https://api.groq.com/openai/v1/chat/completions",
               @"default_model": @"llama-3.3-70b-versatile",
               @"fallback_models": @[@"llama-3.3-70b-versatile", @"llama-3.1-8b-instant", @"mixtral-8x7b-32768"] },
            @{ @"id": @"mistral", @"name": @"Mistral",
               @"endpoint": @"https://api.mistral.ai/v1/chat/completions",
               @"default_model": @"mistral-large-latest",
               @"fallback_models": @[@"mistral-large-latest", @"mistral-small-latest", @"codestral-latest"] },
            @{ @"id": @"deepseek", @"name": @"DeepSeek",
               @"endpoint": @"https://api.deepseek.com/v1/chat/completions",
               @"default_model": @"deepseek-chat",
               @"fallback_models": @[@"deepseek-chat", @"deepseek-reasoner"] },
            @{ @"id": @"openrouter", @"name": @"OpenRouter",
               @"endpoint": @"https://openrouter.ai/api/v1/chat/completions",
               @"default_model": @"openai/gpt-4o-mini",
               @"headers": @{ @"HTTP-Referer": @"https://forgekit.local", @"X-Title": @"ForgeKit" },
               @"fallback_models": @[@"openai/gpt-4o-mini", @"anthropic/claude-sonnet-4.5", @"google/gemini-2.5-flash"] },
            @{ @"id": @"together", @"name": @"Together AI",
               @"endpoint": @"https://api.together.xyz/v1/chat/completions",
               @"default_model": @"meta-llama/Llama-3.3-70B-Instruct-Turbo",
               @"fallback_models": @[@"meta-llama/Llama-3.3-70B-Instruct-Turbo", @"Qwen/Qwen2.5-72B-Instruct-Turbo"] },
            @{ @"id": @"fireworks", @"name": @"Fireworks AI",
               @"endpoint": @"https://api.fireworks.ai/inference/v1/chat/completions",
               @"default_model": @"accounts/fireworks/models/llama-v3p3-70b-instruct",
               @"fallback_models": @[@"accounts/fireworks/models/llama-v3p3-70b-instruct"] },
            @{ @"id": @"xai", @"name": @"xAI (Grok)",
               @"endpoint": @"https://api.x.ai/v1/chat/completions",
               @"default_model": @"grok-2-latest",
               @"fallback_models": @[@"grok-2-latest", @"grok-beta"] },
            @{ @"id": @"perplexity", @"name": @"Perplexity",
               @"endpoint": @"https://api.perplexity.ai/chat/completions",
               @"default_model": @"sonar",
               @"fallback_models": @[@"sonar", @"sonar-pro", @"sonar-reasoning"] },
            @{ @"id": @"cerebras", @"name": @"Cerebras",
               @"endpoint": @"https://api.cerebras.ai/v1/chat/completions",
               @"default_model": @"llama3.3-70b",
               @"fallback_models": @[@"llama3.3-70b", @"llama3.1-8b"] },
            @{ @"id": @"ollama", @"name": @"Ollama (local)",
               @"endpoint": @"http://127.0.0.1:11434/v1/chat/completions",
               @"default_model": @"llama3.2",
               @"local": @YES,
               @"fallback_models": @[@"llama3.2", @"qwen2.5-coder", @"deepseek-r1"] },
            @{ @"id": @"lmstudio", @"name": @"LM Studio (local)",
               @"endpoint": @"http://127.0.0.1:1234/v1/chat/completions",
               @"default_model": @"local-model",
               @"local": @YES,
               @"fallback_models": @[@"local-model"] },
            @{ @"id": @"custom", @"name": @"Custom endpoint",
               @"endpoint": @"",
               @"default_model": @"",
               @"fallback_models": @[] },
        ];
    });
    return list;
}

static NSString *FKAgentNormalizedEndpoint(NSString *raw) {
    NSString *value = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!value.length) value = @"https://api.openai.com/v1/chat/completions";
    if (![value.lowercaseString hasPrefix:@"http://"] && ![value.lowercaseString hasPrefix:@"https://"])
        value = [@"https://" stringByAppendingString:value];
    while ([value hasSuffix:@"/"]) value = [value substringToIndex:value.length - 1];
    // The endpoint is used verbatim. A scheme is added when missing and a trailing
    // slash is trimmed, but no API path is ever appended: whatever the user or the
    // provider preset specifies is what gets requested.
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
    NSURLSessionDataTask *_currentTask;
    NSDictionary *_lastUsage;
    dispatch_queue_t _persistQueue;
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
        _persistQueue = dispatch_queue_create("com.forgekit.agent.history", DISPATCH_QUEUE_SERIAL);
        [self loadPersistedHistory];
        _maxSteps = MAX(1, MIN([FKPrefs integerForKey:@"agentMaxSteps" defaultValue:8], 24));
        _temperature = [FKPrefs doubleForKey:@"agentTemperature" defaultValue:0.2];
        _maxTokens = [FKPrefs integerForKey:@"agentMaxTokens" defaultValue:0];
        _toolMode = [FKPrefs stringForKey:@"agentToolMode" defaultValue:@"auto"];
        _toolProfile = [FKPrefs stringForKey:@"agentToolProfile" defaultValue:@"all"];
        _systemInstructions = [FKPrefs stringForKey:@"agentSystemInstructions" defaultValue:@""];
        _maxToolResultChars = MAX(1000, [FKPrefs integerForKey:@"agentMaxResultChars" defaultValue:24000]);
        _contextMessages = MAX(2, [FKPrefs integerForKey:@"agentContextMessages" defaultValue:24]);
        _requestTimeout = MAX(10, [FKPrefs doubleForKey:@"agentTimeout" defaultValue:90]);
        NSString *headersJSON = [FKPrefs stringForKey:@"agentExtraHeaders" defaultValue:@""];
        NSDictionary *headers = headersJSON.length ? FKAgentJSONValue([headersJSON dataUsingEncoding:NSUTF8StringEncoding]) : nil;
        _extraHeaders = [headers isKindOfClass:[NSDictionary class]] ? headers : @{};
        NSString *toolsJSON = [FKPrefs stringForKey:@"agentEnabledTools" defaultValue:@""];
        NSArray *tools = toolsJSON.length ? FKAgentJSONValue([toolsJSON dataUsingEncoding:NSUTF8StringEncoding]) : nil;
        _enabledTools = [tools isKindOfClass:[NSArray class]] ? tools : @[];
        _provider = [FKPrefs stringForKey:@"agentProvider" defaultValue:@"openai"];
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

+ (NSArray<NSDictionary *> *)providers { return FKAgentProviderList(); }

+ (NSDictionary *)providerWithIdentifier:(NSString *)identifier {
    for (NSDictionary *provider in FKAgentProviderList()) {
        if ([provider[@"id"] isEqualToString:identifier]) return provider;
    }
    return nil;
}

- (void)setProvider:(NSString *)provider {
    _provider = [provider copy] ?: @"custom";
    [FKPrefs setString:_provider forKey:@"agentProvider"];
}

- (void)applyProvider:(NSString *)identifier {
    NSDictionary *provider = [FKAgent providerWithIdentifier:identifier];
    if (!provider) return;
    self.provider = identifier;
    NSString *endpoint = provider[@"endpoint"];
    if (endpoint.length) self.endpoint = endpoint;
    NSString *defaultModel = provider[@"default_model"];
    if (defaultModel.length) self.model = defaultModel;
    FKLog(@"agent: provider %@ -> %@ (%@)", provider[@"name"], self.endpoint, self.model);
}

- (NSDictionary *)providerHeaders {
    NSDictionary *provider = [FKAgent providerWithIdentifier:self.provider];
    NSDictionary *headers = provider[@"headers"];
    return [headers isKindOfClass:[NSDictionary class]] ? headers : @{};
}

- (NSDictionary *)mergedHeaders {
    NSMutableDictionary *headers = [[self providerHeaders] mutableCopy];
    [headers addEntriesFromDictionary:self.extraHeaders ?: @{}];
    return headers;
}

- (NSString *)modelsEndpoint {
    NSString *endpoint = self.endpoint ?: @"";
    if ([endpoint rangeOfString:@"chat/completions"].location != NSNotFound)
        return [endpoint stringByReplacingOccurrencesOfString:@"chat/completions" withString:@"models"];
    if ([endpoint hasSuffix:@"/messages"])
        return [[endpoint stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"models"];
    while ([endpoint hasSuffix:@"/"]) endpoint = [endpoint substringToIndex:endpoint.length - 1];
    if ([endpoint hasSuffix:@"/v1"]) return [endpoint stringByAppendingString:@"/models"];
    return [endpoint stringByAppendingString:@"/models"];
}

- (void)fetchModelsWithCompletion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSDictionary *provider = [FKAgent providerWithIdentifier:self.provider];
    NSArray *fallback = provider[@"fallback_models"];
    NSString *urlString = self.modelsEndpoint;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(fallback ?: @[], [NSError errorWithDomain:@"ForgeKit.Agent" code:10
                                                   userInfo:@{ NSLocalizedDescriptionKey: @"invalid models endpoint" }]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 20;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSString *key = [[FKAgent apiKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (key.length)
        [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    for (NSString *header in [self mergedHeaders])
        [request setValue:[self mergedHeaders][header] forHTTPHeaderField:header];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        id json = FKAgentJSONValue(data);
        NSMutableArray *models = [NSMutableArray array];
        if ([json isKindOfClass:[NSDictionary class]]) {
            id list = json[@"data"] ?: json[@"models"];
            if ([list isKindOfClass:[NSArray class]]) {
                for (id entry in list) {
                    if ([entry isKindOfClass:[NSString class]]) [models addObject:entry];
                    else if ([entry isKindOfClass:[NSDictionary class]])
                        [models addObject:entry[@"id"] ?: entry[@"name"] ?: @""];
                }
            }
        }
        [models removeObject:@""];
        if (models.count) {
            completion([[NSSet setWithArray:models].allObjects sortedArrayUsingSelector:@selector(compare:)], nil);
            return;
        }
        if (fallback.count) {
            FKLog(@"agent: model list unavailable (HTTP %ld), using provider defaults", (long)status);
            completion(fallback, nil);
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
        if (text.length > 300) text = [[text substringToIndex:300] stringByAppendingString:@"…"];
        NSString *message = text.length ? [NSString stringWithFormat:@"HTTP %ld: %@", (long)status, text]
                                        : [NSString stringWithFormat:@"HTTP %ld: no models returned", (long)status];
        completion(@[], [NSError errorWithDomain:@"ForgeKit.Agent" code:status
                                       userInfo:@{ NSLocalizedDescriptionKey: message }]);
    }];
    [task resume];
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

- (void)setMaxSteps:(NSInteger)maxSteps {
    _maxSteps = MAX(1, MIN(maxSteps, 24));
    [FKPrefs setInteger:_maxSteps forKey:@"agentMaxSteps"];
}

- (void)setTemperature:(double)temperature {
    _temperature = MAX(0, MIN(temperature, 2));
    [FKPrefs setDouble:_temperature forKey:@"agentTemperature"];
}

- (void)setMaxTokens:(NSInteger)maxTokens {
    _maxTokens = MAX(0, MIN(maxTokens, 32768));
    [FKPrefs setInteger:_maxTokens forKey:@"agentMaxTokens"];
}

- (void)setToolMode:(NSString *)toolMode {
    NSArray *allowed = @[@"auto", @"none", @"required"];
    _toolMode = [allowed containsObject:toolMode.lowercaseString] ? toolMode.lowercaseString : @"auto";
    [FKPrefs setString:_toolMode forKey:@"agentToolMode"];
}

- (void)setToolProfile:(NSString *)toolProfile {
    NSArray *allowed = @[@"all", @"safe", @"custom"];
    _toolProfile = [allowed containsObject:toolProfile.lowercaseString] ? toolProfile.lowercaseString : @"all";
    [FKPrefs setString:_toolProfile forKey:@"agentToolProfile"];
}

- (void)setEnabledTools:(NSArray<NSString *> *)enabledTools {
    _enabledTools = [enabledTools copy] ?: @[];
    NSData *data = [NSJSONSerialization dataWithJSONObject:_enabledTools options:0 error:nil];
    [FKPrefs setString:data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @""
                forKey:@"agentEnabledTools"];
}

- (void)setExtraHeaders:(NSDictionary<NSString *,NSString *> *)extraHeaders {
    _extraHeaders = [extraHeaders copy] ?: @{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:_extraHeaders options:0 error:nil];
    [FKPrefs setString:data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @""
                forKey:@"agentExtraHeaders"];
}

- (void)setSystemInstructions:(NSString *)systemInstructions {
    _systemInstructions = [systemInstructions copy] ?: @"";
    [FKPrefs setString:_systemInstructions forKey:@"agentSystemInstructions"];
}

- (void)setMaxToolResultChars:(NSInteger)maxToolResultChars {
    _maxToolResultChars = MAX(1000, MIN(maxToolResultChars, 200000));
    [FKPrefs setInteger:_maxToolResultChars forKey:@"agentMaxResultChars"];
}

- (void)setContextMessages:(NSInteger)contextMessages {
    _contextMessages = MAX(2, MIN(contextMessages, 200));
    [FKPrefs setInteger:_contextMessages forKey:@"agentContextMessages"];
}

- (void)setRequestTimeout:(NSTimeInterval)requestTimeout {
    _requestTimeout = MAX(10, MIN(requestTimeout, 600));
    [FKPrefs setDouble:_requestTimeout forKey:@"agentTimeout"];
}

- (NSDictionary *)lastUsage { return _lastUsage ?: @{}; }

- (void)stop {
    [_runLock lock];
    NSURLSessionDataTask *task = _currentTask;
    _currentTask = nil;
    [_runLock unlock];
    [task cancel];
}

#pragma mark - Persistence

- (NSString *)historyPath {
    NSString *directory = [FKDocumentsPath() stringByAppendingPathComponent:@"ForgeKit/agent"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:@"history.json"];
}

- (void)loadPersistedHistory {
    NSData *data = [NSData dataWithContentsOfFile:[self historyPath]];
    if (!data.length) return;
    id json = FKAgentJSONValue(data);
    if (![json isKindOfClass:[NSArray class]]) return;
    NSMutableArray *history = [NSMutableArray array];
    for (id entry in (NSArray *)json) {
        if ([entry isKindOfClass:[NSDictionary class]] && entry[@"role"]) [history addObject:entry];
    }
    if (history.count) {
        _history = history;
        FKLog(@"agent: restored %lu history messages", (unsigned long)history.count);
    }
}

- (void)trimHistoryLocked {
    while (_history.count > 400) [_history removeObjectAtIndex:0];
    while (_history.count && [_history.firstObject[@"role"] isEqualToString:@"tool"])
        [_history removeObjectAtIndex:0];
}

- (void)persistHistory {
    [_runLock lock];
    NSArray *snapshot = [_history copy];
    [_runLock unlock];
    dispatch_async(_persistQueue, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil];
        if (data) [data writeToFile:[self historyPath] options:NSDataWritingAtomic error:nil];
    });
}

+ (BOOL)toolMutates:(NSString *)name { return FKAgentToolMutates(name); }

- (BOOL)toolAllowed:(NSString *)name {
    if (self.toolProfile.lowercaseString == nil) return YES;
    NSString *profile = self.toolProfile.lowercaseString;
    if ([profile isEqualToString:@"safe"] && FKAgentToolMutates(name)) return NO;
    if ([profile isEqualToString:@"custom"]) return [self.enabledTools containsObject:name];
    return YES;
}

- (NSArray<NSDictionary *> *)availableTools {
    NSMutableArray *tools = [NSMutableArray array];
    for (NSDictionary *definition in [FKTools toolDefinitions]) {
        NSString *name = definition[@"name"];
        if (!name.length) continue;
        [tools addObject:@{ @"name": name,
                            @"group": FKAgentToolMutates(name) ? @"mutating" : @"read-only",
                            @"enabled": @([self toolAllowed:name]),
                            @"description": definition[@"description"] ?: @"" }];
    }
    return tools;
}

#pragma mark - Conversation

- (void)resetConversation {
    [_runLock lock];
    [_history removeAllObjects];
    [_activity removeAllObjects];
    [_runLock unlock];
    dispatch_async(_persistQueue, ^{
        [[NSFileManager defaultManager] removeItemAtPath:[self historyPath] error:nil];
    });
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

- (NSString *)systemPromptWithInstructions {
    NSString *base = [self systemPrompt];
    if (self.systemInstructions.length)
        base = [base stringByAppendingFormat:@"\n\nOperator instructions:\n%@", self.systemInstructions];
    return base;
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
        if (![self toolAllowed:name]) continue;
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
        @"temperature": @(self.temperature),
        @"stream": @NO,
    } mutableCopy];
    if (self.maxTokens > 0) payload[@"max_tokens"] = @(self.maxTokens);
    if (tools.count && !_toolsDisabled && ![self.toolMode isEqualToString:@"none"]) {
        payload[@"tools"] = tools;
        payload[@"tool_choice"] = [self.toolMode isEqualToString:@"required"] ? @"required" : @"auto";
    }
    NSError *error = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!body) return nil;
    NSURL *url = [NSURL URLWithString:FKAgentNormalizedEndpoint(self.endpoint)];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = self.requestTimeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"ForgeKit/2.3.1" forHTTPHeaderField:@"User-Agent"];
    NSString *key = [[FKAgent apiKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    for (NSString *header in [self mergedHeaders]) {
        id value = [self mergedHeaders][header];
        if ([header isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]])
            [request setValue:value forHTTPHeaderField:header];
    }
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
    [messages addObject:@{ @"role": @"system", @"content": [self systemPromptWithInstructions] }];
    [_runLock lock];
    NSMutableArray *history = [_history mutableCopy];
    [_runLock unlock];
    while ((NSInteger)history.count > MAX(2, self.contextMessages)) [history removeObjectAtIndex:0];
    while (history.count && [history.firstObject[@"role"] isEqualToString:@"tool"]) [history removeObjectAtIndex:0];
    [messages addObjectsFromArray:history];

    NSURLRequest *request = [self requestForMessages:messages tools:[self toolDefinitionsForAPI]];
    if (!request) {
        completion(nil, _activity, [NSError errorWithDomain:@"ForgeKit.Agent" code:3
                                                   userInfo:@{ NSLocalizedDescriptionKey: @"invalid endpoint" }]);
        return;
    }
    __block NSURLSessionDataTask *task = nil;
    task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self->_runLock lock];
        if (self->_currentTask == task) self->_currentTask = nil;
        [self->_runLock unlock];
        if (error) {
            if (error.code == NSURLErrorCancelled)
                error = [NSError errorWithDomain:@"ForgeKit.Agent" code:error.code
                                        userInfo:@{ NSLocalizedDescriptionKey: @"stopped" }];
            completion(nil, self->_activity, error);
            return;
        }
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
        if ([json[@"usage"] isKindOfClass:[NSDictionary class]]) self->_lastUsage = json[@"usage"];
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
            [self trimHistoryLocked];
            [self->_runLock unlock];
            [self persistHistory];
            for (NSDictionary *call in toolCalls) {
                NSDictionary *function = call[@"function"];
                NSString *name = function[@"name"];
                NSString *arguments = function[@"arguments"];
                if (![name isKindOfClass:[NSString class]]) continue;
                NSDictionary *args = FKAgentJSONValue([arguments dataUsingEncoding:NSUTF8StringEncoding]) ?: @{};
                NSDictionary *result = [self executeTool:name arguments:args];
                NSString *encoded = FKJSONString(result, YES);
                if ((NSInteger)encoded.length > self.maxToolResultChars)
                    encoded = [[encoded substringToIndex:(NSUInteger)self.maxToolResultChars] stringByAppendingString:@"…"];
                [self->_runLock lock];
                [self->_history addObject:@{ @"role": @"tool",
                                             @"tool_call_id": call[@"id"] ?: @"",
                                             @"content": encoded ?: @"{}" }];
                [self trimHistoryLocked];
                [self->_runLock unlock];
                [self persistHistory];
            }
            [self step:step + 1 completion:completion];
            return;
        }
        NSString *content = [message[@"content"] isKindOfClass:[NSString class]] ? message[@"content"] : @"";
        [self->_runLock lock];
        [self->_history addObject:@{ @"role": @"assistant", @"content": content ?: @"" }];
        [self trimHistoryLocked];
        [self->_runLock unlock];
        [self persistHistory];
        completion(content, self->_activity, nil);
    }];
    [_runLock lock];
    _currentTask = task;
    [_runLock unlock];
    [task resume];
}

- (void)emitEvent:(NSDictionary *)event {
    void (^handler)(NSDictionary *) = self.eventHandler;
    if (!handler) return;
    dispatch_async(dispatch_get_main_queue(), ^{ handler(event); });
}

- (NSDictionary *)executeTool:(NSString *)name arguments:(NSDictionary *)arguments {
    if (![self toolAllowed:name]) {
        NSDictionary *blocked = @{ @"ok": @NO,
                                   @"error": [NSString stringWithFormat:
                                              @"tool %@ is excluded by the current tool profile (%@)",
                                              name, self.toolProfile] };
        [self recordActivity:name arguments:arguments result:blocked];
        [self emitEvent:@{ @"type": @"tool_end", @"tool": name ?: @"?", @"ok": @NO, @"result": blocked }];
        return blocked;
    }
    if (FKAgentToolMutates(name) && !self.allowMutations) {
        NSDictionary *blocked = @{ @"ok": @NO,
                                   @"error": @"mutating tools are disabled; enable 'Allow mutations' in Agent settings" };
        [self recordActivity:name arguments:arguments result:blocked];
        return blocked;
    }
    [self emitEvent:@{ @"type": @"tool_start", @"tool": name ?: @"?", @"arguments": arguments ?: @{} }];
    NSDictionary *result = nil;
    @try {
        result = [FKTools callTool:name arguments:arguments] ?: @{ @"ok": @NO, @"error": @"unknown tool" };
    } @catch (NSException *exception) {
        result = @{ @"ok": @NO, @"error": exception.reason ?: @"tool threw" };
    }
    [self recordActivity:name arguments:arguments result:result];
    [self emitEvent:@{ @"type": @"tool_end", @"tool": name ?: @"?",
                       @"ok": result[@"ok"] ?: @NO,
                       @"result": result ?: @{} }];
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
    _lastUsage = @{};
    [_history addObject:@{ @"role": @"user", @"content": prompt }];
    [self trimHistoryLocked];
    [_activity removeAllObjects];
    [_runLock unlock];
    [self persistHistory];
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
