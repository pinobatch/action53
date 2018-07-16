#!/usr/bin/env python3
"""

Program to insert or extract CHR data in an iNES ROM as PNG

See versionText below for copyright notice.

Delayed by one day due to the blackout of GNU.org with no
clickthrough during the SOPA strike of January 18, 2012.

"""
from __future__ import division, with_statement, print_function
from PIL import Image
from itertools import chain
import ines

descriptionText = """Lists, extracts, or inserts 8192-byte CHR ROM banks in an iNES executable."""
versionText = """%prog 0.02

Copyright 2012 Damian Yerrick

Copying and distribution of this file, with or without modification,
are permitted in any medium without royalty provided the copyright
notice and this notice are preserved.  This file is offered as-is,
without any warranty.
"""

def sliver_to_texels(lo, hi):
    return bytearray(((lo >> i) & 1) | (((hi >> i) & 1) << 1)
                     for i in range(7, -1, -1))

def chrrow_to_texels(chrdata):
    from itertools import chain

    _z = zip
    _slv = sliver_to_texels
    _r8 = bytes(range(8))
    scanlines = ((_slv(bp0, bp1)
                  for (bp0, bp1)
                  in _z(chrdata[scanline::16],
                        chrdata[scanline + 8::16]))
                 for scanline in _r8)
    scanlines = [bytearray(chain(*scanline))
                 for scanline in scanlines]
    return scanlines

def chrbank_to_texels(chrdata, tile_width=16):
    """Convert an 8-bit string containing chrdata to a list of pixel arrays."""
    from itertools import chain

    # Break CHR data into rows of tiles
    tile_row_bytes = 16 * tile_width
    chrrows = [chrdata[i:i + tile_row_bytes]
               for i in range(0, len(chrdata), tile_row_bytes)]
    if len(chrrows[-1]) < tile_row_bytes:
        chrrows[-1] = chrrows[-1] + '\0'*(tile_row_bytes - len(chrrows[-1]))

    # Convert each row to CHR
    return list(chain(*(chrrow_to_texels(row) for row in chrrows)))

def chrbank_to_pil(chrdata, tile_width=16):
    txls = chrbank_to_texels(chrdata, tile_width)
    ht = len(txls)
    im = Image.frombytes('P', (8 * tile_width, ht), b''.join(txls))
    im.putpalette(b'\x00\x00\x00\x66\x66\x66\xb2\xb2\xb2\xff\xff\xff'*64)
    return im

def texels_to_sliver(seq):
    from operator import or_
    seq = map(None, *((s & 1, s & 2) for s in seq))
    seq = tuple(reduce(or_,
                       (1 << pv
                        for (s, pv) in zip(s, range(len(s) - 1, -1, -1))
                        if s),
                       0)
           for s in seq)
    return seq

def texels_to_chrrow(texels):
    from itertools import chain

    # Convert each sliver to a pair of bytes, then collect each plane
    # of each tile
    tiles = (map(None, *(texels_to_sliver(row[x:x + 8]) for row in texels))
             for x in range(0, len(texels[0]), 8))

    # Convert a list of lists of planes in tiles to a byte string
    return ''.join(chr(x) for x in chain(*chain(*tiles)))

def test_chrrow():
    a_half = [
        [0, 0, 1, 1, 1, 1, 0, 0,  0, 1, 0, 0, 0, 0, 0, 3],
        [0, 1, 1, 0, 0, 1, 1, 0,  1, 1, 0, 0, 0, 0, 3, 0],
        [0, 2, 2, 0, 0, 2, 2, 0,  0, 1, 0, 0, 0, 3, 0, 0],
        [0, 2, 2, 2, 2, 2, 2, 0,  0, 1, 0, 0, 3, 0, 0, 0],
        [0, 3, 3, 0, 0, 3, 3, 0,  0, 0, 0, 3, 0, 2, 2, 0],
        [0, 3, 3, 0, 0, 3, 3, 0,  0, 0, 3, 0, 0, 0, 0, 2],
        [0, 3, 3, 0, 0, 3, 3, 0,  0, 3, 0, 0, 0, 0, 2, 0],
        [0, 0, 0, 0, 0, 0, 0, 0,  3, 0, 0, 0, 0, 2, 2, 2]
    ]
    from binascii import b2a_hex
    print(b2a_hex(texels_to_chrrow(a_half)))

def texels_to_chrbank(texels):
    """Convert a sequence of sequences of texel values to a CHR bank."""

    if len(texels) % 8 != 0:
        raise ValueError("image height should be a multiple of 8, not %d"
                         % len(texels))
    if len(texels[0]) % 8 != 0:
        raise ValueError("image width should be a multiple of 8, not %d"
                         % len(texels))
    texrows = (texels_to_chrrow(texels[i:i + 8])
               for i in range(0, len(texels), 8))
    return ''.join(texrows)

def pil_to_chrbank(im):
    if im.mode != 'P':
        raise TypeError("image mode should be 'P' (palette), not %s" % im.mode)
    (w, h) = im.size

    # Get texels from tilesheet
    im = im.tostring()
    assert w * h == len(im)

    # Get rows of texels
    im = [bytearray(im[i:i + w]) for i in xrange(0, len(im), w)]
    return texels_to_chrbank(im)

def test_roundtrip():
    filename = "../../my_games/lj65 0.41.nes"
    chrdata = ines.load_ines(filename)['chr'][:8192]
    im = chrbank_to_pil(chrdata)
    otherdata = pil_to_chrbank(im)
    assert otherdata == chrdata
    del chrdata, otherdata
    assert parse_bank_list('0-3,c,e,d-f') == [0,1,2,3,12,13,14,15]
    return im

def parse_bank_list(bank_str):
    from itertools import chain

    ranges = ([int(bn.strip(), 16) for bn in br.split('-',1)]
               for br in bank_str.split(','))
    ranges = (range(br[0], br[1] + 1) if len(br) > 1 else br
              for br in ranges)
    ranges = sorted(set(chain(*ranges)))
    return ranges

def command_list(filename, chrrom, banks):
    from hashlib import sha1

    for bank in banks:
        m = sha1()
        m.update(chrrom[bank * 8192:bank * 8192 + 8192])
        print("%s *%s-%02x" % (m.hexdigest(), filename, bank))

def command_extract(dstprefix, chrrom, banks):
    from hashlib import sha1

    for bank in banks:
        im = chrbank_to_pil(chrrom[bank * 8192:bank * 8192 + 8192])
        imgname = "%s-%02x.png" % (dstprefix, bank)
        im.save(imgname)

def command_insert(filename, chrbase, banks, srcprefix):
    from hashlib import sha1

    with open(filename, 'rb+') as outfp:
        for bank in banks:
            imgname = "%s-%02x.png" % (srcprefix, bank)
            chrbank = pil_to_chrbank(Image.open(imgname))
            seekpos = chrbase + 8192 * bank
            outfp.seek(seekpos)
            outfp.write(chrbank)

def main(argv=None):
    from optparse import OptionParser
    import sys

    if argv is None:
        argv = sys.argv
    parser = OptionParser(usage="usage: %prog [options] NESFILE",
                          description=descriptionText,
                          version=versionText)
    parser.add_option('-l', '--list', dest="cmd",
                      action="store_const", const="l", default="l",
                      help="list SHA-1 sums of all 8 KiB CHR ROM banks")
    parser.add_option('-x', '--extract', dest="cmd",
                      action="store_const", const="x",
                      help="extract CHR banks to e.g. something.nes-00.png")
    parser.add_option('-i', '--insert', dest="cmd",
                      action="store_const", const="i",
                      help="reinsert 128x256 pixel indexed images to CHR ROM banks")
    parser.add_option('-o', '--output-prefix', dest="prefix",
                      help="name of images (followed by -00.png, -01.png, etc.)")
    parser.add_option('-b', '--banks', dest="banks", default="",
                      help="specify banks or ranges of banks by hexadecimal numbers, e.g. 00,01,1c-1f")
    parser.add_option('--prg-rom', dest="prgrom",
                      action="store_true", default=False,
                      help="use PRG ROM instead of CHR ROM")
    (options, filenames) = parser.parse_args(argv[1:])

    if len(filenames) > 1:
        parser.error("too many filenames")
    if len(filenames) < 1:
        import os
        parser.error("no executable given; try %s --help"
                     % os.path.basename(argv[0]))
    try:
        banks = parse_bank_list(options.banks) if options.banks else None
    except ValueError as e:
        parser.error("invalid bank list: "+options.banks)
    try:
        rom = ines.load_ines(filenames[0])
    except ValueError as e:
        parser.error(str(e))

    chrdata = rom['prg'] if options.prgrom else rom.get('chr', b'')
    
    if len(chrdata) < 8192:
        parser.error("%s has no CHR ROM; try --prg-rom" % filenames[0])
    if banks is None:
        banks = range(len(chrdata) // 8192)

    filenameprefix = (options.prefix
                      if options.prefix is not None
                      else filenames[0])

    if options.cmd == 'l':
        command_list(filenames[0], chrdata, banks)
    elif options.cmd == 'x':
        command_extract(filenameprefix, chrdata, banks)
    elif options.cmd == 'i':
        chrbase = 16 + len(rom.get('trainer', ''))
        if not options.prgrom:
            chrbase += len(rom['prg'])
        print("chrbase is", chrbase)
        command_insert(filenames[0], chrbase, banks, filenameprefix)
    else:
        parser.error("unknown command -%s" % options.cmd)

if __name__=='__main__':
    main()
##    main(['ineschr.py',  '-x',
##          '../../thwaite/thwaite.nes'])
