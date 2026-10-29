//
//  FKShellTools.m — MCP surface for the sandbox shell
//

#import "ForgeKit.h"
#import "FKShell.h"
#import "FKToolsPrivate.h"

@implementation FKShellTools

+ (NSArray<NSDictionary *> *)definitions {
    NSDictionary *(^str)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"string", @"description": description };
    };
    NSDictionary *(^num)(NSString *) = ^NSDictionary *(NSString *description) {
        return @{ @"type": @"integer", @"description": description };
    };
    return @[
        @{ @"name": @"shell", @"description":
               @"Execute one sandbox shell command (no popen/exec). Commands: ls, pwd, cd, tree, cat, head, "
               @"tail, hexdump, strings, base64, cp, mv, rm, mkdir, touch, chmod, stat, file, md5, sha256, "
               @"wc, du, realpath, readlink, find, grep, id, uname, whoami, env, date, df, uptime, bundle, "
               @"sandbox, sysinfo, memory, containers, keychain, scp, download, echo, help, version.",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"command": str(@"Command line."),
                                                @"cwd": str(@"Optional working directory."),
                                                @"reset": @{ @"type": @"boolean", @"description": @"Reset cwd before running." } },
                              @"required": @[@"command"], @"additionalProperties": @NO } },
        @{ @"name": @"shell_help", @"description": @"List sandbox shell commands and usage.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"shell_status", @"description": @"Shell state and TCP listener status.",
           @"inputSchema": @{ @"type": @"object", @"properties": @{}, @"required": @[] } },
        @{ @"name": @"shell_server", @"description": @"Start or stop the loopback TCP shell (client.py compatible).",
           @"inputSchema": @{ @"type": @"object",
                              @"properties": @{ @"action": @{ @"type": @"string", @"enum": @[@"start", @"stop"] },
                                                @"port": num(@"Port, default 8080."),
                                                @"lan": @{ @"type": @"boolean", @"description": @"Bind 0.0.0.0 instead of loopback (token-free; only on trusted networks)." } },
                              @"required": @[@"action"], @"additionalProperties": @NO } },
    ];
}

+ (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)args {
    FKShell *shell = [FKShell sharedShell];
    if ([name isEqualToString:@"shell"]) {
        NSString *command = args[@"command"];
        if (![command isKindOfClass:[NSString class]] || !command.length)
            return @{ @"ok": @NO, @"error": @"command required" };
        if ([args[@"reset"] boolValue]) shell.currentDirectory = NSHomeDirectory();
        NSString *cwd = [args[@"cwd"] isKindOfClass:[NSString class]] ? args[@"cwd"] : shell.currentDirectory;
        NSString *output = [shell execute:command inDirectory:cwd];
        return @{ @"ok": @YES, @"output": output ?: @"", @"cwd": shell.currentDirectory };
    }
    if ([name isEqualToString:@"shell_help"]) {
        return @{ @"ok": @YES, @"commands": [shell commandNames], @"help": [FKShell helpText] };
    }
    if ([name isEqualToString:@"shell_status"]) {
        FKShellServer *server = [FKShellServer sharedServer];
        return @{ @"ok": @YES, @"cwd": shell.currentDirectory, @"commands": @([shell commandNames].count),
                  @"tcp": @{ @"running": @(server.isRunning), @"port": @(server.port),
                             @"bind": [FKPrefs boolForKey:@"shellBindLAN" defaultValue:NO] ? @"0.0.0.0" : @"127.0.0.1" } };
    }
    if ([name isEqualToString:@"shell_server"]) {
        NSString *action = args[@"action"];
        FKShellServer *server = [FKShellServer sharedServer];
        if ([action isEqualToString:@"stop"]) {
            [server stop];
            return @{ @"ok": @YES, @"running": @NO };
        }
        if ([args[@"lan"] respondsToSelector:@selector(boolValue)])
            [FKPrefs setBool:[args[@"lan"] boolValue] forKey:@"shellBindLAN"];
        uint16_t port = (uint16_t)MAX(1, MIN([args[@"port"] integerValue] ?: 8080, 65535));
        NSError *error = nil;
        if (![server startOnPort:port error:&error])
            return @{ @"ok": @NO, @"error": error.localizedDescription ?: @"cannot start" };
        return @{ @"ok": @YES, @"running": @YES, @"port": @(port),
                  @"host": [FKPrefs boolForKey:@"shellBindLAN" defaultValue:NO] ? FKLanAddress() : @"127.0.0.1" };
    }
    return nil;
}

@end
