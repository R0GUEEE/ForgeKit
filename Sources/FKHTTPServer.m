//
//  FKHTTPServer.m — embedded HTTP server: dashboard, REST bridge, MCP transport
//

#import "ForgeKit.h"
#import "FKShell.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

extern NSString *FKWebDashboardHTML(void);

static const NSUInteger FKMaxRequestBytes = 32 * 1024 * 1024;

static NSInteger FKHeaderEnd(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    for (NSUInteger i = 0; i + 3 < length; i++) {
        if (bytes[i] == '\r' && bytes[i + 1] == '\n' && bytes[i + 2] == '\r' && bytes[i + 3] == '\n')
            return (NSInteger)i;
    }
    return -1;
}

static NSString *FKStatusText(NSInteger status) {
    switch (status) {
        case 200: return @"OK";
        case 201: return @"Created";
        case 202: return @"Accepted";
        case 204: return @"No Content";
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 403: return @"Forbidden";
        case 404: return @"Not Found";
        case 405: return @"Method Not Allowed";
        case 411: return @"Length Required";
        case 413: return @"Payload Too Large";
        case 431: return @"Request Header Fields Too Large";
        case 500: return @"Internal Server Error";
        default: return @"OK";
    }
}

static BOOL FKConstantTimeEquals(NSString *a, NSString *b) {
    if (a.length != b.length) return NO;
    const char *ca = a.UTF8String;
    const char *cb = b.UTF8String;
    if (!ca || !cb) return NO;
    unsigned char diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) diff |= (unsigned char)(ca[i] ^ cb[i]);
    return diff == 0;
}

static BOOL FKSendAll(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t sent = send(fd, cursor, remaining, 0);
        if (sent <= 0) {
            if (sent < 0 && errno == EINTR) continue;
            return NO;
        }
        cursor += sent;
        remaining -= (size_t)sent;
    }
    return YES;
}

@interface FKHTTPServer ()
@property (nonatomic, readwrite) uint16_t port;
@end

@implementation FKHTTPServer {
    int _listenFD;
    dispatch_queue_t _acceptQueue;
    dispatch_queue_t _workQueue;
    NSMutableArray<NSDictionary *> *_requests;
    NSLock *_lock;
}

+ (instancetype)sharedServer {
    static FKHTTPServer *server;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ server = [[FKHTTPServer alloc] init]; });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
        _requests = [NSMutableArray array];
        _lock = [[NSLock alloc] init];
        _port = 8787;
    }
    return self;
}

- (BOOL)isRunning { return _listenFD >= 0; }

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    if (self.isRunning) {
        if (self.port == port) return YES;
        [self stop];
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.HTTP" code:errno
                                            userInfo:@{ NSLocalizedDescriptionKey: @"socket() failed" }];
        return NO;
    }
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int code = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.HTTP" code:code
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"bind(:%u) failed: %s", port, strerror(code)] }];
        return NO;
    }
    if (listen(fd, 32) != 0) {
        int code = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.HTTP" code:code
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"listen failed: %s", strerror(code)] }];
        return NO;
    }
    _listenFD = fd;
    self.port = port;
    _acceptQueue = dispatch_queue_create("com.forgekit.http.accept", DISPATCH_QUEUE_SERIAL);
    _workQueue = dispatch_queue_create("com.forgekit.http.work", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(_acceptQueue, ^{ [self acceptLoop]; });
    FKLog(@"HTTP server listening on 0.0.0.0:%u", port);
    [[NSNotificationCenter defaultCenter] postNotificationName:FKServerDidChangeNotification object:self];
    return YES;
}

- (void)stop {
    int fd = _listenFD;
    if (fd < 0) return;
    _listenFD = -1;
    shutdown(fd, SHUT_RDWR);
    close(fd);
    FKLog(@"HTTP server stopped");
    [[NSNotificationCenter defaultCenter] postNotificationName:FKServerDidChangeNotification object:self];
}

- (void)acceptLoop {
    while (_listenFD >= 0) {
        int listening = _listenFD;
        if (listening < 0) break;
        fd_set readSet;
        FD_ZERO(&readSet);
        FD_SET(listening, &readSet);
        struct timeval timeout = { 0, 300000 };
        int ready = select(listening + 1, &readSet, NULL, NULL, &timeout);
        if (ready <= 0) continue;
        if (_listenFD < 0) break;
        int client = accept(listening, NULL, NULL);
        if (client < 0) continue;
        int one = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        struct timeval tv = { 20, 0 };
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        dispatch_async(_workQueue, ^{ [self serveClient:client]; });
    }
}

- (void)serveClient:(int)fd {
    NSDate *started = [NSDate date];
    NSMutableData *buffer = [NSMutableData data];
    NSInteger headerEnd = -1;
    NSInteger contentLength = 0;
    NSString *head = nil;

    while (YES) {
        if (headerEnd < 0) {
            headerEnd = FKHeaderEnd(buffer);
            if (headerEnd >= 0) {
                head = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, (NSUInteger)headerEnd)]
                                             encoding:NSUTF8StringEncoding];
                for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
                    NSString *lower = line.lowercaseString;
                    if ([lower hasPrefix:@"content-length:"]) {
                        contentLength = [[line substringFromIndex:15] integerValue];
                    }
                }
                if (contentLength < 0 || contentLength > (NSInteger)FKMaxRequestBytes) {
                    [self sendResponse:@{ @"status": @413, @"type": @"application/json",
                                          @"body": @"{\"error\":\"payload too large\"}" } toClient:fd];
                    close(fd);
                    return;
                }
            } else if (buffer.length > 65536) {
                [self sendResponse:@{ @"status": @431, @"type": @"application/json",
                                      @"body": @"{\"error\":\"header too large\"}" } toClient:fd];
                close(fd);
                return;
            }
        }
        if (headerEnd >= 0 && buffer.length >= (NSUInteger)(headerEnd + 4 + contentLength)) break;
        if (buffer.length > FKMaxRequestBytes + 65536) break;

        uint8_t chunk[16384];
        ssize_t received = recv(fd, chunk, sizeof(chunk), 0);
        if (received <= 0) break;
        [buffer appendBytes:chunk length:(NSUInteger)received];
    }

    if (headerEnd < 0 || !head.length) {
        close(fd);
        return;
    }

    NSData *body = nil;
    NSUInteger bodyStart = (NSUInteger)(headerEnd + 4);
    if (buffer.length >= bodyStart) {
        NSUInteger available = buffer.length - bodyStart;
        NSUInteger take = MIN(available, (NSUInteger)MAX(0, contentLength));
        body = [buffer subdataWithRange:NSMakeRange(bodyStart, take)];
    }

    NSString *requestLine = [head componentsSeparatedByString:@"\r\n"].firstObject ?: @"";
    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    NSString *method = parts.count > 0 ? parts[0].uppercaseString : @"GET";
    NSString *target = parts.count > 1 ? parts[1] : @"/";
    NSRange queryRange = [target rangeOfString:@"?"];
    NSString *rawPath = queryRange.location == NSNotFound ? target : [target substringToIndex:queryRange.location];
    NSString *query = queryRange.location == NSNotFound ? @"" : [target substringFromIndex:queryRange.location + 1];
    NSString *path = FKURLDecode(rawPath);

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (name.length) headers[name] = value;
    }

    NSDictionary *response = [self responseForMethod:method path:path query:FKParseQuery(query)
                                             headers:headers body:body];
    NSUInteger responseBytes = [response[@"rawBody"] isKindOfClass:[NSData class]]
        ? [response[@"rawBody"] length]
        : [(id)(response[@"body"] ?: @"") length];
    [self sendResponse:response toClient:fd];
    close(fd);

    NSTimeInterval elapsed = -[started timeIntervalSinceNow];
    NSMutableDictionary *entry = [@{
        @"time": @([[NSDate date] timeIntervalSince1970]),
        @"method": method,
        @"path": path,
        @"status": response[@"status"] ?: @200,
        @"ms": @((NSInteger)(elapsed * 1000)),
        @"bytes": @(responseBytes),
    } mutableCopy];
    if (query.length) entry[@"query"] = query;
    [self recordRequest:entry];
    FKLog(@"%@ %@ -> %@ (%ldms)", method, path, entry[@"status"], (long)entry[@"ms"]);
}

- (void)recordRequest:(NSDictionary *)entry {
    [_lock lock];
    [_requests addObject:entry];
    while (_requests.count > 200) [_requests removeObjectAtIndex:0];
    [_lock unlock];
}

- (NSArray<NSDictionary *> *)recentRequestsWithLimit:(NSInteger)limit {
    [_lock lock];
    NSArray *copy = [_requests copy];
    [_lock unlock];
    if (limit > 0 && copy.count > (NSUInteger)limit)
        copy = [copy subarrayWithRange:NSMakeRange(copy.count - (NSUInteger)limit, (NSUInteger)limit)];
    return copy;
}

- (void)clearRequestLog {
    [_lock lock];
    [_requests removeAllObjects];
    [_lock unlock];
}

- (void)noteExternalLog:(NSString *)line {
    if (!line.length) return;
    [self recordRequest:@{ @"time": @([[NSDate date] timeIntervalSince1970]), @"method": @"LOG",
                           @"path": line, @"status": @0, @"ms": @0, @"bytes": @0 }];
}

#pragma mark - Responses

- (void)sendResponse:(NSDictionary *)response toClient:(int)fd {
    NSInteger status = [response[@"status"] integerValue] ?: 200;
    NSString *type = response[@"type"] ?: @"application/json; charset=utf-8";
    NSData *body = response[@"rawBody"];
    if (!body) {
        id value = response[@"body"] ?: @"";
        body = [value isKindOfClass:[NSData class]] ? value : [value dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSMutableString *head = [NSMutableString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\n"
        @"Cache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\n"
        @"Access-Control-Allow-Headers: Authorization, Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version\r\n"
        @"Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n",
        (long)status, FKStatusText(status), type, (unsigned long)body.length];
    NSDictionary *extra = response[@"headers"];
    if ([extra isKindOfClass:[NSDictionary class]]) {
        [extra enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [head appendFormat:@"%@: %@\r\n", key, value];
        }];
    }
    [head appendString:@"\r\n"];
    NSMutableData *packet = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [packet appendData:body];
    FKSendAll(fd, packet.bytes, packet.length);
}

- (NSDictionary *)jsonResponse:(id)object status:(NSInteger)status {
    return @{ @"status": @(status), @"type": @"application/json; charset=utf-8",
              @"body": FKJSONString(object, YES) };
}

- (NSDictionary *)responseForMethod:(NSString *)method path:(NSString *)path
                              query:(NSDictionary *)query headers:(NSDictionary *)headers body:(NSData *)body {
    if ([method isEqualToString:@"OPTIONS"]) {
        return @{ @"status": @204, @"type": @"text/plain", @"body": @"" };
    }

    NSString *token = [FKPrefs token];
    BOOL requireToken = [FKPrefs boolForKey:@"requireToken" defaultValue:YES];
    NSString *bearer = headers[@"authorization"];
    if ([bearer hasPrefix:@"Bearer "] || [bearer hasPrefix:@"bearer "]) bearer = [bearer substringFromIndex:7];
    else bearer = nil;
    NSString *presented = bearer.length ? bearer : (query[@"token"] ?: @"");
    BOOL authorized = !requireToken || FKConstantTimeEquals(presented, token);

    if ([path isEqualToString:@"/"] || [path isEqualToString:@"/index.html"]) {
        NSString *html = FKWebDashboardHTML();
        if (authorized && presented.length) {
            html = [html stringByReplacingOccurrencesOfString:@"__FK_TOKEN__" withString:presented];
        } else {
            html = [html stringByReplacingOccurrencesOfString:@"__FK_TOKEN__" withString:@""];
        }
        return @{ @"status": @200, @"type": @"text/html; charset=utf-8", @"body": html };
    }
    if ([path isEqualToString:@"/health"]) {
        return [self jsonResponse:@{ @"ok": @YES, @"name": @"ForgeKit", @"version": FKVersionString } status:200];
    }
    if ([path isEqualToString:@"/favicon.ico"]) {
        return @{ @"status": @204, @"type": @"text/plain", @"body": @"" };
    }

    BOOL protectedPath = [path hasPrefix:@"/mcp"] || [path hasPrefix:@"/api"];
    if (protectedPath && !authorized) {
        return [self jsonResponse:@{ @"ok": @NO, @"error": @"unauthorized: supply Authorization: Bearer <token>" } status:401];
    }

    if ([path isEqualToString:@"/mcp"]) {
        if ([method isEqualToString:@"DELETE"]) return @{ @"status": @204, @"type": @"text/plain", @"body": @"" };
        if (![method isEqualToString:@"POST"]) {
            return [self jsonResponse:@{ @"error": @"MCP endpoint accepts POST only" } status:405];
        }
        if (!body.length) return [self jsonResponse:@{ @"jsonrpc": @"2.0", @"id": [NSNull null],
                                                       @"error": @{ @"code": @-32700, @"message": @"empty body" } } status:400];
        NSError *jsonError = nil;
        id payload = [NSJSONSerialization JSONObjectWithData:body options:0 error:&jsonError];
        if (!payload) {
            return [self jsonResponse:@{ @"jsonrpc": @"2.0", @"id": [NSNull null],
                                         @"error": @{ @"code": @-32700, @"message": @"parse error" } } status:400];
        }
        id response = [FKMCP handleJSONRPC:payload authorized:YES];
        if ([response isKindOfClass:[NSDictionary class]] && ![response count]) {
            return @{ @"status": @202, @"type": @"text/plain", @"body": @"" };
        }
        return [self jsonResponse:response status:200];
    }

    if ([path isEqualToString:@"/api/status"]) {
        return [self jsonResponse:[FKTools callTool:@"devkit_status" arguments:@{}] status:200];
    }
    if ([path isEqualToString:@"/api/log"]) {
        NSInteger limit = [query[@"limit"] integerValue] ?: 100;
        return [self jsonResponse:[FKTools callTool:@"devkit_log" arguments:@{ @"limit": @(limit) }] status:200];
    }
    if ([path isEqualToString:@"/api/screenshot"]) {
        return [self jsonResponse:[FKTools callTool:@"ui_screenshot" arguments:@{ @"quality": @0.6 }] status:200];
    }
    if ([path isEqualToString:@"/api/file"] && [method isEqualToString:@"GET"]) {
        NSString *filePath = FKExpandPath(query[@"path"]);
        NSData *data = filePath.length ? [NSData dataWithContentsOfFile:filePath] : nil;
        if (!data) return [self jsonResponse:@{ @"ok": @NO, @"error": @"file not found" } status:404];
        NSString *type = @"application/octet-stream";
        if ([filePath.pathExtension.lowercaseString isEqualToString:@"png"]) type = @"image/png";
        else if ([filePath.pathExtension.lowercaseString isEqualToString:@"jpg"] ||
                 [filePath.pathExtension.lowercaseString isEqualToString:@"jpeg"]) type = @"image/jpeg";
        else if ([filePath.pathExtension.lowercaseString isEqualToString:@"html"]) type = @"text/html";
        else if ([filePath.pathExtension.lowercaseString isEqualToString:@"txt"] ||
                 [filePath.pathExtension.lowercaseString isEqualToString:@"log"] ||
                 [filePath.pathExtension.lowercaseString isEqualToString:@"json"]) type = @"text/plain; charset=utf-8";
        return @{ @"status": @200, @"type": type, @"rawBody": data,
                  @"headers": @{ @"Content-Disposition": [NSString stringWithFormat:@"inline; filename=\"%@\"", filePath.lastPathComponent] } };
    }
    if ([path isEqualToString:@"/api/file"] && [method isEqualToString:@"POST"]) {
        NSString *filePath = FKExpandPath(query[@"path"]);
        if (!filePath.length) return [self jsonResponse:@{ @"ok": @NO, @"error": @"path required" } status:400];
        NSError *writeError = nil;
        if (!FKWriteDataAtomically(body ?: [NSData data], filePath, &writeError)) {
            return [self jsonResponse:@{ @"ok": @NO, @"error": writeError.localizedDescription ?: @"write failed" } status:500];
        }
        return [self jsonResponse:@{ @"ok": @YES, @"path": filePath, @"bytes": @((unsigned long long)body.length) } status:200];
    }
    if ([path isEqualToString:@"/api/shell"]) {
        NSString *command = query[@"command"];
        NSString *cwd = query[@"cwd"];
        if ([method isEqualToString:@"POST"] && body.length) {
            id payload = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            if ([payload isKindOfClass:[NSDictionary class]]) {
                command = payload[@"command"] ?: command;
                cwd = payload[@"cwd"] ?: cwd;
            } else {
                command = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
            }
        }
        if (!command.length) return [self jsonResponse:@{ @"ok": @NO, @"error": @"command required" } status:400];
        FKShell *shell = [FKShell sharedShell];
        NSString *output = [shell execute:command inDirectory:cwd.length ? cwd : shell.currentDirectory];
        return [self jsonResponse:@{ @"ok": @YES, @"output": output ?: @"", @"cwd": shell.currentDirectory } status:200];
    }
    if ([path isEqualToString:@"/api/shell/help"]) {
        return [self jsonResponse:@{ @"ok": @YES, @"commands": [[FKShell sharedShell] commandNames],
                                     @"help": [FKShell helpText] } status:200];
    }
    if ([path isEqualToString:@"/api/call"]) {
        NSDictionary *arguments = @{};
        NSString *tool = query[@"tool"];
        if ([method isEqualToString:@"POST"] && body.length) {
            id payload = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            if ([payload isKindOfClass:[NSDictionary class]]) {
                if (!tool.length) tool = payload[@"tool"];
                if ([payload[@"arguments"] isKindOfClass:[NSDictionary class]]) arguments = payload[@"arguments"];
            }
        } else {
            NSMutableDictionary *mutable = [query mutableCopy];
            [mutable removeObjectForKey:@"tool"];
            [mutable removeObjectForKey:@"token"];
            arguments = mutable;
        }
        if (!tool.length) return [self jsonResponse:@{ @"ok": @NO, @"error": @"tool required" } status:400];
        return [self jsonResponse:[FKTools callTool:tool arguments:arguments] status:200];
    }

    return [self jsonResponse:@{ @"ok": @NO, @"error": @"not found", @"path": path } status:404];
}

@end
