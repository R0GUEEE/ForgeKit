//
//  FKShell.m — sandbox shell: filesystem, inspection, keychain, transfer
//
//  Every command is implemented with Foundation/POSIX APIs. There is no popen,
//  no exec, no shell expansion, so nothing here depends on a jailbreak.
//

#import "FKShell.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <pwd.h>
#import <grp.h>
#import <mach/mach.h>
#import <fnmatch.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>
#import "FKIL2CPP.h"

static const NSUInteger FKShellMaxOutput = 4 * 1024 * 1024;

#pragma mark - Helpers

static NSArray<NSString *> *FKShellTokens(NSString *line) {
    NSMutableArray *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL single = NO, doubleQuote = NO, escaped = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (escaped) { [current appendFormat:@"%C", c]; escaped = NO; continue; }
        if (c == '\\' && !single) { escaped = YES; continue; }
        if (c == '\'' && !doubleQuote) { single = !single; continue; }
        if (c == '"' && !single) { doubleQuote = !doubleQuote; continue; }
        if ((c == ' ' || c == '\t') && !single && !doubleQuote) {
            if (current.length) { [tokens addObject:[current copy]]; [current setString:@""]; }
            continue;
        }
        [current appendFormat:@"%C", c];
    }
    if (current.length) [tokens addObject:[current copy]];
    return tokens;
}

static NSString *FKShellResolve(NSString *path, NSString *cwd) {
    if (!path.length) return cwd;
    NSString *expanded = path;
    if ([path isEqualToString:@"~"]) expanded = NSHomeDirectory();
    else if ([path hasPrefix:@"~/"]) expanded = [NSHomeDirectory() stringByAppendingPathComponent:[path substringFromIndex:2]];
    if ([expanded isAbsolutePath]) return [expanded stringByStandardizingPath];
    return [[cwd stringByAppendingPathComponent:expanded] stringByStandardizingPath];
}

static NSString *FKShellSize(unsigned long long bytes) { return FKHumanSize(bytes); }

static NSString *FKShellMode(mode_t mode, BOOL isDirectory) {
    char buffer[11];
    buffer[0] = isDirectory ? 'd' : (S_ISLNK(mode) ? 'l' : '-');
    const char *rwx = "rwxrwxrwx";
    for (int i = 0; i < 9; i++) buffer[i + 1] = (mode & (1 << (8 - i))) ? rwx[i] : '-';
    buffer[10] = 0;
    return [NSString stringWithUTF8String:buffer];
}

static NSData *FKShellReadFile(NSString *path) {
    return [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
}

static BOOL FKShellLooksText(NSData *data) {
    if (!data.length) return YES;
    const uint8_t *bytes = data.bytes;
    NSUInteger limit = MIN(data.length, (NSUInteger)8192);
    NSUInteger control = 0;
    for (NSUInteger i = 0; i < limit; i++) {
        uint8_t b = bytes[i];
        if (b == 0) return NO;
        if (b < 9 || (b > 13 && b < 32)) control++;
    }
    return control * 20 < limit;
}

static NSString *FKShellTruncate(NSString *text) {
    if (text.length <= FKShellMaxOutput) return text;
    return [[text substringToIndex:FKShellMaxOutput] stringByAppendingString:
            @"\n… output truncated at 4 MB"];
}

static NSString *FKShellFileType(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    NSDictionary *types = @{
        @"png": @"PNG image", @"jpg": @"JPEG image", @"jpeg": @"JPEG image", @"gif": @"GIF image",
        @"webp": @"WebP image", @"heic": @"HEIC image", @"plist": @"property list",
        @"json": @"JSON data", @"xml": @"XML document", @"txt": @"ASCII text", @"md": @"Markdown text",
        @"html": @"HTML document", @"css": @"CSS stylesheet", @"js": @"JavaScript source",
        @"swift": @"Swift source", @"m": @"Objective-C source", @"mm": @"Objective-C++ source",
        @"h": @"C header", @"c": @"C source", @"cpp": @"C++ source", @"dylib": @"Mach-O dynamic library",
        @"zip": @"Zip archive", @"gz": @"gzip compressed data", @"tar": @"tar archive",
        @"deb": @"Debian package", @"sqlite": @"SQLite database", @"db": @"database",
        @"mp4": @"MPEG-4 video", @"mov": @"QuickTime video", @"mp3": @"MP3 audio",
        @"m4a": @"AAC audio", @"pdf": @"PDF document", @"ttf": @"TrueType font",
        @"mobileprovision": @"provisioning profile", @"p12": @"PKCS#12 certificate",
    };
    if (types[extension]) return types[extension];
    NSData *fileData = FKShellReadFile(path);
    NSData *head = fileData.length ? [fileData subdataWithRange:NSMakeRange(0, MIN((NSUInteger)16, fileData.length))] : nil;
    if (head.length >= 4) {
        uint32_t magic = 0; [head getBytes:&magic length:4];
        if (magic == 0xfeedfacf || magic == 0xcffaedfe) return @"Mach-O 64-bit image";
        if (magic == 0x504b0304) return @"Zip archive";
        if (magic == 0x89504e47) return @"PNG image";
        if (magic == 0xffd8ffe0 || magic == 0xffd8ffe1) return @"JPEG image";
        if (magic == 0x1f8b0800) return @"gzip compressed data";
    }
    return extension.length ? [NSString stringWithFormat:@"%@ data", extension] : @"data";
}

static NSString *FKShellDigest(NSString *path, BOOL sha256) {
    NSData *data = FKShellReadFile(path);
    if (!data) return @"Error: cannot read file";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (sha256) CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    else CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    NSUInteger length = sha256 ? CC_SHA256_DIGEST_LENGTH : CC_MD5_DIGEST_LENGTH;
    for (NSUInteger i = 0; i < length; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static unsigned long long FKShellDirectorySize(NSString *path, NSInteger depth) {
    if (depth > 24) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) return 0;
    if (!isDirectory) return [[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
    unsigned long long total = 0;
    for (NSString *child in [fm contentsOfDirectoryAtPath:path error:nil] ?: @[])
        total += FKShellDirectorySize([path stringByAppendingPathComponent:child], depth + 1);
    return total;
}

#pragma mark - Shell

@implementation FKShell

+ (instancetype)sharedShell {
    static FKShell *shell;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shell = [[FKShell alloc] init];
        shell.currentDirectory = NSHomeDirectory();
    });
    return shell;
}

- (instancetype)init {
    self = [super init];
    if (self) _currentDirectory = NSHomeDirectory();
    return self;
}

- (NSArray<NSString *> *)commandNames {
    return @[@"ls", @"pwd", @"cd", @"tree", @"cat", @"head", @"tail", @"hexdump", @"strings",
             @"base64", @"cp", @"mv", @"rm", @"mkdir", @"touch", @"chmod", @"stat", @"file",
             @"md5", @"sha256", @"wc", @"du", @"realpath", @"readlink", @"find", @"grep",
             @"id", @"uname", @"whoami", @"env", @"date", @"df", @"uptime", @"bundle",
             @"sandbox", @"sysinfo", @"memory", @"containers", @"keychain", @"scp", @"download",
             @"echo", @"help", @"version"];
}

+ (NSString *)helpText {
    return @"Sandbox shell — no popen, no exec, no shell expansion.\n"
           "Navigation : ls [-a] [-l] [path] · pwd · cd [path] · tree [-d N] [path]\n"
           "Read       : cat · head [-n N] · tail [-n N] · hexdump [-n N] · strings [-n N] · base64 [-d]\n"
           "Modify     : cp [-r] src dst · mv · rm [-r] · mkdir [-p] · touch · chmod mode path\n"
           "Inspect    : stat · file · md5 · sha256 · wc · du [-h] · realpath · readlink\n"
           "Search     : find [path] [-name pat] · grep [-i] [-n] pattern [path]\n"
           "System     : id · uname [-a] · whoami · env · date · df · uptime · bundle · sandbox\n"
           "             sysinfo · memory · containers\n"
           "Keychain   : keychain [dump] [--class generic|internet|certificate]\n"
           "Transfer   : download <path> [host_path] · scp -r <path> host:./dir\n"
           "Misc       : echo · help · version\n"
           "Paths accept ~, absolute paths and paths relative to the current directory.";
}

- (NSString *)execute:(NSString *)commandLine {
    return [self execute:commandLine inDirectory:self.currentDirectory];
}

- (NSString *)execute:(NSString *)commandLine inDirectory:(NSString *)directory {
    NSString *cwd = directory.length ? directory : self.currentDirectory;
    NSArray<NSString *> *tokens = FKShellTokens([commandLine stringByTrimmingCharactersInSet:
                                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]]);
    if (!tokens.count) return @"";
    NSString *command = tokens[0].lowercaseString;
    NSArray<NSString *> *args = tokens.count > 1 ? [tokens subarrayWithRange:NSMakeRange(1, tokens.count - 1)] : @[];

    NSString *result = nil;

    if ([command isEqualToString:@"pwd"]) result = cwd;
    else if ([command isEqualToString:@"cd"]) result = [self cd:args cwd:&cwd];
    else if ([command isEqualToString:@"ls"]) result = [self ls:args cwd:cwd];
    else if ([command isEqualToString:@"tree"]) result = [self tree:args cwd:cwd];
    else if ([command isEqualToString:@"cat"]) result = [self cat:args cwd:cwd];
    else if ([command isEqualToString:@"head"] || [command isEqualToString:@"tail"])
        result = [self headTail:args cwd:cwd tail:[command isEqualToString:@"tail"]];
    else if ([command isEqualToString:@"hexdump"]) result = [self hexdump:args cwd:cwd];
    else if ([command isEqualToString:@"strings"]) result = [self strings:args cwd:cwd];
    else if ([command isEqualToString:@"base64"]) result = [self base64:args cwd:cwd];
    else if ([command isEqualToString:@"cp"]) result = [self copyOrMove:args cwd:cwd move:NO];
    else if ([command isEqualToString:@"mv"]) result = [self copyOrMove:args cwd:cwd move:YES];
    else if ([command isEqualToString:@"rm"]) result = [self remove:args cwd:cwd];
    else if ([command isEqualToString:@"mkdir"]) result = [self mkdir:args cwd:cwd];
    else if ([command isEqualToString:@"touch"]) result = [self touch:args cwd:cwd];
    else if ([command isEqualToString:@"chmod"]) result = [self chmod:args cwd:cwd];
    else if ([command isEqualToString:@"stat"]) result = [self stat:args cwd:cwd];
    else if ([command isEqualToString:@"file"]) result = [self file:args cwd:cwd];
    else if ([command isEqualToString:@"md5"]) result = [self digest:args cwd:cwd sha256:NO];
    else if ([command isEqualToString:@"sha256"]) result = [self digest:args cwd:cwd sha256:YES];
    else if ([command isEqualToString:@"wc"]) result = [self wordCount:args cwd:cwd];
    else if ([command isEqualToString:@"du"]) result = [self diskUsage:args cwd:cwd];
    else if ([command isEqualToString:@"realpath"]) result = [self realpath:args cwd:cwd];
    else if ([command isEqualToString:@"readlink"]) result = [self readlink:args cwd:cwd];
    else if ([command isEqualToString:@"find"]) result = [self find:args cwd:cwd];
    else if ([command isEqualToString:@"grep"]) result = [self grep:args cwd:cwd];
    else if ([command isEqualToString:@"id"]) result = [self identity];
    else if ([command isEqualToString:@"whoami"]) result = NSUserName() ?: @"mobile";
    else if ([command isEqualToString:@"uname"]) result = [self uname:args];
    else if ([command isEqualToString:@"env"]) result = [self environment];
    else if ([command isEqualToString:@"date"]) result = [NSDate date].description;
    else if ([command isEqualToString:@"df"]) result = [self diskFree:cwd];
    else if ([command isEqualToString:@"uptime"]) result = [self uptime];
    else if ([command isEqualToString:@"bundle"]) result = [self bundleInfo];
    else if ([command isEqualToString:@"sandbox"]) result = [self sandboxInfo];
    else if ([command isEqualToString:@"sysinfo"]) result = [self systemInfo];
    else if ([command isEqualToString:@"memory"]) result = [self memoryInfo];
    else if ([command isEqualToString:@"containers"]) result = [self containers];
    else if ([command isEqualToString:@"keychain"]) result = [self keychain:args];
    else if ([command isEqualToString:@"scp"]) result = [self scp:args cwd:cwd];
    else if ([command isEqualToString:@"download"]) result = [self download:args cwd:cwd];
    else if ([command isEqualToString:@"echo"]) result = [args componentsJoinedByString:@" "];
    else if ([command isEqualToString:@"help"]) result = [FKShell helpText];
    else if ([command isEqualToString:@"version"])
        result = [NSString stringWithFormat:@"ForgeKit shell %@ · iOS %@ · %@",
                  FKVersionString, FKOSVersionString(), FKDeviceModelIdentifier()];
    else
        result = [NSString stringWithFormat:@"Unknown command: %@\nType 'help' for available commands.", command];

    if (cwd != self.currentDirectory && [directory isEqualToString:self.currentDirectory])
        self.currentDirectory = cwd;
    return FKShellTruncate(result ?: @"");
}

#pragma mark - Navigation

- (NSString *)cd:(NSArray *)args cwd:(NSString **)cwd {
    NSString *target = args.count ? args[0] : NSHomeDirectory();
    NSString *path = FKShellResolve(target, *cwd);
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
        return [NSString stringWithFormat:@"cd: %@: No such directory", target];
    *cwd = path;
    return [NSString stringWithFormat:@"Changed directory to %@", path];
}

- (NSString *)ls:(NSArray *)args cwd:(NSString *)cwd {
    BOOL showHidden = NO, longFormat = NO;
    NSString *target = cwd;
    for (NSString *arg in args) {
        if ([arg hasPrefix:@"-"]) {
            if ([arg containsString:@"a"]) showHidden = YES;
            if ([arg containsString:@"l"]) longFormat = YES;
        } else {
            target = FKShellResolve(arg, cwd);
        }
    }
    NSError *error = nil;
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:target error:&error];
    if (!names) return [NSString stringWithFormat:@"ls: %@", error.localizedDescription ?: @"cannot list"];
    names = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSString *name in names) {
        if (!showHidden && [name hasPrefix:@"."]) continue;
        [visible addObject:name];
    }
    if (!longFormat) return [visible componentsJoinedByString:@"\n"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MMM dd HH:mm";
    NSMutableString *output = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *name in visible) {
        NSString *path = [target stringByAppendingPathComponent:name];
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
        if (!attributes) continue;
        BOOL isDirectory = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
        mode_t mode = (mode_t)[attributes[NSFilePosixPermissions] unsignedShortValue];
        if (isDirectory) mode |= S_IFDIR;
        NSDate *modified = attributes[NSFileModificationDate];
        [output appendFormat:@"%@ %8llu %@ %@%@\n", FKShellMode(mode, isDirectory),
         [attributes[NSFileSize] unsignedLongLongValue],
         modified ? [formatter stringFromDate:modified] : @"???", name, isDirectory ? @"/" : @""];
    }
    return output.length ? output : @"(empty directory)";
}

- (void)appendTree:(NSString *)path prefix:(NSString *)prefix output:(NSMutableString *)output
             depth:(NSInteger)depth maxDepth:(NSInteger)maxDepth
          dirCount:(NSInteger *)dirCount fileCount:(NSInteger *)fileCount {
    if (depth >= maxDepth || output.length > FKShellMaxOutput) return;
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil] ?: @[];
    children = [children sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSString *child in children) if (![child hasPrefix:@"."]) [visible addObject:child];
    for (NSUInteger i = 0; i < visible.count; i++) {
        NSString *child = visible[i];
        BOOL last = (i == visible.count - 1);
        NSString *full = [path stringByAppendingPathComponent:child];
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDirectory];
        if (isDirectory) (*dirCount)++; else (*fileCount)++;
        [output appendFormat:@"%@%@%@%@\n", prefix, last ? @"└── " : @"├── ", child, isDirectory ? @"/" : @""];
        if (isDirectory)
            [self appendTree:full prefix:[prefix stringByAppendingString:last ? @"    " : @"│   "]
                      output:output depth:depth + 1 maxDepth:maxDepth dirCount:dirCount fileCount:fileCount];
    }
}

- (NSString *)tree:(NSArray *)args cwd:(NSString *)cwd {
    NSString *target = cwd;
    NSInteger depth = 4;
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:@"-d"] && i + 1 < args.count) depth = [args[i + 1] integerValue];
        else if (![args[i] hasPrefix:@"-"]) target = FKShellResolve(args[i], cwd);
    }
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&isDirectory] || !isDirectory)
        return @"tree: not a directory";
    NSMutableString *output = [NSMutableString stringWithFormat:@"%@\n", target.lastPathComponent];
    NSInteger directories = 0, files = 0;
    [self appendTree:target prefix:@"" output:output depth:0 maxDepth:MAX(1, MIN(depth, 12))
            dirCount:&directories fileCount:&files];
    [output appendFormat:@"\n%ld directories, %ld files", (long)directories, (long)files];
    return output;
}

#pragma mark - Reading

- (NSString *)cat:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: cat <path>";
    NSString *path = FKShellResolve(args[0], cwd);
    NSData *data = FKShellReadFile(path);
    if (!data) return [NSString stringWithFormat:@"cat: %@: cannot read", args[0]];
    if (!FKShellLooksText(data))
        return [NSString stringWithFormat:@"cat: %@: binary file (%@)", args[0], FKShellSize(data.length)];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return text ?: [NSString stringWithFormat:@"cat: %@: not decodable as text", args[0]];
}

- (NSString *)headTail:(NSArray *)args cwd:(NSString *)cwd tail:(BOOL)tail {
    NSInteger count = 10;
    NSString *path = nil;
    for (NSUInteger i = 0; i < args.count; i++) {
        if (([args[i] isEqualToString:@"-n"] || [args[i] isEqualToString:@"-c"]) && i + 1 < args.count)
            count = [args[i + 1] integerValue], i++;
        else if (![args[i] hasPrefix:@"-"]) path = args[i];
    }
    if (!path) return [NSString stringWithFormat:@"Usage: %@ [-n N] <path>", tail ? @"tail" : @"head"];
    NSString *full = FKShellResolve(path, cwd);
    NSData *data = FKShellReadFile(full);
    if (!data) return [NSString stringWithFormat:@"%@: %@: cannot read", tail ? @"tail" : @"head", path];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return [NSString stringWithFormat:@"%@: %@: not a text file", tail ? @"tail" : @"head", path];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    count = MAX(1, MIN(count, 5000));
    NSRange range = tail ? NSMakeRange(lines.count > (NSUInteger)count ? lines.count - (NSUInteger)count : 0,
                                       MIN((NSUInteger)count, lines.count))
                         : NSMakeRange(0, MIN((NSUInteger)count, lines.count));
    return [[lines subarrayWithRange:range] componentsJoinedByString:@"\n"];
}

- (NSString *)hexdump:(NSArray *)args cwd:(NSString *)cwd {
    NSInteger bytes = 512;
    NSString *path = nil;
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:@"-n"] && i + 1 < args.count) bytes = [args[i + 1] integerValue];
        else if (![args[i] hasPrefix:@"-"]) path = args[i];
    }
    if (!path) return @"Usage: hexdump [-n bytes] <path>";
    NSData *data = FKShellReadFile(FKShellResolve(path, cwd));
    if (!data) return @"hexdump: cannot read file";
    return FKHexDump(data, 0, (NSUInteger)MAX(16, MIN(bytes, 65536)));
}

- (NSString *)strings:(NSArray *)args cwd:(NSString *)cwd {
    NSInteger minimum = 4;
    NSString *path = nil;
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:@"-n"] && i + 1 < args.count) minimum = [args[i + 1] integerValue];
        else if (![args[i] hasPrefix:@"-"]) path = args[i];
    }
    if (!path) return @"Usage: strings [-n min] <path>";
    NSData *data = FKShellReadFile(FKShellResolve(path, cwd));
    if (!data) return @"strings: cannot read file";
    const uint8_t *bytes = data.bytes;
    NSMutableString *output = [NSMutableString string];
    NSMutableString *current = [NSMutableString string];
    NSInteger emitted = 0;
    for (NSUInteger i = 0; i < data.length && emitted < 4000; i++) {
        uint8_t b = bytes[i];
        if (b >= 32 && b < 127) {
            [current appendFormat:@"%c", b];
        } else {
            if ((NSInteger)current.length >= MAX(2, minimum)) {
                [output appendFormat:@"%@\n", current];
                emitted++;
            }
            [current setString:@""];
        }
    }
    if ((NSInteger)current.length >= MAX(2, minimum)) [output appendFormat:@"%@\n", current];
    return output.length ? output : @"(no printable strings)";
}

- (NSString *)base64:(NSArray *)args cwd:(NSString *)cwd {
    BOOL decode = NO;
    NSString *path = nil;
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-d"]) decode = YES;
        else if (![arg hasPrefix:@"-"]) path = arg;
    }
    if (!path) return @"Usage: base64 [-d] <path>";
    NSData *data = FKShellReadFile(FKShellResolve(path, cwd));
    if (!data) return @"base64: cannot read file";
    if (!decode) return [data base64EncodedStringWithOptions:0];
    NSString *encoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSData *decoded = encoded ? [[NSData alloc] initWithBase64EncodedString:
                                 [encoded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                                                  options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
    if (!decoded) return @"base64: invalid input";
    NSString *text = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    return text ?: [NSString stringWithFormat:@"(decoded %@ of binary data)", FKShellSize(decoded.length)];
}

#pragma mark - Modify

- (NSString *)copyOrMove:(NSArray *)args cwd:(NSString *)cwd move:(BOOL)move {
    BOOL recursive = NO;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-r"] || [arg isEqualToString:@"-R"]) recursive = YES;
        else if (![arg hasPrefix:@"-"]) [paths addObject:arg];
    }
    if (paths.count < 2) return [NSString stringWithFormat:@"Usage: %@ %@<source> <destination>",
                                 move ? @"mv" : @"cp", recursive ? @"-r " : @""];
    NSString *source = FKShellResolve(paths[0], cwd);
    NSString *destination = FKShellResolve(paths[1], cwd);
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:source isDirectory:&isDirectory])
        return [NSString stringWithFormat:@"%@: %@: no such file", move ? @"mv" : @"cp", paths[0]];
    BOOL destinationIsDirectory = NO;
    if ([fm fileExistsAtPath:destination isDirectory:&destinationIsDirectory] && destinationIsDirectory)
        destination = [destination stringByAppendingPathComponent:source.lastPathComponent];
    if (isDirectory && !move && !recursive)
        return [NSString stringWithFormat:@"cp: %@ is a directory (use -r)", paths[0]];
    NSError *error = nil;
    [fm createDirectoryAtPath:[destination stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = move ? [fm moveItemAtPath:source toPath:destination error:&error]
                   : [fm copyItemAtPath:source toPath:destination error:&error];
    if (!ok) return [NSString stringWithFormat:@"%@: %@", move ? @"mv" : @"cp",
                     error.localizedDescription ?: @"operation failed"];
    return [NSString stringWithFormat:@"%@: %@ -> %@", move ? @"moved" : @"copied", paths[0], destination];
}

- (NSString *)remove:(NSArray *)args cwd:(NSString *)cwd {
    BOOL recursive = NO;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *arg in args) {
        if ([arg hasPrefix:@"-"]) { if ([arg containsString:@"r"] || [arg containsString:@"R"]) recursive = YES; }
        else [paths addObject:arg];
    }
    if (!paths.count) return @"Usage: rm [-r] <path>";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableString *output = [NSMutableString string];
    for (NSString *path in paths) {
        NSString *full = FKShellResolve(path, cwd);
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDirectory]) {
            [output appendFormat:@"rm: %@: no such file\n", path];
            continue;
        }
        if (isDirectory && !recursive) {
            [output appendFormat:@"rm: %@: is a directory (use -r)\n", path];
            continue;
        }
        NSError *error = nil;
        if (![fm removeItemAtPath:full error:&error])
            [output appendFormat:@"rm: %@: %@\n", path, error.localizedDescription];
        else
            [output appendFormat:@"removed %@\n", path];
    }
    return output;
}

- (NSString *)mkdir:(NSArray *)args cwd:(NSString *)cwd {
    BOOL intermediates = NO;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *arg in args) {
        if ([arg hasPrefix:@"-"]) { if ([arg containsString:@"p"]) intermediates = YES; }
        else [paths addObject:arg];
    }
    if (!paths.count) return @"Usage: mkdir [-p] <path>";
    NSError *error = nil;
    NSMutableString *output = [NSMutableString string];
    for (NSString *path in paths) {
        NSString *full = FKShellResolve(path, cwd);
        if (![[NSFileManager defaultManager] createDirectoryAtPath:full
                                      withIntermediateDirectories:intermediates
                                                       attributes:nil error:&error])
            [output appendFormat:@"mkdir: %@: %@\n", path, error.localizedDescription];
        else
            [output appendFormat:@"created %@\n", full];
    }
    return output;
}

- (NSString *)touch:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: touch <path>";
    NSString *full = FKShellResolve(args[0], cwd);
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:full]) {
        NSError *error = nil;
        if (![fm setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:full error:&error])
            return [NSString stringWithFormat:@"touch: %@", error.localizedDescription];
        return [NSString stringWithFormat:@"touched %@", full];
    }
    NSError *error = nil;
    if (![[NSData data] writeToFile:full options:NSDataWritingAtomic error:&error])
        return [NSString stringWithFormat:@"touch: %@", error.localizedDescription];
    return [NSString stringWithFormat:@"created %@", full];
}

- (NSString *)chmod:(NSArray *)args cwd:(NSString *)cwd {
    if (args.count < 2) return @"Usage: chmod <octal> <path>";
    unsigned long mode = strtoul([args[0] UTF8String], NULL, 8);
    NSString *full = FKShellResolve(args[1], cwd);
    NSError *error = nil;
    if (![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @(mode) }
                                         ofItemAtPath:full error:&error])
        return [NSString stringWithFormat:@"chmod: %@", error.localizedDescription];
    return [NSString stringWithFormat:@"%@ -> %@", full, args[0]];
}

#pragma mark - File info

- (NSString *)stat:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: stat <path>";
    NSString *full = FKShellResolve(args[0], cwd);
    struct stat st;
    if (stat(full.UTF8String, &st) != 0)
        return [NSString stringWithFormat:@"stat: %@: %s", args[0], strerror(errno)];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [NSString stringWithFormat:
            @"  File: %@\n  Size: %lld\t Blocks: %lld\t IO Block: %d\n"
            @"Device: %d\t Inode: %llu\t Links: %d\n"
            @"Access: (%04o/%@)\t Uid: %d\t Gid: %d\n"
            @"Access: %@\nModify: %@\nChange: %@",
            full, (long long)st.st_size, (long long)st.st_blocks, (int)st.st_blksize,
            (int)st.st_dev, (unsigned long long)st.st_ino, (int)st.st_nlink,
            (unsigned)(st.st_mode & 07777), FKShellMode(st.st_mode, S_ISDIR(st.st_mode)),
            (int)st.st_uid, (int)st.st_gid,
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:st.st_atime]],
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:st.st_mtime]],
            [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:st.st_ctime]]];
}

- (NSString *)file:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: file <path>";
    NSString *full = FKShellResolve(args[0], cwd);
    NSData *data = FKShellReadFile(full);
    if (!data) return [NSString stringWithFormat:@"file: %@: cannot read", args[0]];
    return [NSString stringWithFormat:@"%@: %@, %@", full, FKShellFileType(full), FKShellSize(data.length)];
}

- (NSString *)digest:(NSArray *)args cwd:(NSString *)cwd sha256:(BOOL)sha256 {
    if (!args.count) return [NSString stringWithFormat:@"Usage: %@ <path>", sha256 ? @"sha256" : @"md5"];
    NSString *full = FKShellResolve(args[0], cwd);
    NSString *digest = FKShellDigest(full, sha256);
    return [digest hasPrefix:@"Error"] ? digest : [NSString stringWithFormat:@"%@  %@", digest, full];
}

- (NSString *)wordCount:(NSArray *)args cwd:(NSString *)cwd {
    BOOL linesOnly = NO;
    NSString *path = nil;
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-l"]) linesOnly = YES;
        else if (![arg hasPrefix:@"-"]) path = arg;
    }
    if (!path) return @"Usage: wc [-l] <path>";
    NSData *data = FKShellReadFile(FKShellResolve(path, cwd));
    if (!data) return @"wc: cannot read file";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSUInteger lines = [[text componentsSeparatedByString:@"\n"] count] - 1;
    if ([text hasSuffix:@"\n"]) lines++;
    if (linesOnly) return [NSString stringWithFormat:@"%lu", (unsigned long)lines];
    NSArray *words = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger wordCount = 0;
    for (NSString *word in words) if (word.length) wordCount++;
    return [NSString stringWithFormat:@"%lu %lu %llu %@", (unsigned long)lines,
            (unsigned long)wordCount, (unsigned long long)data.length, path];
}

- (NSString *)diskUsage:(NSArray *)args cwd:(NSString *)cwd {
    BOOL human = NO;
    NSString *path = cwd;
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-h"]) human = YES;
        else if (![arg hasPrefix:@"-"]) path = FKShellResolve(arg, cwd);
    }
    unsigned long long size = FKShellDirectorySize(path, 0);
    return [NSString stringWithFormat:@"%@\t%@", human ? FKShellSize(size)
            : [NSString stringWithFormat:@"%llu", size], path];
}

- (NSString *)realpath:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: realpath <path>";
    return [FKShellResolve(args[0], cwd) stringByResolvingSymlinksInPath];
}

- (NSString *)readlink:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: readlink <path>";
    NSString *destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:
                             FKShellResolve(args[0], cwd) error:nil];
    return destination ?: [NSString stringWithFormat:@"readlink: %@: not a symbolic link", args[0]];
}

#pragma mark - Search

- (NSString *)find:(NSArray *)args cwd:(NSString *)cwd {
    NSString *root = cwd;
    NSString *pattern = nil;
    for (NSUInteger i = 0; i < args.count; i++) {
        if (([args[i] isEqualToString:@"-name"] || [args[i] isEqualToString:@"-iname"]) && i + 1 < args.count)
            pattern = args[++i];
        else if (![args[i] hasPrefix:@"-"]) root = FKShellResolve(args[i], cwd);
    }
    NSMutableString *output = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
    NSInteger matches = 0;
    for (NSString *relative in enumerator) {
        if (matches >= 2000 || output.length > FKShellMaxOutput) break;
        NSString *name = relative.lastPathComponent;
        BOOL matched = YES;
        if (pattern.length) {
            if ([pattern rangeOfString:@"*"].location != NSNotFound || [pattern rangeOfString:@"?"].location != NSNotFound)
                matched = fnmatch(pattern.UTF8String, name.UTF8String, FNM_CASEFOLD) == 0;
            else
                matched = [name rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound;
        }
        if (!matched) continue;
        [output appendFormat:@"%@\n", [root stringByAppendingPathComponent:relative]];
        matches++;
    }
    return matches ? output : @"(no matches)";
}

- (NSString *)grep:(NSArray *)args cwd:(NSString *)cwd {
    BOOL ignoreCase = NO, showLine = NO;
    NSString *pattern = nil;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-i"]) ignoreCase = YES;
        else if ([arg isEqualToString:@"-n"]) showLine = YES;
        else if (![arg hasPrefix:@"-"]) {
            if (!pattern) pattern = arg;
            else [paths addObject:arg];
        }
    }
    if (!pattern) return @"Usage: grep [-i] [-n] <pattern> [path]";
    if (!paths.count) [paths addObject:cwd];
    NSMutableString *output = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger matches = 0;

    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *path in paths) {
        NSString *full = FKShellResolve(path, cwd);
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDirectory] && isDirectory) {
            NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:full];
            for (NSString *relative in enumerator) {
                NSString *child = [full stringByAppendingPathComponent:relative];
                NSDictionary *attributes = [fm attributesOfItemAtPath:child error:nil];
                if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
                if ([attributes[NSFileSize] unsignedLongLongValue] > 2 * 1024 * 1024) continue;
                [files addObject:child];
            }
        } else {
            [files addObject:full];
        }
    }

    for (NSString *file in files) {
        if (matches >= 500 || output.length > FKShellMaxOutput) break;
        NSData *data = FKShellReadFile(file);
        if (!data || !FKShellLooksText(data)) continue;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) continue;
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        for (NSUInteger i = 0; i < lines.count && matches < 500; i++) {
            NSString *line = lines[i];
            NSRange range = [line rangeOfString:pattern
                                        options:ignoreCase ? NSCaseInsensitiveSearch : 0];
            if (range.location == NSNotFound) continue;
            if (showLine) [output appendFormat:@"%@:%lu:%@\n", file, (unsigned long)i + 1, line];
            else [output appendFormat:@"%@:%@\n", file, line];
            matches++;
        }
    }
    return matches ? output : @"(no matches)";
}

#pragma mark - System

- (NSString *)identity {
    struct passwd *pw = getpwuid(getuid());
    struct group *gr = getgrgid(getgid());
    return [NSString stringWithFormat:@"uid=%d(%s) gid=%d(%s) euid=%d egid=%d\nsandboxed=%@ jailbroken=%@",
            getuid(), pw ? pw->pw_name : "?", getgid(), gr ? gr->gr_name : "?",
            geteuid(), getegid(),
            FKIsJailbroken() ? @"no" : @"yes", FKIsJailbroken() ? @"yes" : @"no"];
}

- (NSString *)uname:(NSArray *)args {
    struct utsname info;
    if (uname(&info) != 0) return @"uname: failed";
    if (args.count && [args[0] containsString:@"a"])
        return [NSString stringWithFormat:@"%s %s %s %s %s",
                info.sysname, info.nodename, info.release, info.version, info.machine];
    return [NSString stringWithUTF8String:info.machine] ?: @"arm64";
}

- (NSString *)environment {
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSMutableString *output = [NSMutableString string];
    for (NSString *key in [environment.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [output appendFormat:@"%@=%@\n", key, environment[key]];
    return output;
}

- (NSString *)diskFree:(NSString *)cwd {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:cwd error:nil];
    unsigned long long total = [attributes[NSFileSystemSize] unsignedLongLongValue];
    unsigned long long free = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
    return [NSString stringWithFormat:@"Filesystem: container\nSize: %@\nUsed: %@\nAvail: %@\nCapacity: %.0f%%\nPath: %@",
            FKShellSize(total), FKShellSize(total - free), FKShellSize(free),
            total ? (double)(total - free) / total * 100 : 0, cwd];
}

- (NSString *)uptime {
    NSTimeInterval seconds = [[NSProcessInfo processInfo] systemUptime];
    NSInteger days = (NSInteger)(seconds / 86400);
    NSInteger hours = (NSInteger)(seconds / 3600) % 24;
    NSInteger minutes = (NSInteger)(seconds / 60) % 60;
    return [NSString stringWithFormat:@"up %ld days, %ld:%02ld, %.0f users, load %.2f",
            (long)days, (long)hours, (long)minutes, 1.0, 0.0];
}

- (NSString *)bundleInfo {
    NSDictionary *info = FKInfoPlist();
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"Bundle ID:    %@\n", FKAppIdentifier()];
    [output appendFormat:@"Display Name: %@\n", FKAppName()];
    [output appendFormat:@"Version:      %@\n", FKAppVersion()];
    [output appendFormat:@"Executable:   %@\n", info[@"CFBundleExecutable"] ?: @"N/A"];
    [output appendFormat:@"Bundle Path:  %@\n", FKBundlePath()];
    [output appendFormat:@"Container:    %@\n", FKContainerPath()];
    [output appendFormat:@"Min iOS:      %@\n", info[@"MinimumOSVersion"] ?: @"N/A"];
    [output appendFormat:@"SDK:          %@\n", info[@"DTSDKName"] ?: @"N/A"];
    [output appendFormat:@"Platform:     %@\n", info[@"DTPlatformName"] ?: @"N/A"];
    NSArray *urlTypes = info[@"CFBundleURLTypes"];
    NSMutableArray *schemes = [NSMutableArray array];
    for (NSDictionary *type in urlTypes) [schemes addObjectsFromArray:type[@"CFBundleURLSchemes"] ?: @[]];
    if (schemes.count) [output appendFormat:@"URL Schemes:  %@\n", [schemes componentsJoinedByString:@", "]];
    NSDictionary *ats = info[@"NSAppTransportSecurity"];
    if (ats) [output appendFormat:@"ATS:          %@\n",
              [ats[@"NSAllowsArbitraryLoads"] boolValue] ? @"allows arbitrary loads" : @"restricted"];
    return output;
}

- (NSString *)sandboxInfo {
    NSMutableString *output = [NSMutableString stringWithString:@"=== Sandbox paths ===\n"];
    [output appendFormat:@"Home:       %@\n", FKHomePath()];
    [output appendFormat:@"Tmp:        %@\n", FKTempPath()];
    [output appendFormat:@"Bundle:     %@\n", FKBundlePath()];
    [output appendFormat:@"Documents:  %@\n", FKDocumentsPath()];
    [output appendFormat:@"Library:    %@\n", FKLibraryPath()];
    for (NSString *group in FKGroupContainerPaths()) [output appendFormat:@"App Group:  %@\n", group];
    [output appendString:@"\n=== Access test ===\n"];
    NSArray *paths = @[FKHomePath(), FKTempPath(), @"/var/mobile", @"/var/root", @"/etc", @"/usr",
                       @"/private/var", @"/System", @"/var/jb"];
    for (NSString *path in paths) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [output appendFormat:@"  %@%@ %@\n", [fm isReadableFileAtPath:path] ? @"R" : @"-",
         [fm isWritableFileAtPath:path] ? @"W" : @"-", path];
    }
    return output;
}

- (NSString *)systemInfo {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:FKHomePath() error:nil];
    unsigned long long total = [attributes[NSFileSystemSize] unsignedLongLongValue];
    unsigned long long free = [attributes[NSFileSystemFreeSize] unsignedLongLongValue];
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"Device:      %@\n", FKDeviceModelIdentifier()];
    [output appendFormat:@"System:      iOS %@\n", FKOSVersionString()];
    [output appendFormat:@"Arch:        arm64\n"];
    [output appendFormat:@"Cores:       %lu\n", (unsigned long)[[NSProcessInfo processInfo] processorCount]];
    [output appendFormat:@"Memory:      %@\n", FKShellSize([[NSProcessInfo processInfo] physicalMemory])];
    [output appendFormat:@"Disk:        %@ free of %@\n", FKShellSize(free), FKShellSize(total)];
    [output appendFormat:@"Jailbroken:  %@\n", FKIsJailbroken() ? @"yes" : @"no"];
    [output appendFormat:@"App:         %@ (%@)\n", FKAppName(), FKAppIdentifier()];
    [output appendFormat:@"IL2CPP:      %@\n", [FKIL2CPP available] ? [FKIL2CPP statusText] : @"unavailable"];
    [output appendFormat:@"LAN:         %@\n", [FKLanAddresses() componentsJoinedByString:@", "]];
    return output;
}

- (NSString *)memoryInfo {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    uint64_t resident = FKResidentMemory();
    uint64_t virtualSize = 0;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
        virtualSize = info.virtual_size;
    return [NSString stringWithFormat:@"resident: %@\nvirtual:  %@\nphysical: %@\nthreads:  %u",
            FKShellSize(resident), FKShellSize(virtualSize),
            FKShellSize([[NSProcessInfo processInfo] physicalMemory]),
            (unsigned)[[NSProcessInfo processInfo] activeProcessorCount]];
}

- (NSString *)containers {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *pairs = @[ @[ @"/var/mobile/Containers/Data/Application", @"data" ],
                        @[ @"/var/containers/Bundle/Application", @"bundle" ],
                        @[ @"/var/mobile/Containers/Shared/AppGroup", @"group" ] ];
    NSMutableString *output = [NSMutableString string];
    NSInteger found = 0;
    for (NSArray *pair in pairs) {
        NSString *root = pair[0];
        for (NSString *uuid in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
            NSString *path = [root stringByAppendingPathComponent:uuid];
            NSString *metadataPath = [path stringByAppendingPathComponent:
                                      @".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
            NSString *identifier = metadata[@"MCMMetadataIdentifier"] ?: @"unknown";
            [output appendFormat:@"%@  %@  %@\n", pair[1], identifier, path];
            found++;
        }
    }
    if (!found) return @"No other containers visible from this sandbox.";
    return [NSString stringWithFormat:@"kind  identifier  path\n%@", output];
}

#pragma mark - Keychain

- (NSString *)keychain:(NSArray *)args {
    NSString *itemClass = @"generic";
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:@"--class"] && i + 1 < args.count) itemClass = args[++i].lowercaseString;
        else if ([args[i] hasPrefix:@"--class="]) itemClass = [args[i] substringFromIndex:8].lowercaseString;
    }
    if (args.count && ![args[0] hasPrefix:@"-"]) {
        NSString *subcommand = args[0].lowercaseString;
        if ([subcommand isEqualToString:@"dump"] || [subcommand isEqualToString:@"list"]) {
            // default class unless overridden
        } else if ([subcommand isEqualToString:@"generic"] || [subcommand isEqualToString:@"internet"] ||
                   [subcommand isEqualToString:@"certificate"]) {
            itemClass = subcommand;
        }
    }
    NSArray *items = FKKeychainItems(itemClass);
    if (!items.count) return [NSString stringWithFormat:@"(no %@ keychain items visible)", itemClass];
    NSMutableString *output = [NSMutableString stringWithFormat:@"%@ items: %lu\n",
                               itemClass, (unsigned long)items.count];
    for (NSDictionary *item in items) {
        [output appendFormat:@"\nservice: %@\naccount: %@\naccess : %@\n",
         item[@"service"] ?: @"", item[@"account"] ?: @"", item[@"access_group"] ?: @""];
        if ([item[@"text"] length]) [output appendFormat:@"value  : %@\n", item[@"text"]];
        else if ([item[@"data"] length]) [output appendFormat:@"data   : %@\n", item[@"data"]];
    }
    return output;
}

#pragma mark - Transfer

- (NSString *)encodeDownload:(NSString *)path hostPath:(NSString *)hostPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory])
        return @"Error: source path does not exist";
    NSMutableString *output = [NSMutableString stringWithFormat:@"SCP:%@;", hostPath];
    if (!isDirectory) {
        NSData *data = FKShellReadFile(path);
        if (!data) return @"Error: cannot read file";
        if (data.length > 3 * 1024 * 1024) return @"Error: file exceeds the 3 MB transfer limit";
        [output appendFormat:@"FILE;%@;%@\n", path.lastPathComponent,
         [data base64EncodedStringWithOptions:0]];
        return output;
    }
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    for (NSString *relative in enumerator) {
        if (output.length > FKShellMaxOutput) break;
        if ([relative.lastPathComponent hasPrefix:@"."]) continue;
        NSString *full = [path stringByAppendingPathComponent:relative];
        BOOL childDirectory = NO;
        [fm fileExistsAtPath:full isDirectory:&childDirectory];
        if (childDirectory) continue;
        NSData *data = FKShellReadFile(full);
        if (!data) continue;
        [output appendFormat:@"FILE;%@;%@\n", relative, [data base64EncodedStringWithOptions:0]];
    }
    return output;
}

- (NSString *)download:(NSArray *)args cwd:(NSString *)cwd {
    if (!args.count) return @"Usage: download <path> [host_path]";
    NSString *path = FKShellResolve(args[0], cwd);
    NSString *hostPath = args.count > 1 ? args[1] : @"./download";
    return [self encodeDownload:path hostPath:hostPath];
}

- (NSString *)scp:(NSArray *)args cwd:(NSString *)cwd {
    BOOL recursive = NO;
    NSMutableArray *operands = [NSMutableArray array];
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"-r"]) recursive = YES;
        else if (![arg hasPrefix:@"-"]) [operands addObject:arg];
    }
    if (operands.count < 2)
        return @"Usage: scp -r <path> host:./dir\n       scp <source> <destination>";
    NSString *destination = operands[1];
    if ([destination hasPrefix:@"host:"]) {
        if (!recursive) return @"Error: host download requires -r";
        return [self encodeDownload:FKShellResolve(operands[0], cwd)
                           hostPath:[destination substringFromIndex:5]];
    }
    return [self copyOrMove:@[operands[0], operands[1]] cwd:cwd move:NO];
}

@end
