//
//  FKShell.h — sandbox shell (no popen, no exec) and loopback TCP transport
//

#import "ForgeKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface FKShell : NSObject
+ (instancetype)sharedShell;
@property (nonatomic, copy) NSString *currentDirectory;
- (NSString *)execute:(NSString *)commandLine;
- (NSString *)execute:(NSString *)commandLine inDirectory:(NSString *)directory;
- (NSArray<NSString *> *)commandNames;
+ (NSString *)helpText;
@end

@interface FKShellServer : NSObject
+ (instancetype)sharedServer;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) uint16_t port;
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
