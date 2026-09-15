#!/usr/bin/env python3
"""Convert a raw little-endian binary into a $readmemh image: one 32-bit word
per line, word 0 first, so the file loads straight into the BRAM array."""
import sys, struct

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: bin2hex.py <in.bin> <out.hex>")
    data = open(sys.argv[1], "rb").read()
    data += b"\0" * (-len(data) % 4)
    with open(sys.argv[2], "w", newline="\n") as f:
        for (w,) in struct.iter_unpack("<I", data):
            f.write(f"{w:08x}\n")

if __name__ == "__main__":
    main()
