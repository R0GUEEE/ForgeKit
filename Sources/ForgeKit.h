//
//  ForgeKit.h
//  ForgeKit — sideload-safe application development toolkit
//
//  Injected as a plain dylib (LC_LOAD_DYLIB) into a jailed or jailbroken app.
//  No MobileSubstrate / ElleKit / libhooker linkage: all method replacement is
//  done with the Objective-C runtime so the binary loads in any codesigned app.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const FKVersionString;
FOUNDATION_EXPORT NSString * const FKServerDidChangeNotification;

#pragma mark - Logging

FOUNDATION_EXPORT void FKLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT NSArray<NSString *> *FKLogLines(void);
FOUNDATION_EXPORT void FKLogClear(void);

#pragma mark - Environment

FOUNDATION_EXPORT NSString *FKHomePath(void);
FOUNDATION_EXPORT NSString *FKContainerPath(void);
FOUNDATION_EXPORT NSString *FKDataContainerPath(void);
FOUNDATION_EXPORT NSString *FKBundlePath(void);
FOUNDATION_EXPORT NSString *FKDocumentsPath(void);
FOUNDATION_EXPORT NSString *FKLibraryPath(void);
FOUNDATION_EXPORT NSString *FKTempPath(void);
FOUNDATION_EXPORT NSArray<NSString *> *FKGroupContainerPaths(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *FKRoots(void);
FOUNDATION_EXPORT BOOL FKIsJailbroken(void);
FOUNDATION_EXPORT NSString *FKAppName(void);
FOUNDATION_EXPORT NSString *FKAppIdentifier(void);
FOUNDATION_EXPORT NSString *FKAppVersion(void);
FOUNDATION_EXPORT NSDictionary *FKInfoPlist(void);
FOUNDATION_EXPORT NSDictionary *FKEntitlements(void);
FOUNDATION_EXPORT NSString *FKDeviceModelIdentifier(void);
FOUNDATION_EXPORT NSString *FKOSVersionString(void);
FOUNDATION_EXPORT uint64_t FKResidentMemory(void);
FOUNDATION_EXPORT NSString *FKLanAddress(void);
FOUNDATION_EXPORT NSArray<NSString *> *FKLanAddresses(void);
FOUNDATION_EXPORT NSString *FKPrimaryInterfaceAddress(void);

#pragma mark - Formatting / serialisation

FOUNDATION_EXPORT NSString *FKHumanSize(unsigned long long bytes);
FOUNDATION_EXPORT NSString *FKHexDump(NSData *data, NSUInteger baseOffset, NSUInteger maxBytes);
FOUNDATION_EXPORT id FKJSONSafe(id object);
FOUNDATION_EXPORT NSString *FKJSONString(id object, BOOL pretty);
FOUNDATION_EXPORT NSString *FKFormatDate(NSDate *date);
FOUNDATION_EXPORT NSString *FKRandomToken(NSUInteger byteCount);
FOUNDATION_EXPORT NSString *FKURLEncode(NSString *string);
FOUNDATION_EXPORT NSString *FKURLDecode(NSString *string);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *FKParseQuery(NSString *query);

#pragma mark - Files

FOUNDATION_EXPORT NSData * _Nullable FKReadData(NSString *path, NSError **error);
FOUNDATION_EXPORT BOOL FKWriteDataAtomically(NSData *data, NSString *path, NSError **error);
FOUNDATION_EXPORT NSDictionary *FKFileAttributes(NSString *path);
FOUNDATION_EXPORT NSArray<NSDictionary *> *FKDirectoryList(NSString *path, BOOL includeHidden, NSError **error);
FOUNDATION_EXPORT NSString *FKExpandPath(NSString *path);
FOUNDATION_EXPORT NSArray<NSDictionary *> *FKMachODependencies(NSString *path);
FOUNDATION_EXPORT NSArray<NSString *> *FKLoadedImages(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *FKKeychainItems(NSString *itemClass);
FOUNDATION_EXPORT NSArray<NSDictionary *> *FKHTTPCookies(void);
FOUNDATION_EXPORT NSDictionary *FKApplicationPaths(void);

#pragma mark - Runtime helpers

FOUNDATION_EXPORT void FKSwizzleInstance(Class cls, SEL original, SEL replacement);
FOUNDATION_EXPORT void FKSwizzleClass(Class cls, SEL original, SEL replacement);
FOUNDATION_EXPORT UIWindowScene * _Nullable FKActiveWindowScene(void);
FOUNDATION_EXPORT UIWindow * _Nullable FKKeyWindow(void);
FOUNDATION_EXPORT UIViewController * _Nullable FKTopViewController(void);
FOUNDATION_EXPORT void FKRunOnMain(dispatch_block_t block);
FOUNDATION_EXPORT UIImage * _Nullable FKSnapshotKeyWindow(void);
FOUNDATION_EXPORT void FKPresentAlert(NSString *title, NSString *message);

#pragma mark - Preferences

@interface FKPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)value;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)value;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (double)doubleForKey:(NSString *)key defaultValue:(double)value;
+ (void)setDouble:(double)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)value;
+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)token;
+ (void)regenerateToken;
+ (void)synchronize;
@end

#pragma mark - Archive

@interface FKZip : NSObject
+ (BOOL)createArchiveAtPath:(NSString *)archivePath
                  fromPaths:(NSArray<NSString *> *)paths
                      error:(NSError **)error;
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                   toDirectory:(NSString *)destination
                         error:(NSError **)error;
+ (NSArray<NSDictionary *> *)listArchiveAtPath:(NSString *)archivePath error:(NSError **)error;
@end

#pragma mark - Tools

@interface FKTools : NSObject
+ (NSArray<NSDictionary *> *)toolDefinitions;
+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)arguments;
@end

#pragma mark - Runtime automation

@interface FKRuntime : NSObject
+ (id)evaluateScript:(NSString *)source error:(NSString **)error;
+ (NSDictionary *)viewTreeWithDepth:(NSInteger)depth maxNodes:(NSInteger)maxNodes;
+ (NSDictionary *)tapAtPoint:(CGPoint)point;
+ (NSDictionary *)tapElementWithLabel:(NSString *)label;
+ (NSDictionary *)typeText:(NSString *)text intoElementWithLabel:(nullable NSString *)label;
+ (NSDictionary *)screenshotJPEGQuality:(CGFloat)quality;
+ (NSArray<NSDictionary *> *)classesWithPrefix:(NSString *)prefix limit:(NSInteger)limit;
+ (NSDictionary *)classInfo:(NSString *)className;
@end

#pragma mark - HTTP / MCP

@interface FKHTTPServer : NSObject
+ (instancetype)sharedServer;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) uint16_t port;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;
- (NSArray<NSDictionary *> *)recentRequestsWithLimit:(NSInteger)limit;
- (void)clearRequestLog;
- (void)noteExternalLog:(NSString *)line;
@end

@interface FKMCP : NSObject
+ (id)handleJSONRPC:(id)payload authorized:(BOOL)authorized;
+ (NSArray<NSDictionary *> *)toolDefinitions;
+ (NSDictionary *)dispatchToolCall:(NSString *)name arguments:(NSDictionary *)arguments;
+ (NSString *)protocolVersion;
@end

#pragma mark - UI

@class FKFileBrowserViewController;

@interface FKListViewController : UITableViewController
@property (nonatomic, copy) NSString *screenTitle;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
+ (instancetype)listWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections;
- (void)reloadSections;
@end

@interface FKTextViewController : UIViewController
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) BOOL readOnly;
+ (instancetype)viewerWithTitle:(NSString *)title text:(NSString *)text;
+ (instancetype)viewerWithPath:(NSString *)path;
+ (instancetype)editorWithPath:(NSString *)path;
@end

@interface FKHexViewController : UIViewController
+ (instancetype)viewerWithPath:(NSString *)path;
@end

@interface FKImageViewController : UIViewController
+ (instancetype)viewerWithPath:(NSString *)path;
@end

@interface FKFileBrowserViewController : UITableViewController
+ (instancetype)browserAtPath:(NSString *)path;
@end

@interface FKPanel : NSObject
+ (instancetype)sharedPanel;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
- (void)show;
- (void)hide;
- (void)toggle;
- (void)installGestureOnWindow:(UIWindow *)window;
@end

NS_ASSUME_NONNULL_END
