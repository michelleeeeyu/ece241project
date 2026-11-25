#!/usr/bin/env python3
"""
img2mif.py - convert an image (PNG, JPG, BMP, ...) into a MIF file for the
VGA adapter's BACKGROUND_IMAGE.

Usage:
    python3 img2mif.py input.png output.mif [--res 640x480] [--depth 9]
    python3 img2mif.py sprite.png template.mif --size 32x32

  --res    VGA adapter RESOLUTION: 640x480 (default), 320x240 or 160x120
  --size   any WIDTHxHEIGHT instead of --res, e.g. for an object/template memory
           (object_mem needs a power-of-2 width, such as 16x16 or 32x32)
  --depth  VGA adapter COLOR_DEPTH: 3, 6, 9 (default), 12, ... (multiple of 3)

The image is resized to fit the resolution (stretched; crop it beforehand if
you want to keep its aspect ratio). Each pixel is stored at address y*COLS + x
as {R, G, B}, each channel using COLOR_DEPTH/3 bits, which is the format the
vga_adapter expects. Requires Pillow:  pip install pillow
"""
import argparse
import sys

from PIL import Image

RESOLUTIONS = {"640x480": (640, 480), "320x240": (320, 240), "160x120": (160, 120)}


def pixel_to_word(r, g, b, bits):
    """Scale 8-bit channels down to `bits` bits each and pack as RGB."""
    shift = 8 - bits
    return ((r >> shift) << (2 * bits)) | ((g >> shift) << bits) | (b >> shift)


def main():
    ap = argparse.ArgumentParser(description="Convert an image to a VGA adapter MIF file.")
    ap.add_argument("input", help="input image file")
    ap.add_argument("output", help="output .mif file")
    ap.add_argument("--res", default="640x480", choices=RESOLUTIONS.keys(),
                    help="VGA adapter RESOLUTION (default 640x480)")
    ap.add_argument("--size", help="output size WIDTHxHEIGHT, overrides --res (e.g. 32x32)")
    ap.add_argument("--depth", type=int, default=9,
                    help="VGA adapter COLOR_DEPTH, a multiple of 3 (default 9)")
    args = ap.parse_args()

    if args.depth % 3 != 0 or not 3 <= args.depth <= 24:
        sys.exit("error: --depth must be a multiple of 3 between 3 and 24")
    bits = args.depth // 3
    cols, rows = RESOLUTIONS[args.res]
    if args.size:
        try:
            cols, rows = (int(v) for v in args.size.lower().split("x"))
        except ValueError:
            sys.exit("error: --size must look like 32x32")

    img = Image.open(args.input).convert("RGB")
    if img.size != (cols, rows):
        print(f"note: resizing {img.size[0]}x{img.size[1]} -> {cols}x{rows}")
        img = img.resize((cols, rows), Image.LANCZOS)

    raw = img.tobytes()  # R,G,B bytes, row by row (address = y*cols + x)
    words = [pixel_to_word(raw[i], raw[i + 1], raw[i + 2], bits)
             for i in range(0, len(raw), 3)]
    hex_digits = (args.depth + 3) // 4

    with open(args.output, "w") as f:
        f.write(f"WIDTH={args.depth};\nDEPTH={cols * rows};\n\n")
        f.write("ADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n")
        # Write runs of identical pixels as ranges to keep the file small.
        start = 0
        for i in range(1, len(words) + 1):
            if i == len(words) or words[i] != words[start]:
                val = f"{words[start]:0{hex_digits}X}"
                if i - 1 == start:
                    f.write(f"{start} : {val};\n")
                else:
                    f.write(f"[{start}..{i - 1}] : {val};\n")
                start = i
        f.write("END;\n")

    print(f"wrote {args.output}: {cols}x{rows}, {args.depth}-bit color, {cols * rows} words")


if __name__ == "__main__":
    main()
