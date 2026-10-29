//
//  FKToolsPrivate.h — internal declarations shared by FKTools.m and FKToolsApp.m
//

#import "ForgeKit.h"

@interface FKTools (Application)
+ (NSDictionary *)appInfo;
+ (NSDictionary *)infoPlist:(NSDictionary *)args;
+ (NSDictionary *)plistGet:(NSDictionary *)args;
+ (NSDictionary *)plistSet:(NSDictionary *)args;
+ (NSDictionary *)defaultsList;
+ (NSDictionary *)defaultsGet:(NSDictionary *)args;
+ (NSDictionary *)defaultsSet:(NSDictionary *)args;
+ (NSDictionary *)urlSchemes;
+ (NSDictionary *)binaries;
+ (NSDictionary *)keychain:(NSDictionary *)args;
+ (NSDictionary *)dylibLoad:(NSDictionary *)args;
+ (NSDictionary *)runtimeEval:(NSDictionary *)args;
+ (NSDictionary *)runtimeClasses:(NSDictionary *)args;
+ (NSDictionary *)runtimeClassInfo:(NSDictionary *)args;
+ (NSDictionary *)runtimeMemory;
+ (NSDictionary *)uiTree:(NSDictionary *)args;
+ (NSDictionary *)uiTap:(NSDictionary *)args;
+ (NSDictionary *)uiType:(NSDictionary *)args;
+ (NSDictionary *)uiScreenshot:(NSDictionary *)args;
+ (NSDictionary *)uiAlert:(NSDictionary *)args;
+ (NSDictionary *)uiOpenURL:(NSDictionary *)args;
+ (NSDictionary *)status;
+ (NSDictionary *)logWithArgs:(NSDictionary *)args;
+ (NSDictionary *)serverStart:(NSDictionary *)args;
+ (NSDictionary *)serverLog:(NSDictionary *)args;
@end
