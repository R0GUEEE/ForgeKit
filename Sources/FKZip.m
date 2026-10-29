//
//  FKZip.m — minimal zip writer/reader (store + deflate, no dependencies beyond zlib)
//

#import "ForgeKit.h"
#import <zlib.h>

static NSError *FKZipError(NSString *message) {
    return [NSError errorWithDomain:@"ForgeKit.Zip" code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"zip error" }];
}

static void FKAppendU16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = { value & 0xff, (value >> 8) & 0xff };
    [data appendBytes:bytes length:2];
}

static void FKAppendU32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = { value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff };
    [data appendBytes:bytes length:4];
}

static uint16_t FKReadU16(const uint8_t *bytes, NSUInteger offset) {
    return (uint16_t)(bytes[offset] | (bytes[offset + 1] << 8));
}

static uint32_t FKReadU32(const uint8_t *bytes, NSUInteger offset) {
    return (uint32_t)bytes[offset] | ((uint32_t)bytes[offset + 1] << 8)
         | ((uint32_t)bytes[offset + 2] << 16) | ((uint32_t)bytes[offset + 3] << 24);
}

static void FKDosDateTime(NSDate *date, uint16_t *dosTime, uint16_t *dosDate) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                                         NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                               fromDate:date ?: [NSDate date]];
    NSInteger year = MAX(1980, components.year);
    *dosTime = (uint16_t)((components.hour << 11) | (components.minute << 5) | (components.second / 2));
    *dosDate = (uint16_t)(((year - 1980) << 9) | (components.month << 5) | components.day);
}

static NSData *FKDeflateData(NSData *input) {
    if (!input.length) return [NSData data];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK)
        return nil;
    uLong bound = deflateBound(&stream, (uLong)input.length);
    NSMutableData *output = [NSMutableData dataWithLength:bound];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;
    stream.next_out = output.mutableBytes;
    stream.avail_out = (uInt)bound;
    int status = deflate(&stream, Z_FINISH);
    if (status != Z_STREAM_END) {
        deflateEnd(&stream);
        return nil;
    }
    output.length = stream.total_out;
    deflateEnd(&stream);
    return output;
}

static NSData *FKInflateData(NSData *input, NSUInteger expectedSize) {
    if (!input.length) return [NSData data];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return nil;
    NSUInteger capacity = MAX(expectedSize, (NSUInteger)4096);
    NSMutableData *output = [NSMutableData dataWithLength:capacity];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;

    int status = Z_OK;
    while (status == Z_OK) {
        if (stream.total_out == output.length) [output increaseLengthBy:65536];
        stream.next_out = (Bytef *)output.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(output.length - stream.total_out);
        status = inflate(&stream, Z_NO_FLUSH);
    }
    if (status != Z_STREAM_END) {
        inflateEnd(&stream);
        return nil;
    }
    output.length = stream.total_out;
    inflateEnd(&stream);
    return output;
}

@implementation FKZip

+ (void)collectFilesAtPath:(NSString *)path
                    prefix:(NSString *)prefix
                   entries:(NSMutableArray<NSDictionary *> *)entries
                     error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) return;
    if (!isDirectory) {
        [entries addObject:@{ @"disk": path, @"name": prefix }];
        return;
    }
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:path error:error];
    if (!children) return;
    if (children.count == 0) {
        [entries addObject:@{ @"disk": path, @"name": [prefix stringByAppendingString:@"/"], @"directory": @YES }];
    }
    for (NSString *child in [children sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSString *childPrefix = [prefix stringByAppendingPathComponent:child];
        [self collectFilesAtPath:[path stringByAppendingPathComponent:child] prefix:childPrefix entries:entries error:error];
    }
}

+ (BOOL)createArchiveAtPath:(NSString *)archivePath
                  fromPaths:(NSArray<NSString *> *)paths
                      error:(NSError **)error {
    if (!paths.count) {
        if (error) *error = FKZipError(@"no sources");
        return NO;
    }
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *source in paths) {
        NSString *expanded = FKExpandPath(source);
        NSString *base = [expanded stringByDeletingLastPathComponent];
        [self collectFilesAtPath:expanded prefix:[expanded lastPathComponent] entries:entries error:error];
        (void)base;
    }
    NSMutableData *archive = [NSMutableData data];
    NSMutableData *central = [NSMutableData data];
    NSUInteger fileCount = 0;

    for (NSDictionary *entry in entries) {
        NSString *name = entry[@"name"];
        NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        NSData *payload = [NSData data];
        if (![entry[@"directory"] boolValue]) {
            NSError *readError = nil;
            payload = [NSData dataWithContentsOfFile:entry[@"disk"] options:0 error:&readError];
            if (!payload) {
                if (error) *error = readError ?: FKZipError([NSString stringWithFormat:@"cannot read %@", entry[@"disk"]]);
                return NO;
            }
        }
        uint32_t crc = (uint32_t)crc32(0L, payload.bytes, (uInt)payload.length);
        NSData *compressed = [entry[@"directory"] boolValue] ? payload : FKDeflateData(payload);
        uint16_t method = 8;
        if (!compressed || compressed.length >= payload.length) {
            compressed = payload;
            method = 0;
        }
        uint16_t dosTime = 0, dosDate = 0;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:entry[@"disk"] error:nil];
        FKDosDateTime(attributes[NSFileModificationDate], &dosTime, &dosDate);
        uint32_t offset = (uint32_t)archive.length;

        FKAppendU32(archive, 0x04034b50);
        FKAppendU16(archive, 20);
        FKAppendU16(archive, 0);
        FKAppendU16(archive, method);
        FKAppendU16(archive, dosTime);
        FKAppendU16(archive, dosDate);
        FKAppendU32(archive, crc);
        FKAppendU32(archive, (uint32_t)compressed.length);
        FKAppendU32(archive, (uint32_t)payload.length);
        FKAppendU16(archive, (uint16_t)nameBytes.length);
        FKAppendU16(archive, 0);
        [archive appendData:nameBytes];
        [archive appendData:compressed];

        FKAppendU32(central, 0x02014b50);
        FKAppendU16(central, 20);
        FKAppendU16(central, 20);
        FKAppendU16(central, 0);
        FKAppendU16(central, method);
        FKAppendU16(central, dosTime);
        FKAppendU16(central, dosDate);
        FKAppendU32(central, crc);
        FKAppendU32(central, (uint32_t)compressed.length);
        FKAppendU32(central, (uint32_t)payload.length);
        FKAppendU16(central, (uint16_t)nameBytes.length);
        FKAppendU16(central, 0);
        FKAppendU16(central, 0);
        FKAppendU16(central, 0);
        FKAppendU16(central, 0);
        FKAppendU32(central, 0);
        FKAppendU32(central, offset);
        [central appendData:nameBytes];
        fileCount++;
    }

    uint32_t centralOffset = (uint32_t)archive.length;
    [archive appendData:central];
    FKAppendU32(archive, 0x06054b50);
    FKAppendU16(archive, 0);
    FKAppendU16(archive, 0);
    FKAppendU16(archive, (uint16_t)fileCount);
    FKAppendU16(archive, (uint16_t)fileCount);
    FKAppendU32(archive, (uint32_t)central.length);
    FKAppendU32(archive, centralOffset);
    FKAppendU16(archive, 0);

    [archive writeToFile:archivePath options:NSDataWritingAtomic error:error];
    return archive.length > 0;
}

+ (NSArray<NSDictionary *> *)listArchiveAtPath:(NSString *)archivePath error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:archivePath options:NSDataReadingMappedIfSafe error:error];
    if (!data) return @[];
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 22) {
        if (error) *error = FKZipError(@"not a zip archive");
        return @[];
    }
    NSUInteger eocd = NSNotFound;
    for (NSUInteger i = length - 22; i != NSNotFound && i > (length > 65558 ? length - 65558 : 0); i--) {
        if (FKReadU32(bytes, i) == 0x06054b50) { eocd = i; break; }
    }
    if (eocd == NSNotFound) {
        if (error) *error = FKZipError(@"end of central directory not found");
        return @[];
    }
    uint16_t count = FKReadU16(bytes, eocd + 10);
    uint32_t offset = FKReadU32(bytes, eocd + 16);
    NSMutableArray *items = [NSMutableArray array];
    for (uint16_t index = 0; index < count && offset + 46 <= length; index++) {
        if (FKReadU32(bytes, offset) != 0x02014b50) break;
        uint16_t method = FKReadU16(bytes, offset + 10);
        uint32_t compressedSize = FKReadU32(bytes, offset + 20);
        uint32_t uncompressedSize = FKReadU32(bytes, offset + 24);
        uint16_t nameLength = FKReadU16(bytes, offset + 28);
        uint16_t extraLength = FKReadU16(bytes, offset + 30);
        uint16_t commentLength = FKReadU16(bytes, offset + 32);
        if (offset + 46 + nameLength > length) break;
        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLength encoding:NSUTF8StringEncoding] ?: @"";
        [items addObject:@{
            @"name": name,
            @"compressed_size": @(compressedSize),
            @"size": @(uncompressedSize),
            @"method": method == 8 ? @"deflate" : @"store",
        }];
        offset += 46 + nameLength + extraLength + commentLength;
    }
    return items;
}

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                 toDirectory:(NSString *)destination
                       error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:archivePath options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger eocd = NSNotFound;
    for (NSUInteger i = length >= 22 ? length - 22 : 0; i != NSNotFound && i > (length > 65558 ? length - 65558 : 0); i--) {
        if (FKReadU32(bytes, i) == 0x06054b50) { eocd = i; break; }
    }
    if (eocd == NSNotFound) {
        if (error) *error = FKZipError(@"end of central directory not found");
        return NO;
    }
    uint16_t count = FKReadU16(bytes, eocd + 10);
    uint32_t offset = FKReadU32(bytes, eocd + 16);
    NSFileManager *fm = [NSFileManager defaultManager];
    destination = [destination stringByStandardizingPath];
    if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error]) return NO;

    for (uint16_t index = 0; index < count && offset + 46 <= length; index++) {
        if (FKReadU32(bytes, offset) != 0x02014b50) break;
        uint16_t method = FKReadU16(bytes, offset + 10);
        uint32_t compressedSize = FKReadU32(bytes, offset + 20);
        uint32_t uncompressedSize = FKReadU32(bytes, offset + 24);
        uint16_t nameLength = FKReadU16(bytes, offset + 28);
        uint16_t extraLength = FKReadU16(bytes, offset + 30);
        uint16_t commentLength = FKReadU16(bytes, offset + 32);
        uint32_t localOffset = FKReadU32(bytes, offset + 42);
        if (offset + 46 + nameLength > length) break;
        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLength encoding:NSUTF8StringEncoding] ?: @"";
        offset += 46 + nameLength + extraLength + commentLength;

        if (!name.length || [name hasPrefix:@"/"] || [name rangeOfString:@".."].location != NSNotFound) continue;
        if (localOffset + 30 > length || FKReadU32(bytes, localOffset) != 0x04034b50) continue;
        uint16_t localNameLength = FKReadU16(bytes, localOffset + 26);
        uint16_t localExtraLength = FKReadU16(bytes, localOffset + 28);
        NSUInteger dataStart = localOffset + 30 + localNameLength + localExtraLength;
        if (dataStart + compressedSize > length) continue;

        NSString *target = [destination stringByAppendingPathComponent:name];
        if ([name hasSuffix:@"/"]) {
            [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        NSData *compressed = [data subdataWithRange:NSMakeRange(dataStart, compressedSize)];
        NSData *payload = method == 8 ? FKInflateData(compressed, uncompressedSize) : compressed;
        if (!payload) continue;
        [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:nil];
        [payload writeToFile:target options:NSDataWritingAtomic error:nil];
    }
    return YES;
}

@end
