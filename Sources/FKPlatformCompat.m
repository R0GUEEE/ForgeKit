//
//  FKPlatformCompat.m — provides __isPlatformVersionAtLeast for cross-links
//
//  Xcode links libclang_rt.ios.a automatically; a Linux clang + lld link does
//  not, so @available() references would stay undefined. This hidden definition
//  keeps the dylib self-contained and behaves exactly like the builtin.
//

#import <Foundation/Foundation.h>

__attribute__((visibility("hidden")))
int __isPlatformVersionAtLeast(int platform, int major, int minor, int patch) {
    (void)platform;
    NSOperatingSystemVersion version = { major, minor, patch };
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version] ? 1 : 0;
}
