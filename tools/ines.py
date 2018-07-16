#!/usr/bin/env python3
"""
iNES executable loader supporting some NES 2.0 features

Copyright 2012 Damian Yerrick

Copying and distribution of this file, with or without modification,
are permitted in any medium without royalty provided the copyright
notice and this notice are preserved.  This file is offered as-is,
without any warranty.
"""

from __future__ import with_statement

def load_ines(filename):
    """Load an NES executable in iNES format.

DiskDude! and other corruptions are automatically recognized and
disregarded.

Return a dictionary with these keys:
'prg': PRG ROM data
'chr' (optional): CHR ROM data
'prgram' (optional): PRG RAM size (not battery backed)
'prgsave' (optional): PRG RAM size (battery backed)
'chrram' (optional): CHR RAM size (not battery backed)
'chrsave' (optional): CHR RAM size (battery backed)
'trainer' (optional): 512 bytes to load into PRG RAM $7000-$71FF
'NES 2.0' (optional): If present, the executable uses Kevin Horton's
format extension. <http://wiki.nesdev.com/w/index.php/NES_2.0>
'mapper': type of board, largely characterized by bank switching
hardware (1=s*rom, 2=u*rom, 3=cnrom, 4=most t*rom, etc.)
'submapper' (optional): NES 2.0 mapper variant
'mirrType': default nametable mirroring (AAAA=1 screen,
AABB=horizontal, ABAB=vertical, ABCD=4 screen)
"""
    out = {}
    with open(filename, 'rb') as infp:
        header = bytearray(infp.read(16))
        if not header.startswith(b"NES\x1a"):
            raise ValueError(filename+" is not an iNES ROM")

        # Trainer: data preloaded into PRG RAM $7000-$71FF
        # Usually only mapper hacks for Front copiers use one.
        trainer = header[6] & 0x04
        if trainer:
            out['trainer'] = infp.read(512)

        nes2 = (header[7] & 0x0C) == 0x08
        if nes2:
            out['NES 2.0'] = True
        elif header[12] or header[13] or header[14] or header[15]:
            # probably a DiskDude! type header
            header[7:] = [0 for i in range(9)]
        prgSize = header[4]
        chrSize = header[5]
        if nes2:
            prgSize |= (header[8] & 0x0F) << 8
            chrSize |= (header[9] & 0xF0) << 4
        if not prgSize:
            raise ValueError("rom has no PRG memory")

        out['prg'] = infp.read(prgSize * 16384)
        if chrSize > 0:
            out['chr'] = infp.read(chrSize * 8192)

    # And at this point we've loaded the entire ROM.  All that's
    # left is to set up the board.
    mapperNumber = ((header[6] & 0xF0) >> 4
                    | (header[7] & 0xF0))
    if nes2:
        mapperNumber |= (header[8] & 0x0F) << 8
        out['submapper'] = (header[8] & 0xF0) >> 4
    out['mapper'] = mapperNumber
            
    # Save most commonly means battery-backed PRG RAM, but it
    # could also be a serial EEPROM.  In a couple cases, it's
    # even battery-backed CHR RAM.
    save = header[6] & 0x04
    if nes2:
        prgramSize = header[10] & 0x0F
        prgramSize = (64 << prgramSize) if prgramSize else 0
        prgsaveSize = (header[10] >> 4) & 0x0F
        prgsaveSize = (64 << prgsaveSize) if prgsaveSize else 0
        chrramSize = header[11] & 0x0F
        chrramSize = (64 << chrramSize) if chrramSize else 0
        chrsaveSize = (header[11] >> 4) & 0x0F
        chrsaveSize = (64 << chrsaveSize) if chrsaveSize else 0
        if save and not (prgsaveSize or chrsaveSize):
            raise ValueError("save present but size not specified")
        if (prgsaveSize or chrsaveSize) and not save:
            raise ValueError("save size specified but not present")
        if not chrramSize and not chrSize:
            raise ValueError("rom has no CHR memory")
    else:
        # Guess the sizes from the mapper
        prgramSize = 8192 if save else 0
        if mapperNumber in (16, 86, 159):
            # 16, 159: Bandai FCG boards with serial EEPROM save
            # 86: Jaleco JF-13, with a sample player in $6000-$7FFF
            prgramSize = 0  # none of these support PRG RAM
        chrramSize = 8192 if chrSize else 0
        if mapperNumber == 13:
            # CPROM, the Videomation board
            chrramSize = 16384
        prgsaveSize = 0 if save else 8192
        chrsaveSize = 0
        if save:
            if mapperNumber == 16:
                prgsaveSize = 256
            elif mapperNumber == 159:
                prgsaveSize = 128
            elif mapperNumber == 186:  # RacerMate Challenge
                prgsaveSize = 0
                chrramSize = 0
                chrsaveSize = 65536
    if ((prgsaveSize or chrsaveSize)
        and mapperNumber in (86,)):
        raise ValueError("mapper %d does not support save" % mapperNumber)
    out['prgram'] = prgramSize
    out['prgsave'] = prgsaveSize
    out['chrram'] = chrramSize
    out['chrsave'] = chrsaveSize

    # Mirroring: mapping between PPU A10-A11 and CIRAM A10
    # Some mappers ignore this
    mirrType = header[6] & 0x09
    if mapperNumber == 7:
        mirrType = 'AAAA'  # 1-screen, always mapper controlled
    elif mirrType == 0:
        mirrType = 'AABB'  # V arrangement == H mirroring
    elif mirrType == 1:
        mirrType = 'ABAB'  # H arrangement == V mirroring
    else:
        mirrType = 'ABCD'  # Four screens using extra VRAM on cart
    out['mirrtype'] = mirrType

    return out
