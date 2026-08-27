#!/usr/bin/env bash
# generate a 256x256 solid PNG icon if none exists (so desktop entry has an icon)
OUT="${1:?out path}"
python3 - "$OUT" <<'PY'
import sys,struct,zlib
out=sys.argv[1]
w=h=256
raw=bytearray()
for y in range(h):
  raw.append(0)  # filter none
  for x in range(w):
    raw += bytes([0x16,0x21,0x3e,0xff])  # #16213e
def chunk(t,d):
  c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
sig=b'\x89PNG\r\n\x1a\n'
ihdr=struct.pack('>IIBBBBB',w,h,8,6,0,0,0)
idat=zlib.compress(bytes(raw),9)
open(out,'wb').write(sig+chunk(b'IHDR',ihdr)+chunk(b'IDAT',idat)+chunk(b'IEND',b''))
PY
