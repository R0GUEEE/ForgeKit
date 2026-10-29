//
//  FKShellServer.m — one-command-per-connection TCP transport, loopback by default
//
//  Wire compatible with iOS-sandbox-explorer's client.py:
//      $ python3 client.py "ls -l" --host 127.0.0.1 --port 8080
//  Commands are executed by FKShell, never by a shell.
//

#import "FKShell.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

static void FKShellSendAll(int fd, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t sent = send(fd, cursor, remaining, 0);
        if (sent <= 0) {
            if (sent < 0 && errno == EINTR) continue;
            break;
        }
        cursor += sent;
        remaining -= (size_t)sent;
    }
}

@interface FKShellServer ()
@property (nonatomic, readwrite) uint16_t port;
@end

@implementation FKShellServer {
    int _listenFD;
    dispatch_queue_t _acceptQueue;
    dispatch_queue_t _workQueue;
}

+ (instancetype)sharedServer {
    static FKShellServer *server;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ server = [[FKShellServer alloc] init]; });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) _listenFD = -1, _port = 8080;
    return self;
}

- (BOOL)isRunning { return _listenFD >= 0; }

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    if (self.isRunning) {
        if (self.port == port) return YES;
        [self stop];
    }
    BOOL lan = [FKPrefs boolForKey:@"shellBindLAN" defaultValue:NO];
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.Shell" code:errno
                                            userInfo:@{ NSLocalizedDescriptionKey: @"socket() failed" }];
        return NO;
    }
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = lan ? htonl(INADDR_ANY) : htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int code = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.Shell" code:code
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"bind(127.0.0.1:%u) failed: %s",
                                                 port, strerror(code)] }];
        return NO;
    }
    if (listen(fd, 8) != 0) {
        int code = errno;
        close(fd);
        if (error) *error = [NSError errorWithDomain:@"ForgeKit.Shell" code:code
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"listen failed: %s", strerror(code)] }];
        return NO;
    }
    _listenFD = fd;
    _port = port;
    _acceptQueue = dispatch_queue_create("com.forgekit.shell.accept", DISPATCH_QUEUE_SERIAL);
    _workQueue = dispatch_queue_create("com.forgekit.shell.work", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(_acceptQueue, ^{ [self acceptLoop]; });
    FKLog(@"shell TCP listening on %s:%u", lan ? "0.0.0.0" : "127.0.0.1", port);
    [[FKHTTPServer sharedServer] noteExternalLog:
        [NSString stringWithFormat:@"shell tcp %s:%u", lan ? "0.0.0.0" : "127.0.0.1", port]];
    return YES;
}

- (void)stop {
    int fd = _listenFD;
    if (fd < 0) return;
    _listenFD = -1;
    shutdown(fd, SHUT_RDWR);
    close(fd);
    FKLog(@"shell TCP stopped");
}

- (void)acceptLoop {
    while (_listenFD >= 0) {
        int listening = _listenFD;
        if (listening < 0) break;
        fd_set readSet;
        FD_ZERO(&readSet);
        FD_SET(listening, &readSet);
        struct timeval timeout = { 0, 300000 };
        if (select(listening + 1, &readSet, NULL, NULL, &timeout) <= 0) continue;
        int client = accept(listening, NULL, NULL);
        if (client < 0) continue;
        int one = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        struct timeval tv = { 10, 0 };
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        dispatch_async(_workQueue, ^{ [self serveClient:client]; });
    }
}

- (void)serveClient:(int)fd {
    NSMutableData *buffer = [NSMutableData data];
    uint8_t chunk[4096];
    while (buffer.length < 64 * 1024) {
        ssize_t received = recv(fd, chunk, sizeof(chunk), 0);
        if (received <= 0) break;
        [buffer appendBytes:chunk length:(NSUInteger)received];
        if (memchr(chunk, '\n', (size_t)received)) break;
    }
    if (!buffer.length) { close(fd); return; }
    NSString *command = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding] ?: @"";
    command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *response = [[FKShell sharedShell] execute:command];
    NSData *payload = [(response ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    FKShellSendAll(fd, payload.bytes, payload.length);
    close(fd);
    [[FKHTTPServer sharedServer] noteExternalLog:
        [NSString stringWithFormat:@"tcp> %@", command.length > 80 ? [command substringToIndex:80] : command]];
}

@end
