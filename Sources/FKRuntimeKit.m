//
//  FKRuntimeKit.m — native runtime explorer / memory toolkit
//

#import "FKRuntimeKit.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <malloc/malloc.h>
#import <mach/mach.h>
#import <mach/vm_region.h>
#import <sys/mman.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import <string.h>
#import <stdlib.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static const NSInteger FKMaxHeapScanSeconds = 4;

#pragma mark - Memory helpers

static BOOL FKMemReadable(uintptr_t address, size_t length) {
    if (!address || !length) return NO;
    vm_address_t region = (vm_address_t)address;
    vm_size_t regionSize = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &region, &regionSize,
                                        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info,
                                        &count, &objectName);
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    if (result != KERN_SUCCESS) return NO;
    if (!(info.protection & VM_PROT_READ)) return NO;
    return address >= (uintptr_t)region && address + length <= (uintptr_t)region + regionSize;
}

static vm_prot_t FKProtectionAt(uintptr_t address) {
    vm_address_t region = (vm_address_t)address;
    vm_size_t regionSize = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    mach_port_t objectName = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &region, &regionSize, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &count, &objectName) != KERN_SUCCESS) return 0;
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    return info.protection;
}

static NSSet<NSValue *> *FKClassRegistry(void) {
    static NSSet<NSValue *> *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet<NSValue *> *classes = [NSMutableSet set];
        int count = objc_getClassList(NULL, 0);
        if (count <= 0) { registry = classes; return; }
        Class *list = malloc(sizeof(Class) * (size_t)count);
        if (!list) { registry = classes; return; }
        count = objc_getClassList(list, count);
        for (int i = 0; i < count; i++) [classes addObject:[NSValue valueWithPointer:list[i]]];
        free(list);
        registry = classes;
    });
    return registry;
}

static BOOL FKClassChainContains(Class cls, Class ancestor) {
    NSInteger depth = 0;
    while (cls && depth++ < 64) {
        if (cls == ancestor) return YES;
        cls = class_getSuperclass(cls);
    }
    return NO;
}

#pragma mark - Heap scan

typedef struct {
    __unsafe_unretained NSSet<NSValue *> *classes;
    __unsafe_unretained Class target;
    __unsafe_unretained NSMutableArray *results;
    NSUInteger limit;
    NSTimeInterval deadline;
    BOOL truncated;
} FKHeapScanContext;

static kern_return_t FKHeapReader(task_t task, vm_address_t address, vm_size_t size, void **pointer) {
    (void)task; (void)size;
    *pointer = (void *)address;
    return KERN_SUCCESS;
}

static void FKHeapRecorder(task_t task, void *baton, unsigned typeMask,
                           vm_range_t *ranges, unsigned rangeCount) {
    (void)task; (void)typeMask;
    FKHeapScanContext *context = (FKHeapScanContext *)baton;
    if (!context || !context->results) return;
    for (unsigned i = 0; i < rangeCount; i++) {
        if (context->results.count >= context->limit) { context->truncated = YES; return; }
        if ([NSDate timeIntervalSinceReferenceDate] > context->deadline) { context->truncated = YES; return; }
        vm_range_t range = ranges[i];
        if (range.size < sizeof(void *)) continue;
        uintptr_t address = (uintptr_t)range.address;
        if (!FKMemReadable(address, sizeof(void *))) continue;
        void *rawISA = *(void **)address;
        if (!rawISA) continue;
        Class isa = (__bridge Class)rawISA;
        if (![context->classes containsObject:[NSValue valueWithPointer:isa]]) continue;
        if (context->target && !FKClassChainContains(isa, context->target)) continue;
        [context->results addObject:@(address)];
    }
}

#pragma mark - Value decoding

static NSDictionary *FKDecodePointerValue(id value) {
    if (!value) return @{ @"value": [NSNull null] };
    Class cls = object_getClass(value);
    NSString *description = nil;
    @try { description = [value description]; } @catch (__unused NSException *exception) { description = @"<description threw>"; }
    if (description.length > 400) description = [[description substringToIndex:400] stringByAppendingString:@"…"];
    return @{ @"value": description ?: @"",
              @"ptr": [NSString stringWithFormat:@"%llu", (unsigned long long)(uintptr_t)(__bridge void *)value],
              @"class": cls ? NSStringFromClass(cls) : @"?" };
}

static id FKDecodeIvar(id object, Ivar ivar) {
    if (!object || !ivar) return [NSNull null];
    const char *encoding = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (!encoding) return [NSNull null];
    void *address = (uint8_t *)(__bridge void *)object + offset;
    if (!FKMemReadable((uintptr_t)address, 8)) return @{ @"error": @"unreadable ivar" };
    switch (encoding[0]) {
        case '@': {
            void *raw = *(void **)address;
            id value = raw ? (__bridge id)raw : nil;
            return FKDecodePointerValue(value);
        }
        case '#': {
            void *raw = *(void **)address;
            Class value = raw ? (__bridge Class)raw : Nil;
            return @{ @"value": value ? NSStringFromClass(value) : @"nil" };
        }
        case ':': {
            SEL value = *(SEL *)address;
            return @{ @"value": value ? NSStringFromSelector(value) : @"nil" };
        }
        case 'c': case 'C': case 'B': return @{ @"value": @(*(uint8_t *)address) };
        case 's': case 'S': return @{ @"value": @(*(int16_t *)address) };
        case 'i': case 'I': return @{ @"value": @(*(int32_t *)address) };
        case 'l': case 'L': case 'q': case 'Q': return @{ @"value": @(*(int64_t *)address) };
        case 'f': return @{ @"value": @(*(float *)address) };
        case 'd': return @{ @"value": @(*(double *)address) };
        case '*': {
            const char *string = *(const char **)address;
            if (!string || !FKMemReadable((uintptr_t)string, 1)) return @{ @"value": [NSNull null] };
            return @{ @"value": [NSString stringWithUTF8String:string] ?: @"" };
        }
        case '{': {
            NSData *data = [NSData dataWithBytes:address length:32];
            return @{ @"value": @"<struct>", @"hex": [data base64EncodedStringWithOptions:0] };
        }
        default: {
            void *value = *(void **)address;
            return @{ @"value": [NSString stringWithFormat:@"0x%llx", (unsigned long long)(uintptr_t)value] };
        }
    }
}

static BOOL FKSetIvarValue(id object, Ivar ivar, id value) {
    if (!object || !ivar) return NO;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    void *address = (uint8_t *)(__bridge void *)object + offset;
    switch (encoding[0]) {
        case '@':
            if ([value isKindOfClass:[NSDictionary class]] && value[@"ptr"]) {
                object_setIvar(object, ivar, (__bridge id)(void *)(uintptr_t)[value[@"ptr"] unsignedLongLongValue]);
            } else if ([value isKindOfClass:[NSNull class]]) {
                object_setIvar(object, ivar, nil);
            } else if ([value isKindOfClass:[NSString class]]) {
                object_setIvar(object, ivar, value);
            } else {
                object_setIvar(object, ivar, value);
            }
            return YES;
        case 'c': case 'C': case 'B': *(uint8_t *)address = (uint8_t)[value charValue]; return YES;
        case 's': case 'S': *(int16_t *)address = (int16_t)[value shortValue]; return YES;
        case 'i': case 'I': *(int32_t *)address = (int32_t)[value intValue]; return YES;
        case 'l': case 'L': case 'q': case 'Q': *(int64_t *)address = (int64_t)[value longLongValue]; return YES;
        case 'f': *(float *)address = [value floatValue]; return YES;
        case 'd': *(double *)address = [value doubleValue]; return YES;
        case '*': {
            NSString *string = [value description];
            *(const char **)address = string.UTF8String;
            return YES;
        }
        default: return NO;
    }
}

static id FKDecodeReturnValue(NSInvocation *invocation) {
    const char *type = invocation.methodSignature.methodReturnType;
    if (!type) return [NSNull null];
    if (strcmp(type, @encode(void)) == 0) return @"void";
    switch (type[0]) {
        case '@': { __unsafe_unretained id value = nil; [invocation getReturnValue:&value]; return FKDecodePointerValue(value); }
        case '#': { Class value = Nil; [invocation getReturnValue:&value]; return @{ @"value": value ? NSStringFromClass(value) : @"nil" }; }
        case ':': { SEL value = NULL; [invocation getReturnValue:&value]; return @{ @"value": value ? NSStringFromSelector(value) : @"nil" }; }
        case 'c': case 'C': case 'B': { uint8_t value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case 's': case 'S': { int16_t value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case 'i': case 'I': { int32_t value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case 'l': case 'L': case 'q': case 'Q': { int64_t value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case 'f': { float value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case 'd': { double value = 0; [invocation getReturnValue:&value]; return @{ @"value": @(value) }; }
        case '*': { const char *value = NULL; [invocation getReturnValue:&value]; return @{ @"value": value ? [NSString stringWithUTF8String:value] : @"" }; }
        default: {
            NSUInteger length = invocation.methodSignature.methodReturnLength;
            if (length == 0 || length > 64) return [NSNull null];
            uint8_t buffer[64] = { 0 };
            [invocation getReturnValue:buffer];
            return @{ @"value": [[NSData dataWithBytes:buffer length:length] base64EncodedStringWithOptions:0] };
        }
    }
}

static BOOL FKSetInvocationArgument(NSInvocation *invocation, NSUInteger index, id value, const char *type) {
    if (!type) return NO;
    switch (type[0]) {
        case '@': {
            id argument = value;
            if ([value isKindOfClass:[NSDictionary class]] && value[@"ptr"])
                argument = (__bridge id)(void *)(uintptr_t)[value[@"ptr"] unsignedLongLongValue];
            else if ([value isKindOfClass:[NSNull class]])
                argument = nil;
            [invocation setArgument:&argument atIndex:(NSInteger)index];
            return YES;
        }
        case '#': {
            Class argument = NSClassFromString([value description]);
            [invocation setArgument:&argument atIndex:(NSInteger)index];
            return YES;
        }
        case ':': {
            SEL argument = NSSelectorFromString([value description]);
            [invocation setArgument:&argument atIndex:(NSInteger)index];
            return YES;
        }
        case 'c': case 'C': case 'B': { uint8_t argument = (uint8_t)[value charValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case 's': case 'S': { int16_t argument = (int16_t)[value shortValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case 'i': case 'I': { int32_t argument = (int32_t)[value intValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case 'l': case 'L': case 'q': case 'Q': { int64_t argument = (int64_t)[value longLongValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case 'f': { float argument = [value floatValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case 'd': { double argument = [value doubleValue]; [invocation setArgument:&argument atIndex:(NSInteger)index]; return YES; }
        case '*': {
            const char *argument = [[value description] UTF8String];
            [invocation setArgument:&argument atIndex:(NSInteger)index];
            return YES;
        }
        default: return NO;
    }
}

#pragma mark - Implementation

@implementation FKRuntimeKit

+ (NSDictionary *)heapObjectsOfClass:(NSString *)className limit:(NSInteger)limit {
    Class target = className.length ? NSClassFromString(className) : Nil;
    if (className.length && !target)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"class not found: %@", className] };
    NSInteger cap = MAX(1, MIN(limit, 2000));
    NSMutableArray *results = [NSMutableArray array];
    FKHeapScanContext context = { FKClassRegistry(), target, results, (NSUInteger)cap,
                                  [NSDate timeIntervalSinceReferenceDate] + FKMaxHeapScanSeconds, NO };

    vm_address_t *zones = NULL;
    unsigned zoneCount = 0;
    kern_return_t status = malloc_get_all_zones(mach_task_self(), NULL, &zones, &zoneCount);
    if (status != KERN_SUCCESS)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"malloc_get_all_zones: %d", status] };

    for (unsigned i = 0; i < zoneCount && results.count < (NSUInteger)cap; i++) {
        malloc_zone_t *zone = (malloc_zone_t *)zones[i];
        if (!zone || !zone->introspect || !zone->introspect->enumerator) continue;
        zone->introspect->enumerator(mach_task_self(), &context, MALLOC_PTR_IN_USE_RANGE_TYPE,
                                     (vm_address_t)zone, FKHeapReader, FKHeapRecorder);
        if ([NSDate timeIntervalSinceReferenceDate] > context.deadline) break;
    }

    NSMutableArray *objects = [NSMutableArray array];
    for (NSNumber *address in results) {
        uintptr_t pointer = (uintptr_t)address.unsignedLongLongValue;
        if (!FKMemReadable(pointer, sizeof(void *))) continue;
        Class cls = object_getClass((__bridge id)(void *)pointer);
        if (!cls) continue;
        [objects addObject:@{ @"ptr": [NSString stringWithFormat:@"%llu", (unsigned long long)pointer],
                              @"class": NSStringFromClass(cls) }];
    }
    return @{ @"ok": @YES, @"class": className ?: @"*", @"count": @(objects.count),
              @"truncated": @(context.truncated), @"objects": objects };
}

+ (NSDictionary *)objectInfo:(unsigned long long)pointer depth:(NSInteger)depth {
    if (!pointer || !FKMemReadable((uintptr_t)pointer, sizeof(void *)))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
    id object = (__bridge id)(void *)(uintptr_t)pointer;
    Class cls = object_getClass(object);
    if (!cls) return @{ @"ok": @NO, @"error": @"no class for pointer" };

    NSMutableArray *chain = [NSMutableArray array];
    Class cursor = cls;
    while (cursor && chain.count < 24) {
        [chain addObject:NSStringFromClass(cursor)];
        cursor = class_getSuperclass(cursor);
    }
    NSMutableArray *ivars = [NSMutableArray array];
    cursor = cls;
    NSInteger levels = MAX(1, MIN(depth, 8));
    while (cursor && levels-- > 0) {
        unsigned int count = 0;
        Ivar *list = class_copyIvarList(cursor, &count);
        for (unsigned i = 0; i < count; i++) {
            Ivar ivar = list[i];
            const char *name = ivar_getName(ivar);
            const char *type = ivar_getTypeEncoding(ivar);
            id value = FKDecodeIvar(object, ivar);
            [ivars addObject:@{ @"name": name ? [NSString stringWithUTF8String:name] : @"?",
                                @"type": type ? [NSString stringWithUTF8String:type] : @"?",
                                @"offset": @(ivar_getOffset(ivar)),
                                @"declaring": NSStringFromClass(cursor),
                                @"value": value ?: [NSNull null] }];
        }
        free(list);
        cursor = class_getSuperclass(cursor);
    }

    NSString *description = nil;
    @try { description = [object description]; } @catch (__unused NSException *exception) { description = @"<description threw>"; }
    if (description.length > 2000) description = [[description substringToIndex:2000] stringByAppendingString:@"…"];
    return @{ @"ok": @YES, @"ptr": [NSString stringWithFormat:@"%llu", pointer],
              @"class": NSStringFromClass(cls), @"chain": chain,
              @"size": @(class_getInstanceSize(cls)),
              @"description": description ?: @"",
              @"ivars": ivars, @"ivar_count": @(ivars.count) };
}

+ (NSDictionary *)callClass:(NSString *)className selector:(NSString *)selector
                     object:(unsigned long long)pointer classMethod:(BOOL)classMethod args:(NSArray *)args {
    Class cls = NSClassFromString(className);
    if (!cls) return @{ @"ok": @NO, @"error": @"class not found" };
    SEL sel = NSSelectorFromString(selector);
    Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) {
        // Walk superclasses for inherited methods.
        Class cursor = class_getSuperclass(cls);
        while (cursor && !method) {
            method = classMethod ? class_getClassMethod(cursor, sel) : class_getInstanceMethod(cursor, sel);
            cursor = class_getSuperclass(cursor);
        }
    }
    if (!method) return @{ @"ok": @NO, @"error": @"method not found" };
    id target = classMethod ? (id)cls : (__bridge id)(void *)(uintptr_t)pointer;
    if (!classMethod && (!pointer || !FKMemReadable((uintptr_t)pointer, sizeof(void *))))
        return @{ @"ok": @NO, @"error": @"target is not readable" };

    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = sel;
    NSInteger argumentCount = (NSInteger)signature.numberOfArguments;
    for (NSInteger i = 2; i < argumentCount; i++) {
        id value = (i - 2) < (NSInteger)args.count ? args[(NSUInteger)(i - 2)] : nil;
        if (!FKSetInvocationArgument(invocation, (NSUInteger)i, value ?: [NSNull null],
                                     [signature getArgumentTypeAtIndex:(NSUInteger)i]))
            return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"unsupported argument %ld", (long)i],
                      @"type": [NSString stringWithUTF8String:[signature getArgumentTypeAtIndex:(NSUInteger)i]] };
    }
    @try {
        [invocation invoke];
    } @catch (NSException *exception) {
        return @{ @"ok": @NO, @"error": exception.reason ?: @"invocation threw" };
    }
    return @{ @"ok": @YES, @"class": className, @"selector": selector,
              @"return_type": [NSString stringWithUTF8String:signature.methodReturnType],
              @"result": FKDecodeReturnValue(invocation) };
}

+ (NSDictionary *)getIvar:(NSString *)name object:(unsigned long long)pointer {
    if (!pointer || !FKMemReadable((uintptr_t)pointer, sizeof(void *)))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
    id object = (__bridge id)(void *)(uintptr_t)pointer;
    Class cursor = object_getClass(object);
    Ivar ivar = NULL;
    while (cursor && !ivar) {
        ivar = class_getInstanceVariable(cursor, name.UTF8String);
        if (!ivar) cursor = class_getSuperclass(cursor);
    }
    if (!ivar) return @{ @"ok": @NO, @"error": @"ivar not found" };
    return @{ @"ok": @YES, @"name": name,
              @"type": [NSString stringWithUTF8String:ivar_getTypeEncoding(ivar)],
              @"value": FKDecodeIvar(object, ivar) };
}

+ (NSDictionary *)setIvar:(NSString *)name object:(unsigned long long)pointer value:(id)value {
    if (!pointer || !FKMemReadable((uintptr_t)pointer, sizeof(void *)))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
    id object = (__bridge id)(void *)(uintptr_t)pointer;
    Class cursor = object_getClass(object);
    Ivar ivar = NULL;
    while (cursor && !ivar) {
        ivar = class_getInstanceVariable(cursor, name.UTF8String);
        if (!ivar) cursor = class_getSuperclass(cursor);
    }
    if (!ivar) return @{ @"ok": @NO, @"error": @"ivar not found" };
    if (!FKSetIvarValue(object, ivar, value))
        return @{ @"ok": @NO, @"error": @"unsupported ivar type" };
    return @{ @"ok": @YES, @"name": name, @"value": FKDecodeIvar(object, ivar) };
}

+ (NSDictionary *)highlightRect:(CGRect)rect duration:(double)seconds {
    __block BOOL shown = NO;
    FKRunOnMain(^{
        UIWindowScene *scene = FKActiveWindowScene();
        UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                                 : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = UIWindowLevelAlert + 60;
        window.backgroundColor = [UIColor clearColor];
        window.userInteractionEnabled = NO;
        UIViewController *controller = [[UIViewController alloc] init];
        controller.view.backgroundColor = [UIColor clearColor];
        UIView *border = [[UIView alloc] initWithFrame:rect];
        border.layer.borderColor = [UIColor systemRedColor].CGColor;
        border.layer.borderWidth = 3;
        border.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
        [controller.view addSubview:border];
        window.rootViewController = controller;
        window.hidden = NO;
        shown = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.3, seconds) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{ window.alpha = 0; } completion:^(BOOL finished) {
                window.hidden = YES;
            }];
        });
    });
    return @{ @"ok": @(shown), @"rect": NSStringFromCGRect(rect), @"seconds": @(seconds) };
}


#pragma mark - Modules

+ (NSArray<NSDictionary *> *)modules {
    NSMutableArray *modules = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header) continue;
        const char *name = _dyld_get_image_name(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uintptr_t base = (uintptr_t)header;
        uintptr_t end = base;
        const uint8_t *cursor = (const uint8_t *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
                uintptr_t segmentEnd = base + segment->vmaddr + segment->vmsize - header->sizeofcmds;
                uintptr_t candidate = (uintptr_t)header + (segment->vmaddr - 0) + segment->vmsize;
                if (candidate > end) end = candidate;
                (void)segmentEnd;
            }
            cursor += command->cmdsize;
            if (command->cmdsize == 0) break;
        }
        [modules addObject:@{ @"name": name ? [NSString stringWithUTF8String:name] : @"?",
                              @"base": [NSString stringWithFormat:@"0x%llx", (unsigned long long)base],
                              @"end": [NSString stringWithFormat:@"0x%llx", (unsigned long long)end],
                              @"slide": [NSString stringWithFormat:@"0x%llx", (unsigned long long)slide],
                              @"size": @(end > base ? end - base : 0) }];
    }
    return modules;
}

#pragma mark - Memory

+ (NSDictionary *)readMemory:(unsigned long long)address length:(NSInteger)length {
    if (!address) return @{ @"ok": @NO, @"error": @"address required" };
    NSInteger requested = MAX(1, MIN(length, 1024 * 1024));
    NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)requested];
    vm_size_t outSize = 0;
    kern_return_t status = vm_read_overwrite(mach_task_self(), (vm_address_t)address,
                                             (vm_size_t)requested, (vm_address_t)buffer.mutableBytes,
                                             &outSize);
    if (status != KERN_SUCCESS)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"vm_read_overwrite: %d", status],
                  @"address": [NSString stringWithFormat:@"0x%llx", address] };
    buffer.length = outSize;
    return @{ @"ok": @YES, @"address": [NSString stringWithFormat:@"0x%llx", address],
              @"length": @(outSize), @"base64": [buffer base64EncodedStringWithOptions:0],
              @"hex": FKHexDump(buffer, 0, MIN((NSUInteger)256, buffer.length)) };
}

+ (NSDictionary *)writeMemory:(unsigned long long)address base64:(NSString *)base64 {
    if (!address) return @{ @"ok": @NO, @"error": @"address required" };
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 ?: @"" options:0];
    if (!data.length) return @{ @"ok": @NO, @"error": @"empty payload" };
    if (data.length > 1024 * 1024) return @{ @"ok": @NO, @"error": @"payload exceeds 1 MB" };
    uintptr_t pageSize = (uintptr_t)vm_page_size;
    uintptr_t start = (uintptr_t)address & ~(pageSize - 1);
    uintptr_t end = ((uintptr_t)address + data.length + pageSize - 1) & ~(pageSize - 1);
    vm_prot_t original = FKProtectionAt((uintptr_t)address);
    kern_return_t status = vm_protect(mach_task_self(), (vm_address_t)start,
                                      (vm_size_t)(end - start), NO,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (status != KERN_SUCCESS)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"vm_protect: %d", status] };
    memcpy((void *)(uintptr_t)address, data.bytes, data.length);
    vm_protect(mach_task_self(), (vm_address_t)start, (vm_size_t)(end - start), NO,
               original ? original : (VM_PROT_READ | VM_PROT_EXECUTE));
    sys_icache_invalidate((void *)(uintptr_t)address, data.length);
    return @{ @"ok": @YES, @"address": [NSString stringWithFormat:@"0x%llx", address],
              @"bytes": @(data.length) };
}

static NSData *FKPatternBytes(NSString *pattern, NSData **maskOut) {
    *maskOut = nil;
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < pattern.length; i++) {
        unichar c = [pattern characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n') continue;
        [hex appendFormat:@"%C", c];
    }
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF?"];
    BOOL looksHex = hex.length >= 2 && hex.length % 2 == 0;
    for (NSUInteger i = 0; i < hex.length && looksHex; i++) {
        if (![hexSet characterIsMember:[hex characterAtIndex:i]]) looksHex = NO;
    }
    if (!looksHex) return [pattern dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *bytes = [NSMutableData data];
    NSMutableData *mask = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        NSString *pair = [hex substringWithRange:NSMakeRange(i, 2)];
        uint8_t value = 0, flag = 1;
        if ([pair isEqualToString:@"??"]) { value = 0; flag = 0; }
        else value = (uint8_t)strtoul(pair.UTF8String, NULL, 16);
        [bytes appendBytes:&value length:1];
        [mask appendBytes:&flag length:1];
    }
    *maskOut = mask;
    return bytes;
}

+ (NSDictionary *)scanMemory:(NSString *)pattern module:(NSString *)module limit:(NSInteger)limit {
    if (!pattern.length) return @{ @"ok": @NO, @"error": @"pattern required" };
    NSData *mask = nil;
    NSData *needle = FKPatternBytes(pattern, &mask);
    if (!needle.length) return @{ @"ok": @NO, @"error": @"empty pattern" };
    NSInteger cap = MAX(1, MIN(limit, 200));
    NSArray *modules = [self modules];
    NSMutableArray *results = [NSMutableArray array];
    NSUInteger scanned = 0;
    const uint8_t *needleBytes = needle.bytes;

    for (NSDictionary *entry in modules) {
        NSString *name = entry[@"name"];
        if (module.length && [name rangeOfString:module options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        uintptr_t base = strtoull([entry[@"base"] UTF8String], NULL, 0);
        uintptr_t size = (uintptr_t)[entry[@"size"] unsignedLongLongValue];
        if (!base || !size) continue;
        NSUInteger budget = 96 * 1024 * 1024;
        size = MIN(size, budget);
        if (!FKMemReadable(base, MIN(size, (uintptr_t)4096))) continue;
        const uint8_t *bytes = (const uint8_t *)base;
        for (NSUInteger i = 0; i + needle.length <= size; i++) {
            BOOL match = YES;
            const uint8_t *maskBytes = mask.bytes;
            for (NSUInteger j = 0; j < needle.length; j++) {
                if (maskBytes && maskBytes[j] == 0) continue;
                if (bytes[i + j] != needleBytes[j]) { match = NO; break; }
            }
            if (!match) continue;
            [results addObject:@{ @"address": [NSString stringWithFormat:@"0x%llx", (unsigned long long)(base + i)],
                                  @"module": name }];
            if ((NSInteger)results.count >= cap) break;
        }
        scanned += size;
        if ((NSInteger)results.count >= cap || scanned > 128 * 1024 * 1024) break;
    }
    return @{ @"ok": @YES, @"pattern": pattern, @"count": @(results.count),
              @"scanned": @(scanned), @"results": results };
}

+ (NSArray<NSDictionary *> *)exportsOfModule:(NSString *)module filter:(NSString *)filter limit:(NSInteger)limit {
    NSDictionary *target = nil;
    for (NSDictionary *entry in [self modules]) {
        if ([entry[@"name"] rangeOfString:module options:NSCaseInsensitiveSearch].location != NSNotFound) {
            target = entry;
            break;
        }
    }
    if (!target) return @[];
    uintptr_t base = strtoull([target[@"base"] UTF8String], NULL, 0);
    intptr_t slide = (intptr_t)strtoull([target[@"slide"] UTF8String], NULL, 0);
    const struct mach_header_64 *header = (const struct mach_header_64 *)base;
    if (!header || header->magic != MH_MAGIC_64) return @[];

    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const struct symtab_command *symtab = NULL;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SYMTAB) { symtab = (const struct symtab_command *)cursor; break; }
        cursor += command->cmdsize;
        if (command->cmdsize == 0) break;
    }
    if (!symtab) return @[];

    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    NSMutableArray *exports = [NSMutableArray array];
    NSInteger cap = MAX(1, MIN(limit, 500));
    NSString *needle = filter.lowercaseString;
    for (uint32_t i = 0; i < symtab->nsyms && (NSInteger)exports.count < cap; i++) {
        const struct nlist_64 *symbol = &symbols[i];
        if ((symbol->n_type & N_STAB) != 0) continue;
        if ((symbol->n_type & N_TYPE) != N_SECT) continue;
        if (!symbol->n_un.n_strx || symbol->n_un.n_strx >= symtab->strsize) continue;
        const char *name = strings + symbol->n_un.n_strx;
        if (!name || !name[0]) continue;
        NSString *string = [NSString stringWithUTF8String:name] ?: @"";
        if (needle.length && [string.lowercaseString rangeOfString:needle].location == NSNotFound) continue;
        [exports addObject:@{ @"name": string,
                              @"address": [NSString stringWithFormat:@"0x%llx",
                                           (unsigned long long)(slide + (intptr_t)symbol->n_value)] }];
    }
    return exports;
}

#pragma mark - Hooks

static NSMutableArray<NSDictionary *> *gHooks = nil;
static NSLock *gHooksLock = nil;

static uintptr_t FKResolveSymbolAddress(NSString *value) {
    if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"])
        return (uintptr_t)strtoull(value.UTF8String, NULL, 0);
    void *pointer = dlsym(RTLD_DEFAULT, value.UTF8String);
    if (!pointer && ![value hasPrefix:@"_"])
        pointer = dlsym(RTLD_DEFAULT, [NSString stringWithFormat:@"_%@", value].UTF8String);
    return (uintptr_t)pointer;
}

+ (NSDictionary *)redirectSymbol:(NSString *)source to:(NSString *)destination {
    uintptr_t from = FKResolveSymbolAddress(source);
    uintptr_t to = FKResolveSymbolAddress(destination);
    if (!from) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"source not found: %@", source] };
    if (!to) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"destination not found: %@", destination] };
    if (from == to) return @{ @"ok": @NO, @"error": @"source and destination are the same" };
    vm_prot_t protection = FKProtectionAt(from);
    if (!(protection & VM_PROT_EXECUTE))
        return @{ @"ok": @NO, @"error": @"source is not executable" };

    if (!gHooks) { gHooks = [NSMutableArray array]; gHooksLock = [[NSLock alloc] init]; }
    [gHooksLock lock];
    for (NSDictionary *hook in gHooks) {
        if ([hook[@"source"] isEqualToString:source]) {
            [gHooksLock unlock];
            return @{ @"ok": @NO, @"error": @"a hook for this source already exists" };
        }
    }
    [gHooksLock unlock];

    NSData *original = [NSData dataWithBytes:(const void *)from length:16];
    uint8_t stub[16];
    uint32_t load = 0x58000050;   // ldr x16, #8
    uint32_t branch = 0xD61F0200; // br x16
    memcpy(stub, &load, 4);
    memcpy(stub + 4, &branch, 4);
    memcpy(stub + 8, &to, 8);

    uintptr_t pageSize = (uintptr_t)vm_page_size;
    uintptr_t start = from & ~(pageSize - 1);
    uintptr_t end = (from + 16 + pageSize - 1) & ~(pageSize - 1);
    kern_return_t status = vm_protect(mach_task_self(), (vm_address_t)start,
                                      (vm_size_t)(end - start), NO,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (status != KERN_SUCCESS)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"vm_protect: %d", status] };
    memcpy((void *)from, stub, 16);
    vm_protect(mach_task_self(), (vm_address_t)start, (vm_size_t)(end - start), NO,
               protection | VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void *)from, 16);

    [gHooksLock lock];
    [gHooks addObject:@{ @"source": source, @"destination": destination,
                         @"address": [NSString stringWithFormat:@"0x%llx", (unsigned long long)from],
                         @"target": [NSString stringWithFormat:@"0x%llx", (unsigned long long)to],
                         @"original": original }];
    [gHooksLock unlock];
    FKLog(@"hook %@ -> %@", source, destination);
    return @{ @"ok": @YES, @"source": source, @"destination": destination,
              @"address": [NSString stringWithFormat:@"0x%llx", (unsigned long long)from] };
}

+ (NSDictionary *)restoreSymbol:(NSString *)source {
    if (!gHooks) return @{ @"ok": @NO, @"error": @"no hooks installed" };
    [gHooksLock lock];
    NSDictionary *match = nil;
    for (NSDictionary *hook in gHooks) {
        if ([hook[@"source"] isEqualToString:source]) { match = hook; break; }
    }
    if (match) [gHooks removeObject:match];
    [gHooksLock unlock];
    if (!match) return @{ @"ok": @NO, @"error": @"no matching hook" };

    uintptr_t from = (uintptr_t)strtoull([match[@"address"] UTF8String], NULL, 0);
    NSData *original = match[@"original"];
    vm_prot_t protection = FKProtectionAt(from);
    uintptr_t pageSize = (uintptr_t)vm_page_size;
    uintptr_t start = from & ~(pageSize - 1);
    uintptr_t end = (from + 16 + pageSize - 1) & ~(pageSize - 1);
    vm_protect(mach_task_self(), (vm_address_t)start, (vm_size_t)(end - start), NO,
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    memcpy((void *)from, original.bytes, MIN(original.length, (NSUInteger)16));
    vm_protect(mach_task_self(), (vm_address_t)start, (vm_size_t)(end - start), NO,
               protection | VM_PROT_READ | VM_PROT_EXECUTE);
    sys_icache_invalidate((void *)from, 16);
    return @{ @"ok": @YES, @"restored": source };
}

+ (NSArray<NSDictionary *> *)activeHooks {
    if (!gHooks) return @[];
    [gHooksLock lock];
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *hook in gHooks) {
        [list addObject:@{ @"source": hook[@"source"], @"destination": hook[@"destination"],
                           @"address": hook[@"address"], @"target": hook[@"target"] }];
    }
    [gHooksLock unlock];
    return list;
}


@end
#pragma mark - Network capture

static NSMutableArray<NSDictionary *> *gNetworkRecords = nil;
static NSLock *gNetworkLock = nil;

static void FKRecordNetwork(NSURLRequest *request, NSURLResponse *response,
                            NSData *data, NSError *error, NSDate *started) {
    if (![FKPrefs boolForKey:@"netCapture" defaultValue:YES]) return;
    if (!gNetworkRecords) return;
    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"time"] = @([[NSDate date] timeIntervalSince1970]);
    record[@"method"] = request.HTTPMethod ?: @"GET";
    record[@"url"] = request.URL.absoluteString ?: @"";
    record[@"duration_ms"] = @((NSInteger)(-[started timeIntervalSinceNow] * 1000));
    if (request.allHTTPHeaderFields.count) record[@"request_headers"] = request.allHTTPHeaderFields;
    if (request.HTTPBody.length) record[@"request_bytes"] = @(request.HTTPBody.length);
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        record[@"status"] = @(http.statusCode);
        record[@"response_headers"] = http.allHeaderFields ?: @{};
    }
    record[@"bytes"] = @(data.length);
    record[@"mime"] = response.MIMEType ?: @"";
    if (data.length) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (text.length) record[@"preview"] = text.length > 4096 ? [text substringToIndex:4096] : text;
        else record[@"preview"] = @"<binary>";
    }
    if (error) record[@"error"] = error.localizedDescription ?: @"error";

    [gNetworkLock lock];
    [gNetworkRecords addObject:record];
    while (gNetworkRecords.count > 300) [gNetworkRecords removeObjectAtIndex:0];
    [gNetworkLock unlock];
}

@interface NSURLSession (FKForgeKit)
@end

@implementation NSURLSession (FKForgeKit)

- (NSURLSessionDataTask *)fk_dataTaskWithRequest:(NSURLRequest *)request
                              completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    if (!completion) return [self fk_dataTaskWithRequest:request completionHandler:completion];
    NSDate *started = [NSDate date];
    return [self fk_dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        FKRecordNetwork(request, response, data, error, started);
        completion(data, response, error);
    }];
}

- (NSURLSessionDataTask *)fk_dataTaskWithURL:(NSURL *)url
                          completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    if (!completion) return [self fk_dataTaskWithURL:url completionHandler:completion];
    NSDate *started = [NSDate date];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self fk_dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        FKRecordNetwork(request, response, data, error, started);
        completion(data, response, error);
    }];
}

@end

@implementation FKRuntimeKit (Network)

+ (void)installNetworkRecorder {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gNetworkRecords = [NSMutableArray array];
        gNetworkLock = [[NSLock alloc] init];
        Class sessionClass = [NSURLSession class];
        FKSwizzleInstance(sessionClass, @selector(dataTaskWithRequest:completionHandler:),
                          @selector(fk_dataTaskWithRequest:completionHandler:));
        FKSwizzleInstance(sessionClass, @selector(dataTaskWithURL:completionHandler:),
                          @selector(fk_dataTaskWithURL:completionHandler:));
        FKLog(@"network recorder installed");
    });
}

+ (NSDictionary *)networkHistory:(NSInteger)limit {
    if (!gNetworkRecords) return @{ @"ok": @YES, @"records": @[], @"total": @0 };
    [gNetworkLock lock];
    NSArray *all = [gNetworkRecords copy];
    [gNetworkLock unlock];
    NSInteger cap = MAX(1, MIN(limit, 300));
    NSUInteger start = all.count > (NSUInteger)cap ? all.count - (NSUInteger)cap : 0;
    NSArray *slice = [all subarrayWithRange:NSMakeRange(start, all.count - start)];
    return @{ @"ok": @YES, @"total": @(all.count), @"records": [[slice reverseObjectEnumerator] allObjects] };
}

+ (void)clearNetworkHistory {
    [gNetworkLock lock];
    [gNetworkRecords removeAllObjects];
    [gNetworkLock unlock];
}

@end
