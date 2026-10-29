//
//  FKUtil.m — environment, filesystem, formatting, preferences
//

#import "ForgeKit.h"
#import <Security/Security.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <zlib.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

NSString * const FKVersionString = @"1.2.0";
NSString * const FKServerDidChangeNotification = @"FKServerDidChangeNotification";

static NSMutableArray<NSString *> *FKLogStorage(void) {
    static NSMutableArray *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lines = [NSMutableArray array]; });
    return lines;
}

static NSLock *FKLogLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });
    return lock;
}

void FKLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@", FKFormatDate([NSDate date]), message];
    NSLock *lock = FKLogLock();
    [lock lock];
    NSMutableArray *storage = FKLogStorage();
    [storage addObject:line];
    while (storage.count > 2000) [storage removeObjectAtIndex:0];
    [lock unlock];
    NSLog(@"[ForgeKit] %@", message);
}

NSArray<NSString *> *FKLogLines(void) {
    NSLock *lock = FKLogLock();
    [lock lock];
    NSArray *copy = [FKLogStorage() copy];
    [lock unlock];
    return copy;
}

void FKLogClear(void) {
    NSLock *lock = FKLogLock();
    [lock lock];
    [FKLogStorage() removeAllObjects];
    [lock unlock];
}

#pragma mark - Paths

NSString *FKHomePath(void) { return NSHomeDirectory(); }

NSString *FKContainerPath(void) {
    return [NSHomeDirectory() stringByDeletingLastPathComponent];
}

NSString *FKDataContainerPath(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // /var/mobile/Containers/Data/Application/<UUID>
        cached = [NSHomeDirectory() stringByDeletingLastPathComponent];
    });
    return cached;
}

NSString *FKBundlePath(void) { return [[NSBundle mainBundle] bundlePath]; }

NSString *FKDocumentsPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
        ?: [FKHomePath() stringByAppendingPathComponent:@"Documents"];
}

NSString *FKLibraryPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
        ?: [FKHomePath() stringByAppendingPathComponent:@"Library"];
}

NSString *FKTempPath(void) { return NSTemporaryDirectory(); }

NSArray<NSString *> *FKGroupContainerPaths(void) {
    NSMutableArray *result = [NSMutableArray array];
    // Group identifiers declared in the app's entitlements.
    NSDictionary *entitlements = FKEntitlements();
    id groups = entitlements[@"com.apple.security.application-groups"];
    if ([groups isKindOfClass:[NSArray class]]) {
        for (NSString *group in groups) {
            NSURL *url = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
            if (url.path.length) [result addObject:url.path];
        }
    }
    return result;
}

NSArray<NSDictionary *> *FKRoots(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *roots = [NSMutableArray array];
    void (^add)(NSString *, NSString *) = ^(NSString *name, NSString *path) {
        BOOL readable = [fm isReadableFileAtPath:path];
        BOOL writable = [fm isWritableFileAtPath:path];
        NSMutableDictionary *entry = [@{ @"name": name, @"path": path,
                                         @"readable": @(readable), @"writable": @(writable) } mutableCopy];
        if (readable) {
            NSError *error = nil;
            NSArray *contents = [fm contentsOfDirectoryAtPath:path error:&error];
            if (contents) entry[@"entries"] = @(contents.count);
        }
        [roots addObject:entry];
    };
    add(@"Bundle", FKBundlePath());
    add(@"Container", FKContainerPath());
    add(@"Documents", FKDocumentsPath());
    add(@"Library", FKLibraryPath());
    add(@"tmp", FKTempPath());
    for (NSString *group in FKGroupContainerPaths()) add(@"App Group", group);
    add(@"Root /", @"/");
    add(@"User /var", @"/var");
    add(@"Mobile home", @"/var/mobile");
    add(@"Bundle containers", @"/var/containers/Bundle/Application");
    add(@"Data containers", @"/var/mobile/Containers/Data/Application");
    add(@"Shared App Group", @"/var/mobile/Containers/Shared/AppGroup");
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) add(@"Jailbreak /var/jb", @"/var/jb");
    return roots;
}

BOOL FKIsJailbroken(void) {
    static BOOL result;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *probes = @[@"/var/jb", @"/usr/lib/libsubstrate.dylib", @"/usr/lib/libellekit.dylib",
                            @"/Library/MobileSubstrate", @"/bin/bash", @"/usr/sbin/sshd",
                            @"/Applications/Cydia.app", @"/var/lib/dpkg/status"];
        for (NSString *path in probes) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) { result = YES; return; }
        }
        result = [[NSFileManager defaultManager] isWritableFileAtPath:@"/var/mobile/Library/Preferences"];
    });
    return result;
}

NSString *FKAppName(void) {
    NSDictionary *info = FKInfoPlist();
    NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
    if ([name isKindOfClass:[NSString class]] && name.length) return name;
    return [[NSProcessInfo processInfo] processName] ?: @"App";
}

NSString *FKAppIdentifier(void) {
    id value = FKInfoPlist()[@"CFBundleIdentifier"];
    if ([value isKindOfClass:[NSString class]]) return value;
    return NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
}

NSString *FKAppVersion(void) {
    NSDictionary *info = FKInfoPlist();
    NSString *shortVersion = info[@"CFBundleShortVersionString"];
    NSString *build = info[@"CFBundleVersion"];
    if ([shortVersion isKindOfClass:[NSString class]] && [build isKindOfClass:[NSString class]])
        return [NSString stringWithFormat:@"%@ (%@)", shortVersion, build];
    return [shortVersion isKindOfClass:[NSString class]] ? shortVersion : @"?";
}

NSDictionary *FKInfoPlist(void) {
    static NSDictionary *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [FKBundlePath() stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        cached = plist ?: @{};
    });
    return cached;
}

static NSDictionary *FKEntitlementsFromMachO(void) {
    NSString *executable = NSBundle.mainBundle.executablePath;
    if (!executable.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:executable options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 32) return nil;

    const uint8_t magicBytes[4] = { 0xFA, 0xDE, 0x71, 0x71 }; // CSMAGIC_EMBEDDED_ENTITLEMENTS
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSRange found = NSMakeRange(NSNotFound, 0);
    for (NSUInteger i = 0; i + 4 < length; i++) {
        if (memcmp(bytes + i, magicBytes, 4) == 0) { found = NSMakeRange(i, 4); break; }
    }
    if (found.location == NSNotFound) return nil;

    NSUInteger start = found.location + 8;
    NSUInteger end = start;
    const char *xml = "<?xml";
    const char *closing = "</plist>";
    NSUInteger xmlStart = NSNotFound;
    for (NSUInteger i = start; i + 5 < length && i < start + 4096; i++) {
        if (memcmp(bytes + i, xml, 5) == 0) { xmlStart = i; break; }
    }
    if (xmlStart == NSNotFound) return nil;
    for (NSUInteger i = xmlStart; i + 8 < length; i++) {
        if (memcmp(bytes + i, closing, 8) == 0) { end = i + 8; break; }
    }
    if (end <= xmlStart) return nil;
    NSData *plistData = [data subdataWithRange:NSMakeRange(xmlStart, end - xmlStart)];
    id plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                        options:NSPropertyListImmutable
                                                         format:NULL
                                                          error:nil];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

static NSDictionary *FKEntitlementsFromProfile(void) {
    NSData *data = [NSData dataWithContentsOfFile:[FKBundlePath() stringByAppendingPathComponent:@"embedded.mobileprovision"]];
    if (data.length < 100) return nil;
    const char *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger start = NSNotFound;
    for (NSUInteger i = 0; i + 5 < length; i++) {
        if (memcmp(bytes + i, "<?xml", 5) == 0) { start = i; break; }
    }
    if (start == NSNotFound) return nil;
    NSUInteger end = NSNotFound;
    for (NSUInteger i = start; i + 8 < length; i++) {
        if (memcmp(bytes + i, "</plist>", 8) == 0) { end = i + 8; break; }
    }
    if (end == NSNotFound) return nil;
    NSData *plistData = [data subdataWithRange:NSMakeRange(start, end - start)];
    id plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                        options:NSPropertyListImmutable
                                                         format:NULL
                                                          error:nil];
    if ([plist isKindOfClass:[NSDictionary class]]) {
        id entitlements = plist[@"Entitlements"];
        if ([entitlements isKindOfClass:[NSDictionary class]]) return entitlements;
    }
    return nil;
}

NSDictionary *FKEntitlements(void) {
    static NSDictionary *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *merged = [NSMutableDictionary dictionary];
        NSDictionary *profile = FKEntitlementsFromProfile();
        if (profile) [merged addEntriesFromDictionary:profile];
        NSDictionary *signedOnes = FKEntitlementsFromMachO();
        if (signedOnes) [merged addEntriesFromDictionary:signedOnes];

        cached = merged.count ? [merged copy] : @{};
    });
    return cached;
}

NSString *FKDeviceModelIdentifier(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t size = 0;
        if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) == 0 && size > 0) {
            char *value = malloc(size);
            if (sysctlbyname("hw.machine", value, &size, NULL, 0) == 0) {
                cached = [NSString stringWithUTF8String:value];
            }
            free(value);
        }
        if (!cached.length) cached = @"iPhone";
    });
    return cached;
}

NSString *FKOSVersionString(void) {
    NSDictionary *system = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *version = system[@"ProductVersion"];
    if ([version isKindOfClass:[NSString class]]) return version;
    return [[UIDevice currentDevice] systemVersion];
}

uint64_t FKResidentMemory(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        return info.resident_size;
    }
    return 0;
}

NSArray<NSString *> *FKLanAddresses(void) {
    NSMutableArray *addresses = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return addresses;
    for (struct ifaddrs *cursor = interfaces; cursor != NULL; cursor = cursor->ifa_next) {
        if (!cursor->ifa_addr || cursor->ifa_addr->sa_family != AF_INET) continue;
        NSString *name = [NSString stringWithUTF8String:cursor->ifa_name ?: ""];
        if ([name hasPrefix:@"lo"]) continue;
        char buffer[INET_ADDRSTRLEN];
        struct sockaddr_in *sin = (struct sockaddr_in *)cursor->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, buffer, sizeof(buffer))) {
            [addresses addObject:[NSString stringWithUTF8String:buffer]];
        }
    }
    freeifaddrs(interfaces);
    return addresses;
}

NSString *FKLanAddress(void) {
    return FKLanAddresses().firstObject ?: @"127.0.0.1";
}

NSString *FKPrimaryInterfaceAddress(void) { return FKLanAddress(); }

#pragma mark - Formatting

NSString *FKHumanSize(unsigned long long bytes) {
    NSArray *units = @[@"B", @"KB", @"MB", @"GB", @"TB"];
    double value = (double)bytes;
    NSUInteger index = 0;
    while (value >= 1024.0 && index + 1 < units.count) { value /= 1024.0; index++; }
    return [NSString stringWithFormat:(index == 0 ? @"%.0f %@" : @"%.1f %@"), value, units[index]];
}

NSString *FKHexDump(NSData *data, NSUInteger baseOffset, NSUInteger maxBytes) {
    if (!data.length) return @"";
    NSUInteger length = MIN(data.length, maxBytes);
    const uint8_t *bytes = data.bytes;
    NSMutableString *output = [NSMutableString stringWithCapacity:length * 4];
    for (NSUInteger offset = 0; offset < length; offset += 16) {
        [output appendFormat:@"%08lx  ", (unsigned long)(baseOffset + offset)];
        for (NSUInteger i = 0; i < 16; i++) {
            if (offset + i < length) [output appendFormat:@"%02x ", bytes[offset + i]];
            else [output appendString:@"   "];
            if (i == 7) [output appendString:@" "];
        }
        [output appendString:@" |"];
        for (NSUInteger i = 0; i < 16 && offset + i < length; i++) {
            uint8_t byte = bytes[offset + i];
            [output appendFormat:@"%c", (byte >= 32 && byte < 127) ? byte : '.'];
        }
        [output appendString:@"|\n"];
    }
    return output;
}

id FKJSONSafe(id object) {
    if (!object) return [NSNull null];
    if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) return object;
    if ([object isKindOfClass:[NSNull class]]) return object;
    if ([object isKindOfClass:[NSData class]]) return [object base64EncodedStringWithOptions:0];
    if ([object isKindOfClass:[NSDate class]]) return @([(NSDate *)object timeIntervalSince1970]);
    if ([object isKindOfClass:[NSURL class]]) return [(NSURL *)object absoluteString];
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id value in (NSArray *)object) [result addObject:FKJSONSafe(value)];
        return result;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            NSString *stringKey = [key description];
            result[stringKey] = FKJSONSafe(value);
        }];
        return result;
    }
    if ([object isKindOfClass:[NSValue class]]) return [(NSValue *)object description];
    return [object description];
}

NSString *FKJSONString(id object, BOOL pretty) {
    id safe = FKJSONSafe(object);
    if (![NSJSONSerialization isValidJSONObject:safe]) {
        safe = @{ @"value": [safe description] ?: @"" };
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe
                                                   options:(pretty ? NSJSONWritingPrettyPrinted : 0)
                                                     error:&error];
    if (!data) return [NSString stringWithFormat:@"{\"error\":\"%@\"}", error.localizedDescription ?: @"encode failed"];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string ?: @"{}";
}

NSString *FKFormatDate(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    return [formatter stringFromDate:date ?: [NSDate date]];
}

NSString *FKRandomToken(NSUInteger byteCount) {
    NSMutableData *data = [NSMutableData dataWithLength:MAX(byteCount, 16)];
    if (SecRandomCopyBytes(kSecRandomDefault, data.length, data.mutableBytes) != errSecSuccess) {
        arc4random_buf(data.mutableBytes, data.length);
    }
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

NSString *FKURLEncode(NSString *string) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

NSString *FKURLDecode(NSString *string) {
    return [string stringByRemovingPercentEncoding] ?: string;
}

NSDictionary<NSString *, NSString *> *FKParseQuery(NSString *query) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (!query.length) return result;
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        NSString *key = equals.location == NSNotFound ? pair : [pair substringToIndex:equals.location];
        NSString *value = equals.location == NSNotFound ? @"" : [pair substringFromIndex:equals.location + 1];
        key = FKURLDecode([key stringByReplacingOccurrencesOfString:@"+" withString:@" "]);
        value = FKURLDecode([value stringByReplacingOccurrencesOfString:@"+" withString:@" "]);
        if (key.length) result[key] = value;
    }
    return result;
}

#pragma mark - Files

NSData *FKReadData(NSString *path, NSError **error) {
    return [NSData dataWithContentsOfFile:path options:0 error:error];
}

BOOL FKWriteDataAtomically(NSData *data, NSString *path, NSError **error) {
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length && ![[NSFileManager defaultManager] fileExistsAtPath:directory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                        withIntermediateDirectories:YES
                                                         attributes:nil
                                                              error:error]) {
            return NO;
        }
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

NSString *FKExpandPath(NSString *path) {
    if (!path.length) return FKContainerPath();
    NSString *expanded = [path stringByExpandingTildeInPath];
    NSDictionary *tokens = @{
        @"$APP": FKBundlePath(),
        @"$HOME": FKHomePath(),
        @"$CONTAINER": FKContainerPath(),
        @"$DOCS": FKDocumentsPath(),
        @"$LIB": FKLibraryPath(),
        @"$TMP": FKTempPath(),
    };
    for (NSString *token in tokens) {
        expanded = [expanded stringByReplacingOccurrencesOfString:token withString:tokens[token]];
    }
    if (![expanded isAbsolutePath]) expanded = [FKContainerPath() stringByAppendingPathComponent:expanded];
    return [expanded stringByStandardizingPath];
}

NSString *FKModeString(mode_t mode) {
    char buffer[11];
    buffer[0] = S_ISDIR(mode) ? 'd' : (S_ISLNK(mode) ? 'l' : '-');
    const char *rwx = "rwxrwxrwx";
    for (int i = 0; i < 9; i++) buffer[i + 1] = (mode & (1 << (8 - i))) ? rwx[i] : '-';
    buffer[10] = 0;
    return [NSString stringWithUTF8String:buffer];
}

NSDictionary *FKFileAttributes(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:&error];
    if (!attributes) {
        return @{ @"path": path ?: @"", @"exists": @NO, @"error": error.localizedDescription ?: @"missing" };
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"path"] = path;
    info[@"exists"] = @YES;
    info[@"directory"] = @([attributes[NSFileType] isEqualToString:NSFileTypeDirectory]);
    info[@"symlink"] = @([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]);
    info[@"size"] = attributes[NSFileSize] ?: @0;
    info[@"size_text"] = FKHumanSize([attributes[NSFileSize] unsignedLongLongValue]);
    info[@"mode"] = FKModeString([attributes[NSFilePosixPermissions] unsignedShortValue]);
    info[@"mode_octal"] = [NSString stringWithFormat:@"%o", [attributes[NSFilePosixPermissions] unsignedShortValue] & 07777];
    info[@"owner"] = attributes[NSFileOwnerAccountName] ?: @"?";
    info[@"group"] = attributes[NSFileGroupOwnerAccountName] ?: @"?";
    if (attributes[NSFileModificationDate]) info[@"modified"] = @([attributes[NSFileModificationDate] timeIntervalSince1970]);
    if (attributes[NSFileCreationDate]) info[@"created"] = @([attributes[NSFileCreationDate] timeIntervalSince1970]);
    info[@"readable"] = @([fm isReadableFileAtPath:path]);
    info[@"writable"] = @([fm isWritableFileAtPath:path]);
    info[@"executable"] = @([fm isExecutableFileAtPath:path]);
    if (info[@"symlink"]) {
        NSString *destination = [fm destinationOfSymbolicLinkAtPath:path error:nil];
        if (destination) info[@"destination"] = destination;
    }
    NSNumber *fileSize = attributes[NSFileSize];
    info[@"type"] = [info[@"directory"] boolValue] ? @"directory"
                   : ([path.pathExtension.lowercaseString isEqualToString:@"dylib"] ? @"dylib" : @"file");
    if (![info[@"directory"] boolValue]) info[@"extension"] = path.pathExtension ?: @"";
    (void)fileSize;
    return info;
}

NSArray<NSDictionary *> *FKDirectoryList(NSString *path, BOOL includeHidden, NSError **error) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *listingError = nil;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:path error:&listingError];
    if (!names) {
        if (error) *error = listingError;
        return @[];
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in names) {
        if (!includeHidden && [name hasPrefix:@"."]) continue;
        NSString *full = [path stringByAppendingPathComponent:name];
        NSDictionary *attributes = [fm attributesOfItemAtPath:full error:nil];
        BOOL isDirectory = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
        unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
        NSMutableDictionary *entry = [@{
            @"name": name,
            @"path": full,
            @"directory": @(isDirectory),
            @"size": @(size),
            @"size_text": isDirectory ? @"—" : FKHumanSize(size),
        } mutableCopy];
        if (attributes[NSFileModificationDate]) entry[@"modified"] = @([attributes[NSFileModificationDate] timeIntervalSince1970]);
        [entries addObject:entry];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aDir = [a[@"directory"] boolValue];
        BOOL bDir = [b[@"directory"] boolValue];
        if (aDir != bDir) return aDir ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return entries;
}

#pragma mark - Mach-O

static uint32_t FKReadU32(const uint8_t *bytes, NSUInteger offset, BOOL littleEndian) {
    uint32_t value;
    memcpy(&value, bytes + offset, 4);
    return littleEndian ? value : __builtin_bswap32(value);
}

NSArray<NSDictionary *> *FKMachODependencies(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (data.length < 32) return @[];
    const uint8_t *bytes = data.bytes;
    uint32_t magic = FKReadU32(bytes, 0, YES);
    BOOL littleEndian = YES;
    BOOL is64 = NO;
    if (magic == 0xfeedfacf) { is64 = YES; }
    else if (magic == 0xfeedface) { is64 = NO; }
    else if (magic == 0xcffaedfe) { littleEndian = NO; is64 = YES; }
    else if (magic == 0xcefaedfe) { littleEndian = NO; is64 = NO; }
    else if (magic == 0xbebafeca || magic == 0xcafebabe) {
        // Fat binary: parse the first slice.
        uint32_t count = FKReadU32(bytes, 4, NO);
        if (count == 0 || data.length < 8 + count * 20) return @[];
        uint32_t offset = FKReadU32(bytes, 8 + 8, NO); // cputype(4)+cpusubtype(4)+offset(4)
        if (offset >= data.length) return @[];
        NSData *slice = [data subdataWithRange:NSMakeRange(offset, data.length - offset)];
        NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fk-macho-slice"];
        [slice writeToFile:temp atomically:YES];
        NSArray *result = FKMachODependencies(temp);
        [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];
        return result;
    } else {
        return @[];
    }

    NSUInteger headerSize = is64 ? 32 : 28;
    if (data.length < headerSize) return @[];
    uint32_t ncmds = FKReadU32(bytes, 16, littleEndian);
    NSUInteger offset = headerSize;
    NSMutableArray *dependencies = [NSMutableArray array];

    for (uint32_t i = 0; i < ncmds && offset + 8 <= data.length; i++) {
        uint32_t cmd = FKReadU32(bytes, offset, littleEndian);
        uint32_t cmdSize = FKReadU32(bytes, offset + 4, littleEndian);
        if (cmdSize < 8 || offset + cmdSize > data.length) break;

        if (cmd == 0xc || cmd == 0x80000018 || cmd == 0x8000001f || cmd == 0xd || cmd == 0x8000001c
            || cmd == 0x1f /* LC_LOAD_UPWARD_DYLIB */) {
            uint32_t nameOffset = FKReadU32(bytes, offset + 8, littleEndian);
            if (nameOffset < cmdSize) {
                const char *name = (const char *)(bytes + offset + nameOffset);
                NSUInteger maxLength = cmdSize - nameOffset;
                NSUInteger length = strnlen(name, maxLength);
                NSString *value = [[NSString alloc] initWithBytes:name length:length encoding:NSUTF8StringEncoding];
                NSString *type = @"load";
                if (cmd == 0xd) type = @"id";
                else if (cmd == 0x80000018) type = @"weak";
                else if (cmd == 0x8000001f) type = @"reexport";
                else if (cmd == 0x8000001c) type = @"rpath";
                else if (cmd == 0x1f) type = @"upward";
                if (value.length) [dependencies addObject:@{ @"type": type, @"path": value }];
            }
        }
        offset += cmdSize;
    }
    return dependencies;
}

NSArray<NSString *> *FKLoadedImages(void) {
    NSMutableArray *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) [images addObject:[NSString stringWithUTF8String:name] ?: @""];
    }
    return images;
}

#pragma mark - Keychain / cookies

NSArray<NSDictionary *> *FKKeychainItems(NSString *itemClass) {
    CFStringRef secClass = kSecClassGenericPassword;
    if ([itemClass.lowercaseString isEqualToString:@"internet"]) secClass = kSecClassInternetPassword;
    if ([itemClass.lowercaseString isEqualToString:@"certificate"]) secClass = kSecClassCertificate;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)secClass,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return @[];
    NSArray *items = (__bridge_transfer NSArray *)result;
    NSMutableArray *output = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"service"] = item[(__bridge id)kSecAttrService] ?: @"";
        entry[@"account"] = item[(__bridge id)kSecAttrAccount] ?: @"";
        entry[@"access_group"] = item[(__bridge id)kSecAttrAccessGroup] ?: @"";
        entry[@"class"] = item[(__bridge id)kSecClass] ?: @"";
        NSData *secret = item[(__bridge id)kSecValueData];
        if ([secret isKindOfClass:[NSData class]]) {
            entry[@"data"] = [secret base64EncodedStringWithOptions:0];
            NSString *utf8 = [[NSString alloc] initWithData:secret encoding:NSUTF8StringEncoding];
            if (utf8.length) entry[@"text"] = utf8;
        }
        [output addObject:entry];
    }
    return output;
}

NSArray<NSDictionary *> *FKHTTPCookies(void) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
        [result addObject:@{
            @"name": cookie.name ?: @"",
            @"value": cookie.value ?: @"",
            @"domain": cookie.domain ?: @"",
            @"path": cookie.path ?: @"",
            @"secure": @(cookie.isSecure),
            @"http_only": @(cookie.isHTTPOnly),
            @"expires": cookie.expiresDate ? @([cookie.expiresDate timeIntervalSince1970]) : @0,
        }];
    }
    return result;
}

NSDictionary *FKApplicationPaths(void) {
    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    paths[@"bundle"] = FKBundlePath();
    paths[@"executable"] = NSBundle.mainBundle.executablePath ?: @"";
    paths[@"container"] = FKContainerPath();
    paths[@"documents"] = FKDocumentsPath();
    paths[@"library"] = FKLibraryPath();
    paths[@"caches"] = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject] ?: @"";
    paths[@"temp"] = FKTempPath();
    NSArray *groups = FKGroupContainerPaths();
    paths[@"group_containers"] = groups;
    paths[@"bundle_info_plist"] = [FKBundlePath() stringByAppendingPathComponent:@"Info.plist"];
    paths[@"embedded_profile"] = [FKBundlePath() stringByAppendingPathComponent:@"embedded.mobileprovision"];
    return paths;
}

#pragma mark - Swizzling

void FKSwizzleInstance(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        FKLog(@"swizzle failed %@ %@", cls, NSStringFromSelector(original));
        return;
    }
    if (class_addMethod(cls, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod))) {
        class_replaceMethod(cls, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

void FKSwizzleClass(Class cls, SEL original, SEL replacement) {
    Class meta = object_getClass(cls);
    if (!meta) return;
    FKSwizzleInstance(meta, original, replacement);
}

#pragma mark - Window helpers

UIWindowScene *FKActiveWindowScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive) return windowScene;
        if (!fallback) fallback = windowScene;
    }
    return fallback;
}

UIWindow *FKKeyWindow(void) {
    UIWindowScene *scene = FKActiveWindowScene();
    if (scene) {
        for (UIWindow *window in scene.windows) {
            if (window.isKeyWindow) return window;
        }
        for (UIWindow *window in scene.windows) {
            if (!window.hidden && window.windowLevel <= UIWindowLevelStatusBar) return window;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

UIViewController *FKTopViewController(void) {
    UIViewController *controller = FKKeyWindow().rootViewController;
    while (controller) {
        UIViewController *next = nil;
        if ([controller isKindOfClass:[UINavigationController class]])
            next = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:[UITabBarController class]])
            next = ((UITabBarController *)controller).selectedViewController;
        else if (controller.presentedViewController)
            next = controller.presentedViewController;
        if (!next) break;
        controller = next;
    }
    return controller;
}

void FKRunOnMain(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        // Synchronous: callers (HTTP worker threads) read the result immediately after.
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

UIImage *FKSnapshotKeyWindow(void) {
    UIWindow *window = FKKeyWindow();
    if (!window) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
}

void FKPresentAlert(NSString *title, NSString *message) {
    FKRunOnMain(^{
        UIViewController *host = FKTopViewController();
        if (!host) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [host presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Preferences

static NSString * const FKPrefPrefix = @"fk.";

@implementation FKPrefs

+ (NSUserDefaults *)defaults { return [NSUserDefaults standardUserDefaults]; }

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)value {
    id stored = [[self defaults] objectForKey:[FKPrefPrefix stringByAppendingString:key]];
    return stored ? [stored boolValue] : value;
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[self defaults] setBool:value forKey:[FKPrefPrefix stringByAppendingString:key]];
    [self synchronize];
}

+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)value {
    id stored = [[self defaults] objectForKey:[FKPrefPrefix stringByAppendingString:key]];
    return stored ? [stored integerValue] : value;
}

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [[self defaults] setInteger:value forKey:[FKPrefPrefix stringByAppendingString:key]];
    [self synchronize];
}

+ (double)doubleForKey:(NSString *)key defaultValue:(double)value {
    id stored = [[self defaults] objectForKey:[FKPrefPrefix stringByAppendingString:key]];
    return stored ? [stored doubleValue] : value;
}

+ (void)setDouble:(double)value forKey:(NSString *)key {
    [[self defaults] setDouble:value forKey:[FKPrefPrefix stringByAppendingString:key]];
    [self synchronize];
}

+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)value {
    id stored = [[self defaults] objectForKey:[FKPrefPrefix stringByAppendingString:key]];
    return [stored isKindOfClass:[NSString class]] ? stored : value;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    [[self defaults] setObject:value forKey:[FKPrefPrefix stringByAppendingString:key]];
    [self synchronize];
}

+ (NSString *)token {
    NSString *token = [self stringForKey:@"token" defaultValue:@""];
    if (!token.length) {
        token = FKRandomToken(24);
        [[self defaults] setObject:token forKey:@"fk.token"];
        [self synchronize];
    }
    return token;
}

+ (void)regenerateToken {
    [[self defaults] setObject:FKRandomToken(24) forKey:@"fk.token"];
    [self synchronize];
}

+ (void)synchronize { [[self defaults] synchronize]; }

@end
