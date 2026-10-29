//
//  FKRuntimeKit.h — native ObjC explorer, memory tools, hooks and traffic capture
//
//  This is ForgeKit's in-process replacement for FLEX (runtime explorer) and the
//  Frida gadget (memory / module / hook tooling). Nothing is loaded from another
//  dylib.
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKRuntimeKit : NSObject

// ObjC explorer
+ (NSDictionary *)heapObjectsOfClass:(nullable NSString *)className limit:(NSInteger)limit;
+ (NSDictionary *)heapClassCounts:(NSInteger)limit;
+ (NSDictionary *)objectInfo:(unsigned long long)pointer depth:(NSInteger)depth;
+ (NSDictionary *)callClass:(NSString *)className
                   selector:(NSString *)selector
                     object:(unsigned long long)pointer
                classMethod:(BOOL)classMethod
                       args:(NSArray *)args;
+ (NSDictionary *)getIvar:(NSString *)name object:(unsigned long long)pointer;
+ (NSDictionary *)setIvar:(NSString *)name object:(unsigned long long)pointer value:(id)value;
+ (NSDictionary *)highlightRect:(CGRect)rect duration:(double)seconds;
+ (NSDictionary *)highlightAllViewsInWindow:(UIWindow *)window duration:(double)seconds;
+ (NSDictionary *)referencesTo:(unsigned long long)pointer limit:(NSInteger)limit;

// Memory and modules
+ (NSArray<NSDictionary *> *)modules;
+ (NSDictionary *)readMemory:(unsigned long long)address length:(NSInteger)length;
+ (NSDictionary *)writeMemory:(unsigned long long)address base64:(NSString *)base64;
+ (NSDictionary *)scanMemory:(NSString *)pattern module:(nullable NSString *)module limit:(NSInteger)limit;
+ (NSArray<NSDictionary *> *)exportsOfModule:(NSString *)module
                                      filter:(nullable NSString *)filter
                                       limit:(NSInteger)limit;

// Function hooks (inline redirect, restorable)
+ (NSDictionary *)redirectSymbol:(NSString *)source to:(NSString *)destination;
+ (NSDictionary *)restoreSymbol:(NSString *)source;
+ (NSArray<NSDictionary *> *)activeHooks;

// Network capture
+ (void)installNetworkRecorder;
+ (NSDictionary *)networkHistory:(NSInteger)limit;
+ (void)clearNetworkHistory;

// Notifications
+ (void)installNotificationRecorder;
+ (NSDictionary *)notificationHistory:(NSInteger)limit;
+ (void)clearNotificationHistory;

// SQLite
+ (NSArray<NSDictionary *> *)sqliteFiles;
+ (NSDictionary *)sqliteTablesAtPath:(NSString *)path;
+ (NSDictionary *)sqliteQuery:(NSString *)sql atPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
