#!/usr/bin/env python3
import struct, sys
data = open(sys.argv[1], 'rb').read()
magic = struct.unpack('>I', data[:4])[0]
slices = []
if magic == 0xCAFEBABE:
    n = struct.unpack('>I', data[4:8])[0]
    for i in range(n):
        cpu, sub, off, size, align = struct.unpack('>5I', data[8+i*20:28+i*20])
        slices.append((cpu, sub, data[off:off+size]))
else:
    slices.append((0, 0, data))
for cpu, sub, blob in slices:
    arch = {0x0100000C: 'arm64e' if sub & 0x80000000 else 'arm64'}.get(cpu, hex(cpu))
    ncmds = struct.unpack('<I', blob[16:20])[0]
    p = 32
    libs, ident = [], None
    for _ in range(ncmds):
        cmd, size = struct.unpack('<II', blob[p:p+8])
        if cmd in (0xc, 0xd):
            no = struct.unpack('<I', blob[p+8:p+12])[0]
            name = blob[p+no:p+size].split(b'\0')[0].decode()
            if cmd == 0xd: ident = name
            else: libs.append(name)
        p += size
    print(arch, 'id=%s' % ident, 'deps=%d' % len(libs))
    for lib in libs:
        print('   ', lib)
