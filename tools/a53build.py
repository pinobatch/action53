#!/usr/bin/env python3
import re
import sys
import os
from firstfit import ffd_add, slices_union, slices_find, slices_remove
from innie import InnieParser
from pb53 import pb53
import a53charset

trace = True
trace_parser = False
default_screenshot_filename = '../tilesets/screenshots/default.png'
default_title_screen = '../tilesets/title_screen.png'
default_title_palette = bytes.fromhex('0f0010200f1626200f1A2A200f122220')
default_menu_prg = '../a53menu.prg'

# Parsing the config file ###########################################

def oxford_join(seq, glue="and"):
    l = len(seq)
    if l <= 0: return ''
    if l <= 1: return seq[0]
    if l <= 2: return ' '.join((seq[0], glue, seq[1]))
    allbutlast = ', '.join(seq[:-1])
    return ''.join([allbutlast, ', ', glue, ' ', seq[-1]])

def relpathjoin(basepath, filename):
    if os.path.isabs(filename) or not basepath:
        return filename
    return os.path.join(os.path.dirname(basepath), filename)

class RomsetParser(InnieParser):
    """

.pages is a list whose elements are (name, list of title entries)
.pages_by_name is a dict from a page name to an index in .pages

"""

    def __init__(self, data=None, filenames=None):
        InnieParser.__init__(self)
        self.pages = []
        self.pages_by_name = {}
        self.cur_page = None
        self.title_lines = []
        self.addfilter(self.handle_pair)
        self.start_bank = 0
        self.menu_prg = default_menu_prg
        self.title_screen = default_title_screen
        self.title_palette = default_title_palette
        self.cur_section = ''
        if data:
            self.readstring(data)
        if filenames:
            filenames = iter(filenames)
            try:
                firstfilename = next(filenames)
            except StopIteration:
                filenames = []
            else:
                self.menu_prg = relpathjoin(firstfilename, self.menu_prg)
                self.title_screen = relpathjoin(firstfilename, self.title_screen)
                ok = self.read([firstfilename])
            ok = self.read(filenames)
        
    def set_menu_page(self, name):
        if name not in self.pages_by_name:
            self.pages.append((name, []))
            self.pages_by_name[name] = len(self.pages) - 1
        self.cur_page = self.pages_by_name[name]
    
    def assert_relpathjoin(self, filename):
        filename = relpathjoin(self.cur_path, filename)
        with open(filename, 'rb') as infp:
            pass
        return filename

    textcolorcombos = {
        (1, 0): 0x00,
        (3, 2): 0x20,
        (0, 1): 0x40,
        (2, 3): 0x60,
        (2, 0): 0x80,
        (3, 1): 0xA0,
        (0, 2): 0xC0,
        (1, 3): 0xE0,
    }

    def add_title_line(self, v):
        lines = [line.rstrip() for line in v.split("\n")]
        while lines and not lines[-1]:
            del lines[-1]
        self.title_lines.append([lines, 64, 24, 0x80])

    def do_title_pair(self, k, v):

        if k == 'titlescreen':
            self.title_screen = self.assert_relpathjoin(v)
            return
        if k == 'titlepalette':
            self.title_palette = bytes.fromhex(v)
            if len(self.title_palette) != 16:
                raise ValueError("invalid palette '%s': should be 32 hex digits"
                                 % (v,))
            if max(self.title_palette) >= 0x40:
                raise ValueError("invalid palette '%s': color %02X exceeds 3F"
                                 % (v, max(self.title_palette)))
            return

        if k == 'text':
            self.add_title_line(v)
            return 
        if len(self.title_lines) == 0:
            raise ValueError("%s valid only in a text line" % k)
        if k == 'at':
            xy = [x.strip() for x in v.split(",")]
            if len(xy) != 2:
                raise ValueError("%s is not an x,y coordinate" % v)
            if not all(x.isdigit() for x in xy):
                raise ValueError("%s is not numeric" % v)
            x, y = (int(x) for x in xy)
            if not 0 <= x <= 248:
                raise ValueError("%s: x must be 0-248" % v)
            if not 0 <= x <= 232:
                raise ValueError("%s: y must be 0-232" % v)
            self.title_lines[-1][1] = x
            self.title_lines[-1][2] = y // 8
            return
        if k in ('color', 'colour'):
            fb = [x.strip() for x in v.split(",")]
            if len(fb) != 2:
                raise ValueError("%s is not a fgcolor,bgcolor pair" % v)
            if not all(x.isdigit() for x in fb):
                raise ValueError("%s is not numeric" % v)
            fb = tuple(int(x) for x in fb)
            if not 0 <= fb[0] < 4:
                raise ValueError("%s: fgcolor must be 0-3" % v)
            if not 0 <= fb[1] < 4:
                raise ValueError("%s: bgcolor must be 0-3" % v)
            try:
                fbcode = self.textcolorcombos[fb]
            except KeyError:
                tcombos = ("%d,%d" % x for x in sorted(self.textcolorcombos))
                tcombos = " or ".join(tcombos)
                raise ValueError("cannot use colors %d and %d together; try %s"
                                 % (fb[0], fb[1], tcombos))
            self.title_lines[-1][3] = fbcode
            return
        raise ValueError("%s unrecognized in title" % k)

    def do_games_pair(self, k, v):
        if k == 'page':
            self.set_menu_page(v)
            return
        if self.cur_page is None:
            raise ValueError("%s valid only in a page" % k)
        if k == 'title':
            if len(self.pages[self.cur_page][1]) >= 20:
                self.set_menu_page('More')
            if len(self.pages[self.cur_page][1]) >= 20:
                raise IndexError('each page can have only 20 titles')
            self.pages[self.cur_page][1].append({})
        this_page_titles = self.pages[self.cur_page][1]
        if not this_page_titles:
            raise ValueError("%s valid only in a title" % k)
        this_page_titles[-1][k] = v

    sectionhandlers = {
        'title': do_title_pair,
        'games': do_games_pair,
    }

    def handle_pair(self, k, v):
        if k in ('#', ';'):
            return
        if k == 'startbank':
            self.start_bank = int(v)
            return
        if k == 'menuprg':
            self.menu_prg = self.assert_relpathjoin(v)
            return
        if k == '[':
            v = v.lower()
            if v not in self.sectionhandlers:
                thandlers = oxford_join(sorted(self.sectionhandlers, "or"))
                raise ValueError("no such section %s; try %s" % thandlers)
            self.cur_section = v
            return
        if self.cur_section:
            handler = self.sectionhandlers[self.cur_section]
            return handler(self, k, v)
        raise ValueError("%s unrecognized outside section" % k)

hexrangeRE = re.compile(r'([0-9a-fA-F]+)-([0-9a-fA-F]+)')
def parse_prgunused(s):
    if not s:
        return None
    s = str(s).strip()
    m = hexrangeRE.match(s)
    if not m:
        raise ValueError("range '%s' must be two 4-digit base 16 ints separated by a hyphen"
                         % s)

    unusedStart = int(m.group(1), 16)
    unusedEnd = int(m.group(2), 16)
    if (unusedStart < 0x8000
        or unusedEnd < unusedStart
        or 0xFFFF < unusedEnd):
        raise ValueError("range %4x-%4x must be increasing and in 8000-FFFF"
                         % (t['title'], t['prgbank']))
        return None

    # Second number of a Python slice refers to first USED byte after
    # the unused range
    return (unusedStart, unusedEnd + 1)

patchRE = re.compile(r'\s*([89A-Fa-f][0-9A-Fa-f]{3})\s*[=:]\s*((?:[0-9A-Fa-f]{2})+)\s*')
def parse_patch(s):
    """Parse a binary patch.

A few of Shiru's games start by clearing all nametables, but due to a
mistake in programming, they end up clearing too much and scribbling
over the pattern tables as well.  This has no effect on a CHR ROM
mapper, but it becomes apparent when the game is inserted into a
CHR RAM multicart.  So I've added a mechanism for the config file to
fix such bugs directly in the binary during the build process.

Return a pair (address as int, bytes to write there).

"""
    if not s:
        return None
    s = str(s).strip()
    m = patchRE.match(s)
    if not m:
        raise ValueError("range '%s' must be a 4-digit base 16 int, a : or =, and a hex string"
                         % s)
    return (int(m.group(1), 16), bytes.fromhex(m.group(2)))

# ROM file parsing ##################################################

def get_entrypoint(rom):
    """Find the NMI and reset points for each 32K bank in a ROM."""
    prg = rom['prg']
    banksize = min(32768, len(prg))
    pts = [(prg[i-3] << 8 | prg[i-4], prg[i-5] << 8 | prg[i-6])
           for i in range(banksize, len(prg) + banksize, banksize)]
    rom['resetpoints'] = [pt[0] for pt in pts]
    rom['nmipoints'] = [pt[1] for pt in pts]
    rom['base'] = [0x8000 for pt in pts]
    if len(prg) == 16384 and rom['resetpoints'][0] >= 0xC000:
        rom['base'] = [0xC000]

# The outer bank size
prgSizeToA53 = {
    16384: 0x00,
    32768: 0x00,
    65536: 0x10,
    131072: 0x20,
    262144: 0x30
}

# bit 7: reg $5000 default (0: 8K CHR bank; 1: inner PRG bank)
# bits 5-0: reg $81 default
mapperToA53 = {
    0: 0x80,    # NROM-256: 32K
    3: 0x00,    # CNROM: 32K, and control CHR
    2: 0x8C,    # UNROM: fixed top half
    180: 0x88,  # UNROM Crazy Climber: fixed bottom half
    7: 0x80,    # AOROM: 32K
    34: 0x80,   # BNROM: 32K
    28: 0x8C,   # Action 53: boot as if it were UNROM
}

# Action 53 mapper uses MMC1 nametable mirroring codes
mirrtypeToMMC1 = {
    'AAAA': 0x00,  # CIRAM A10 = bit 0 of control reg
    'ABAB': 0x02,  # CIRAM A10 = PA10
    'AABB': 0x03   # CIRAM A10 = PA11
}

def get_mapmode(romdata):
    romsize = len(romdata['prg'])
    try:
        mapmode_prgsize = prgSizeToA53[romsize]
    except KeyError:
        raise ValueError("unsupported ROM size %d" % romsize)
    try:
        mapmode_mapper = mapperToA53[romdata['mapper']]
    except KeyError:
        raise ValueError("unsupported iNES mapper %d" % romdata['mapper'])
    try:
        mapmode_mirroring = mirrtypeToMMC1[romdata['mirrtype']]
    except KeyError:
        raise ValueError("unsupported mirroring type %s" % romdata['mirrtype'])
    return mapmode_prgsize | mapmode_mapper | mapmode_mirroring

# ROM and title validation ##########################################

players_types = {
    '1': 0,  # 1 player
    '2': 1,  # 2 players ONLY
    '1-2': 2,  # 1 or 2 players
    '1-2 alt': 3,  # 1 or 2 players alternating
    '1-3': 4,  # 1 to 3 players
    '1-4': 5,  # 1 to 4 players
    '2-4 alt': 6,  # 2 to 4 players alternating
    '2-6 alt': 7,  # 2 to 6 players alternating
    '2-4': 8,  # 2 to 4 players w/Four Score
}


def pad_nrom128(rom):
    """Pad a 16 KiB PRG ROM to 32 KiB, leaving larger PRG ROM alone.

Always puts original size of the PRG ROM in rom['prg_orig_size'].
If padded, the new unused range is added to rom['prgunused'], and
rom['prg'] is modified.
"""
    prgsize = rom['prg_orig_size'] = len(rom['prg'])
    if prgsize >= 32768:
        return

    padlen = 0x8000 - prgsize
    resetvectorhi = rom['prg'][-1]
    if resetvectorhi >= 0xC0:
        # If the ROM is linked for $C000-$FFFF, prepad it
        prgstart = 0x10000 - prgsize
        new_unused = 0x8000, prgstart
        parts = [bytes([0xFF]) * padlen, rom['prg']]
    else:
        # Otherwise, the ROM is linked for $C000-$FFFF, postpad it,
        # but duplicate the vectors
        prgend = 0x8000 + prgsize
        new_unused = prgend, 0xFFFA
        parts = [rom['prg'], bytes([0xFF]) * (padlen - 6), rom['prg'][-6:]]

    rom['prgunused'][0].add(new_unused)
    rom['prg'] = b''.join(parts)

def validate_title(t, romdata):
    """Validate title info for a ROM.

These are changed in t:
'year' (req) to int with 0 meaning 1970
'players' to a players types value
'mapmode' to a mapmode value
'prgbank', 'chrbank', 'entrypoint' to integers
'exitpoint': replacement reset vector for this prgbank or None

These are changed in romdata:
'prgunused': list of unused ranges

Return a 2-tuple (rom_patches, warnings):
rom_patches is a list of (pathname, bank, address, data) tuples
warnings is a list of warning strings
"""
    warnings = []
    w = warnings.append

    # FDS epoch is 1975 (Showa era), but we use the UNIX epoch instead
    epoch_year = 1970
    try:
        year = int(t['year']) - epoch_year
    except KeyError:
        raise ValueError("year of first publication required")
    except ValueError:
        raise ValueError("year '%s' must be a 4-digit integer" % t['year'])
    if year < 0 or year > 2099 - epoch_year:
        raise ValueError("year %d must be between 1970 and 2099"
                         % (epoch_year + year,))
    t['year'] = year

    players = t.get('players', '1').replace(',', '-')
    try:
        players = players_types[players]
    except KeyError:
        raise ValueError("invalid number of players '%s'" % t['players'])
    t['players'] = players

    try:
        mapmode = t['mapmode']
    except KeyError:
        mapmode = get_mapmode(romdata)
        if trace:
            w("guessed mapmode %02x" % mapmode)
    else:
        try:
            mapmode = int(mapmode.lstrip('$'), 16)
        except ValueError:
            raise ValueError("mapmode value '%s' must be a hexadecimal integer"
              % (t['title'], mapmode))
        if not 0x00 <= mapmode <= 0xFF:
            raise ValueError("mapmode value $%02x must be in $00-$FF"
                             % mapmode)
    t['mapmode'] = mapmode

    num_prg_banks = len(romdata['base'])
    try:
        prgbank = int(t['prgbank'])
        if num_prg_banks > 1 and trace:
            w("specified PRG bank %d of %d" % (prgbank, num_prg_banks))
    except KeyError:
        # Default to first bank for UNROM (180), last for others
        prgbank = (num_prg_banks - 1
                   if (mapmode & 0x0C) != 0x08
                   else 0)
        if num_prg_banks > 1 and trace:
            w("guessing PRG bank %d of %d" % (prgbank, num_prg_banks))
    except ValueError:
        raise ValueError("PRG bank '%s' must be an integer" % t['prgbank'])
    if not 0 <= prgbank < num_prg_banks:
        raise ValueError("PRG bank %d exceeds PRG ROM size %d"
                         % (prgbank, num_prg_banks))
    t['prgbank'] = prgbank

    try:
        chrbank = int(t.get('chrbank', 0))
    except ValueError:
        raise ValueError("CHR bank '%s' must be an integer" % t['chrbank'])
    if 'chr' in romdata:
        num_chr_banks = len(romdata['chr']) // 8192
        if not 0 <= chrbank < num_chr_banks:
            raise ValueError("CHR bank %d exceeds CHR ROM size %d"
                             % (chrbank, num_chr_banks))
    else:
        chrbank = -1
    t['chrbank'] = chrbank

    try:
        exitpoint = int(t['exitpoint'].lstrip('$'), 16)
    except KeyError:
        exitpoint = None
    except ValueError:
        raise ValueError("exit point '%s' must be a hexadecimal integer"
                         % t['exitpoint'])
    else:
        if not 0x8000 <= exitpoint <= 0xFFF7:
            raise ValueError("exit point $%04X must be in $8000-$FFF7"
                             % exitpoint)
    t['exitpoint'] = exitpoint

    try:
        entrypoint = int(t['entrypoint'].lstrip('$'), 16)
    except KeyError:
        entrypoint = romdata['resetpoints'][prgbank]
    except ValueError:
        raise ValueError("entry point '%s' must be a hexadecimal integer"
                         % (t['entrypoint'],))
    if not 0x8000 <= entrypoint <= 0xFFF7:
        raise ValueError("entry point $%04X in bank %d must be in $8000-$FFF7"
                         % (entrypoint, prgbank))
    t['entrypoint'] = entrypoint

    prgunuseds = [
        (k[9:], v)
        for k, v in t.items()
        if k.startswith('prgunused') and v
    ]
    errs = []
    for bank, prgslices in prgunuseds:
        bank = int(bank) if bank.isdigit() else prgbank
        for prgslice in prgslices.split(','):
            try:
                prgslice = parse_prgunused(prgslice)
            except ValueError as e:
                errs.append(str(e))
                continue
            romdata['prgunused'][bank].add(prgslice)
            if trace:
                w("unused in %d: %s" % (bank, repr(prgslice)))
    if errs:
        raise ValueError("; ".join(errs))

    patches = [
        (k[5:], v)
        for k, v in t.items()
        if k.startswith('patch') and v
    ]
    rom_patches = []
    for bank, patchset in patches:
        bank = int(bank) if bank.isdigit() else prgbank
        for patch in patchset.split(','):
            try:
                patch = parse_patch(patch)
            except ValueError as e:
                errs.append(str(e))
                continue
            if patch:
                rom_patches.append((t['rom'], bank) + patch)
    if errs:
        raise ValueError("; ".join(errs))

    return rom_patches, warnings

def load_page_roms(pages, basepath=None):
    """Filter titles on pages to only those whose ROM was loaded.

pages is a list of (name, list of titles on page)
where each title is a dict containing keys 'rom', 'title', 'author',
'year', and other things in a game's record in roms.cfg

Return a tuple (page_titles, titles, roms, roms_by_name, all_patches).
page_titles is a list of (page name, index of first title on next page)
titles is a list of dicts, which generally have items
'title': string, 'description': longer string, 'author': string,
'rom': filename
roms is a list of (filename, romdata) pairs, where each romdata
is a dict returned by load_ines(), with elements 'prg' and 'chr'
and arrays 'base' and 'resetpoints' with one element per 32k bank
roms_by_name is a dict from filenames to indices into roms
all_patches is a list of (rompath, bank, address, data bytes) values
"""
    from ines import load_ines

    loaded_roms = {}
    unloadable_roms = {}
    all_patches = []
    skips = []

    # Attempt to load all ROMs
    for (pagename, titles_on_page) in pages:
        for t in titles_on_page:
            t['rom'] = rompath = os.path.normpath(relpathjoin(basepath, t['rom']))
            if rompath not in loaded_roms:
                try:
                    romdata = load_ines(rompath)
                    get_entrypoint(romdata)
                    romdata['prgunused'] = [set() for i in romdata['base']]
                    pad_nrom128(romdata)
                except Exception as e:
                    if rompath not in unloadable_roms:
                        print("%s: %s" % (rompath, e), file=sys.stderr)
                    unloadable_roms[rompath] = e
                    continue
                loaded_roms[rompath] = romdata
            try:
                rom_patches, warnings = validate_title(t, loaded_roms[rompath])
            except Exception as e:
                print("%s: loading: %s" % (t['title'], e), file=sys.stderr)
                continue
            skips.extend(warnings)
            all_patches.extend(rom_patches)
    
    if unloadable_roms:
        print("These ROMs failed to load:", file=sys.stderr)
        print("\n".join(
            "%s: %s" % (k, v) for (k, v) in sorted(unloadable_roms.items())
        ), file=sys.stderr)

    def rom_sortkey(row):
        rompath, romdata = row
        return -len(row[1]['prg']), os.path.basename(row[0]).lower()

    # Append only those titles whose ROM was loaded
    roms_in_order = sorted(loaded_roms.items(), key=rom_sortkey)
    roms_by_name = {row[0]: i for i, row in enumerate(roms_in_order)}
    page_titles = []
    titles = []
    lines = []
    d = skips.append
    for (pagename, titles_on_page) in pages:
        pagename = pagename.strip()
        if not pagename:
            titles_pl = "title" if len(titles_on_page) == 1 else "titles"
            skips.append("Omitting page with blank name and %d %s"
                         % (len(titles_on_page), titles_pl))
            continue

        lines.append("\n== %s ==" % pagename)
        for t in titles_on_page:
            rompath = t['rom']
            try:
                romdata = loaded_roms[rompath]
            except Exception as e:
                d("%s: paginating: %s" % (rompath, e))
                continue

            titles.append(t)
            # printable, or ignorable
            lines.extend(("", t['title']))
            t = sorted((k, v) for (k, v) in t.items() if k != 'title')
            lines.extend("  %s: %s" % row for row in t)
            lines.append("ROM size: %d KiB PRG + %d KiB CHR"
                         % (len(romdata['prg']) // 1024,
                            len(romdata.get('chr', '')) // 1024))
            t = sorted((k, v) for (k, v) in romdata.items()
                       if k not in ('prg', 'chr', 'trainer'))
            lines.extend("  %s: %s" % row for row in t)

        # Finalize the page
        if (len(titles) > 0
            and (len(page_titles) == 0 or len(titles) > page_titles[0][-1])):
            page_titles.append((pagename, len(titles)))

    if trace and all_patches:
        skips.append("%s ROM patches from cfg file" % len(all_patches))
        skips.extend("%s: %02x/%04x:%s"
                     % (rompath, bank, address, data.hex())
                     for rompath, bank, address, data in all_patches)
    if trace_parser:
        skips.extend(lines)
    if skips:
        print("\n".join(skips), file=sys.stderr)

    return (page_titles, titles, roms_in_order,
            roms_by_name, all_patches)

# Exit patching #####################################################

def get_exit_patches(titles, roms, skip_full=True):
    """

titles --
roms -- an iterable of (filename, romdict) tuples, where romdict is a
    dict with keys 'prg', 'chr' (optional), 'mapper', and 'prgunused'
start_bank -- the number of 32768-byte banks to insert before the
    first PRG ROM
"""
    from collections import defaultdict
    from exitpatch import ExitPatcher, UnpatchableError
    import json

    # Collect exit specs for all entry banks in each ROM
    rom_exits = defaultdict(dict)
    inheadings = ['rom', 'prgbank', 'exitmethod', 'exitpoint']
    for title in titles:
        path, prgbank, method, exitpoint = [title.get(x) for x in inheadings]
        assert not isinstance(exitpoint, str)
        if exitpoint is not None: method = None
        bank_exits = rom_exits[path]
        try:
            old_method, old_exitpoint = bank_exits[prgbank]
        except KeyError:
            pass
        else:
            if method != old_method:
                raise ValueError("%s bank %d changed exit method from %s to %s"
                                 % (path, prgbank, old_method, method))
            if exitpoint != old_exitpoint:
                raise ValueError("%s bank %d changed exit point from %s to %s"
                                 % (path, prgbank, old_exitpoint, exitpoint))
        bank_exits[prgbank] = method, exitpoint

    # Get a list of exit patches for each ROM
    patches = []
    for path, romdata in roms:
        u = [slices_union(x) for x in romdata['prgunused']]
        romdata['prgunused'] = u
        patcher = ExitPatcher(len(romdata['prg']), romdata['mapper'], u)
##        ['base', 'chrram', 'chrsave', 'mapper', 'mirrtype', 'nmipoints',
##         'prg', 'prgram', 'prgsave', 'prgunused', 'resetpoints']
        bank_exits = sorted(
            (prgbank, method, exitpoint)
            for prgbank, (method, exitpoint) in rom_exits[path].items()
        )
        try:
            for prgbank, method, exitpoint in bank_exits:
                if exitpoint is not None:
                    patcher.add_exitpoint(exitpoint, prgbank)
                else:
                    patcher.add_patch(method, prgbank)
            patcher.finish(skip_full=skip_full)
        except UnpatchableError as e:
            print("Unused for %s\n  %s" % (path, repr(u)), file=sys.stderr)
            raise UnpatchableError("%s: %s" % (path, e))

        patches.extend(
            (path, prgbank, offset, data)
            for (prgbank, offset, data) in patcher.patches
        )

    return patches

def format_sliceset(unused_ranges):
    return ', '.join("%04X-%04X" % (a, b-1) for (a, b) in unused_ranges)

def roms_to_banks(roms, start_bank=0):
    """Break up all ROMs into banks.

roms is an iterable of 2-tuples (filename, romdict) where romdict is
a dictionary with keys "prg", "chr", and "prgunused".

Return a 4-tuple (prgbanks, chrbanks, prg_starts, chr_starts).
prgbanks is [(bytearray of 32768 bytes, set of unused slices), ...]
chrbanks is just an array of 8-bit strings
prg_starts and chr_starts are arrays from indices into roms to
indices into prgbanks and chrbanks respectively
"""
    prgbanks = [(create_blank_prg_bank(), [(0xFFF0, 0xFFFA)])
                for i in range(start_bank)]
    chrbanks = []
    prg_starts = []
    chr_starts = []
    lines = []

    # At this point, split GNROMs into PRG banks, pad each NROM-128
    # to 32 KiB, and split CNROMs and GNROMs into CHR banks
    for (filename, romdata) in roms:
        prg_starts.append(len(prgbanks))
        chr_starts.append(len(chrbanks))
        prgunused = romdata['prgunused']
        lines.append("Adding %s" % filename)

        # Get all 32K banks from the PRG ROM
        for i, unused_ranges in enumerate(prgunused):
            byte_offset = i * 0x8000
            prgbytes = bytearray(romdata['prg'][byte_offset:byte_offset + 0x8000])

            # TO DO: Allow larger ROM
            assert len(prgbytes) == 32768
            lines.append("  PRG bank $%02x, not using ranges %s"
                         % (len(prgbanks), format_sliceset(unused_ranges)))
            prgbanks.append((prgbytes, unused_ranges))

        if 'chr' in romdata:
            for byte_offset in range(0, len(romdata['chr']), 0x2000):
                chrdata = romdata['chr'][byte_offset:byte_offset + 0x2000]
                assert len(chrdata) == 8192
                lines.append("  CHR bank $%02x" % (len(chrbanks),))
                chrbanks.append(chrdata)

    if trace:
        print("\n".join(lines))
    return (prgbanks, chrbanks, prg_starts, chr_starts)

blank_bank = b''.join((
    bytes(32768 - 16),
    bytes.fromhex("78A2FF9A8EF2FF6CFCFFF0FFF0FFF0FF")
))
assert len(blank_bank) == 32768

# Graphics data #####################################################

def bmptosb53(infilename, palette, max_tiles=256, trace=False):
    """Convert an image to an sb53."""
    import savtool
    from PIL import Image
    import pilbmp2nes
    import chnutils
    import donut
    #TODO: rename sb53 with pb53 replaced with donut to something diffrent.

    im = Image.open(infilename)
    if im.size[0] > 256 or im.size[1] > 240:
        raise ValueError("%s: size is %dx%d pixels (expected 256x240 or smaller)"
                         % (infilename, im.size[0], im.size[1]))
    padded = Image.new('RGB', (256, 240))
    padtopleft = ((256 - im.size[0]) // 2, (240 - im.size[1]) // 2)
    padded.paste(im, padtopleft)
    im = padded

    # Quantize picture to palette
    palette = b''.join(palette[0:1] + palette[i + 1:i + 4]
                       for i in range(0, 16, 4))
    palettes = [[tuple(savtool.bisqpal[r]) for r in palette[i:i + 4]]
                 for i in range(0, 16, 4)]
    imf, attrs = savtool.colorround(im, palettes)

    # Convert to unique tiles
    chrdata = pilbmp2nes.pilbmp2chr(imf, 8, 8)
    chrdata, namdata = chnutils.dedupe_chr(chrdata)
    if len(chrdata) > max_tiles:
        raise ValueError("%s: %d unique tiles exceeds %d"
                         % (infilename, len(chrdata), max_tiles))
    namdata = bytearray(namdata)

    # Pack attributes into bytes
    if len(attrs) % 2:
        attrs.append([0] * len(attrs[0]))
    attrs = [[lc | (rc << 2) for lc, rc in zip(row[0::2], row[1::2])]
             for row in attrs]
    attrs = [bytes(tc | (bc << 4) for (tc, bc) in zip(t, b))
             for (t, b) in zip(attrs[0::2], attrs[1::2])]
    namdata.extend(b''.join(attrs))

    compressed_tile_data = donut.compress_multiple_blocks(b''.join(chrdata))
    outdata = b''.join([
        bytes([compressed_tile_data[1] & 0xFF]),
        compressed_tile_data[0],
        donut.compress_multiple_blocks(namdata)[0],
        palette
    ])
    if trace:
        print("%d unique tiles, %d bytes"
              % (len(chrdata), len(outdata)), file=sys.stderr)
    return outdata

def load_screenshot(filename, palette=None):
    from PIL import Image
    import a53screenshot as S

    imorig = Image.open(filename).convert("RGB")
    palette = S.parse_palette(palette) if palette else S.guess_palette(imorig)
    tiles01, tiles2, attrs = S.convert_im(imorig, palette)
    header, tiledata = S.form_screenshot(tiles01, tiles2, attrs, palette)
    return header, tiledata

def load_screenshots(titles, basepath=None):
    """Load and compress all titles' screenshots.

This function takes a list of dictionaries with element 'screenshot',
loads the images using PIL, maps the screenshots to the NES color
palette, converts them to tiles, and compresses the tiles.

Return (screenshots, screenshots_by_titleno).
screenshots is [(pb53_bytes, [color1, color2, color3]), ...]
screenshot_ids is a list of one index into screenshots for each title

"""
    screenshots = []
    screenshots_by_name = {}
    screenshot_ids = []
    for d in titles:
        filename = d.get('screenshot', default_screenshot_filename)
        filename = os.path.normpath(relpathjoin(basepath, filename))
        try:
            scrid = screenshots_by_name[filename]
        except KeyError:
            headerdata, tiledata = load_screenshot(filename)
            scrid = len(screenshots)
            ctiledata, midpoint = pb53(tiledata)
            screenshots.append(headerdata+ctiledata)
            screenshots_by_name[filename] = scrid
        screenshot_ids.append(scrid)
    return (screenshots, screenshot_ids)

def neg_len_x_1_0(x):
    return -len(x[1][0])

def insert_screenshots(titles, prgbanks, basepath=None):
    """Load screenshots and insert them into unused space.

Return a tuple (scrdir, screenshot_ids).
scrdir is a byte string with 3 bytes per entry:
bank, address low, address high
screenshot_ids is a list of scrdir entries, one for each title.
If i = screenshot_ids[titleno], then the title's entry is
scrdir[i * 3:i * 3 + 3].

"""
    # Load screenshots
    (screenshots, screenshot_ids) = load_screenshots(titles, basepath)

    # Insert screenshots into unused PRG ROM
    scr_sorted = sorted(enumerate(screenshots), key=lambda x: -len(x[1]))
    scr_directory = [None for i in screenshots]
    for (i, d) in scr_sorted:
        scr_directory[i] = ffd_add(prgbanks, d)
    if trace:
        print("%d screenshots totaling %d compressed bytes plus %d for the directory"
              % (len(screenshots),
                 sum(len(d) for d in screenshots),
                 len(scr_directory)))

    # Format screenshot directory
    scrdir = b''.join(bytes([
        bank & 0xFF, addr & 0xFF, addr >> 8
    ]) for (bank, addr) in scr_directory)
    return (scrdir, screenshot_ids)

def insert_chr(chrbanks, prgbanks):
    """Compress and insert the CHR banks into unused PRG ROM.

chrbanks -- a list of 8192-byte BLOs
prgbanks -- a list of PRG banks as used by ffd_add

Return a byte string representing a directory of the compressed
CHR ROM, whose entries in the following format:

00: PRG bank
01-02: Address (little endian)
03-04: Midpoint (little endian)

The midpoint is used for decoding PB53 banks whose tiles in
$1000-$1FFF reference tiles in $0000-$0FFF.  The decoder runs two
instances of the pb53 decoder in parallel, and the second instance
copies tiles from the first.  The first starts from Address, the
second from (Address + Midpoint).

"""
    total_unco = sum(len(c) for c in chrbanks)
    pb53banks = [pb53(c) for c in chrbanks]
    del chrbanks

    # Insert the CHR banks
    pb53banks_sorted = sorted(enumerate(pb53banks), key=neg_len_x_1_0)
    if False:
        print("Compressed %d CHR bytes to %d"
              % (total_unco,
                 sum(len(c) + 4 for (c, sp) in pb53banks)))
        print("\n".join("CHR bank $%02x:%5d bytes" % (i, len(d))
                        for (i, (d, mp)) in pb53banks_sorted))
    chr_directory = [None for i in pb53banks]
    for (i, (data, midpoint)) in pb53banks_sorted:
        chr_directory[i] = ffd_add(prgbanks, data) + tuple(midpoint)
    chrdir = b''.join(bytes([
        b & 0xFF, a & 0xFF, a >> 8, mp & 0xFF, mp >> 8
    ]) for (b, a, mp) in chr_directory)
    # At this point, chr_directory[] is a list of
    # (bank, address, midpoint) tuples, one for each CHR ROM bank
    # and chrdir is the NES-readable version of that

    if trace:
        print("CHR directory:")
        print("\n".join("CHR bank $%02x in PRG bank $%02x address $%02x"
                        % (i, b, a)
                        for (i, (b, a, m)) in enumerate(chr_directory)))
    return chrdir

# Directory serialization ###########################################

def make_rom_directory(prg_starts, prg_lengths, unpatch_info, chr_starts, chr_total):
    """Turn an unpatch list into a ROM directory.

prg_starts is the index of the first PRG bank for each rom
prg_lengths is the length in bytes of each PRG ROM.  Can't infer this
from prg_starts because it doesn't distinguish NROM-128 (16384 bytes
before padding) from NROM-256 (32768 bytes and was not padded).
unpatch_info is a list of tuples, one for each bank:
(original reset vector, unpatch data)
chr_starts is the index of the first CHR bank for each ROM
chr_total is the total number of CHR banks in the ROM

Ordinarily, copylefted code and non-free code cannot be placed in the
same executable file.  But if the executable file is structured as an
archive, like a CD image, the "aggregate" exception of popular
copyleft licenses kicks in.  In order to qualify as an archive, the
multicart must allow lossless extraction of individual ROMs.

Extracting each page to a separate file is not enough because the
unpacker needs to do three things to be lossless:
1. combine the appropriate CHR bank or banks with the PRG data,
2. combine the PRG banks of a GNROM or BNROM multicart, and
3. reverse the exit patch.

The ROM directory gives instructions to turn the data in the
multicart's PRG ROM banks and compressed CHR segments back into
usable ROMs.  All data replaced by the exit patch is saved, except
in the case of NROM-128, where the reset patch is assumed to end up
in the padding.  Large ranges marked as unused in the config file are
replaced with other games' CHR ROM and screenshots, and the data that
they replace is not saved, but marking such large ranges is optional
anyway.  A collection of 53 NROM games, all patched at $BFF0
or $FFF0, should produce a ROM directory no bigger than 1 KiB.

Return a byte string with each ROM's data formatted as follows:

PRG size in 16 KiB units (1 byte) = np
CHR size in 8 KiB units (1 byte) = nc
PRG bank records (ceil(np/2) records of variable length)
CHR bank IDs (nc records of 1 byte each)

The format of a PRG bank record is as follows:
PRG bank index (1 byte)
Original contents of $FFFC-$FFFD, the reset vector (2 bytes)
Length of reset patch (1 byte; may be 0; bit 7 is 1 if the patch
covered a run of a single byte value)
Data that the reset patch replaced (1 byte if a run; otherwise as
long as the reset patch)

When writing the directory to the ROM, write a zero byte afterward so
that the extractor knows to stop extracting ROMs at a 0-length PRG.

When unpatching the ROM, replace data starting at the reset vector
with the data that the reset patch replaced, and then replace the
reset vector with the original one.

"""
    prg_starts = list(prg_starts)
    prg_starts.append(len(unpatch_info))
    chr_starts = list(chr_starts)
    chr_starts.append(chr_total)
    prg_lengths = [n // 16384 for n in prg_lengths]
    romdir = bytearray()
    if trace:
        print("prg_starts is", prg_starts)
        print("%d roms" % len(prg_lengths))

    for i in range(len(prg_lengths)):
        start_offset = len(romdir)
        prg_start_bank = prg_starts[i]
        prg_num_halfbanks = prg_lengths[i]

        # This fails when there are empty banks, as
        # spurious unpatch_data gets added.
        # prg_num_banks = prg_starts[i + 1] - prg_start_bank
        # So instead, derive the number of banks from the number
        # of half-banks, which is what the unpacker expects.
        prg_num_banks = (prg_num_halfbanks + 1) // 2
        romdir.append(prg_num_halfbanks)
        chr_start_bank = chr_starts[i]
        chr_num_banks = chr_starts[i + 1] - chr_start_bank
        romdir.append(chr_num_banks)
        for j in range(prg_start_bank, prg_start_bank + prg_num_banks):
            (orig_fffc, unpatch_data) = unpatch_info[j]
            if prg_num_halfbanks < 2:  # don't unpatch NROM-128
                unpatch_data = ''
            unpatch_len = len(unpatch_data)

            # compress runs of unpatch data
            if (unpatch_len > 0
                and all(c == unpatch_data[0] for c in unpatch_data[1:])):
                unpatch_len = unpatch_len | 0x80
                unpatch_data = unpatch_data[:1]
            romdir.extend([j, orig_fffc & 0xFF, orig_fffc >> 8, unpatch_len])
            romdir.extend(unpatch_data)
        romdir.extend(range(chr_start_bank, chr_start_bank + chr_num_banks))
        if trace:
            print(romdir[start_offset:].hex())

    romdir.append(0)
    return romdir

def ffd_prg_factory():
    return (bytearray(blank_bank), [(0x8000, 0xFFF0)])

def pad_to_pow2m1(prgbanks):
    """Add blank PRG banks until reaching one less than a power of two."""

    # In binary, if (x & (x + 1)) is zero, then x is one less than
    # a power of two.
    while (len(prgbanks) & (len(prgbanks) + 1)) != 0:
        prgbanks.append(ffd_prg_factory())

def make_title_directory(titles, roms_by_name,
                         prg_starts, chr_starts, screenshot_ids):
    """Make a machine-readable directory of ROM titles.

On the screen it is printed thus:

Title
20yy Author
Number of players

Description (up to
16 lines)

So the title directory will have 16 bytes per entry:
PRG bank number
CHR bank number (128+: none; game uses CHR RAM)
Screenshot number
Year minus 1970
Number of players type
(3 bytes unused)
2-byte offset to title and author within the name block
2-byte offset to description within the description block
2-byte reset vector
1-byte mapper configuration
(1 byte unused)
For 64 entries this is only 1 KiB.

Each entry in the name and description blocks is terminated by a NUL
byte ('\0').  Each name block entry is a title and author separated
by a '\n', and the description block is likewise newline-delimited.

The title directory and the name block MUST be stored in the last
32 KiB bank of the ROM along with the menu.  Descriptions MAY
be in a separate bank, but they're all in one bank for a maximum
total of 32752 bytes.  In a 53-game collection, this limits the
descriptions to average a bit over half a kilobyte each, which is
fine considering 16 lines of VWF with about 28 characters per line.

Return a tuple of three 8-bit byte strings: the title directory,
the name block, and the description block.

"""
    # convert each title's PRG and CHR bank numbers from ROM-relative
    # to absolute
    prg_starts = [prg_starts[roms_by_name[t['rom']]] + t['prgbank']
                  for t in titles]
    chr_starts = [(chr_starts[roms_by_name[t['rom']]] + t['chrbank']
                   if t['chrbank'] >= 0
                   else 255)
                  for t in titles]

    titledir = bytearray()
    name_block = bytearray()
    desc_block = bytearray()
    for (i, title) in enumerate(titles):
        try:
            reset = title['entrypoint']
            title_name = title['title']
            author_name = title['author']
            description = title['description']
            year = title['year']
            players = title['players']
            mapmode = title['mapmode']
        except KeyError:
            print("The game %s is missing something:" % title.get('title', ''),
                  file=sys.stderr)
            raise
        name_offset = len(name_block)
        desc_offset = len(desc_block)
        name_block.extend(title_name.encode('action53'))
        name_block.append(10)  # newline
        name_block.extend(author_name.encode('action53'))
        name_block.append(0)
        desc_block.extend(description.encode('action53'))
        desc_block.append(0)

        # UNROM needs prgstart to be set at the LAST bank of
        # each title
        prgstart = prg_starts[i]
        if (mapmode & 0x0C) == 0x0C and (mapmode & 0x30) > 1:
            banksizemask = (1 << ((mapmode & 0x30) >> 4)) - 1
            prgstart = prgstart | banksizemask
            print("UNROM detected in %s:\n"
                  "applying bank size adjustment $%02x forming prgstart $%02x"
                  % (title['title'], banksizemask, prgstart))
            #raise NotImplementedError
        
        titledir_data = [
            prgstart, chr_starts[i], screenshot_ids[i], year,
            int(players), 0, 0, 0,
            name_offset & 0xFF, name_offset >> 8,
            desc_offset & 0xFF, desc_offset >> 8,
            reset & 0xFF, reset >> 8,
            mapmode, 0
        ]
        titledir.extend(titledir_data)

    return titledir, name_block, desc_block

def make_pagedir(pages):
    pageoffsets = bytearray()
    pageoffsets.append(len(pages))
    pageoffsets.extend(p[1] for p in pages)
    for p in pages:
        title = p[0]
        pageoffsets.extend(title.encode('action53'))
        pageoffsets.append(0)
    return pageoffsets

def convert_title_lines(title_lines):
    out = []
    for lines, xpx, yline, colorcode in title_lines:
        for yoffset, line in enumerate(lines):
            line = line.rstrip()
            if not line: continue
            if yoffset + yline >= 30:
                raise ValueError("%s: Y below screen bottom" % line)
            line8 = line.encode("action53").replace(b"\0", b"")
            thisline = bytearray()
            thisline.append(colorcode | (yoffset + yline))
            thisline.append(xpx)
            thisline.extend(line8)
            thisline.append(0)
            out.append(thisline)
    out.append(b'\xFF')
    return b''.join(out)

def main(argv=None):
    argv = argv or sys.argv

    # Load the config file
    cfgfilename, outfilename = argv[1:3]
    parsed = RomsetParser(filenames=[cfgfilename])
    if not parsed.pages:
        raise IndexError("%s: no pages" % (cfgfilename,))

    a53charset.register()  # Make 'action53' encoding available

    # Convert the title screen
    title_screen_sb53 = bmptosb53(parsed.title_screen, parsed.title_palette)

    # Convert the title lines
    print(parsed.title_lines)
    title_lines_data = convert_title_lines(parsed.title_lines)

    # Load the ROMs
    start_bank = parsed.start_bank
    (pages, titles, roms, roms_by_name, cfg_patches) \
            = load_page_roms(parsed.pages, cfgfilename)
    if len(titles) == 0:
        raise IndexError("Not writing ROM: no titles were loaded")
    if trace:
        print("%d titles across %d roms on %d pages loaded successfully"
              % (len(titles), len(roms), len(pages)))
    with open(parsed.menu_prg, 'rb') as infp:
        final_bank = bytearray(infp.read())
    if len(final_bank) != 32768:
        raise ValueError("%s: %s should be 32768 bytes, not %d"
                         % (cfgfilename, parsed.menu_prg, len(final_bank)))
    parsed = None

    # Compute the length of each PRG ROM, so that the ROM directory
    # can distinguish NROM-128 from NROM-256
    prg_lengths = [romdata['prg_orig_size'] for (nm, romdata) in roms]

    # Pack ROMs into the first PRG banks
    if trace:
        print("start_bank is %s" % start_bank)
    mapperNumber, submapperNumber = 28, 0
    skip_full = mapperNumber == 28
    exit_patches = get_exit_patches(titles, roms, skip_full)
    if trace:
        print("%d exit patches, %d cfg patches"
              % (len(exit_patches), len(cfg_patches)))

    (prgbanks, chrbanks, prg_starts, chr_starts) \
               = roms_to_banks(roms, start_bank)
    roms = [rom[0] for rom in roms]
    if trace:
        print("ROM size before adding CHR: %d PRG banks" % len(prgbanks))
    pad_to_pow2m1(prgbanks)
    if trace:
        print("padded to power of 2: %d PRG banks" % len(prgbanks))

    # Find the part of each PRG bank that will be replaced with a
    # reset patch, apply the patch, and save info needed to reverse
    # the patch
    unpatch_info = [(0xFFFF, b'')
                    for (romdata, unused_ranges) in prgbanks]
    # unpatch_info is supposed to be one row for each bank:
    # [(original reset vector, unpatch address, unpatch data), ...]

    # Now that all banks except the last have been reset patched,
    # add the menu's bank to the collection.  Both final_banks and
    # the last element of prgbanks point to the same final bank's
    # data and unused list.  This way I can insert objects wherever
    # they'll fit (prgbanks) or into the final bank specifically
    # (final_banks).
    final_banks = [(final_bank, [(0x8000, 0xBFF0)])]
    prgbanks.extend(final_banks)

    # Create those directories that don't depend on other directories
    romdir = make_rom_directory(prg_starts, prg_lengths, unpatch_info,
                                chr_starts, len(chrbanks))
    pagedir = make_pagedir(pages)

    # Estimate size of other last-bank directories to be inserted
    # after CHR and screenshot directories
    est_dirs_len = (len(chrbanks) * 5
                    + len(set(d.get('screenshot', default_screenshot_filename)
                              for d in titles)) * 3
                    + 16 * len(titles)
                    + sum(len(d['title']) + len(d['author']) + 2
                          for d in titles)
                    + len(title_screen_sb53))

    # Apply binary patches in the cfg (as opposed to reset patches)
    all_patches = []
    all_patches.extend(exit_patches)
    all_patches.extend(cfg_patches)
    for (rompath, prgbank, offset, data) in all_patches:
        i = roms_by_name[rompath]
        prgbank = prgbanks[prg_starts[i] + prgbank][0]
        offset -= 0x8000
        prgbank[offset:offset + len(data)] = data
    del prgbank, all_patches, cfg_patches, exit_patches
        
    # Insert tile data for CHR ROM and screenshots
    chrdir = insert_chr(chrbanks, prgbanks)
    del chrbanks
    (scrdir, screenshot_ids) = insert_screenshots(titles, prgbanks, cfgfilename)

    # Create the title directory
    (titledir, name_block, desc_block) \
               = make_title_directory(titles, roms_by_name,
                                      prg_starts, chr_starts, screenshot_ids)
    pagedir_sz = sum(len(p[0]) for p in pages) + 2 * len(pages) + 1
    assert len(pagedir) == pagedir_sz

    # Save the ROM directory, CHR directory, screenshot directory,
    # title directory, and name block to the menu bank
    dirs_len1 = len(romdir) + len(pagedir)
    dirs_len2 = sum(len(x) for x in (
        chrdir, scrdir, titledir, name_block, title_screen_sb53
    ))
    if trace:
        print("Main bank directories already inserted total %d bytes.\n"
              "Those not yet inserted total %d bytes, compared to estimate of %d.\n"
              "Descriptions total %d."
              % (dirs_len1, dirs_len2, est_dirs_len, len(desc_block)))
    if dirs_len2 + dirs_len1 > 0x3FF0:
        raise ValueError("internal error: directory size of %d bytes exceed 16 KiB"
                         % (dirs_len2 + dirs_len1))
    if dirs_len2 != est_dirs_len:
        raise ValueError("internal error: directory size of %d bytes does not match estimate of %d"
                         % (dirs_len2, est_dirs_len))

    desc_block_addr = ffd_add(prgbanks, desc_block)
    name_block_addr = ffd_add(final_banks, name_block)
    romdir_addr = ffd_add(final_banks, romdir)
    titledir_addr = ffd_add(final_banks, titledir)
    scrdir_addr = ffd_add(final_banks, scrdir)
    chrdir_addr = ffd_add(final_banks, chrdir)
    pagedir_addr = ffd_add(final_banks, pagedir)
    title_screen_addr = ffd_add(final_banks, title_screen_sb53)
    if trace:
        print("Remaining space in last bank:",
              ', '.join("%04x-%04x" % (s, e - 1)
                        for s, e in final_banks[0][1]))

    title_strings_addr = ffd_add(final_banks, title_lines_data)
    print("title strings addr is", title_strings_addr)
    title_strings_invert = 0x00

    # And finally make the key block at FF00
    # Format:
    # 00 ROM dir address, CHR dir address
    # 04 screenshot dir address, title dir address
    # 08 page dir address, name block address
    # 0C desc block address, desc block bank, unused,
    # 10 title screen address, 12 title strings address
    keyblock = bytes([
        romdir_addr[1] & 0xFF, romdir_addr[1] >> 8,
        chrdir_addr[1] & 0xFF, chrdir_addr[1] >> 8,
        scrdir_addr[1] & 0xFF, scrdir_addr[1] >> 8,
        titledir_addr[1] & 0xFF, titledir_addr[1] >> 8,
        pagedir_addr[1] & 0xFF, pagedir_addr[1] >> 8,
        name_block_addr[1] & 0xFF, name_block_addr[1] >> 8,
        desc_block_addr[1] & 0xFF, desc_block_addr[1] >> 8,
        desc_block_addr[0], 0xFF,
        title_screen_addr[1] & 0xFF, title_screen_addr[1] >> 8,
        title_strings_addr[1] & 0xFF, title_strings_addr[1] >> 8,
    ])
    if trace:
        print("descriptions in bank %d byte $%04x" % desc_block_addr)
        print("romdir at $%04x-$%04x, titledir at $%04x-$%04x"
              % (romdir_addr[1], romdir_addr[1] + len(romdir) - 1,
                 titledir_addr[1], titledir_addr[1] + len(titledir) - 1))
    final_bank[0x7F00:0x7F00 + len(keyblock)] = keyblock

    if trace:
        print("Allocation of PRG banks")
        print("\n".join("Bank %d: %s" % row for row in zip(prg_starts, roms)))
        print("Bank %d: Menu" % (len(prgbanks) - 1))
        for (i, (d, unused_ranges)) in enumerate(prgbanks):
            print("Bank %d unused: %s"
                  % (i, ", ".join("%04x-%04x" % (s, e-1)
                                  for (s, e) in unused_ranges)))

    iNES_prgbanks = len(prgbanks) * 2
    iNESheader = bytearray(b"NES\x1A")
    
    iNESheader.append(iNES_prgbanks & 0xFF)
    iNESheader.append(0)  # no CHR ROM
    iNESheader.append(((mapperNumber & 0x0F) << 4) | 0x01)
    iNESheader.append((mapperNumber & 0xF0) | 0x08)
    iNESheader.append((mapperNumber >> 8) | (submapperNumber << 4))
    iNESheader.append(iNES_prgbanks >> 8)
    iNESheader.append(0)  # no PRG RAM
    iNESheader.append(0x09)  # 64 << 9 bytes of CHR RAM
    iNESheader.extend(bytes(16 - len(iNESheader)))

    with open(outfilename, "wb") as outfp:
        outfp.write(iNESheader)
        outfp.writelines(b[0] for b in prgbanks)
    
if __name__ == '__main__':
    in_IDLE = 'idlelib.__main__' in sys.modules or 'idlelib.run' in sys.modules
    if in_IDLE:
        cmd = """
a53build.py a53minimal.cfg ../a53minimal.nes
"""
        main(cmd.split())
    else:
        main()
