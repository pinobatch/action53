#!/usr/bin/env python3
import ines, os, sys
from binascii import a2b_hex


# [0]: Output file
# [1]: ROM file for first half of bank
# [2]: Address of 16-byte reset patch in first half (in $8000-$BFE0)
# [3]: ROM file for second half of bank
submultis = [
    (
        '../submulti/SM_JupiterScope2_SuperTiltBro.nes',
        '../revised3/jupiter2.nes',
        0xBFE0,
        '../revised3/Super_Tilt_Bro_v4_(E).nes'
    ),
    (
        '../submulti/SM_BrickBreaker_RPSLS.nes',
        '../revised3/brix_2018-02-28.nes',
        0xBFB8,
        '../revised3/Rock9b.nes'
    ),
]

def get_vectors(prg):
    prg = prg[-6:]
    return [prg[i + 1] * 256 + prg[i] for i in (0, 2, 4)]

def ls_roms(folder='.'):
    for filename in sorted(os.listdir(folder), key=str.lower):
        try:
            rom = ines.load_ines(os.path.join(folder, filename))
        except Exception as e:
            continue
        if len(rom['prg']) != 16384:
            continue
        nmi, reset, irq = get_vectors(rom['prg'])
        trominfo = ("%s:\n  %d kbit PRG, %d kbit CHR, %s mirroring,\n"
                    "  nmi:$%04x reset:$%04x irq:$%04x"
                    % (filename,
                       len(rom['prg']) // 128, len(rom.get('chr', '')) // 128,
                       rom['mirrtype'],
                       nmi, reset, irq))
        print(trominfo)


# This adds a patch to $8000-$BFFF:
# LDA #$01 STA $2000         ; kill NMI
# STA $5000 STA $8000        ; put second 16K bank in $C000-$FFFF
# LDA #$81 STA $5000         ; next $8000 write controls outer bank
# JMP ($FFFC)
# 
# After this, the standard reset patch in $C000-$FFFF takes over:
# LDX #$FF STX $8000  ; set outer bank to last
# JMP ($FFFC)  ; jump to start of menu
resetpatchmaster = a2b_hex("A9018D00208D00508D0080A9818D00506CFCFF")

def make_submulti(outfilename, rom80_filename, resetpatchaddr, romC0_filename):

    rom80 = ines.load_ines(rom80_filename)
    rom80_reset = get_vectors(rom80['prg'])[1]
    rom80_mirrtype = rom80['mirrtype']
    prgrom = bytearray(rom80['prg'])
    chrrom = [rom80.get('chr', '')]
    del rom80

    romC0 = ines.load_ines(romC0_filename)
    romC0_mirrtype = romC0['mirrtype']
    prgrom.extend(romC0['prg'])
    chrrom.append(romC0.get('chr', ''))
    del romC0

    rom80_mapmode = 0x8A if rom80_mirrtype == 'ABAB' else 0x8B
    romC0_mapmode = 0x8E if romC0_mirrtype == 'ABAB' else 0x8F
    print("[%s]\n"
          "rom80 (%s):\n  entrypoint=%04X\n  mapmode=%02X\n"
          "romC0 (%s):\n  mapmode=%02X\n"
          % (outfilename,
             rom80_filename, rom80_reset, rom80_mapmode,
             romC0_filename, romC0_mapmode))
    
    # In order to reset correctly, the game in the lower bank needs
    # to switch in the upper bank to run its reset code.
    # Print the lower bank's old reset vector (formerly in $BFFC-$BFFD)
    # The following code brings the reset vector into the upper 16K,
    # prepares to set the outer bank, and jumps to the submulti's
    # master reset vector.
    # lda #$01 sta $2000 sta $5000 sta $8000 lda #$81 sta $5000 jmp ($FFFC)
    assert 0x8000 <= resetpatchaddr <= 0xBFFA - len(resetpatchmaster)
    resetpatchdata = bytearray(resetpatchmaster)
    resetpatchoffset = resetpatchaddr - 0x8000
    prgrom[0x3FFC] = resetpatchaddr & 0xFF
    prgrom[0x3FFD] = (resetpatchaddr >> 8) & 0xFF
    prgrom[resetpatchoffset:resetpatchoffset + len(resetpatchmaster)] = resetpatchdata

    inesheader = bytearray(b"NES\x1A")
    inesheader.extend([(len(prgrom) // 16384),
                       (sum(len(x) for x in chrrom) // 8192),
                       0xC0, 0x10])
    inesheader.extend([0] * (16 - len(inesheader)))
    with open(outfilename, 'wb') as outfp:
        outfp.write(inesheader)
        outfp.write(prgrom)
        outfp.writelines(chrrom)

def main(argv=None):
    argv = argv or sys.argv

##    ls_roms("../revised3")
##    ls_roms("../roms4")
##    ls_roms("../revised4")
    for outfilename, rom80name, rom80patch, romC0name in submultis:
        make_submulti(outfilename, rom80name, rom80patch, romC0name)

if __name__=='__main__':
    main()
