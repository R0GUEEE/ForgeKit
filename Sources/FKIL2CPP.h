//
//  FKIL2CPP.h — IL2CPP runtime bridge (resolved dynamically, optional)
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKIL2CPP : NSObject

+ (BOOL)available;
+ (NSString *)statusText;

+ (NSDictionary *)runtimeInfo;
+ (NSArray<NSDictionary *> *)images;
+ (NSArray<NSDictionary *> *)allClasses;
+ (NSArray<NSDictionary *> *)classesMatching:(nullable NSString *)filter limit:(NSInteger)limit;
+ (NSDictionary *)classInfoFor:(NSString *)className;

+ (NSDictionary *)findObjectsOfClass:(NSString *)className limit:(NSInteger)limit;
+ (NSDictionary *)inspectObjectOfClass:(NSString *)className
                              pointer:(unsigned long long)pointer
                                limit:(NSInteger)limit;
+ (NSDictionary *)inspectCollection:(unsigned long long)pointer limit:(NSInteger)limit;

+ (NSDictionary *)readField:(NSString *)field
                  ofClass:(NSString *)className
                   object:(unsigned long long)pointer;
+ (NSDictionary *)writeField:(NSString *)field
                     ofClass:(NSString *)className
                      object:(unsigned long long)pointer
                       value:(id)value;
+ (NSDictionary *)invokeMethod:(NSString *)method
                       ofClass:(NSString *)className
                        object:(unsigned long long)pointer
                          args:(NSArray *)args
                      overload:(NSInteger)overload;

+ (NSDictionary *)patchMethod:(NSString *)method
                      ofClass:(NSString *)className
                         mode:(NSString *)mode
                        value:(id _Nullable)value
                     overload:(NSInteger)overload;
+ (NSDictionary *)restorePatchOfClass:(NSString *)className method:(NSString *)method;
+ (NSDictionary *)restoreAllPatches;
+ (NSDictionary *)patchStatus;

+ (NSDictionary *)findFieldOwners:(NSString *)typeName limit:(NSInteger)limit;
+ (NSDictionary *)findMethodsByPattern:(nullable NSString *)pattern
                            returnType:(nullable NSString *)returnType
                                 limit:(NSInteger)limit;
+ (NSDictionary *)findClassesInheritingFrom:(NSString *)baseName limit:(NSInteger)limit;
+ (NSDictionary *)findClassesImplementing:(NSString *)protocolName limit:(NSInteger)limit;
+ (NSDictionary *)findSingletonsWithImage:(nullable NSString *)image limit:(NSInteger)limit;
+ (NSDictionary *)sceneRootsWithLimit:(NSInteger)limit;
+ (NSDictionary *)scanUIText:(NSString *)needle limit:(NSInteger)limit;
+ (NSDictionary *)playerPrefsRead:(NSString *)key type:(NSString *)type;
+ (NSDictionary *)playerPrefsWrite:(NSString *)key type:(NSString *)type value:(id _Nullable)value delete:(BOOL)deleteKey;
+ (NSDictionary *)dumpWithFilter:(nullable NSString *)filter path:(nullable NSString *)path;

@end

NS_ASSUME_NONNULL_END
