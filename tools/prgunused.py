#!/usr/bin/env python3
"""
Tool to find unused space in PRG ROM

Copyright 2017 Damian Yerrick

Copying and distribution of this file, with or without modification,
are permitted in any medium without royalty provided the copyright
notice and this notice are preserved.  This file is offered as-is,
without any warranty.
"""
assert str is not bytes
import sys
import argparse
import ines

# Partial list of mappers, including all licensed US releases
NROM = 0
MMC1 = 1
UNROM = 2
CNROM = 3
MMC3 = 4
AOROM = 7
MMC2 = 9
MMC4 = 10
COLORDREAMS = 11
NAMCO163 = 19
VRC4AC = 21
VRC2A = 22
VRC4BD = 23
VRC4E = 25
VRC4WORLDHERO = 27
UNROM512 = 30
BNROM = 34
GNROM = 66
RAMBO1 = 64
SUNSOFT3 = 67
SUNSOFT4 = 68
FME7 = 69          # Gimmick, Batman: ROTJ
CAMERICA = 71
VRC3 = 73
VRC1 = 75
NAMCOT3446 = 76    # Megami Tensei: Digital Devil Story
HOLYDIVER = 78
VRC7 = 85
NAMCOTQUINTY = 88  # Quinty and 2 others
NAMCOT3425 = 95    # Dragon Buster, MIMIC counterpart to TLSROM
TLSROM = 118
TQROM = 119
NAMCOT3453 = 154   # Devil Man
UNROM180 = 180
CNROM185 = 185     # CNROM with only one valid CHR bank
MIMIC1 = 206       # MMC3 subset (Namco 108/109/118/119)
NAMCO340 = 210

# Some mappers are intentionally omitted from bank size guessing
# because of their variable PRG bank size.  These include MMC5,
# VRC6, and most multicarts.  But apart from those, these should
# cover all licensed North American releases.

mappertoprgbanksize = {
    MMC1: 16,
    NROM: 32, CNROM: 32, CNROM185: 32,
    UNROM: 16, UNROM180: 16, UNROM512: 16,
    AOROM: 32,
    GNROM: 32,
    MMC2: 8,
    MMC3: 8, TQROM: 8, TLSROM: 8,
    MMC4: 16,
    SUNSOFT3: 16,
    SUNSOFT4: 16,
    FME7: 8,
    VRC1: 8,
    VRC2A: 8, VRC4AC: 8, VRC4BD: 8, VRC4E: 8, VRC4WORLDHERO: 8,
    VRC3: 16,
    VRC7: 8,
    HOLYDIVER: 16,
    MIMIC1: 8, NAMCOT3446: 8, NAMCOTQUINTY: 8, NAMCOT3453: 8,
    NAMCOT3425: 8,
    NAMCO163: 8, NAMCO340: 8,
    RAMBO1: 8,
    COLORDREAMS: 32,
    CAMERICA: 16,
}

fix8000_mappers = {UNROM180}

def bankbase(bankindex, numbanks, prgbanksize, fix8000):
    """Calculate the base address of a PRG bank.

bankindex -- the index of a bank (0=first)
numbanks -- the total number of banks in the ROM
prgbanksize -- the size in 1024 byte units of a bank,
    usually 8, 16, or 32
fix8000 -- if false, treat the first window ($8000) as
    switchable; if true, treat the last window as switchable
"""
    if prgbanksize > 32:
        return 0  # for future use with Super NES HiROM
    numwindows = 32 // prgbanksize
    if fix8000:
        wndindex = min(bankindex, numwindows - 1)
    else:
        wndindex = max(0, bankindex + numwindows - numbanks)
    return 0x8000 + 0x400 * prgbanksize * wndindex

def find_runs(it):
    rstart, i, rval = 0, 0, 0
    for el in it:
        if rval != el:
            if i > rstart: yield rstart, i, rval
            rstart, rval = i, el
        i += 1
    if i > rstart: yield rstart, i, rval

def run_is_big_enough(s, e, bankend):
    """Check whether a run is big enough to consider.

A run of $FF or $00 is OK if it's 32 bytes or longer, or if it's
10 bytes or longer and touches the reset vectors.
"""
    if e - s >= 32:
        return True
    if s <= bankend - 15 and e >= bankend - 6:
        return True
    return False

def get_unused(prg, mapper=None, prgbanksize=None, fix8000=None):

    # Guess missing PRG bank size based on mapper
    if prgbanksize is None:
        try:
            prgbanksize = mappertoprgbanksize[mapper]
        except KeyError:
            raise ValueError("could not guess PRG bank size for mapper %d"
                             % mapper)
    prgbanksize = min(prgbanksize, len(prg) // 1024)
    if fix8000 is None:
        fix8000 = mapper in fix8000_mappers

    # Find long enough runs of $00 and $FF in each bank
    prgbanksize_bytes = 1024 * prgbanksize
    runlists = [
        [(s, e)
         for s, e, v in find_runs(prg[i:i + prgbanksize_bytes])
         if (v in (0x00, 0xFF)
             and run_is_big_enough(s, e, prgbanksize_bytes - 6))]
        for i in range(0, len(prg), prgbanksize_bytes)
    ]
    return [
        (i, bankbase(i, len(runlists), prgbanksize, fix8000), runlist)
        for i, runlist in enumerate(runlists)
        if runlist
    ]

def parse_argv(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("romfile", nargs='+',
                        help="path to .nes ROM image")
    parser.add_argument("--prg-bank-size", "--pbs",
                        type=int, choices=[4, 8, 16, 32],
                        help="size in KiB of each PRG bank, overriding mapper autodetection")
    parser.add_argument("--fix-8000", "--crazy",
                        action="store_true",
                        help="treat last window as switchable instead of first")
    parser.add_argument("--a53",
                        action="store_true",
                        help="output for Action 53 config file")
    return parser.parse_args(argv[1:])

def main(argv=None):
    args = parse_argv(argv or sys.argv)
    runformat = "prgunused%d=%s" if args.a53 else "%d: %s"
    banksize = 32 if args.a53 else args.prg_bank_size
    for filename in args.romfile:
        rom = ines.load_ines(filename)
        prg = rom['prg']
        mapper = rom['mapper']

        runlists = get_unused(prg, mapper, banksize, args.fix_8000)
        tunused = [
            runformat
            % (i, ",".join(
                "%04x-%04x" % (base + start, base + end - 1)
                for start, end in runs
            ))
            for i, base, runs in runlists
        ]
        if len(args.romfile) > 1:
            print(filename)
        print("\n".join(tunused))

if __name__=='__main__':
##    main("prgunused.py --a53 /home/pino/develop/240pee/240pee.nes".split())
    main()
