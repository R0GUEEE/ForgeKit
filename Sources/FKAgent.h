//
//  FKAgent.h — in-app build agent (OpenAI-compatible tool-calling loop)
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKAgent : NSObject

+ (instancetype)sharedAgent;

@property (nonatomic, copy) NSString *provider;     // provider identifier
@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, assign) BOOL allowMutations;
@property (nonatomic, assign) NSInteger maxSteps;
@property (nonatomic, assign) double temperature;
@property (nonatomic, assign) NSInteger maxTokens;
@property (nonatomic, copy) NSString *toolMode;          // auto | none | required
@property (nonatomic, copy) NSString *toolProfile;       // all | safe | custom
@property (nonatomic, copy) NSArray<NSString *> *enabledTools;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extraHeaders;
@property (nonatomic, copy) NSString *systemInstructions;
@property (nonatomic, assign) NSInteger maxToolResultChars;
@property (nonatomic, assign) NSInteger contextMessages;
@property (nonatomic, assign) NSTimeInterval requestTimeout;
@property (nonatomic, readonly) NSDictionary *lastUsage;
@property (nonatomic, copy, nullable) void (^eventHandler)(NSDictionary *event);

+ (NSString *)apiKey;
+ (void)setAPIKey:(nullable NSString *)key;

+ (NSArray<NSDictionary *> *)providers;
+ (NSDictionary *)providerWithIdentifier:(NSString *)identifier;
+ (BOOL)toolMutates:(NSString *)name;
- (void)applyProvider:(NSString *)identifier;
- (NSString *)modelsEndpoint;
- (void)fetchModelsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable models,
                                           NSError *_Nullable error))completion;
- (NSArray<NSDictionary *> *)availableTools;
- (void)stop;
- (void)resetConversation;
- (NSArray<NSDictionary *> *)transcript;
- (void)runPrompt:(NSString *)prompt
       completion:(void (^)(NSString *_Nullable answer,
                            NSArray<NSDictionary *> *activity,
                            NSError *_Nullable error))completion;
- (NSDictionary *)runPromptSynchronously:(NSString *)prompt timeout:(NSTimeInterval)timeout;

@end

@interface FKAgentTools : NSObject
+ (NSArray<NSDictionary *> *)definitions;
+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)arguments;
+ (NSArray<NSDictionary *> *)projects;
@end

NS_ASSUME_NONNULL_END
