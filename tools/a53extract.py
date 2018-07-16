#!/usr/bin/env python3
import collections
from binascii import b2a_hex

class A53ROM(collections.Mapping):
    nplayers_types_list = [
        '1', '2', '1-2', '1-2 alt', '1-3', '1-4', '2-4 alt', '2-6 alt'
    ]
        
    def __init__(self, prg_rom):
        """Load an Action 53 compilation's PRG ROM as an 8-bit string."""
        from bisect import bisect_right
        self.prg_banks = [prg_rom[i:i + 0x8000]
                          for i in range(0, len(prg_rom), 0x8000)]
        last_bank = self.prg_banks[-1]
        ff00 = [ord(c) for c in last_bank[-256:-240]]
        self.romdir_addr = (ff00[0] | (ff00[1] << 8)) - 0x8000
        self.chrdir_addr = (ff00[2] | (ff00[3] << 8)) - 0x8000
        titledir_addr = (ff00[6] | (ff00[7] << 8)) - 0x8000
        pagedir_addr = (ff00[8] | (ff00[9] << 8)) - 0x8000
        name_block_addr = (ff00[10] | (ff00[11] << 8)) - 0x8000
        desc_block_addr = (ff00[12] | (ff00[13] << 8)) - 0x8000
        desc_block_bank = ff00[14]
        
        num_pages = ord(last_bank[pagedir_addr])
        self.page_boundaries = [ord(c)
                                for c in last_bank[pagedir_addr+1:pagedir_addr + num_pages + 1]]
        num_titles = self.page_boundaries[-1]
        allpt = last_bank[pagedir_addr + num_pages + 1:]
        self.page_titles = allpt.split('\0', num_pages)[:num_pages]
        del allpt

        # Parse all the titles
        titledir = [last_bank[titledir_addr + i * 16:titledir_addr + i * 16 + 16]
                    for i in range(num_titles)]
        titles = []
        titleno_by_abs_prg = [set() for row in self.prg_banks]
        for (titleno, row) in enumerate(titledir):
            (abs_prg, abs_chr, screenshotid, year,
             nplayers, u1, u1, u1,
             title_off, title_offhi, desc_off, desc_offhi, reset, resethi,
             reg80, u1) = [ord(c) for c in row]
            title_off += (title_offhi - 0x80) << 8
            desc_off += (desc_offhi - 0x80) << 8
            title_author = last_bank[name_block_addr + title_off:]
            title_author = title_author.split('\0', 1)[0]
            (title, author) = title_author.split('\n', 1)
            description = self.prg_banks[desc_block_bank][desc_block_addr + desc_off:]
            description = description.split('\0', 1)[0]
            reset += resethi << 8
            pageno = bisect_right(self.page_boundaries, titleno)
            titles.append({
                'page': self.page_titles[pageno],
                'titleno': titleno,
                'title': title,
                'author': author,
                'screenshotid': screenshotid,
                'players': self.nplayers_types_list[nplayers],
                'year': year + 1970,
                'description': description,
                'entrypoint': "%04x" % reset,
                'abs_prg': abs_prg,
                'abs_chr': abs_chr if abs_chr < 128 else None,
                'reg80': reg80
            })
            titleno_by_abs_prg[abs_prg].add(titleno)
        del titledir

        # Determine which titles use each CHR bank
        num_chr = [t['abs_chr'] for t in titles
                   if t['abs_chr'] is not None]
        num_chr = max(num_chr) + 1 if num_chr else 0
        titleno_by_abs_chr = [set() for i in range(num_chr)]
        for (titleno, title) in enumerate(titles):
            if title['abs_chr'] is not None:
                titleno_by_abs_chr[title['abs_chr']].add(titleno)

        self.title_list = titles
        self.titles_by_name = dict({t['title'], n} for (n, t) in enumerate(titles))

        # Now look up to which ROM each title belongs and which
        # relative banks within each ROM correspond to each game.
        self.get_romdir()
        self.titles_by_romid = []
        for (romid, (u1, rom_prgbanks, rom_chrids)) in enumerate(self.romdir):
            titles_in_this_rom = set()
            for (rel_prg, (abs_prg, u1, u1)) in enumerate(rom_prgbanks):
                titles_in_this_rom.update(titleno_by_abs_prg[abs_prg])
                for titleno in titleno_by_abs_prg[abs_prg]:
                    titles[titleno]['romid'] = romid
                    titles[titleno]['prgbank'] = rel_prg
            self.titles_by_romid.append(titles_in_this_rom)
            for (rel_chr, abs_chr) in enumerate(rom_chrids):
                for titleno in titleno_by_abs_chr[abs_chr]:
                    titles[titleno]['chrbank'] = rel_chr

    @staticmethod
    def from_ines_file(filename):
        """Load an iNES ROM, then load its PRG ROM."""
        from ines import load_ines
        return A53ROM(load_ines('../a53games.nes')['prg'])

    def get_romdir(self):
        """Load the ROM directory.

The ROM directory is a list of 3-tuples:
(PRG size in 16384 byte units, list of PRG bank records,
list of CHR directory IDs)

Each PRG bank record is also a 3-tuple:
(absolute bank number, original reset vector, unpatch data)

"""
        try:
            return self.romdir
        except AttributeError:
            pass

        last_bank = self.prg_banks[-1]
        offset = (ord(last_bank[-256]) | (ord(last_bank[-255]) << 8)) - 0x8000
        print "ROM directory offset: 0x%02x" % offset
        roms = []
        it = iter(last_bank[offset:])
        romdirsz = 0
        while True:
            direntsz = 0
            prgbanks = []
            prgSize = ord(it.next())
            if prgSize == 0:
                break
            if prgSize > 32:
                print "romdirsz so far is", romdirsz
                raise ValueError("ROM %d has unexpected PRG size %d"
                                 % (len(roms), prgSize))
            chrSize = ord(it.next())
            print ("ROM %d has PRG size %d and CHR size %d"
                   % (len(roms), prgSize, chrSize))
            direntsz += 2
            for i in range((prgSize + 1) // 2):
                bankNum = ord(it.next())
                resetVector = ord(it.next())
                resetVector |= ord(it.next()) << 8
                unpatchLen = ord(it.next())
                direntsz += 4
                if unpatchLen > 0x80:
                    unpatchData = it.next() * (unpatchLen - 0x80)
                    direntsz += 1
                else:
                    unpatchData = ''.join(it.next() for i in range(unpatchLen))
                    direntsz += unpatchLen
                prgbanks.append((bankNum, resetVector, unpatchData))
                print ("> Bank %d, reset %04x, unpatch %d bytes"
                       % (bankNum, resetVector, len(unpatchData)))
            chrids = [ord(it.next()) for i in range(chrSize)]
            print "> CHR banks:", chrids
            direntsz += chrSize
            roms.append((prgSize, prgbanks, chrids))
            print b2a_hex(last_bank[offset + romdirsz:offset + direntsz + romdirsz])
            romdirsz += direntsz
        print "ROM directory end: 0x%02x" % (offset + romdirsz)
        print b2a_hex(last_bank[offset:offset + romdirsz + 1])
        self.romdir = roms
        return roms

    def get_chr_bank(self, chrid):
        """Extract a CHR bank from the ROM as 8192 bytes of NES tiles."""
        from pb53 import unpb53

        prg = self.prg_banks
        chrdir_addr = (ord(prg[-1][-254]) | (ord(prg[-1][-253]) << 8)) - 0x8000
        chrdir_addr += chrid*5
        chrdir_entry = [ord(c) for c in prg[-1][chrdir_addr:chrdir_addr + 5]]
        chrdir_bank = chrdir_entry[0]
        chrdir_address = (chrdir_entry[1] | (chrdir_entry[2] << 8)) - 0x8000
        data = unpb53(prg[chrdir_bank][chrdir_address:], 512)
        return data

    # Sized methods
    def __len__(self):
        """Count the titles in the ROM."""
        return len(self.title_list)

    # Iterable methods
    def __iter__(self):
        """Iterate through the titles of games in the ROM."""
        return (t['title'] for t in self.title_list)

    # Container methods
    def __contains__(self, title):
        """Return True iff title is the title of a game in the ROM."""
        return title in self.titles_by_name

    # Mapping methods
    def __getitem__(self, title):
        """Return information about the game in the ROM with a given title.

These keys correspond to roms.cfg entries:
page -- the page on which the game appears
title -- the game's title
author -- the name of the author
year -- the year of publication
players -- a string representing the number of players
description -- multi-line short instructions
entrypoint -- the address to start execution

These keys don't quite:
titleno -- the zero-based index of the title in self.title_list
screenshotid -- the ID of the screenshot for get_screenshot()

These need to be combined with information from get_romdir() to form
rom, prgbank, and chrbank:
abs_prg -- absolute PRG bank
abs_chr -- absolute CHR bank

"""
        return self.title_list[self.titles_by_name[title]]

    def iterkeys(self):
        return iter(self)

    def keys(self):
        return list(iter(self))

    def itervalues(self):
        return iter(self.title_list)

    def values(self):
        return list(self.title_list)

    def iteritems(self):
        return ((t['title'], t) for t in self.title_list)

    def items(self):
        return list(self.iteritems())

    def num_screenshots(self):
        return max(t['screenshotid'] for t in self.title_list) + 1

    def get_screenshot_tiles(self, scrid):
        """Get a screenshot from the ROM in NES tile format.

Return a tuple (tiledata, palette).  tiledata is an 896-byte
8-bit string, and palette is a list of four NES color numbers.

"""
        from pb53 import unpb53

        last_bank = self.prg_banks[-1]
        ff00 = [ord(c) for c in last_bank[-256:-240]]
        scrdir_addr = (ff00[4] | (ff00[5] << 8)) - 0x8000 + 6 * scrid
        scrdata = [ord(c) for c in last_bank[scrdir_addr:scrdir_addr + 6]]
        (bank, addr, addrhi, c1, c2, c3) = scrdata
        addr |= addrhi << 8
        c = unpb53(self.prg_banks[bank][addr - 32768:], 56)
        return (c, [0x0F, c1, c2, c3])

    def get_screenshot(self, scrid):
        """Get a screenshot from the ROM as an indexed PIL image."""
        from ineschr import chrbank_to_pil
        from nespalette import nespal
        from itertools import chain

        (tiles, palette) = self.get_screenshot_tiles(scrid)
        im = chrbank_to_pil(tiles, 8)
        palette = [nespal[c] for c in palette]
        p = list(chain(*palette)) + [0] * (768 - 12)
        im.putpalette(p)
        return im

    def extract_rom(self, i):
        """Extract a ROM in iNES format from the collection.

Return a tuple of three 8-byte strings:
(16-byte header, PRG ROM, CHR ROM)
These can be used with ''.join() or writelines().

"""
        from array import array

        (prgSize, prgbanks, chrbanks) = self.get_romdir()[i]
        print "rom %d: banks" % i, prgbanks
        prgbanks = [(array('B', self.prg_banks[b]), reset, array('B', patch))
                    for (b, reset, patch) in prgbanks]
        for row in prgbanks:
            (data, reset, patch) = row
            patchLoc = (data[-4] | (data[-3] << 8)) - 0x8000
            data[-4] = reset & 0xFF
            data[-3] = reset >> 8
            data[patchLoc:patchLoc + len(patch)] = patch
        prgbanks = ''.join(data.tostring() for (data, reset, patch) in prgbanks)
        chrbanks = ''.join(self.get_chr_bank(i) for i in chrbanks)
        if prgSize == 1:
            if reset < 0xC000:
                prgbanks = prgbanks[:0x4000]
            else:
                prgbanks = prgbanks[0x4000:]

        iNESheader = array('B', 'NES\x1A')
        mapperNumber = 0
        if len(chrbanks) > 0 and len(prgbanks) > 32768:
            mapperNumber = 66  # GNROM: multi PRG ROM, CHR ROM
        elif len(chrbanks) > 8192:
            mapperNumber = 3  # CNROM: one PRG ROM, multi CHR ROM
        elif len(prgbanks) > 32768:
            mapperNumber = 34  # BNROM: multi PRG ROM, CHR RAM
        else:
            mapperNumber = 0  # NROM: one PRG ROM, CHR ROM or RAM
        iNESheader.append(prgSize)
        iNESheader.append(len(chrbanks) // 8192)
        iNESheader.append(((mapperNumber & 0x0F) << 4) | 0x01)
        iNESheader.append(mapperNumber & 0xF0)
        iNESheader.extend(0 for i in range(8))
        return (iNESheader.tostring(), prgbanks, chrbanks)

    def get_rom_filename(self, romid):
        """Come up with a unique filename for the ROM.

For best results, override this in your subclass.

"""
        return "a53extract_%02x.nes" % romid

    def get_screenshot_filename(self, scrid):
        """Come up with a unique filename for the screenshot.

For best results, override this in your subclass.

"""
        return "a53screenshot_%02x.png" % scrid

    @staticmethod
    def innieformat(k, v):
        k = k.strip()
        v = str(v) if v is not None else ''
        short_v = v.replace('\n', '').strip()
        if v == short_v:
            return "%s=%s\n" % (k, v)
        v = v.replace('\n.', '\n..')  # escape dots as in smtp bodies
        return "%s:\n%s\n.\n" % (k, v)

    def get_unpatch_range(self, romid, prgbank):
        (abs_prg, u1, patch) = self.get_romdir()[romid][1][prgbank]
        data = self.prg_banks[abs_prg]
        patchLoc = (ord(data[-4]) | (ord(data[-3]) << 8))
        return (patchLoc, patchLoc + len(patch))

    def get_roms_cfg(self):
        """Make a roms.cfg.

This does NOT attempt to reproduce prgunused or chrunused because of
a limitation in the pb53 API: it does not report the bytes consumed.

"""
        out = []
        last_page = None
        for t in self.title_list:
            pairs = []
            if t['page'] != last_page:
                last_page = t['page']
                pairs.append(('page', last_page))
            romid = t['romid']
            scrid = t['screenshotid']
            rel_prg = t['prgbank']
            (unused_start, unused_end) = self.get_unpatch_range(romid, rel_prg)
            pairs.extend([('title', t['title']),
                          ('author', t['author']),
                          ('year', t['year']),
                          ('players', t['players']),
                          ('screenshot', self.get_screenshot_filename(scrid)),
                          ('description', t['description']),
                          ('rom', self.get_rom_filename(romid)),
                          ('prgbank', rel_prg),
                          ('entrypoint', t['entrypoint'])])
            if t.get('chrbank') is not None:
                pairs.append(('chrbank', t['chrbank']))
            if unused_end > unused_start:
                pairs.append(('prgunused', "%04x-%04x" % (unused_start, unused_end - 1)))
            out.extend(self.innieformat(*pair) for pair in pairs)
            out.append("\n")
        return ''.join(out)

rom = A53ROM.from_ines_file('../a53games.nes')
print ("%d titles in %d ROMs, %d unique screenshots"
       % (len(rom), len(rom.romdir), rom.num_screenshots()))
for romid in range(len(rom.romdir)):
    ines_data = rom.extract_rom(romid)
    with open(rom.get_rom_filename(romid), "wb") as outfp:
        outfp.writelines(ines_data)
del ines_data
for scrid in range(rom.num_screenshots()):
    rom.get_screenshot(scrid).save(rom.get_screenshot_filename(scrid))
cfg_data = rom.get_roms_cfg()
with open("a53extract_roms.cfg", "wt") as outfp:
    outfp.write(cfg_data)
