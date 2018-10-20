#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# 10-color screenshot converter for Action 53
#
# Copyright 2018 Damian Yerrick
# 
# This software is provided 'as-is', without any express or implied
# warranty.  In no event will the authors be held liable for any damages
# arising from the use of this software.
# 
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
# 
# 1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.

"""
Screenshot specification

Screenshots are 64x56 pixels with up to 10 colors.  Each 8x8-pixel
area of the image can use up to 7 of these colors:

* black, dark gray, light gray, white, and custom colors 1-3
* black, dark gray, light gray, white, and custom colors 4-6

Custom colors 1-3 cannot appear in the same tile as custom colors 4-6
unless the same color appears in both sets.

Screenshot conversion options

If you provide a list of the custom colors, the converter rounds the
image to both of the palettes and chooses which fits each 8x8 pixel
area best.  This will always succeed, but conversion of out-of-spec
images may produce posterization or attribute clash.  For example,
"16122A162738" creates two sets of custom colors:

* Medium red (16), medium blue (12), and light green (2A)
* Medium red (16), light orange (27), and pale yellow (38)

If you do not provide a list of the custom colors, the converter will
try to guess them from the image's pixels, but an image that does not
follow the specification will not be converted at all.

Copyright 2018 Damian Yerrick


"""
import sys
import itertools
from PIL import Image, ImageChops, ImageStat
from savtool import bisqpal

def quantizetopalette(silf, palette, dither=False):
    """Convert an RGB or L mode image to use a given P image's palette."""

    silf.load()

    # use palette from reference image
    palette.load()
    if palette.mode != "P":
        raise ValueError("bad mode for palette image")
    if silf.mode != "RGB" and silf.mode != "L":
        raise ValueError(
            "only RGB or L mode images can be quantized to a palette"
            )
    im = silf.im.convert("P", 1 if dither else 0, palette.im)
    # the 0 above means turn OFF dithering
    try:
        return silf._makeself(im)  # Pillow 3
    except AttributeError:
        return silf._new(im)  # Pillow 4 changed the name

def make_bisqpal_image(size, hidebad=False):
    """Load the NES palette with some transformations.

size -- (width, height) to return an indexed Pillow image or None
    to return a bytes of length 768
hidebad -- if true, replace these colors with gray $00 to hide less
    desirable colors from quantizetopalette():
    $0D (which causes sync problems on some TVs)
    $2D and $3D (which are missing on 2C03/2C05 PPU of
    PlayChoice 10 and early RGB modded NES consoles)
    $0E (which is black but appears before canonical black)
"""
    from savtool import bisqpal

    bpnoD = list(bisqpal)
    darkgray = bpnoD[0x00]
    if hidebad:
        bpnoD[0x0D] = bpnoD[0x0E] = bpnoD[0x2D] = bpnoD[0x3D] = darkgray
    refpal = b''.join(bpnoD) + darkgray * 192
    if size is None: return refpal
    refim = Image.new('P', size)
    refim.putpalette(refpal)
    return refim

def sorthexspc(it):
    return " ".join("%02x" % x for x in sorted(it))

def dump_tiles(tiles, tilepalettes):
    for tile, p in zip(tiles, tilepalettes):
        print("Colors", sorthexspc(p))
        print("\n".join(tile[r:r + 8].hex() for r in range(0, len(tile), 8)))
        print()

def find_supersets(fsets):
    """In a set of frozensets, find those that aren't subsets of another."""
    uniqpalettes = sorted(set(fsets), key=len, reverse=True)
    return [
        palette
        for numpreceding, palette in enumerate(uniqpalettes)
        if not any(prev.issuperset(palette)
                   for prev in uniqpalettes[:numpreceding])
    ]

def vm_pack_once(itsets, maxlen):
    packs = []
    for s in itsets:
        found = False
        for i in range(len(packs)):
            u = frozenset.union(s, packs[i])
            if len(u) <= maxlen:
                packs[i], found = u, True
                break
        if not found:
            packs.append(s)
    return packs

def vm_pack_bruteforce(sets, maxlen):
    """Create a list of sets of size maxlen that cover all given sets.

The "VM packing" problem is hard to even approximate.  So I'm just
gonna brute-force it by using first-fit in all permutations.
"""
    return min((vm_pack_once(permutation, maxlen)
               for permutation in itertools.permutations(sets)),
               key=len)

def imtom7tiles(im, palette=None):
    if palette:
        im = quantizetopalette(im.convert("RGB"), palette)
    if im.mode != 'P':
        raise ValueError("image must be indexed")
        
    w = im.size[0]
    errs = []
    if w % 8 != 0:
        errs.append("width %d not a multiple of 8 pixels" % w)
    if im.size[1] % 8 != 0:
        errs.append("height %d not a multiple of 8 pixels" % im.size[1])
    if errs:
        raise ValueError("; ".join(errs))

    pixels = bytes(im.getdata())
    ts = 8 * w * 3 + 8 * 2
    tilestarts = [
        ts
        for trs in range(0, len(pixels), w * 8)
        for ts in range(trs, trs + w, 8)
    ]
    return [
        b''.join(pixels[sls:sls + 8] for sls in range(ts, ts + w * 8, w))
        for ts in tilestarts
    ]

def parse_palette(s):
    """Parse a palette string with up to 12 hex digits."""
    b = bytes.fromhex(s)
    if len(b) > 6:
        raise ValueError("too many colors in palette string (%d, more than 6)"
                         % len(b))
    p = [b[:3]]
    if len(b) > 3:
        p.append(b[3:])
    return p

def guess_palette(im):
    """Try to guess the palette of an image that already follows the guidelines."""
    palette = make_bisqpal_image((16, 16), hidebad=True)
    tiles = imtom7tiles(im, palette)
    palette, errs = None, []

    # Ensure each tile meets the limit of 3 nongrays
    grays = [0x0F, 0x00, 0x10, 0x20]
    tilepalettes = [frozenset(x).difference(grays) for x in tiles]
    overallpalette = frozenset.union(*tilepalettes)
    if len(overallpalette) > 6:
        errs.append("too many non-gray colors: " + sorthexspc(overallpalette))

    tile_width = im.size[0] // 8
    for tn, p in enumerate(tilepalettes):
        if len(p) > 3:
            xt, yt = tn % tile_width, tn // tile_width
            errs.append("too many non-gray colors in (%d, %d)-(%d, %d): %s"
                        % (xt * 8, yt * 8, xt * 8 + 7, yt * 8 + 7,
                           sorthexspc(p)))
    if errs:
        raise ValueError("; ".join(errs))

    # Consider only palettes that are not subsets of another palette
    supersets = find_supersets(tilepalettes)

    # Now try to cover them with 2 sets of 3 colors
    if len(overallpalette) <= 3:
        packs = [overallpalette]
    elif len(supersets) <= 2:
        packs = supersets
    else:
        packs = vm_pack_bruteforce(supersets, 3)
        if len(packs) > 2:
            raise ValueError("could not pack palettes into 2 sets of 3: "
                             + ", ".join(sorthexspc(s) for s in supersets))
    return [sorted(p) for p in packs]

def tiletoplanes(m7tile, nplanes):
    out = bytearray()
    ltile = len(m7tile)
    for plane in range(nplanes):
        planemask = 1 << plane
        for y in range(0, ltile, 8):
            byte = 0
            for px in m7tile[y:y + 8]:
                byte = byte << 1
                if px & planemask:
                    byte = byte | 1
            out.append(byte)
    return bytes(out)

def convert_im(im, palette):
    """Convert

palette -- a list of up to 2 sequences of up to 3 NES palette indices
    in 0x01-0x0C, 0x11-0x1C, 0x22-0x2C, 0x33-0x3C
"""
    w, h = im.size
    if w % 8 != 0 or h % 8 != 0:
        raise ValueError("not multiple of 8x8 pixels")

    converted = []
    im = im.convert("RGB")
    for p in palette:
        clut = [0x0F, 0x00, 0x10, 0x20, 0x0F]
        clut.extend(p)
        rgbpal = [bisqpal[i] for i in clut]
        rgbpal.extend([rgbpal[0]] * (256 - len(rgbpal)))
        refim = Image.new("P", (16, 16))
        refim.putpalette(b"".join(rgbpal))
        trialconversion = quantizetopalette(im, refim)
        trialtiles = imtom7tiles(trialconversion)
            
        difference = ImageChops.difference(im, trialconversion.convert("RGB"))
        sum2s = [
            ImageStat.Stat(difference.crop((x, y, x + 8, y + 8))).sum2
            for y in range(0, h, 8)
            for x in range(0, w, 8)
        ]
        # Though 3, 6, 1 are the weights for brightness,
        # better weights for difference are 2, 4, 3.
        # https://en.wikipedia.org/wiki/Color_difference
        tilediffs = [2*dr2 + 4*dg2 + 3*db2 for dr2, dg2, db2 in sum2s]
        converted.append(list(zip(tilediffs, trialtiles)))

    # Convert the best of each to planar
    tiles01 = []
    tiles2 = []
    attrs = []
    for candidates in zip(*converted):
        l = min(enumerate(candidates), key=lambda x: x[1][0])
        planartile = tiletoplanes(l[1][1], 3)
        tiles01.append(planartile[:16])
        tiles2.append(planartile[16:])
        attrs.append(l[0])
    attrs = tiletoplanes(attrs, 1)
    return tiles01, tiles2, attrs

def form_screenshot(tiles01, tiles2, attrs, palette):
    """

tiles01 -- list of 16-byte plane 0 and 1
tiles2 -- list of 8-byte plane 2
attrs -- attribute bitmap
palette -- [c4, c5, c6], [c7, c8, c9]
"""
    c4to6 = bytes(palette[0]) + bytes(3)
    c7to9 = bytes(palette[1]) if len(palette) > 1 else b''
    c7to9 = c7to9 + bytes(3)
    header = b''.join((c4to6[:3], c7to9[:3], attrs[:7]))
    tiledata = []
    for i in range(0, len(tiles01), 4):
        tiledata.extend(tiles01[i:i + 4])
        tiledata.extend(tiles2[i:i + 4])
#    print("tiles01 length is", len(tiles01))
#    print("tiles2 length is", len(tiles2))
    tiledata = b''.join(tiledata)
#    print("header size:", len(header))
#    print("tiledata size:", len(tiledata))
    return header, tiledata

def render_screenshot(tiles01, tiles2, attrs, palette):
    wholepalette = [0x0F, 0x00, 0x10, 0x20, 0x0F]
    if len(palette) > 0: wholepalette.extend(palette[0][:3])
    wholepalette.extend([0] * (9 - len(wholepalette)))
    if len(palette) > 1: wholepalette.extend(palette[1][:3])
    attri = iter(attrs)
    pixels = [bytearray() for i in range(56)]

    for tileno, (tile01, tile2) in enumerate(zip(tiles01, tiles2)):
        xt, yt = tileno % 8, tileno // 8
        y = yt * 8
        if xt == 0:
            attrrow = next(attri)
        attr = 8 if attrrow & (0x80 >> xt) else 4
        for y, p0, p1, p2 in zip(
            range(yt * 8, yt * 8 + 8), tile01[:8], tile01[8:], tile2
        ):
            row = pixels[y]
            for x in range(8):
                mask = 0x80 >> x
                px = 0
                if (p0 & mask):
                    px += 1
                if (p1 & mask):
                    px += 2
                if px and (p2 & mask):
                    px += attr
                row.append(px)

    im = Image.new('P', (64, 56))
    im.putdata(b''.join(pixels))
    im.putpalette(b''.join(bisqpal[i] for i in wholepalette))
    return im

def parse_argv(argv):
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("IMAGE",
        help="path of (preferably indexed) 64x56 pixel screenshot")
    parser.add_argument("-o", "--output",
        help="path of converted output; otherwise, display on screen")
    parser.add_argument("-p", "--palette", metavar="PALETTE",
        help="use a 6-color hex palette (e.g. 16273812262A)")
    parser.add_argument("-v", "--verbose", action="store_true",
        help="show full exception")
    
    return parser.parse_args(argv[1:])

def main(argv=None):
    args = parse_argv(argv or sys.argv)
    infilename = args.IMAGE
    palette = args.palette
    im = Image.open(infilename)
    try:
        if im.size != (64, 56):
            raise ValueError("size must be 64x56, not %dx%d" % im.size)
        if args.palette:
            palette = parse_palette(args.palette)
        else:
            palette = guess_palette(im)
        print("palette:", " ".join(bytes(s).hex() for s in palette))
        tiles01, tiles2, attrs = convert_im(im, palette)
        rendered = render_screenshot(tiles01, tiles2, attrs, palette)
        if args.output:
            rendered.save(args.output)
        else:
            rendered.show()
    except Exception as e:
        if args.verbose:
            from traceback import print_exc
            print_exc()
        print("%s: %s" % (infilename, e), file=sys.stderr)
        return 1

if __name__=='__main__':
##    main(["a53screenshot.py", "../tilesets/screenshots/pently58rehearsal.png"])
##    main(["a53screenshot.py", "../tilesets/screenshots/parallax.png"])
##    main(["a53screenshot.py", "-v", "../tilesets/screenshots/thwaite.png"])
    main()
