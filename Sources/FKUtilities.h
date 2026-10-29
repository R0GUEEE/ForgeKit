//
//  FKUtilities.h — FLEX, Frida gadget and WebKit inspector integration
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKUtilities : NSObject

+ (NSDictionary *)status;

+ (void)installWebInspectorSwizzle;
+ (NSDictionary *)webInspectorStatus;
+ (void)setWebInspectorEnabled:(BOOL)enabled;
+ (void)applyWebInspectorToOpenWebViews;

+ (NSDictionary *)loadFLEXAtPath:(nullable NSString *)path show:(BOOL)show;
+ (NSDictionary *)showFLEX;
+ (NSDictionary *)hideFLEX;

+ (NSDictionary *)loadFridaGadgetAtPath:(nullable NSString *)path
                                 config:(nullable NSDictionary *)config;
+ (NSDictionary *)fridaStatus;
+ (NSDictionary *)writeFridaConfig:(NSDictionary *)config;

+ (NSArray<NSDictionary *> *)discoveredLibraries;

@end

NS_ASSUME_NONNULL_END
