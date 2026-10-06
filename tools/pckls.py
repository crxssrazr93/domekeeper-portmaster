#!/usr/bin/env python3
"""List files in a Godot 4 .pck (format v2/v3) with sizes. Usage: pckls.py game.pck [--by-ext]"""
import struct, sys, collections

def entries(path):
    f = open(path, 'rb')
    assert f.read(4) == b'GDPC', 'not a pck'
    ver, major, minor, patch, flags, base = struct.unpack('<IIIIIQ', f.read(28))
    if ver >= 3:
        f.read(8)  # directory offset
    f.read(16 * 4)
    count, = struct.unpack('<I', f.read(4))
    for _ in range(count):
        n, = struct.unpack('<I', f.read(4))
        name = f.read(n).rstrip(b'\0').decode()
        off, size = struct.unpack('<QQ', f.read(16))
        f.read(16)
        fl, = struct.unpack('<I', f.read(4))
        yield name, base + off, size

if __name__ == '__main__':
    items = list(entries(sys.argv[1]))
    if '--by-ext' in sys.argv:
        agg = collections.Counter(); cnt = collections.Counter()
        for n, o, s in items:
            ext = n.rsplit('/', 1)[-1].split('.', 1)[-1] if '.' in n else '-'
            ext = '.'.join(ext.split('.')[-2:])
            agg[ext] += s; cnt[ext] += 1
        for ext, s in agg.most_common(15):
            print(f'{s/1048576:9.1f} MB  {cnt[ext]:6d}  {ext}')
    else:
        for n, o, s in items:
            print(s, o, n)
