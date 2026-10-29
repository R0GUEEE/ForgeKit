#!/usr/bin/env python3
"""Combine thin Mach-O slices into a universal (fat) binary."""
import struct, sys, os

out, inputs = sys.argv[1], sys.argv[2:]
ALIGN = 1 << 14

def cputype(data):
    magic = struct.unpack('<I', data[:4])[0]
    if magic not in (0xfeedfacf, 0xfeedface):
        raise SystemExit('not a thin Mach-O: %s' % magic)
    cputype, cpusubtype = struct.unpack('<II', data[4:12])
    return cputype, cpusubtype

slices = []
for path in inputs:
    data = open(path, 'rb').read()
    cpu, sub = cputype(data)
    if cpu == 0x0100000C:
        sub = 0 if 'arm64e' not in path else 0x80000002
    slices.append((cpu, sub, data))

header_size = 8 + 20 * len(slices)
offset = (header_size + ALIGN - 1) // ALIGN * ALIGN
arch_entries = []
blob = bytearray()
blob += struct.pack('>II', 0xCAFEBABE, len(slices))
for cpu, sub, data in slices:
    arch_entries.append((cpu, sub, offset, len(data), 14))
    offset += (len(data) + ALIGN - 1) // ALIGN * ALIGN

out_data = bytearray(struct.pack('>II', 0xCAFEBABE, len(slices)))
for cpu, sub, off, size, align in arch_entries:
    out_data += struct.pack('>IIIII', cpu, sub, off, size, align)
out_data += bytes(arch_entries[0][2] - len(out_data))
for (cpu, sub, off, size, align), (_, _, data) in zip(arch_entries, slices):
    out_data += data
    out_data += bytes(((len(out_data) + ALIGN - 1) // ALIGN * ALIGN) - len(out_data))
open(out, 'wb').write(out_data)
print('wrote', out, len(out_data), 'bytes,', len(slices), 'slices')
