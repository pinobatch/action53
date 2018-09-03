Action 53 file system
=====================

The Action 53 ROM builder stores several data structures related to
the ROMs in a collection.

Key block
---------
The **key block** is a set of metadata about the entire collection.
It's analogous to the volume boot record in the boot sector of a
computer storage device's file system.

As of the 2018 version of _Action 53_, used for volumes 3 and 4, the
key block begins 256 bytes from the end of the ROM, at offset $7F00
in the last 32 KiB bank.  Because the NES maps ROM to $8000-$FFFF,
it appears at $FF00 in CPU address space.  A ROM image in iNES format
(or its offshoot NES 2.0) carries a 16-byte NES 2.0 header before the
ROM data, and the key block for a 512 KiB collection in iNES format
is thus at file offset $07FF10.

All CPU addresses in the key block and elsewhere are little-endian,
meaning bits 7-0 come before bits 15-8, and they have bit 15 set to
true ($8000-$FFFF not $0000-$7FFF).  Thus an offset of $4321 in a
bank is stored as `21 C3`.  All addresses in the key block refer to
the last bank of the ROM unless stated otherwise.

* $FF00: Address of ROM directory
* $FF02: Address of CHR directory
* $FF04: Address of screenshot directory
* $FF06: Address of activity directory
* $FF08: Address of page directory
* $FF0A: Address of activity name directory
* $FF0C: Address of descriptions (possibly in another bank)
* $FF0E: 32K bank number where descriptions are stored
* $FF0F: Unused
* $FF10: Address of compressed title screen
* $FF12: Address of title strings
* $FF14: Address of replacement table for DTE decompression

ROM directory
-------------
The menu does not use this; it's for the extraction tool.
Records in the following format describe each ROM in a collection:

* 1 byte: Size of PRG ROM in 16384 byte half banks (same as header
  byte 4).  Usually 1, 2, 4, 8, or 16.
* 1 byte: Size of CHR ROM in 8192 byte units (same as header byte 5).
  Usually 0, 1, 2, or 4.
* Variable: An unpatch record for each 32768-byte PRG bank.
* 0-4 bytes: The CHR directory index for each CHR ROM bank, if any.

A PRG ROM size of 0 ends the ROM directory.

Unpatch records contain the data that the exit patch overwrote in
each PRG ROM bank.

* 1 byte: PRG ROM bank number
* 2 bytes: Original reset vector at $FFFC
* 1 byte: Length of unpatch data in bytes
* n bytes: Length of data

The unpatch data starts at the patched reset vector.  If the
length is less than 128, it consists of that many literal bytes.
Otherwise, a single byte is stored, and the exit patch consists
of _n_ minus 128 repetitions of a single byte.

Unpatch data for CHR ROM, screenshots, and the description block
is treated as solid $FF.

CHR directory
-------------
To be rewritten after interleave for Donut is rethought.

*The following refers to a previous version*

Each 8192-byte CHR ROM bank consists of two 4096-byte half banks
compressed with PB53.  They are decoded in parallel because many
games, especially those by Shiru, have many identical tiles across
the two banks for use in CHR animation.

* 1 byte: PRG bank holding compressed data
* 2 bytes: Address of first half bank's data
* 2 bytes: Address of second half bank's data

Screenshots
-----------
The screenshot directory:

* 1 byte: PRG bank holding compressed data
* 2 bytes: Address of screenshot

Each screenshot converted with `form_screenshot()` in
`a53screenshot.py` consists of a 13-byte header followed by
a block of Donut compressed tile data.

* 3 bytes: Colors used for color set 0
* 3 bytes: Colors used for color set 1
* 7 bytes: 64x56-bit bitmap of which color set each tile uses

Tiles have 3 bits per pixel and are stored in 14 groups of four
tiles, each of which decompresses to 128 bytes (two Donut blocks).
Each group consists of planes 0 and 1 for four tiles (64 bytes)
followed by plane 2 for all four tiles (32 bytes) and 32 zero bytes.
A 0 in plane 2 means this pixel is gray (0, 1, 2, or 3 meaning black,
dark gray, light gray, or white); 1 means it uses a color from the
tile's color set.

Activities
----------
Each activity has a 16-byte record:

* 1 byte: Starting PRG bank number
* 1 byte: Starting CHR bank number
* 1 byte: Screenshot directory index
* 1 byte: Year of first publication minus 1970 (48 means 2018)
* 1 byte: Number of players type
* 1 byte: Number of CHR banks
* 2 bytes: Unused
* 2 bytes: Offset in activity names to start of title and author
* 2 bytes: Offset in descriptions to start of description
* 2 bytes: Reset vector
* 1 byte: Mapper configuration
* 1 byte: Unused

The total number of activities is the sum of the number of activities
on all pages.

Mapper configuration consits of a bit field with four members.
The meaning of bits 3-0 is similar to that of MMC1.

    7654 3210
    | || ||++- Nametable arrangement
    | || ||    0: AAAA (single screen)
    | || ||    2: ABAB (horizontal arrangement or vertical mirroring)
    | || ||    3: AABB (vertical arrangement or horizontal mirroring)
    | || ++--- PRG ROM bank style
    | ||       0: 32 KiB banks
    | ||       2: 16 KiB banks, $8000-$BFFF fixed to first bank
    | ||       3: 16 KiB banks, $C000-$FFFF fixed to last bank
    | ++------ PRG ROM size
    |          0: 32 KiB; 1: 64 KiB; 2: 128 KiB; 3: 256 KiB
    +--------- Starting register
               0: CHR ROM bank (CNROM); 1: PRG ROM bank (other)

Page directory
--------------
The menu is divided into several pages.

* 1 byte: Number of pages
* n bytes: For each page, the last index of activities plus 1.
* NUL-terminated string: Title of first page
* NUL-terminated string: Title of second page
* etc.

The first page is assumed to start at index 0,
subsequent pages start at n-1 of "last index" list.

The encoding of page titles and all other text in Action 53
is an ASCII superset defined by `a53charset.py`.

Activity names
--------------
Each activity's name consists of a title, a newline ($0A), the name
of the author, and a NUL terminator ($00).  To find the address of an
activity name, add the offset in the activity directory to the start
address of the activity names block.

The title can be up to 128 pixels long as defined in `vwf7.png`,
or about 28 characters.  Because the year of first publication
precedes the author's name, it can be only 101 pixels long.

Descriptions
------------
Each activity's description is up to 16 lines of up to 128 pixels.
As with title and author, $0A separates lines, and $00 ends the
description.  Addresses of descriptions are calculated the same way
as title addresses, except that the description block can be stored
in a PRG bank other than the last.

Unlike title and author, descriptions may be compressed using digram
tree encoding (DTE) using a replacement table of up to 256 bytes.
Decompression replaces each byte of compressed text from $80 through
$FF with the corresponding pair of bytes in the replacement table.
The "tree" in DTE means that the replacement table is recursive:
entries refer to literal code units or to previous entries.
(If `DTE_MIN_CODEUNIT` exceeds 128, decompression ignores the first
`DTE_MIN_CODEUNIT - 128` entries of the table and instead copies
DTE bytes from $80 through `DTE_MIN_CODEUNIT - 1` literally.)

Title screen
-------------
This is similar to the "sb53" format also used in the NES port of
240p Test Suite, except that PB53 is replaced with Donut.

* 1 byte: Number of distinct tiles, with $00 meaning 256
* Variable: Donut compressed tile data
* Variable: Donut compressed nametable; decompresses to 960
  bytes of tilemap and 64 bytes of color attributes
* 16 bytes: Palette

Title strings
-------------
Text drawn on the title screen as text compresses better than
text drawn as pixels into the sb53 data.  This is used for
gift messages, copyright notices, and the like.

* 1 byte: Color code (bits 7-5) and Y position in tiles (bits 4-0)
* 1 byte: X position (in pixels)
* NUL-terminated string

Y positions 0-2 are above the 80% safe area on NTSC, and 27-29
are below it.  Y positions 30 and 31 are invalid.  A byte with
such a position, such as $FF, terminates the list.

Color codes are all combinations of 2 colors where the foreground
color is 1 bit different from the background color.

* $00: 1 on 0
* $20: 3 on 2
* $40: 0 on 1
* $60: 2 on 3
* $80: 2 on 0
* $A0: 3 on 1
* $C0: 0 on 2
* $E0: 1 on 3

This can also be interpreted as a bit field:

    7654 3210
    |||+-++++- Y position
    ||+------- Value of plane not containing text. 0: $00; 1: $FF
    |+-------- 1: Invert plane containing text
    +--------- Bit plane containing text. 0: bit 0; 1: bit 1

Credits
-------
This document is under the same license as the Action 53 builder:

Copyright 2018 Damian Yerrick

Copying and distribution of this file, with or without
modification, are permitted in any medium without royalty provided
the copyright notice and this notice are preserved in all source
code copies.  This file is offered as-is, without any warranty.
