//
//  FKIL2CPP.m — dynamic IL2CPP bridge: discovery, fields, methods, patching
//
//  Every il2cpp entry point is resolved with dlsym at runtime. Apps built with
//  Mono, or with stripped/renamed exports, simply report the bridge unavailable.
//

#import "FKIL2CPP.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/vm_region.h>
#import <sys/mman.h>
#import <string.h>
#import <libkern/OSCacheControl.h>
#import <math.h>

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppClass Il2CppClass;
typedef struct Il2CppObject Il2CppObject;
typedef struct Il2CppType Il2CppType;
typedef struct Il2CppString Il2CppString;
typedef struct Il2CppException Il2CppException;
typedef struct MethodInfo MethodInfo;
typedef struct FieldInfo FieldInfo;

typedef struct {
    Il2CppDomain *(*domain_get)(void);
    const Il2CppAssembly **(*domain_get_assemblies)(const Il2CppDomain *, size_t *);
    Il2CppImage *(*assembly_get_image)(const Il2CppAssembly *);
    const char *(*image_get_name)(Il2CppImage *);
    size_t (*image_get_class_count)(Il2CppImage *);
    Il2CppClass *(*image_get_class)(Il2CppImage *, size_t);
    Il2CppClass *(*class_from_name)(const Il2CppImage *, const char *, const char *);
    const char *(*class_get_name)(Il2CppClass *);
    const char *(*class_get_namespace)(Il2CppClass *);
    Il2CppClass *(*class_get_parent)(Il2CppClass *);
    Il2CppImage *(*class_get_image)(Il2CppClass *);
    const char *(*class_get_assemblyname)(Il2CppClass *);
    Il2CppClass *(*class_from_il2cpp_type)(const Il2CppType *);
    Il2CppType *(*class_get_type)(Il2CppClass *);
    int (*class_is_enum)(Il2CppClass *);
    int (*class_is_valuetype)(Il2CppClass *);
    Il2CppClass *(*class_get_interfaces)(Il2CppClass *, void **);
    FieldInfo *(*class_get_fields)(Il2CppClass *, void **);
    FieldInfo *(*class_get_field_from_name)(Il2CppClass *, const char *);
    const MethodInfo *(*class_get_methods)(Il2CppClass *, void **);
    const MethodInfo *(*class_get_method_from_name)(Il2CppClass *, const char *, int);
    const char *(*field_get_name)(FieldInfo *);
    Il2CppType *(*field_get_type)(FieldInfo *);
    int (*field_get_flags)(FieldInfo *);
    size_t (*field_get_offset)(FieldInfo *);
    void (*field_get_value)(Il2CppObject *, FieldInfo *, void *);
    void (*field_set_value)(Il2CppObject *, FieldInfo *, void *);
    void (*field_static_get_value)(FieldInfo *, void *);
    void (*field_static_set_value)(FieldInfo *, void *);
    const char *(*method_get_name)(const MethodInfo *);
    const Il2CppType *(*method_get_return_type)(const MethodInfo *);
    uint32_t (*method_get_param_count)(const MethodInfo *);
    const Il2CppType *(*method_get_param)(const MethodInfo *, uint32_t);
    char *(*type_get_name)(const Il2CppType *);
    int (*type_get_type)(const Il2CppType *);
    Il2CppObject *(*type_get_object)(const Il2CppType *);
    Il2CppObject *(*runtime_invoke)(const MethodInfo *, void *, void **, Il2CppException **);
    Il2CppString *(*string_new)(const char *);
    size_t (*array_length)(Il2CppObject *);
    size_t (*array_element_size)(Il2CppObject *);
    Il2CppClass *(*class_get_element_class)(Il2CppClass *);
    Il2CppClass *(*object_get_class)(Il2CppObject *);
    void (*free)(void *);
    Il2CppObject *(*object_new)(Il2CppClass *);
    void *(*object_unbox)(Il2CppObject *);
    Il2CppObject *(*value_box)(Il2CppClass *, void *);
    void *(*method_get_pointer)(const MethodInfo *);
    void (*gc_disable)(void);
    void (*gc_enable)(void);
    void (*class_init)(Il2CppClass *);
    int (*class_is_subclass_of)(Il2CppClass *, Il2CppClass *, BOOL);
} FKIL2CPPApi;

static FKIL2CPPApi gAPI;
static BOOL gResolved = NO;
static BOOL gAvailable = NO;
static NSString *gLoadError = nil;
static NSArray<NSDictionary *> *gClasses = nil;
static NSMutableArray<NSDictionary *> *gPatches = nil;

static NSString *FKIL2CPPString(const char *value) {
    return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
}

static BOOL FKIL2CPPResolve(void) {
    if (gResolved) return gAvailable;
    gResolved = YES;
    gPatches = [NSMutableArray array];
    void *handle = dlopen(NULL, RTLD_NOW);
    if (!handle) { gLoadError = @"dlopen(NULL) failed"; return NO; }

#define FKSYM(field, name) gAPI.field = (void *)dlsym(handle, name)
    FKSYM(domain_get, "il2cpp_domain_get");
    FKSYM(domain_get_assemblies, "il2cpp_domain_get_assemblies");
    FKSYM(assembly_get_image, "il2cpp_assembly_get_image");
    FKSYM(image_get_name, "il2cpp_image_get_name");
    FKSYM(image_get_class_count, "il2cpp_image_get_class_count");
    FKSYM(image_get_class, "il2cpp_image_get_class");
    FKSYM(class_from_name, "il2cpp_class_from_name");
    FKSYM(class_get_name, "il2cpp_class_get_name");
    FKSYM(class_get_namespace, "il2cpp_class_get_namespace");
    FKSYM(class_get_parent, "il2cpp_class_get_parent");
    FKSYM(class_get_image, "il2cpp_class_get_image");
    FKSYM(class_get_assemblyname, "il2cpp_class_get_assemblyname");
    FKSYM(class_from_il2cpp_type, "il2cpp_class_from_il2cpp_type");
    FKSYM(class_get_type, "il2cpp_class_get_type");
    FKSYM(class_is_enum, "il2cpp_class_is_enum");
    FKSYM(class_is_valuetype, "il2cpp_class_is_valuetype");
    FKSYM(class_get_interfaces, "il2cpp_class_get_interfaces");
    FKSYM(class_get_fields, "il2cpp_class_get_fields");
    FKSYM(class_get_field_from_name, "il2cpp_class_get_field_from_name");
    FKSYM(class_get_methods, "il2cpp_class_get_methods");
    FKSYM(class_get_method_from_name, "il2cpp_class_get_method_from_name");
    FKSYM(field_get_name, "il2cpp_field_get_name");
    FKSYM(field_get_type, "il2cpp_field_get_type");
    FKSYM(field_get_flags, "il2cpp_field_get_flags");
    FKSYM(field_get_offset, "il2cpp_field_get_offset");
    FKSYM(field_get_value, "il2cpp_field_get_value");
    FKSYM(field_set_value, "il2cpp_field_set_value");
    FKSYM(field_static_get_value, "il2cpp_field_static_get_value");
    FKSYM(field_static_set_value, "il2cpp_field_static_set_value");
    FKSYM(method_get_name, "il2cpp_method_get_name");
    FKSYM(method_get_return_type, "il2cpp_method_get_return_type");
    FKSYM(method_get_param_count, "il2cpp_method_get_param_count");
    FKSYM(method_get_param, "il2cpp_method_get_param");
    FKSYM(type_get_name, "il2cpp_type_get_name");
    FKSYM(type_get_type, "il2cpp_type_get_type");
    FKSYM(type_get_object, "il2cpp_type_get_object");
    FKSYM(runtime_invoke, "il2cpp_runtime_invoke");
    FKSYM(string_new, "il2cpp_string_new");
    FKSYM(array_length, "il2cpp_array_length");
    FKSYM(array_element_size, "il2cpp_array_element_size");
    FKSYM(class_get_element_class, "il2cpp_class_get_element_class");
    FKSYM(object_get_class, "il2cpp_object_get_class");
    FKSYM(free, "il2cpp_free");
    FKSYM(object_new, "il2cpp_object_new");
    FKSYM(object_unbox, "il2cpp_object_unbox");
    FKSYM(value_box, "il2cpp_value_box");
    FKSYM(method_get_pointer, "il2cpp_method_get_pointer");
    FKSYM(gc_disable, "il2cpp_gc_disable");
    FKSYM(gc_enable, "il2cpp_gc_enable");
    FKSYM(class_init, "il2cpp_class_init");
    FKSYM(class_is_subclass_of, "il2cpp_class_is_subclass_of");
#undef FKSYM

    NSMutableArray *missing = [NSMutableArray array];
    if (!gAPI.domain_get) [missing addObject:@"il2cpp_domain_get"];
    if (!gAPI.domain_get_assemblies) [missing addObject:@"il2cpp_domain_get_assemblies"];
    if (!gAPI.assembly_get_image) [missing addObject:@"il2cpp_assembly_get_image"];
    if (!gAPI.image_get_class_count) [missing addObject:@"il2cpp_image_get_class_count"];
    if (!gAPI.image_get_class) [missing addObject:@"il2cpp_image_get_class"];
    if (!gAPI.class_get_name) [missing addObject:@"il2cpp_class_get_name"];
    if (!gAPI.class_get_fields) [missing addObject:@"il2cpp_class_get_fields"];
    if (!gAPI.field_get_name) [missing addObject:@"il2cpp_field_get_name"];
    if (!gAPI.field_get_type) [missing addObject:@"il2cpp_field_get_type"];
    if (!gAPI.field_static_get_value) [missing addObject:@"il2cpp_field_static_get_value"];
    if (!gAPI.class_get_methods) [missing addObject:@"il2cpp_class_get_methods"];
    if (!gAPI.method_get_name) [missing addObject:@"il2cpp_method_get_name"];
    if (!gAPI.type_get_name) [missing addObject:@"il2cpp_type_get_name"];
    if (!gAPI.runtime_invoke) [missing addObject:@"il2cpp_runtime_invoke"];
    if (!gAPI.object_get_class) [missing addObject:@"il2cpp_object_get_class"];
    if (!gAPI.array_length) [missing addObject:@"il2cpp_array_length"];

    gAvailable = missing.count == 0;
    if (!gAvailable) {
        gLoadError = [NSString stringWithFormat:@"IL2CPP exports unavailable (%@)",
                      [missing componentsJoinedByString:@", "]];
        FKLog(@"%@", gLoadError);
    } else {
        FKLog(@"IL2CPP bridge resolved");
    }
    return gAvailable;
}

static NSString *FKClassFullName(Il2CppClass *klass) {
    if (!klass || !gAPI.class_get_name) return @"";
    const char *name = gAPI.class_get_name(klass);
    if (!name) return @"";
    const char *ns = gAPI.class_get_namespace ? gAPI.class_get_namespace(klass) : NULL;
    if (ns && ns[0]) return [NSString stringWithFormat:@"%s.%s", ns, name];
    return [NSString stringWithUTF8String:name] ?: @"";
}

static NSString *FKTypeName(const Il2CppType *type) {
    if (!type || !gAPI.type_get_name) return @"?";
    char *name = gAPI.type_get_name(type);
    if (!name) return @"?";
    NSString *result = [NSString stringWithUTF8String:name] ?: @"?";
    if (gAPI.free) gAPI.free(name);
    return result;
}

static NSString *FKStringFromIl2Cpp(Il2CppString *string) {
    if (!string) return nil;
    const uint8_t *bytes = (const uint8_t *)string;
    int32_t length = *(const int32_t *)(bytes + 16);
    if (length < 0 || length > 4 * 1024 * 1024) return @"";
    return [[NSString alloc] initWithBytes:bytes + 20 length:(NSUInteger)length * 2
                                  encoding:NSUTF16LittleEndianStringEncoding] ?: @"";
}

static BOOL FKCanRead(const void *pointer, size_t length) {
    if (!pointer) return NO;
    vm_address_t address = (vm_address_t)pointer;
    vm_size_t regionSize = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &address, &regionSize,
                                        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info,
                                        &count, &objectName);
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    if (result != KERN_SUCCESS) return NO;
    if (!(info.protection & VM_PROT_READ)) return NO;
    return address <= (vm_address_t)pointer &&
           ((vm_address_t)pointer + length) <= (address + regionSize);
}

static NSArray<NSDictionary *> *FKClassCache(void) {
    if (gClasses) return gClasses;
    if (!FKIL2CPPResolve()) return @[];
    NSMutableArray *classes = [NSMutableArray array];
    size_t assemblyCount = 0;
    const Il2CppAssembly **assemblies = gAPI.domain_get_assemblies(gAPI.domain_get(), &assemblyCount);
    for (size_t a = 0; a < assemblyCount; a++) {
        Il2CppImage *image = gAPI.assembly_get_image(assemblies[a]);
        if (!image) continue;
        NSString *imageName = FKIL2CPPString(gAPI.image_get_name ? gAPI.image_get_name(image) : "");
        size_t classCount = gAPI.image_get_class_count(image);
        for (size_t i = 0; i < classCount; i++) {
            Il2CppClass *klass = gAPI.image_get_class(image, i);
            if (!klass) continue;
            NSString *full = FKClassFullName(klass);
            if (!full.length) continue;
            [classes addObject:@{ @"name": full,
                                  @"namespace": FKIL2CPPString(gAPI.class_get_namespace ? gAPI.class_get_namespace(klass) : ""),
                                  @"short": FKIL2CPPString(gAPI.class_get_name(klass)),
                                  @"image": imageName,
                                  @"ptr": [NSValue valueWithPointer:klass] }];
        }
    }
    gClasses = classes;
    FKLog(@"IL2CPP class cache: %lu classes in %zu assemblies", (unsigned long)classes.count, assemblyCount);
    return gClasses;
}

static Il2CppClass *FKClassByName(NSString *name) {
    if (!name.length) return NULL;
    for (NSDictionary *entry in FKClassCache()) {
        if ([entry[@"name"] isEqualToString:name]) return (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
    }
    return NULL;
}

static FieldInfo *FKFieldByName(Il2CppClass *klass, NSString *fieldName) {
    if (gAPI.class_get_field_from_name) {
        FieldInfo *field = gAPI.class_get_field_from_name(klass, fieldName.UTF8String);
        if (field) return field;
    }
    void *iterator = NULL;
    FieldInfo *field = NULL;
    while ((field = gAPI.class_get_fields(klass, &iterator))) {
        const char *name = gAPI.field_get_name(field);
        if (name && [fieldName isEqualToString:[NSString stringWithUTF8String:name]]) return field;
    }
    return NULL;
}

static id FKValueAtType(const Il2CppType *type, void *address) {
    if (!type || !address) return [NSNull null];
    int typeEnum = gAPI.type_get_type ? gAPI.type_get_type(type) : 0x12;
    switch (typeEnum) {
        case 0x02: return @(*(uint8_t *)address != 0);
        case 0x03: return @(*(uint16_t *)address);
        case 0x04: return @(*(int8_t *)address);
        case 0x05: return @(*(uint8_t *)address);
        case 0x06: return @(*(int16_t *)address);
        case 0x07: return @(*(uint16_t *)address);
        case 0x08: return @(*(int32_t *)address);
        case 0x09: return @(*(uint32_t *)address);
        case 0x0a: return @(*(int64_t *)address);
        case 0x0b: return @(*(uint64_t *)address);
        case 0x0c: return @(*(float *)address);
        case 0x0d: return @(*(double *)address);
        case 0x0e: return FKStringFromIl2Cpp(*(Il2CppString **)address) ?: @"";
        case 0x11: case 0x15: {
            Il2CppClass *valueClass = gAPI.class_from_il2cpp_type ? gAPI.class_from_il2cpp_type(type) : NULL;
            if (valueClass && gAPI.class_is_enum && gAPI.class_is_enum(valueClass))
                return @(*(int32_t *)address);
            NSData *data = [NSData dataWithBytes:address length:32];
            return @{ @"struct": FKClassFullName(valueClass),
                      @"hex": [data base64EncodedStringWithOptions:0] };
        }
        default: {
            void *pointer = *(void **)address;
            if (!pointer) return [NSNull null];
            if (!FKCanRead(pointer, 16)) return @{ @"ptr": @((unsigned long long)(uintptr_t)pointer) };
            Il2CppClass *klass = gAPI.object_get_class((Il2CppObject *)pointer);
            return @{ @"ptr": @((unsigned long long)(uintptr_t)pointer),
                      @"class": FKClassFullName(klass) };
        }
    }
}

static BOOL FKWriteValueAtType(const Il2CppType *type, void *address, id value) {
    if (!type || !address || !value) return NO;
    int typeEnum = gAPI.type_get_type ? gAPI.type_get_type(type) : 0x12;
    switch (typeEnum) {
        case 0x02: *(uint8_t *)address = [value boolValue] ? 1 : 0; return YES;
        case 0x04: *(int8_t *)address = (int8_t)[value charValue]; return YES;
        case 0x05: *(uint8_t *)address = (uint8_t)[value unsignedCharValue]; return YES;
        case 0x06: *(int16_t *)address = (int16_t)[value shortValue]; return YES;
        case 0x07: *(uint16_t *)address = (uint16_t)[value unsignedShortValue]; return YES;
        case 0x08: *(int32_t *)address = (int32_t)[value intValue]; return YES;
        case 0x09: *(uint32_t *)address = (uint32_t)[value unsignedIntValue]; return YES;
        case 0x0a: *(int64_t *)address = (int64_t)[value longLongValue]; return YES;
        case 0x0b: *(uint64_t *)address = (uint64_t)[value unsignedLongLongValue]; return YES;
        case 0x0c: *(float *)address = [value floatValue]; return YES;
        case 0x0d: *(double *)address = [value doubleValue]; return YES;
        case 0x0e:
            if (![value isKindOfClass:[NSString class]] || !gAPI.string_new) return NO;
            *(Il2CppString **)address = gAPI.string_new([value UTF8String]);
            return YES;
        case 0x11: case 0x15: {
            Il2CppClass *valueClass = gAPI.class_from_il2cpp_type ? gAPI.class_from_il2cpp_type(type) : NULL;
            if (valueClass && gAPI.class_is_enum && gAPI.class_is_enum(valueClass)) {
                *(int32_t *)address = (int32_t)[value intValue];
                return YES;
            }
            return NO;
        }
        default: {
            unsigned long long pointer = 0;
            if ([value isKindOfClass:[NSNumber class]]) pointer = [value unsignedLongLongValue];
            else if ([value isKindOfClass:[NSString class]]) pointer = strtoull([value UTF8String], NULL, 0);
            else if ([value isKindOfClass:[NSDictionary class]] && value[@"ptr"])
                pointer = [value[@"ptr"] unsignedLongLongValue];
            *(void **)address = (void *)(uintptr_t)pointer;
            return YES;
        }
    }
}

@implementation FKIL2CPP

+ (BOOL)available { return FKIL2CPPResolve(); }

+ (NSString *)statusText {
    return FKIL2CPPResolve() ? @"IL2CPP bridge ready" : (gLoadError ?: @"IL2CPP unavailable");
}

+ (NSDictionary *)runtimeInfo {
    if (!FKIL2CPPResolve()) {
        return @{ @"ok": @NO, @"backend": @"none", @"error": gLoadError ?: @"IL2CPP unavailable" };
    }
    NSArray *classes = FKClassCache();
    NSArray *images = [self images];
    return @{ @"ok": @YES, @"backend": @"il2cpp", @"arch": @"arm64",
              @"image_count": @(images.count), @"class_count": @(classes.count),
              @"gc_control": @(gAPI.gc_disable != NULL),
              @"patch_capacity": @(64), @"active_patches": @(gPatches.count) };
}

+ (NSArray<NSDictionary *> *)images {
    if (!FKIL2CPPResolve()) return @[];
    NSMutableArray *images = [NSMutableArray array];
    size_t count = 0;
    const Il2CppAssembly **assemblies = gAPI.domain_get_assemblies(gAPI.domain_get(), &count);
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = gAPI.assembly_get_image(assemblies[i]);
        if (!image) continue;
        [images addObject:@{ @"name": FKIL2CPPString(gAPI.image_get_name ? gAPI.image_get_name(image) : ""),
                             @"classes": @(gAPI.image_get_class_count(image)) }];
    }
    return images;
}

+ (NSArray<NSDictionary *> *)allClasses { return FKClassCache(); }

+ (NSArray<NSDictionary *> *)classesMatching:(NSString *)filter limit:(NSInteger)limit {
    NSString *needle = [filter lowercaseString];
    NSInteger cap = MAX(1, MIN(limit, 5000));
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        if (needle.length && [[entry[@"name"] lowercaseString] rangeOfString:needle].location == NSNotFound) continue;
        [results addObject:@{ @"name": entry[@"name"], @"image": entry[@"image"], @"ptr": entry[@"ptr"] }];
        if ((NSInteger)results.count >= cap) break;
    }
    return results;
}

+ (NSDictionary *)classInfoFor:(NSString *)className {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"class not found: %@", className] };

    NSMutableArray *fields = [NSMutableArray array];
    void *iterator = NULL;
    FieldInfo *field = NULL;
    while ((field = gAPI.class_get_fields(klass, &iterator))) {
        int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
        [fields addObject:@{
            @"name": FKIL2CPPString(gAPI.field_get_name(field)),
            @"type": FKTypeName(gAPI.field_get_type(field)),
            @"static": @((flags & 0x0010) != 0),
            @"offset": @(gAPI.field_get_offset ? gAPI.field_get_offset(field) : 0),
        }];
    }

    NSMutableArray *methods = [NSMutableArray array];
    iterator = NULL;
    const MethodInfo *method = NULL;
    while ((method = gAPI.class_get_methods(klass, &iterator))) {
        uint32_t paramCount = gAPI.method_get_param_count ? gAPI.method_get_param_count(method) : 0;
        NSMutableArray *params = [NSMutableArray array];
        for (uint32_t i = 0; i < paramCount; i++)
            [params addObject:FKTypeName(gAPI.method_get_param ? gAPI.method_get_param(method, i) : NULL)];
        [methods addObject:@{
            @"name": FKIL2CPPString(gAPI.method_get_name(method)),
            @"return": gAPI.method_get_return_type ? FKTypeName(gAPI.method_get_return_type(method)) : @"?",
            @"params": params, @"param_count": @(paramCount),
        }];
    }

    NSMutableArray *interfaces = [NSMutableArray array];
    iterator = NULL;
    Il2CppClass *interface = NULL;
    while (gAPI.class_get_interfaces && (interface = gAPI.class_get_interfaces(klass, &iterator)))
        [interfaces addObject:FKClassFullName(interface)];

    Il2CppClass *parent = gAPI.class_get_parent ? gAPI.class_get_parent(klass) : NULL;
    return @{ @"ok": @YES, @"name": FKClassFullName(klass),
              @"namespace": FKIL2CPPString(gAPI.class_get_namespace ? gAPI.class_get_namespace(klass) : ""),
              @"image": FKIL2CPPString(gAPI.class_get_image && gAPI.image_get_name
                                       ? gAPI.image_get_name(gAPI.class_get_image(klass)) : ""),
              @"parent": parent ? FKClassFullName(parent) : @"",
              @"interfaces": interfaces, @"fields": fields, @"methods": methods,
              @"field_count": @(fields.count), @"method_count": @(methods.count) };
}

#pragma mark - Objects and fields

static NSArray<NSNumber *> *FKArrayElements(Il2CppObject *arrayObject, NSUInteger limit, NSString **elementClass) {
    if (!arrayObject) return @[];
    size_t count = gAPI.array_length(arrayObject);
    if (count == 0) return @[];
    size_t take = MIN(count, limit ?: 256);
    void **data = (void **)((uint8_t *)arrayObject + 32);
    NSMutableArray *results = [NSMutableArray array];
    for (size_t i = 0; i < take; i++) {
        void *pointer = data[i];
        [results addObject:@((unsigned long long)(uintptr_t)pointer)];
        if (elementClass && i == 0 && pointer && FKCanRead(pointer, 16)) {
            *elementClass = FKClassFullName(gAPI.object_get_class((Il2CppObject *)pointer));
        }
    }
    return results;
}

static NSArray<NSDictionary *> *FKScanStaticFieldsForClass(Il2CppClass *target, NSInteger limit, NSTimeInterval budget) {
    NSMutableArray *results = [NSMutableArray array];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:budget];
    NSArray *classes = FKClassCache();
    for (NSDictionary *entry in classes) {
        if ([deadline timeIntervalSinceNow] < 0) break;
        Il2CppClass *klass = (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
        void *iterator = NULL;
        FieldInfo *field = NULL;
        while ((field = gAPI.class_get_fields(klass, &iterator))) {
            int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
            if (!(flags & 0x0010)) continue;
            const Il2CppType *type = gAPI.field_get_type(field);
            if (!type) continue;
            int typeEnum = gAPI.type_get_type ? gAPI.type_get_type(type) : 0x12;
            if (typeEnum != 0x12 && typeEnum != 0x1c) continue;
            uint8_t buffer[16] = { 0 };
            gAPI.field_static_get_value(field, buffer);
            void *pointer = *(void **)buffer;
            if (!pointer || !FKCanRead(pointer, 16)) continue;
            Il2CppClass *objectClass = gAPI.object_get_class((Il2CppObject *)pointer);
            BOOL matches = objectClass == target;
            if (!matches && gAPI.class_is_subclass_of) matches = gAPI.class_is_subclass_of(objectClass, target, YES) != 0;
            if (!matches) continue;
            [results addObject:@{ @"ptr": @((unsigned long long)(uintptr_t)pointer),
                                  @"class": FKClassFullName(objectClass),
                                  @"via": [NSString stringWithFormat:@"%@.%@", FKClassFullName(klass),
                                           FKIL2CPPString(gAPI.field_get_name(field))] }];
            if ((NSInteger)results.count >= limit) return results;
        }
    }
    return results;
}

+ (NSDictionary *)findObjectsOfClass:(NSString *)className limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"class not found: %@", className] };
    NSInteger cap = MAX(1, MIN(limit, 2000));
    NSString *strategy = @"static-fields";
    NSString *elementClass = nil;
    NSMutableArray *objects = [NSMutableArray array];

    Il2CppClass *unityObject = FKClassByName(@"UnityEngine.Object");
    BOOL derivedFromUnityObject = NO;
    if (unityObject) {
        derivedFromUnityObject = (klass == unityObject);
        if (!derivedFromUnityObject && gAPI.class_is_subclass_of)
            derivedFromUnityObject = gAPI.class_is_subclass_of(klass, unityObject, YES) != 0;
    }
    if (derivedFromUnityObject && gAPI.type_get_object && gAPI.class_get_type) {
        MethodInfo *method = gAPI.class_get_method_from_name(unityObject, "FindObjectsOfType", 1);
        BOOL twoArgs = NO;
        if (!method) {
            method = gAPI.class_get_method_from_name(unityObject, "FindObjectsByType", 2);
            twoArgs = YES;
        }
        if (method) {
            Il2CppObject *typeObject = gAPI.type_get_object(gAPI.class_get_type(klass));
            int32_t sortMode = 0;
            void *arguments[2] = { typeObject, &sortMode };
            Il2CppException *exception = NULL;
            Il2CppObject *arrayObject = gAPI.runtime_invoke(method, NULL, arguments, &exception);
            if (arrayObject && !exception) {
                NSArray<NSNumber *> *pointers = FKArrayElements(arrayObject, (NSUInteger)cap, &elementClass);
                for (NSNumber *number in pointers) {
                    unsigned long long pointer = number.unsignedLongLongValue;
                    if (!pointer) continue;
                    [objects addObject:@{ @"ptr": @(pointer),
                                          @"class": FKClassFullName(gAPI.object_get_class((Il2CppObject *)(uintptr_t)pointer)) }];
                }
                strategy = twoArgs ? @"FindObjectsByType" : @"FindObjectsOfType";
            } else if (exception) {
                strategy = @"FindObjects exception";
            }
        }
    }
    if (objects.count == 0) {
        NSArray *scanned = FKScanStaticFieldsForClass(klass, cap, 6.0);
        for (NSDictionary *entry in scanned) [objects addObject:entry];
        if (scanned.count) strategy = @"static-fields";
    }
    if (objects.count == 0 && derivedFromUnityObject) strategy = @"unity-api-empty";

    return @{ @"ok": @YES, @"class": FKClassFullName(klass), @"count": @(objects.count),
              @"strategy": strategy, @"objects": objects };
}

+ (NSDictionary *)inspectObjectOfClass:(NSString *)className pointer:(unsigned long long)pointer limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": @"class not found" };
    if (!pointer || !FKCanRead((const void *)(uintptr_t)pointer, 16))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
    NSInteger cap = MAX(1, MIN(limit, 300));
    NSMutableArray *fields = [NSMutableArray array];
    Il2CppClass *cursor = klass;
    NSInteger depth = 0;
    while (cursor && depth++ < 16) {
        void *iterator = NULL;
        FieldInfo *field = NULL;
        while ((field = gAPI.class_get_fields(cursor, &iterator))) {
            int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
            if (flags & 0x0010) continue;
            const Il2CppType *type = gAPI.field_get_type(field);
            NSUInteger offset = gAPI.field_get_offset ? gAPI.field_get_offset(field) : 0;
            uint8_t buffer[256] = { 0 };
            gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
            id value = FKValueAtType(type, buffer);
            NSMutableDictionary *entry = [@{
                @"name": FKIL2CPPString(gAPI.field_get_name(field)),
                @"type": FKTypeName(type),
                @"declaring": FKClassFullName(cursor),
                @"offset": @(offset),
                @"static": @NO,
                @"value": value,
            } mutableCopy];
            if ([value isKindOfClass:[NSDictionary class]] && value[@"ptr"]) {
                entry[@"objectPtr"] = value[@"ptr"];
                entry[@"navigable"] = @YES;
            }
            [fields addObject:entry];
            if ((NSInteger)fields.count >= cap) break;
        }
        if ((NSInteger)fields.count >= cap) break;
        cursor = gAPI.class_get_parent ? gAPI.class_get_parent(cursor) : NULL;
    }
    return @{ @"ok": @YES, @"class": FKClassFullName(klass), @"object": @(pointer),
              @"count": @(fields.count), @"fields": fields };
}

+ (NSDictionary *)readField:(NSString *)fieldName ofClass:(NSString *)className object:(unsigned long long)pointer {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": @"class not found" };
    Il2CppClass *cursor = klass;
    FieldInfo *field = NULL;
    NSInteger depth = 0;
    while (cursor && !field && depth++ < 16) {
        field = FKFieldByName(cursor, fieldName);
        if (!field) cursor = gAPI.class_get_parent ? gAPI.class_get_parent(cursor) : NULL;
    }
    if (!field) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"field not found: %@", fieldName] };
    int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
    BOOL isStatic = (flags & 0x0010) != 0;
    uint8_t buffer[256] = { 0 };
    if (isStatic) {
        gAPI.field_static_get_value(field, buffer);
    } else {
        if (!pointer || !FKCanRead((const void *)(uintptr_t)pointer, 16))
            return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
        gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
    }
    id value = FKValueAtType(gAPI.field_get_type(field), buffer);
    return @{ @"ok": @YES, @"class": FKClassFullName(klass), @"field": fieldName,
              @"type": FKTypeName(gAPI.field_get_type(field)), @"static": @(isStatic),
              @"value": value };
}

+ (NSDictionary *)writeField:(NSString *)fieldName ofClass:(NSString *)className
                      object:(unsigned long long)pointer value:(id)value {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": @"class not found" };
    Il2CppClass *cursor = klass;
    FieldInfo *field = NULL;
    NSInteger depth = 0;
    while (cursor && !field && depth++ < 16) {
        field = FKFieldByName(cursor, fieldName);
        if (!field) cursor = gAPI.class_get_parent ? gAPI.class_get_parent(cursor) : NULL;
    }
    if (!field) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"field not found: %@", fieldName] };
    int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
    BOOL isStatic = (flags & 0x0010) != 0;
    uint8_t buffer[256] = { 0 };
    if (!isStatic && (!pointer || !FKCanRead((const void *)(uintptr_t)pointer, 16)))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };
    const Il2CppType *type = gAPI.field_get_type(field);
    if (isStatic) gAPI.field_static_get_value(field, buffer);
    else gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
    if (!FKWriteValueAtType(type, buffer, value))
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"unsupported field type %@", FKTypeName(type)] };
    if (isStatic) gAPI.field_static_set_value(field, buffer);
    else gAPI.field_set_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
    return @{ @"ok": @YES, @"class": FKClassFullName(klass), @"field": fieldName,
              @"type": FKTypeName(type), @"static": @(isStatic), @"value": FKValueAtType(type, buffer) };
}

#pragma mark - Methods

static MethodInfo *FKFindMethod(Il2CppClass *klass, NSString *methodName, NSInteger overload) {
    void *iterator = NULL;
    const MethodInfo *method = NULL;
    NSInteger index = 0;
    while ((method = gAPI.class_get_methods(klass, &iterator))) {
        const char *name = gAPI.method_get_name(method);
        if (!name) continue;
        if (![methodName isEqualToString:[NSString stringWithUTF8String:name]]) continue;
        if (index == overload) return (MethodInfo *)method;
        index++;
    }
    if (overload <= 0 && gAPI.class_get_method_from_name) {
        MethodInfo *byName = (MethodInfo *)gAPI.class_get_method_from_name(klass, methodName.UTF8String, -1);
        if (byName) return byName;
    }
    return NULL;
}

+ (NSDictionary *)invokeMethod:(NSString *)methodName ofClass:(NSString *)className
                        object:(unsigned long long)pointer args:(NSArray *)args overload:(NSInteger)overload {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": @"class not found" };
    MethodInfo *method = FKFindMethod(klass, methodName, MAX(0, overload));
    if (!method) return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"method not found: %@", methodName] };
    if (pointer && !FKCanRead((const void *)(uintptr_t)pointer, 16))
        return @{ @"ok": @NO, @"error": @"object pointer is not readable" };

    uint32_t count = gAPI.method_get_param_count ? gAPI.method_get_param_count(method) : 0;
    if (args.count != count)
        return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"expected %u args, got %lu",
                                        count, (unsigned long)args.count] };

    void **parameters = calloc(MAX(count, 1), sizeof(void *));
    uint64_t *storage = calloc(MAX(count, 1), sizeof(uint64_t));
    for (uint32_t i = 0; i < count; i++) {
        const Il2CppType *paramType = gAPI.method_get_param ? gAPI.method_get_param(method, i) : NULL;
        int typeEnum = (paramType && gAPI.type_get_type) ? gAPI.type_get_type(paramType) : 0x12;
        id argument = args[i];
        switch (typeEnum) {
            case 0x02: *(uint8_t *)(storage + i) = [argument boolValue] ? 1 : 0;
                parameters[i] = storage + i; break;
            case 0x03: case 0x07: *(uint16_t *)(storage + i) = (uint16_t)[argument unsignedShortValue];
                parameters[i] = storage + i; break;
            case 0x04: case 0x05: case 0x06: case 0x08: case 0x09:
                *(int32_t *)(storage + i) = (int32_t)[argument intValue];
                parameters[i] = storage + i; break;
            case 0x0a: case 0x0b:
                *(int64_t *)(storage + i) = (int64_t)[argument longLongValue];
                parameters[i] = storage + i; break;
            case 0x0c: *(float *)(storage + i) = [argument floatValue];
                parameters[i] = storage + i; break;
            case 0x0d: *(double *)(storage + i) = [argument doubleValue];
                parameters[i] = storage + i; break;
            case 0x0e: {
                NSString *string = [argument isKindOfClass:[NSString class]] ? argument : [argument description];
                Il2CppString *il2cppString = gAPI.string_new(string.UTF8String);
                parameters[i] = il2cppString;
                break;
            }
            default: {
                unsigned long long address = 0;
                if ([argument isKindOfClass:[NSNumber class]]) address = [argument unsignedLongLongValue];
                else if ([argument isKindOfClass:[NSDictionary class]]) address = [argument[@"ptr"] unsignedLongLongValue];
                else if ([argument isKindOfClass:[NSString class]]) address = strtoull([argument UTF8String], NULL, 0);
                parameters[i] = (void *)(uintptr_t)address;
                break;
            }
        }
    }
    Il2CppException *exception = NULL;
    Il2CppObject *result = gAPI.runtime_invoke(method, (void *)(uintptr_t)pointer, parameters, &exception);
    free(parameters);
    free(storage);
    if (exception) {
        Il2CppClass *exceptionClass = gAPI.object_get_class((Il2CppObject *)exception);
        return @{ @"ok": @NO, @"error": @"managed exception",
                  @"exception_class": FKClassFullName(exceptionClass) };
    }
    const Il2CppType *returnType = gAPI.method_get_return_type ? gAPI.method_get_return_type(method) : NULL;
    int returnEnum = (returnType && gAPI.type_get_type) ? gAPI.type_get_type(returnType) : 0x01;
    id value = [NSNull null];
    if (returnEnum == 0x01) value = @"void";
    else if (returnEnum == 0x0e) value = FKStringFromIl2Cpp((Il2CppString *)result) ?: @"";
    else if (result && gAPI.object_unbox && (returnEnum == 0x02 || returnEnum == 0x08 || returnEnum == 0x09 ||
             returnEnum == 0x0a || returnEnum == 0x0b || returnEnum == 0x0c || returnEnum == 0x0d || returnEnum == 0x06 ||
             returnEnum == 0x07 || returnEnum == 0x04 || returnEnum == 0x05 || returnEnum == 0x03 ||
             returnEnum == 0x11 || returnEnum == 0x15)) {
        value = FKValueAtType(returnType, gAPI.object_unbox(result));
    } else if (result) {
        value = @{ @"ptr": @((unsigned long long)(uintptr_t)result),
                   @"class": FKClassFullName(gAPI.object_get_class(result)) };
    }
    return @{ @"ok": @YES, @"class": FKClassFullName(klass), @"method": methodName,
              @"return_type": FKTypeName(returnType), @"result": value };
}

#pragma mark - Patching

static vm_prot_t FKPageProtection(void *address) {
    vm_address_t region = (vm_address_t)address;
    vm_size_t size = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    mach_port_t objectName = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64,
                     (vm_region_info_t)&info, &count, &objectName) != KERN_SUCCESS) return 0;
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    return info.protection;
}

static void *FKMethodCodePointer(MethodInfo *method) {
    if (!method) return NULL;
    if (gAPI.method_get_pointer) return gAPI.method_get_pointer(method);
    void *pointer = *(void **)method;
    if (!pointer || (FKPageProtection(pointer) & VM_PROT_EXECUTE) == 0) return NULL;
    return pointer;
}

static BOOL FKWriteMethodPointer(MethodInfo *method, void *target) {
    if (!method) return NO;
    void **slot = (void **)method;
    vm_address_t page = (vm_address_t)slot & ~(vm_address_t)(vm_page_size - 1);
    vm_prot_t original = FKPageProtection(slot);
    if (mprotect((void *)page, vm_page_size, PROT_READ | PROT_WRITE) != 0) return NO;
    *slot = target;
    mprotect((void *)page, vm_page_size, original ? original : (PROT_READ | PROT_EXEC));
    sys_icache_invalidate(slot, sizeof(void *));
    return YES;
}

static void FKEncodeMovWide(uint8_t **cursor, uint64_t value, BOOL is64) {
    uint32_t base = is64 ? 0xD2800000u : 0x52800000u;   // MOVZ
    uint32_t keep = is64 ? 0xF2800000u : 0x72800000u;   // MOVK
    uint32_t chunks = is64 ? 4 : 2;
    for (uint32_t i = 0; i < chunks; i++) {
        uint32_t imm = (uint32_t)((value >> (16 * i)) & 0xffff);
        uint32_t instruction = (i == 0 ? base : keep) | ((16 * i) << 21) | (imm << 5);
        memcpy(*cursor, &instruction, 4);
        *cursor += 4;
    }
}

static void FKEncode(uint8_t **cursor, uint32_t instruction) {
    memcpy(*cursor, &instruction, 4);
    *cursor += 4;
}

// kind: 0 int32, 1 int64/pointer, 2 float, 3 double, 4 ret
static void *FKMakeReturnStub(NSInteger kind, uint64_t value) {
    size_t page = (size_t)vm_page_size;
    uint8_t *code = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) return NULL;
    uint8_t *cursor = code;
    switch (kind) {
        case 0:
            FKEncodeMovWide(&cursor, (uint32_t)value, NO);
            FKEncode(&cursor, 0xD65F03C0u); // ret
            break;
        case 2: {
            FKEncodeMovWide(&cursor, (uint32_t)value, NO);
            FKEncode(&cursor, 0x1E270000u); // fmov s0, w0
            FKEncode(&cursor, 0xD65F03C0u);
            break;
        }
        case 3: {
            FKEncodeMovWide(&cursor, value, YES);
            FKEncode(&cursor, 0x9E670000u); // fmov d0, x0
            FKEncode(&cursor, 0xD65F03C0u);
            break;
        }
        case 1:
            FKEncodeMovWide(&cursor, value, YES);
            FKEncode(&cursor, 0xD65F03C0u);
            break;
        default:
            FKEncode(&cursor, 0xD65F03C0u); // ret
            break;
    }
    size_t used = (size_t)(cursor - code);
    if (mprotect(code, page, PROT_READ | PROT_EXEC) != 0) {
        munmap(code, page);
        return NULL;
    }
    sys_icache_invalidate(code, used);
    return code;
}

+ (NSDictionary *)patchMethod:(NSString *)methodName ofClass:(NSString *)className
                         mode:(NSString *)mode value:(id)value overload:(NSInteger)overload {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": gLoadError ?: @"IL2CPP unavailable" };
    Il2CppClass *klass = FKClassByName(className);
    if (!klass) return @{ @"ok": @NO, @"error": @"class not found" };
    MethodInfo *method = FKFindMethod(klass, methodName, MAX(0, overload));
    if (!method) return @{ @"ok": @NO, @"error": @"method not found" };
    if (gPatches.count >= 64) return @{ @"ok": @NO, @"error": @"patch capacity reached (64)" };

    void *original = FKMethodCodePointer(method);
    if (!original) return @{ @"ok": @NO, @"error": @"cannot resolve method code pointer" };

    NSString *normalized = [mode.lowercaseString isEqualToString:@"redirect"] ? @"redirect" :
                           ([mode.lowercaseString isEqualToString:@"nop"] ? @"nop" : @"return");
    void *target = NULL;
    if ([normalized isEqualToString:@"redirect"]) {
        if (![value isKindOfClass:[NSString class]])
            return @{ @"ok": @NO, @"error": @"redirect requires value = TargetClass.TargetMethod" };
        NSString *spec = value;
        NSRange dot = [spec rangeOfString:@"." options:NSBackwardsSearch];
        if (dot.location == NSNotFound) return @{ @"ok": @NO, @"error": @"redirect target must be Class.Method" };
        Il2CppClass *targetClass = FKClassByName([spec substringToIndex:dot.location]);
        if (!targetClass) return @{ @"ok": @NO, @"error": @"redirect target class not found" };
        MethodInfo *targetMethod = FKFindMethod(targetClass, [spec substringFromIndex:dot.location + 1], 0);
        if (!targetMethod) return @{ @"ok": @NO, @"error": @"redirect target method not found" };
        target = FKMethodCodePointer(targetMethod);
        if (!target) return @{ @"ok": @NO, @"error": @"cannot resolve redirect target pointer" };
    } else {
        const Il2CppType *returnType = gAPI.method_get_return_type ? gAPI.method_get_return_type(method) : NULL;
        int typeEnum = (returnType && gAPI.type_get_type) ? gAPI.type_get_type(returnType) : 0x01;
        if ([normalized isEqualToString:@"nop"] || typeEnum == 0x01) {
            target = FKMakeReturnStub(4, 0);
        } else if (typeEnum == 0x02) {
            target = FKMakeReturnStub(0, [value boolValue] ? 1 : 0);
        } else if (typeEnum == 0x04 || typeEnum == 0x05 || typeEnum == 0x06 || typeEnum == 0x07 ||
                   typeEnum == 0x08 || typeEnum == 0x09 || typeEnum == 0x11 || typeEnum == 0x15) {
            target = FKMakeReturnStub(0, (uint32_t)[value longLongValue]);
        } else if (typeEnum == 0x0a || typeEnum == 0x0b) {
            target = FKMakeReturnStub(1, [value unsignedLongLongValue]);
        } else if (typeEnum == 0x0c) {
            float number = [value floatValue];
            uint32_t bits = 0;
            memcpy(&bits, &number, 4);
            target = FKMakeReturnStub(2, bits);
        } else if (typeEnum == 0x0d) {
            double number = [value doubleValue];
            uint64_t bits = 0;
            memcpy(&bits, &number, 8);
            target = FKMakeReturnStub(3, bits);
        } else if (typeEnum == 0x0e) {
            if (!gAPI.string_new) return @{ @"ok": @NO, @"error": @"string patching unavailable" };
            Il2CppString *string = gAPI.string_new([value description].UTF8String);
            target = FKMakeReturnStub(1, (uint64_t)(uintptr_t)string);
        } else {
            return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"unsupported return type %@", FKTypeName(returnType)] };
        }
    }
    if (!target) return @{ @"ok": @NO, @"error": @"cannot allocate executable stub (RWX denied)" };
    if (!FKWriteMethodPointer(method, target)) {
        munmap(target, (size_t)vm_page_size);
        return @{ @"ok": @NO, @"error": @"cannot write method pointer" };
    }
    NSDictionary *record = @{ @"class": FKClassFullName(klass),
                              @"method": methodName,
                              @"mode": normalized,
                              @"original": [NSValue valueWithPointer:original],
                              @"stub": [NSValue valueWithPointer:target],
                              @"method_ptr": [NSValue valueWithPointer:method] };
    [gPatches addObject:record];
    FKLog(@"patch %@.%@ [%@]", record[@"class"], methodName, normalized);
    return @{ @"ok": @YES, @"class": record[@"class"], @"method": methodName,
              @"mode": normalized, @"active": @(gPatches.count),
              @"address": [NSString stringWithFormat:@"%p", original] };
}

+ (NSDictionary *)restorePatchOfClass:(NSString *)className method:(NSString *)methodName {
    for (NSInteger i = (NSInteger)gPatches.count - 1; i >= 0; i--) {
        NSDictionary *record = gPatches[(NSUInteger)i];
        if (![record[@"class"] isEqualToString:className]) continue;
        if (![record[@"method"] isEqualToString:methodName]) continue;
        MethodInfo *method = (MethodInfo *)[(NSValue *)record[@"method_ptr"] pointerValue];
        FKWriteMethodPointer(method, [(NSValue *)record[@"original"] pointerValue]);
        void *stub = [(NSValue *)record[@"stub"] pointerValue];
        if (stub) munmap(stub, (size_t)vm_page_size);
        [gPatches removeObjectAtIndex:(NSUInteger)i];
        return @{ @"ok": @YES, @"restored": @YES, @"active": @(gPatches.count) };
    }
    return @{ @"ok": @NO, @"error": @"no matching patch" };
}

+ (NSDictionary *)restoreAllPatches {
    NSInteger count = 0;
    for (NSDictionary *record in [gPatches reverseObjectEnumerator]) {
        MethodInfo *method = (MethodInfo *)[(NSValue *)record[@"method_ptr"] pointerValue];
        FKWriteMethodPointer(method, [(NSValue *)record[@"original"] pointerValue]);
        void *stub = [(NSValue *)record[@"stub"] pointerValue];
        if (stub) munmap(stub, (size_t)vm_page_size);
        count++;
    }
    [gPatches removeAllObjects];
    return @{ @"ok": @YES, @"restoredCount": @(count), @"activePatches": @0, @"maxPatches": @64 };
}

+ (NSDictionary *)patchStatus {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *record in gPatches) {
        [entries addObject:@{ @"class": record[@"class"], @"method": record[@"method"],
                              @"mode": record[@"mode"],
                              @"address": [NSString stringWithFormat:@"%p", [(NSValue *)record[@"original"] pointerValue]] }];
    }
    return @{ @"ok": @YES, @"count": @(entries.count), @"maxPatches": @64, @"patches": entries };
}

#pragma mark - Scans

+ (NSDictionary *)findFieldOwners:(NSString *)typeName limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSString *needle = typeName.lowercaseString;
    NSInteger cap = MAX(1, MIN(limit, 500));
    NSMutableArray *owners = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        Il2CppClass *klass = (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
        void *iterator = NULL;
        FieldInfo *field = NULL;
        BOOL matched = NO;
        while ((field = gAPI.class_get_fields(klass, &iterator))) {
            NSString *type = FKTypeName(gAPI.field_get_type(field)).lowercaseString;
            if ([type rangeOfString:needle].location != NSNotFound) { matched = YES; break; }
        }
        if (matched) {
            [owners addObject:@{ @"class": entry[@"name"], @"image": entry[@"image"] }];
            if ((NSInteger)owners.count >= cap) break;
        }
    }
    return @{ @"ok": @YES, @"type": typeName, @"count": @(owners.count), @"owners": owners };
}

+ (NSDictionary *)findMethodsByPattern:(NSString *)pattern returnType:(NSString *)returnType limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSString *nameNeedle = pattern.lowercaseString;
    NSString *typeNeedle = returnType.lowercaseString;
    NSInteger cap = MAX(1, MIN(limit, 500));
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        Il2CppClass *klass = (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
        void *iterator = NULL;
        const MethodInfo *method = NULL;
        while ((method = gAPI.class_get_methods(klass, &iterator))) {
            NSString *name = FKIL2CPPString(gAPI.method_get_name(method));
            if (nameNeedle.length && [name.lowercaseString rangeOfString:nameNeedle].location == NSNotFound) continue;
            NSString *type = gAPI.method_get_return_type ? FKTypeName(gAPI.method_get_return_type(method)) : @"";
            if (typeNeedle.length && [type.lowercaseString rangeOfString:typeNeedle].location == NSNotFound) continue;
            [results addObject:@{ @"class": entry[@"name"], @"method": name, @"return": type }];
            if ((NSInteger)results.count >= cap) return @{ @"ok": @YES, @"count": @(results.count), @"results": results };
        }
    }
    return @{ @"ok": @YES, @"count": @(results.count), @"results": results };
}

+ (NSDictionary *)findClassesInheritingFrom:(NSString *)baseName limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSString *needle = baseName.lowercaseString;
    NSInteger cap = MAX(1, MIN(limit, 1000));
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        Il2CppClass *cursor = gAPI.class_get_parent ? gAPI.class_get_parent((Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue]) : NULL;
        NSInteger depth = 0;
        while (cursor && depth++ < 32) {
            if ([FKClassFullName(cursor).lowercaseString rangeOfString:needle].location != NSNotFound) {
                [results addObject:@{ @"class": entry[@"name"],
                                      @"base": FKClassFullName(cursor),
                                      @"image": entry[@"image"] }];
                break;
            }
            cursor = gAPI.class_get_parent ? gAPI.class_get_parent(cursor) : NULL;
        }
        if ((NSInteger)results.count >= cap) break;
    }
    return @{ @"ok": @YES, @"base": baseName, @"count": @(results.count), @"results": results };
}

+ (NSDictionary *)findClassesImplementing:(NSString *)protocolName limit:(NSInteger)limit {
    if (!FKIL2CPPResolve() || !gAPI.class_get_interfaces) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSString *needle = protocolName.lowercaseString;
    NSInteger cap = MAX(1, MIN(limit, 1000));
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        void *iterator = NULL;
        Il2CppClass *interface = NULL;
        while ((interface = gAPI.class_get_interfaces((Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue], &iterator))) {
            if ([FKClassFullName(interface).lowercaseString rangeOfString:needle].location != NSNotFound) {
                [results addObject:@{ @"class": entry[@"name"], @"interface": FKClassFullName(interface) }];
                break;
            }
        }
        if ((NSInteger)results.count >= cap) break;
    }
    return @{ @"ok": @YES, @"interface": protocolName, @"count": @(results.count), @"results": results };
}

+ (NSDictionary *)findSingletonsWithImage:(NSString *)image limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSArray *names = @[@"instance", @"_instance", @"s_instance", @"m_instance", @"shared", @"sharedinstance"];
    NSInteger cap = MAX(1, MIN(limit, 200));
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in FKClassCache()) {
        if (image.length && ![entry[@"image"] isEqualToString:image]) continue;
        Il2CppClass *klass = (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
        void *iterator = NULL;
        FieldInfo *field = NULL;
        while ((field = gAPI.class_get_fields(klass, &iterator))) {
            int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
            if (!(flags & 0x0010)) continue;
            NSString *fieldName = FKIL2CPPString(gAPI.field_get_name(field)).lowercaseString;
            if (![names containsObject:fieldName]) continue;
            const Il2CppType *type = gAPI.field_get_type(field);
            if (!type) continue;
            int typeEnum = gAPI.type_get_type ? gAPI.type_get_type(type) : 0x12;
            if (typeEnum != 0x12 && typeEnum != 0x1c) continue;
            uint8_t buffer[16] = { 0 };
            gAPI.field_static_get_value(field, buffer);
            void *pointer = *(void **)buffer;
            if (!pointer || !FKCanRead(pointer, 16)) continue;
            [results addObject:@{ @"class": entry[@"name"], @"field": FKIL2CPPString(gAPI.field_get_name(field)),
                                  @"ptr": @((unsigned long long)(uintptr_t)pointer),
                                  @"object_class": FKClassFullName(gAPI.object_get_class((Il2CppObject *)pointer)) }];
            if ((NSInteger)results.count >= cap) return @{ @"ok": @YES, @"count": @(results.count), @"singletons": results };
        }
    }
    return @{ @"ok": @YES, @"count": @(results.count), @"singletons": results };
}

+ (NSDictionary *)scanUIText:(NSString *)needle limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSArray *classes = @[@"UnityEngine.UI.Text", @"TMPro.TMP_Text", @"TMPro.TextMeshProUGUI"];
    NSInteger cap = MAX(1, MIN(limit, 500));
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *className in classes) {
        Il2CppClass *klass = FKClassByName(className);
        if (!klass) continue;
        NSDictionary *found = [self findObjectsOfClass:className limit:cap];
        for (NSDictionary *object in found[@"objects"]) {
            unsigned long long pointer = [object[@"ptr"] unsignedLongLongValue];
            if (!pointer || !FKCanRead((const void *)(uintptr_t)pointer, 16)) continue;
            for (NSString *fieldName in @[@"m_Text", @"m_text", @"text"]) {
                FieldInfo *field = FKFieldByName(klass, fieldName);
                if (!field) continue;
                uint8_t buffer[16] = { 0 };
                gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
                NSString *text = FKStringFromIl2Cpp(*(Il2CppString **)buffer);
                if (!text.length) continue;
                if (!needle.length || [text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [matches addObject:@{ @"class": className, @"ptr": object[@"ptr"], @"text": text }];
                }
                break;
            }
            if ((NSInteger)matches.count >= cap) break;
        }
    }
    return @{ @"ok": @YES, @"needle": needle ?: @"", @"count": @(matches.count), @"matches": matches };
}

+ (NSDictionary *)sceneRootsWithLimit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSInteger cap = MAX(1, MIN(limit, 200));
    NSDictionary *found = [self findObjectsOfClass:@"UnityEngine.Transform" limit:cap * 3];
    NSMutableArray *roots = [NSMutableArray array];
    for (NSDictionary *object in found[@"objects"]) {
        unsigned long long pointer = [object[@"ptr"] unsignedLongLongValue];
        if (!pointer) continue;
        void *parent = NULL;
        for (NSString *fieldName in @[@"m_Father", @"m_Parent"]) {
            FieldInfo *field = FKFieldByName(FKClassByName(@"UnityEngine.Transform"), fieldName);
            if (!field) continue;
            uint8_t buffer[16] = { 0 };
            gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, field, buffer);
            parent = *(void **)buffer;
            break;
        }
        if (parent) continue;
        NSString *name = @"";
        FieldInfo *gameObjectField = FKFieldByName(FKClassByName(@"UnityEngine.Component"), @"m_GameObject");
        if (gameObjectField) {
            uint8_t buffer[16] = { 0 };
            gAPI.field_get_value((Il2CppObject *)(uintptr_t)pointer, gameObjectField, buffer);
            void *gameObject = *(void **)buffer;
            if (gameObject) {
                NSDictionary *invoked = [self invokeMethod:@"get_name" ofClass:@"UnityEngine.Object"
                                                    object:(unsigned long long)(uintptr_t)gameObject
                                                      args:@[] overload:0];
                if ([invoked[@"result"] isKindOfClass:[NSString class]]) name = invoked[@"result"];
            }
        }
        [roots addObject:@{ @"ptr": @(pointer), @"name": name }];
        if ((NSInteger)roots.count >= cap) break;
    }
    return @{ @"ok": @YES, @"count": @(roots.count), @"roots": roots };
}

#pragma mark - PlayerPrefs, collections, compare, watch

+ (NSDictionary *)playerPrefsRead:(NSString *)key type:(NSString *)type {
    NSString *method = @"GetInt";
    if ([type.lowercaseString isEqualToString:@"float"]) method = @"GetFloat";
    else if ([type.lowercaseString isEqualToString:@"string"]) method = @"GetString";
    NSDictionary *result = [self invokeMethod:method ofClass:@"UnityEngine.PlayerPrefs"
                                       object:0 args:@[key ?: @""] overload:0];
    if (![result[@"ok"] boolValue]) return result;
    return @{ @"ok": @YES, @"key": key ?: @"", @"type": type ?: @"int", @"value": result[@"result"] };
}

+ (NSDictionary *)playerPrefsWrite:(NSString *)key type:(NSString *)type value:(id)value delete:(BOOL)deleteKey {
    if (deleteKey) {
        NSDictionary *result = [self invokeMethod:@"DeleteKey" ofClass:@"UnityEngine.PlayerPrefs"
                                           object:0 args:@[key ?: @""] overload:0];
        return result;
    }
    NSString *method = @"SetInt";
    if ([type.lowercaseString isEqualToString:@"float"]) method = @"SetFloat";
    else if ([type.lowercaseString isEqualToString:@"string"]) method = @"SetString";
    NSDictionary *result = [self invokeMethod:method ofClass:@"UnityEngine.PlayerPrefs"
                                       object:0 args:@[key ?: @"", value ?: @0] overload:0];
    if (![result[@"ok"] boolValue]) return result;
    NSDictionary *save = [self invokeMethod:@"Save" ofClass:@"UnityEngine.PlayerPrefs"
                                     object:0 args:@[] overload:0];
    return @{ @"ok": @([save[@"ok"] boolValue]), @"key": key ?: @"", @"type": type ?: @"int",
              @"value": value ?: [NSNull null], @"saved": save };
}

+ (NSDictionary *)inspectCollection:(unsigned long long)pointer limit:(NSInteger)limit {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    if (!pointer || !FKCanRead((const void *)(uintptr_t)pointer, 32))
        return @{ @"ok": @NO, @"error": @"collection pointer is not readable" };
    Il2CppObject *object = (Il2CppObject *)(uintptr_t)pointer;
    Il2CppClass *klass = gAPI.object_get_class(object);
    NSString *className = FKClassFullName(klass);
    NSInteger cap = MAX(1, MIN(limit, 500));

    if ([className hasSuffix:@"[]"]) {
        size_t count = gAPI.array_length(object);
        void **data = (void **)((uint8_t *)object + 32);
        NSMutableArray *elements = [NSMutableArray array];
        for (size_t i = 0; i < MIN(count, (size_t)cap); i++) {
            void *element = data[i];
            NSMutableDictionary *entry = [@{ @"index": @(i) } mutableCopy];
            if (element && FKCanRead(element, 16)) {
                entry[@"ptr"] = @((unsigned long long)(uintptr_t)element);
                entry[@"class"] = FKClassFullName(gAPI.object_get_class((Il2CppObject *)element));
            } else if (element) {
                entry[@"value"] = @((unsigned long long)(uintptr_t)element);
            } else {
                entry[@"value"] = [NSNull null];
            }
            [elements addObject:entry];
        }
        return @{ @"ok": @YES, @"collection": className, @"kind": @"array",
                  @"count": @(count), @"elements": elements };
    }

    FieldInfo *itemsField = FKFieldByName(klass, @"_items");
    if (itemsField) {
        uint8_t buffer[16] = { 0 };
        gAPI.field_get_value(object, itemsField, buffer);
        Il2CppObject *items = *(Il2CppObject **)buffer;
        FieldInfo *sizeField = FKFieldByName(klass, @"_size");
        int32_t size = 0;
        if (sizeField) {
            uint8_t sizeBuffer[16] = { 0 };
            gAPI.field_get_value(object, sizeField, sizeBuffer);
            size = *(int32_t *)sizeBuffer;
        } else if (items) {
            size = (int32_t)gAPI.array_length(items);
        }
        NSMutableArray *elements = [NSMutableArray array];
        if (items && FKCanRead(items, 32)) {
            void **data = (void **)((uint8_t *)items + 32);
            for (NSInteger i = 0; i < MIN((size_t)size, (size_t)cap); i++) {
                void *element = data[i];
                NSMutableDictionary *entry = [@{ @"index": @(i) } mutableCopy];
                if (element && FKCanRead(element, 16)) {
                    entry[@"ptr"] = @((unsigned long long)(uintptr_t)element);
                    entry[@"class"] = FKClassFullName(gAPI.object_get_class((Il2CppObject *)element));
                } else {
                    entry[@"value"] = element ? @((unsigned long long)(uintptr_t)element) : [NSNull null];
                }
                [elements addObject:entry];
            }
        }
        return @{ @"ok": @YES, @"collection": className, @"kind": @"list",
                  @"count": @(size), @"elements": elements };
    }
    return @{ @"ok": @NO, @"error": [NSString stringWithFormat:@"unsupported collection type %@", className],
              @"hint": @"arrays and List<T> are supported" };
}

+ (NSDictionary *)compareInstances:(NSArray<NSString *> *)classNames fields:(NSArray<NSString *> *)fields {
    NSMutableArray *results = [NSMutableArray array];
    for (NSString *className in [classNames subarrayWithRange:NSMakeRange(0, MIN(classNames.count, (NSUInteger)5))]) {
        NSDictionary *found = [self findObjectsOfClass:className limit:1];
        NSMutableDictionary *entry = [@{ @"class": className,
                                         @"instances": found[@"count"] ?: @0 } mutableCopy];
        NSDictionary *object = [found[@"objects"] firstObject];
        if (object) {
            NSDictionary *inspection = [self inspectObjectOfClass:className
                                                           pointer:[object[@"ptr"] unsignedLongLongValue]
                                                             limit:fields.count ? 60 : 40];
            NSArray *allFields = inspection[@"fields"] ?: @[];
            if (fields.count) {
                NSMutableArray *filtered = [NSMutableArray array];
                for (NSDictionary *field in allFields) {
                    if ([fields containsObject:field[@"name"]]) [filtered addObject:field];
                }
                entry[@"fields"] = filtered;
            } else {
                entry[@"fields"] = [allFields subarrayWithRange:NSMakeRange(0, MIN(allFields.count, (NSUInteger)12))];
            }
        }
        [results addObject:entry];
    }
    return @{ @"ok": @YES, @"count": @(results.count), @"comparison": results };
}

+ (NSDictionary *)watchField:(NSString *)className field:(NSString *)fieldName
                      object:(unsigned long long)pointer samples:(NSInteger)samples intervalMs:(NSInteger)interval {
    NSInteger count = MAX(1, MIN(samples, 60));
    NSInteger delay = MAX(50, MIN(interval, 5000));
    NSMutableArray *values = [NSMutableArray array];
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *read = [self readField:fieldName ofClass:className object:pointer];
        [values addObject:read[@"value"] ?: [NSNull null]];
        if (i + 1 < count) [NSThread sleepForTimeInterval:delay / 1000.0];
    }
    NSMutableSet *distinct = [NSMutableSet set];
    for (id value in values) [distinct addObject:[value description]];
    NSInteger changed = 0;
    for (NSInteger i = 1; i < (NSInteger)values.count; i++) {
        if (![values[(NSUInteger)i] isEqual:values[(NSUInteger)i - 1]]) changed++;
    }
    return @{ @"ok": @YES, @"class": className, @"field": fieldName,
              @"samples": values, @"changedCount": @(changed),
              @"distinctValues": @(distinct.count), @"isLive": @(changed > 0) };
}

+ (NSDictionary *)dumpWithFilter:(NSString *)filter path:(NSString *)path {
    if (!FKIL2CPPResolve()) return @{ @"ok": @NO, @"error": @"IL2CPP unavailable" };
    NSString *destination = path.length ? FKExpandPath(path)
        : [FKDocumentsPath() stringByAppendingPathComponent:
           [NSString stringWithFormat:@"forgekit-dump-%ld.txt", (long)[[NSDate date] timeIntervalSince1970]]];
    NSString *needle = filter.lowercaseString;
    NSDate *start = [NSDate date];
    NSMutableString *output = [NSMutableString stringWithCapacity:1024 * 1024];
    NSInteger classCount = 0, fieldCount = 0, methodCount = 0;

    for (NSDictionary *entry in FKClassCache()) {
        if (needle.length && [[entry[@"name"] lowercaseString] rangeOfString:needle].location == NSNotFound) continue;
        Il2CppClass *klass = (Il2CppClass *)[(NSValue *)entry[@"ptr"] pointerValue];
        [output appendFormat:@"\nclass %@ // %@\n", entry[@"name"], entry[@"image"]];
        void *iterator = NULL;
        FieldInfo *field = NULL;
        while ((field = gAPI.class_get_fields(klass, &iterator))) {
            int flags = gAPI.field_get_flags ? gAPI.field_get_flags(field) : 0;
            [output appendFormat:@"  %@field %@ %@\n", (flags & 0x0010) ? @"static " : @"",
             FKTypeName(gAPI.field_get_type(field)), FKIL2CPPString(gAPI.field_get_name(field))];
            fieldCount++;
        }
        iterator = NULL;
        const MethodInfo *method = NULL;
        while ((method = gAPI.class_get_methods(klass, &iterator))) {
            [output appendFormat:@"  method %@ %@(", FKTypeName(gAPI.method_get_return_type(method)),
             FKIL2CPPString(gAPI.method_get_name(method))];
            uint32_t params = gAPI.method_get_param_count ? gAPI.method_get_param_count(method) : 0;
            for (uint32_t i = 0; i < params; i++) {
                if (i) [output appendString:@", "];
                [output appendString:FKTypeName(gAPI.method_get_param(method, i))];
            }
            [output appendString:@")\n"];
            methodCount++;
        }
        classCount++;
        if (output.length > 64 * 1024 * 1024) break;
    }
    NSError *error = nil;
    BOOL written = [output writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:&error];
    return @{ @"ok": @(written), @"path": destination, @"classes": @(classCount),
              @"fields": @(fieldCount), @"methods": @(methodCount),
              @"bytes": @(output.length),
              @"seconds": @(round(-[start timeIntervalSinceNow] * 100) / 100),
              @"error": written ? [NSNull null] : (error.localizedDescription ?: @"write failed") };
}

@end
