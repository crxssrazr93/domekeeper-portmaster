#!/usr/bin/env python3
"""Runs ON the device: touches and mlocks N MB so they cannot be swapped, leaving less RAM for the
game. Usage: python3 ballast.py <MB> &   (kill it to give the memory back). Used to make a 1 GB
device behave like one that has 530 MB available (see docs/PORTING.md section 8)."""
import mmap, ctypes, sys, time
n = int(sys.argv[1]) * 2**20
m = mmap.mmap(-1, n)
for i in range(0, n, 4096):
    m[i] = 1
libc = ctypes.CDLL(None)
addr = ctypes.addressof(ctypes.c_char.from_buffer(m))
print("mlock", libc.mlock(ctypes.c_void_p(addr), ctypes.c_size_t(n)), flush=True)
time.sleep(10**7)
