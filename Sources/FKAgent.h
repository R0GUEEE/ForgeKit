//
//  FKAgent.h — in-app build agent (OpenAI-compatible tool-calling loop)
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKAgent : NSObject

+ (instancetype)sharedAgent;

@property (nonatomic, copy) NSString *endpoint;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, assign) BOOL allowMutations;
@property (nonatomic, assign) NSInteger maxSteps;

+ (NSString *)apiKey;
+ (void)setAPIKey:(nullable NSString *)key;

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
