#!/usr/bin/env python3
"""
Action 53 patcher
Copyright 2017 Damian Yerrick
zlib license

Very early Action 53 compilations used a board similar to BNROM (iNES
mapper 34), which powers on with an unspecified bank loaded into
$8000-$FFFF.  To get into the menu, we have to patch each 32K bank's
reset vector to switch to the last bank.  And because BNROM has bus
conflicts, it must write the number of the last bank ($FF) over a ROM
byte with the same value.

There are two ways to do this.  The 10-byte patch can be placed at
$BFF0 or $FFF0, as by the time the JMP operand is fetched, the mapper
will have finished switching to the bank with the menu.

fff0:
    sei
    ldx #$FF
    nop
    stx fff0+2
    jmp ($FFFC)

The 20-byte patch can be placed anywhere because it copies itself to
RAM before running.

anywhere:
    sei
    ldx #5
@loop:
    lda @cpsrc,x
    sta $F0,x
    dex
    bpl @loop
    ; X = $FF at end
    jmp $00F0
@cpsrc:
    stx @cpsrc+5
    jmp ($FFFC)

In each case, we overwrite the $FF byte in either the immediate load
or the high byte of the indirect jump's operand.  Because of the
6502's lack of addressing modes relative to the program counter, each
such patch has to be relocated.

In 2012, a custom mapper was designed for Action 53 and assigned iNES
mapper 28.  It differs from BNROM in the following relevant ways:

1. A53 powers on with the ROM's last 16K in $C000-$FFFF, and the
   Reset button leaves it unchanged.  Thus only those banks that
   get switched into $C000-$FFFF must be patched.  But because
   screenshots and CHR ROM can be read out of any bank, banks
   containing such data still need to be patched.
2. No bus conflicts, allowing fewer relocations.
3. The current register ($5000) might not be the outer bank ($81).
4. In a game larger than 32K, changing only the outer bank might
   not make the menu bank visible.  But because the game itself
   is expected to switch to the right inner bank, we need to patch
   only the starting bank.

The Action 53 menu launches games with 32K PRG ROM and no more than
one CHR ROM bank with the current register set to outer bank.
Thus we can exit-patch these with fff0 or anywhere.

If the exit code is running in a game's last bank, it can change the
outer bank to the overall last bank and keep going.  This is true of
32K games (CNROM), fixed-$C000 games (UNROM), and those games using
32K bank mode (AOROM/BNROM) whose init code is in the last bank.
This patch at $FFEB does this:

ffeb:
    sei
    ldy #$81
    sty $5000
    ldx #$FF
    nop
    stx ffeb+2
    jmp ($FFFC)

Otherwise, the patch has to set the game size to 32K first so that
the outer bank controls all high address lines.  This patch copies
itself to RAM, changes to 32K mode, and switches to the last bank.

a53anywhere:
    sei
    ldx #11
@loop:
    lda @cpsrc,x
    sta $F0,x
    dex
    bpl @loop
    ; X = $FF at end
    ldy #$80
    sty $5000
    lda #$00
    iny
    jmp $00F0
@cpsrc:
    sta $8000
    sty $5000
    stx $8000
    jmp ($FFFC)

See help(ExitPatcher.find_dest) for when each of these is used.

The functionality of this module is triggered by the following syntax
in an a53build.py configuration file:

prgbank=0
    Sets the activity's entry bank to 0.
prgunused1=F900-FFF9
    Marks this byte range (inclusive) in bank 1 of the current ROM
    as unused.
exitmethod=unrom
    Uses an exit patch suitable for UNROM.
exitpoint=FFC0
    Uses the preexisting exit stub at $FFC0 in this bank.
exitmethod=none
    Marks this bank as already having been patched while making no
    changes.  For games in A53-mapper compilations with exit in menu.

"""
from firstfit import slices_union, slices_find, slices_remove

fff0_patch = bytes.fromhex("78A2FFEA8E02006CFCFF"), [5]
anywhere_patch = bytes.fromhex("78A205BD0E0095F0CA10F84CF0008E13006CFCFF"), [4, 15]
ffeb_patch = bytes.fromhex("78A0818C0050A2FFEA8E00806CFCFF"), []
a53_anywhere_patch = bytes.fromhex(
    "78A20BBD160095F0CA10F8"    # copying to RAM
    "A0808C0050A900C84CF000"    # setting up register values
    "8D00808C00508E00806CFCFF"  # RAM code
), [4]

def reloc_exit_patch(patch_data, relocs, start_address):
    """Relocate a piece of 6502 code to a given starting address."""
    patch_data = bytearray(patch_data)
    for i in relocs:
        address = patch_data[i] + (patch_data[i + 1] << 8) + start_address
        patch_data[i] = address & 0xFF
        patch_data[i + 1] = address >> 8
    return patch_data

class UnpatchableError(Exception):
    pass

class ExitPatcher(object):
    """Make exit patches for a ROM to be included in an Action 53 compilation.

Action 53 divides the ROM into 32768-byte banks, each of which needs
to be patched so that the Reset button can return to the menu.

Fields:

prgunused -- list of slice lists, one for each bank.  A slice list is
    a list of 2-tuples of what address space is free for this bank.
    The first byte in the bank is 0x8000; one past the end is 0x10000.
    See firstfit.py for details.
patched -- list of bools telling whether each bank has been patched
patches -- list of tuples of the form
    (bank number, start address, bytes-like data)
"""

    mapper_patchtypes = {
        0: 'nrom',
        2: 'unrom',
        3: 'cnrom',
        7: 'aorom',
        28: 'unrom',
        34: 'aorom',
        180: 'unrom180',
    }
        
    def __init__(self, prgsize, mapper, prgunused):
        """prgsize: len(prg); mapper sets default patch type; prgunused: slice lists"""
        if prgsize not in (0x8000, 0x10000, 0x20000, 0x40000):
            raise ValueError("prg size is %d bytes, not 32, 64, 128, or 256 KiB"
                             % prgsize)
        self.prgsize = prgsize
        try:
            self.default_method = self.mapper_patchtypes[mapper]
        except KeyError:
            raise ValueError("no patch method for mapper %s" % (mapper,))
        self.prgunused = prgunused
        self.patched = [False for i in range(0, self.prgsize, 0x8000)]
        self.patches = []

    def num_banks(self):
        """Count 32K banks in prg."""
        return self.prgsize // 0x8000

    def assert_bank_in_range(self, bank):
        """Raise IndexError for out-of-range bank index for prg."""
        last = self.num_banks() - 1
        if not 0 <= bank <= last:
            raise IndexError("bank number %d not in 0 to %d" % (bank, last))

    def assert_bank_not_patched(self, bank):
        """Raise an exception if this bank has been patched."""
        self.assert_bank_in_range(bank)
        if self.patched[bank]:
            raise ValueError("bank number %d was already patched" % (bank,))

    def assert_jmp_in_rom(self, exitpoint):
        """Raise an exception if a JMP target is outside ROM."""
        if not 0x8000 <= exitpoint <= 0xFFF7:
            raise ValueError("jump target $%04x not in $8000-$FFFF"
                             % (exitpoint,))

    def add_exitpoint(self, exitpoint, entrybank=None, unrom180=False):
        """Set a bank's reset vector to existing exit code.

entrybank -- the bank in the ROM, defaulting to the last bank
exitpoint -- the reset vector to add
unrom180 -- if True, patch $BFFC and $FFFC of all banks 0 through
    exitpoint; otherwise, patch only $FFFC of exitpoint
"""
        self.assert_jmp_in_rom(exitpoint)
        reset_vector_data = bytes([exitpoint & 0xFF, exitpoint >> 8])

        if entrybank is None:
            entrybank = self.num_banks() - 1
        banks = list(range(entrybank + 1)) if unrom180 else [entrybank]
        for bank in banks:
            self.assert_bank_not_patched(entrybank)

        patchbases = [0xBFFC, 0xFFFC] if unrom180 else [0xFFFC]
        for bank in banks:
            for base in patchbases:
                self.patches.append((bank, base, reset_vector_data))
            self.patched[bank] = True

    patchmethods = {
        'nrom': [
            (0xFFF0, fff0_patch),
            (0xBFF0, fff0_patch),
            ((0x8000, 0xFFFA), anywhere_patch),
        ],
        'autosubmulti': [
            (0xFFF0, fff0_patch),
            ((0xC000, 0xFFFA), anywhere_patch),
        ],
        'cnrom': [
            (0xFFEB, ffeb_patch),
            (0xBFEB, ffeb_patch),
            ((0x8000, 0xFFFA), a53_anywhere_patch),
        ],
        'unrom': [
            (0xFFEB, ffeb_patch),
            ((0xC000, 0xFFFA), a53_anywhere_patch),
        ],
        'aorom': [
            ((0x8000, 0xFFFA), a53_anywhere_patch),
        ],
        'unrom180': [
            ((0x8000, 0xBFFA), a53_anywhere_patch),
        ],
    }

    def find_dest(self, method=None, entrybank=None):
        """Find a place for an exit patch.

entrybank -- the index of the 32K bank to patch, from 0 to the last
    bank, defaulting to the last bank
method -- the patch method, defaulting to the most common one for the
    mapper

Method can be any of the following strings:

'nrom' -- fff0 or anywhere in entrybank
'autosubmulti' - fff0 or anywhere in the second half of entrybank
'cnrom' -- ffeb or a53_anywhere in entrybank
'unrom' -- ffeb or a53_anywhere in the second half of entrybank
'aorom' -- a53_anywhere in entrybank
'unrom180' -- Put a53_anywhere in the bottom half of the first bank,
    and point the reset vectors in both halves of banks 0 through
    entrybank there

Return
"""
        method = method or self.default_method
##        print("romsize %d find_dest method %s entrybank %s"
##              % (self.prgsize, method, entrybank))
        locs = self.patchmethods[method]
        if entrybank is None:
            entrybank = self.num_banks() - 1
        else:
            self.assert_bank_in_range(entrybank)
        prgunused = self.prgunused[entrybank]

        for loc, (patch_data, relocs) in locs:
            if isinstance(loc, tuple):
                astart, aend = loc
                for ustart, uend in prgunused:
                    # Narrow the unused area to the eligible half of the bank
                    loc, auend = max(astart, ustart), min(aend, uend)
                    # If it fits, use it
                    if auend >= loc + len(patch_data):
                        return loc, reloc_exit_patch(patch_data, relocs, loc)

            else:
                # The patch specifies a specific starting point.
                # If the area that the patch would occupy is contained
                # in the unused slice set, use it
                index = slices_find(prgunused, (loc, loc + len(patch_data)))
                if index >= 0:
                    return loc, reloc_exit_patch(patch_data, relocs, loc)

        raise UnpatchableError("no room in bank %d for an exit patch"
                               % entrybank)

    def add_patch(self, method=None, entrybank=None):
        """Find a patch destination and add it.

In addition to methods accepted by find_dest, this accepts
method="none" (distinct from None in Python itself), which marks a
bank as patched without actually patching anything.  This is useful
in compilations using Action 53 mapper when a game has "Exit" as a
menu item that launches an appropriate exit stub.  Using prgunused
in such a bank is discouraged because pressing Reset while the menu
is loading screenshot, description, or CHR data from this bank may
drop the needle into this game.

"""
        if entrybank is None:
            entrybank = self.num_banks() - 1
        if method == 'none':
            print("ROM already patched")
            self.patched[entrybank] = True
            return
        loc, data = self.find_dest(method, entrybank)
        self.patches.append((entrybank, loc, data))
        slices_remove(self.prgunused[entrybank], (loc, loc + len(data)))
        self.add_exitpoint(loc, entrybank, method == 'unrom180')

    def finish(self, skip_full=False):
        """Add NROM exit patches for all banks not yet patched.

skip_full -- Instead of failing, set prgunused to the empty list.
    Use this for Action 53 mapper, where an unpatched bank can just
    not include any compressed CHR ROM data and screenshots.

"""
        for i, already_patched in enumerate(self.patched):
            if already_patched:
                continue
            try:
                self.add_patch("nrom", i)
            except UnpatchableError:
                if not skip_full:
                    raise
                self.prgunused[i] = []

unromtest = (
    "../revised/mojon-twins--cheril-the-goddess--v1.2.nes",
    [{(49120, 49152)}, {(47360, 49152), (61952, 65530)}],
    {None},
    "default",
    None,
)

def test():
    import ines
    filename, prgunused, entrybanks, exitmethod, exitpoint = unromtest
    rom = ines.load_ines(filename)
    prgunused = [slices_union(p) for p in prgunused]
    patcher = ExitPatcher(len(rom['prg']), rom['mapper'], prgunused)
    rom = None
    print("Prgunused before:")
    print(prgunused)
    patcher.add_patch()
    patcher.finish()
    print("Prgunused after:")
    print(prgunused)
    print("Patches:")
    print("\n".join(
        "%d:%04x = %s" % (b, a, d.hex()) for b, a, d in patcher.patches)
    )

if __name__=='__main__':
    test()
