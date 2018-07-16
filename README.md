Action 53
=========

The Action 53 ROM builder chews up a bunch of ROMs and spits out a
multicart.

Overview
--------
The menu has up to five pages, each represented by a tab at the top
of the screen, and each page may have up to 20 activities.  From this
list, the player can view a more detailed description including basic
play instructions.

For each ROM added to the collection, the ROM builder patches each
bank with a small piece of code that allows the activity to reset
back to the menu.  NROM games use one of two patches: a 10-byte one
that fits at $BFF0-$BFF9 or $FFF0-$FFF9, or a 20-byte one that fits
anywhere in the PRG bank.  (Larger games use more involved patches
that change more of the mapper's state.)  Then it stores the ROM's
PRG data, its CHR data compressed with PB53, and information used
by the extractor to reverse the reset patch.

The config file may specify ranges of addresses within $8000-$FFFF
that are not used by the ROM.  The reset patch is placed here, and
other programs' CHR ROM and screenshot tile data may be placed here.
For an NROM-128 program, this unused area automatically includes the
half of $8000-$BFFF where the reset vector does not point.

For each activity, the builder stores information needed to
display it in the menu:  title, author, year of publication, number
of players, a description with up to 16 lines of play instructions,
and a screenshot as defined below.  It also stores information
needed to start the activity after the user has chosen it: which PRG
and CHR banks it uses and where in the program to start running.

A ROM may have multiple entry points within one PRG bank, one for
each activity.  This allows a ROM with multiple separate activities
to become several items in the menu.  Examples of these from the
commercial NES library include _Duck Hunt_ ("Duck Hunt" and "Clay
Shooting") and _Donkey Kong Classics_ ("Donkey Kong" and
"Donkey Kong Jr.").  In fact, packing activities into "submultis",
or ROMs with multiple activities sharing a PRG bank, is the most
efficient way to fit a large number of activities into a collection.
If no entry point is specified, the builder uses the reset vector
from the ROM.

A ROM may have multiple CHR banks.  If you specify one, the menu will
load it into CHR RAM before launching your activity.  Some developers
have used defective startup code that tries to clear the nametables
($2000-$27FF), but it loops too much and ends up clearing the pattern
tables too, so don't do that.  The builder provides a patching
mechanism that allows the config file to fix minor bugs, such as
scribbling over the pattern tables, switching CHR banks, or a wrong
version number.

ROM requirements
----------------
The builder produces a ROM, usually 128 to 2048 KiB.  It can be
configured to use an extended-BNROM mapper (iNES #34) with vertical
mirroring or a custom Action 53 mapper (iNES #28).  Each ROM inserted
into a BNROM collection:

* MUST work with vertical mirroring.
* MUST initialize all hardware and memory needed to run from each
  activity's declared entry point.
* MUST NOT write to $8000-$FFFF after the declared entry point.
* MUST NOT blindly overwrite CHR data if using CHR ROM.
* MUST declare an unused range of the ROM to hold the reset patch
  if the PRG ROM is at least 32768 bytes.
* MUST NOT play samples if the PRG ROM is 16384 bytes or smaller
  and has a reset vector in $8000-$BFFF.

Most of these restrictions are lifted for collections using the
Action 53 mapper, which may use common discrete mappers: UNROM
(iNES #2 or #180), CNROM (iNES #3), AOROM (iNES #7), or BNROM.
But if a game actually uses CNROM, as opposed to being a submulti
with a separate CHR ROM bank for each activity, the cartridge will
need to have 32 KiB of CHR RAM instead of 8 KiB.

Preparing graphics
------------------
A collection needs a title screen and a screenshot for each activity.

The title screen is 30 rows of 32 tiles, each 8 by 8 pixels.
A picture can use up to 256 different tiles. Each 2 by 2 tile
(16 by 16 pixel) area can use one of four color sets in the palette.
Each color set has three colors plus a shared backdrop color.

To save ROM space, text may be overlaid on top of the title screen.
Each 8x8-pixel area covered by text reduces available tiles by 1.
For example, three 128-pixel lines of text take 16 tiles each,
leaving 208 for graphics.

The title screen's palette is specified with a 32-nibble string
representing a hex dump of NES palette memory ($3F00-$3F0F).
The following example specifies a black ($0F) backdrop, color set 0
as grays ($00, $10, $20), color set 1 as reds ($06, $16, $26),
color set 2 as greens ($0A, $1A, $2A), and color set 3 as blues
($02, $12, $22).  By convention, the ignored bytes match the
backdrop color.

    0F0010200F0616260F0A1A2A0F021222
    ||||||||||||||||||||||||||++++++- Color set 3
    ||||||||||||||||||||||||++------- Ignored
    ||||||||||||||||||++++++--------- Color set 2
    ||||||||||||||||++--------------- Ignored
    ||||||||||++++++----------------- Color set 1
    ||||||||++----------------------- Ignored
    ||++++++------------------------- Color set 0
    ++------------------------------- Backdrop color

An activity's screenshot is 7 rows of 8 tiles, each 8 by 8 pixels.
Each tile can use one of two color sets in the palette.  Each color
set has three colors plus four grays ($0F, $00, $10, and $20).
If a screenshot fails to meet this restriction, the builder will
fail and print a diagnostic.  If no screenshot is assigned to an
activity, the builder assigns a fallback image:
`../tilesets/screenshots/default.png`

Prerequisites
-------------
To build a collection, you'll need Python 3 and Pillow (Python
Imaging Library).  To rebuild the menu itself, you'll also need
GNU Make, GNU Coreutils, cc65, and optionally the SoX audio
converter.  Instructions to install most of this are at
https://github.com/pinobatch/nrom-template

Use
---
After you've installed Python and Pillow, make a config file
and put it in a folder with your ROMs.  Then run this command,
specifying the filename of the config file and ROM file:

    tools/a53build.py example.cfg example.nes

If no fatal errors occurred, a53games.nes should appear in the
top level folder.

**Warning: The following mechanism is broken.**  
The package also includes a tool to extract ROMs from the collection.
If you have an a53games.nes file, you can extract ROMs, screenshots,
and the skeleton of a.cfg file by running a53extract.py.  Thus, a
collection is an "aggregate" under the GNU General Public License
in the same way that a bootable disc image is.  One caveat is that
the only prgunused entries in the resulting configuration file
correspond to the reset patches.

The configuration file
----------------------
The configuration file uses a name-value pair syntax similar to that
of .ini files but allowing multiple-line values.  See the docstring
at the top of tools/innie.py for detailed syntax information.

A sample config file with one activity follows:

    # BEGIN example.cfg
    
    [title]
    titlescreen=title_screen.png
    titlepalette=0f0010200f1616160f1616160f161616
    
    text=Hi Mom!
    at=64,192
    color=2,0
    
    [games]
    page=Platform
    title=Wrecking Ball Boy
    author=Justin Bailey
    year=2011
    description:
    Use your grappling hook
    to swing over gaps and
    through obstacles.

    + Move
    A: Fire or retract
      grappling hook
    .
    players=1-2 alt
    screenshot=screenshots/Wrecking Ball Boy.png
    rom=roms/Wrecking Ball Boy.nes
    prgunused3=f700-fff9

    # END example.cfg

Let's take that apart, with comments this time:

    [title]

Commands related to the title screen must appear in this section.

    titlescreen=../tilesets/title_screen.png

The title screen is a 256x240 pixel image as described above.
This and other paths are relative to the directory containing
the config file.

    titlepalette=0f0010200f1616160f1616160f161616

Sets the palette for converting the title screen to an NES
background image.
    
    text=Hi Mom!

Adds a line of text.  Multiple-line values are allowed, but
behavior is undefined if any line is longer than 128 pixels,
which is about 28 characters.

    at=64,192

Sets the top left X,Y coordinate for the latest line of text.
X is pixel precise, but Y is rounded down to a multiple of 8.

    color=2,0

Sets the foreground color for the latest line of text to color 2
and the background color to 0.  One of the colors must be 0 or 3,
and the other must be 1 or 2.  They appear with whatever attribute
was already at that position in the PNG.

    [games]

Commands related to activities must appear in this section.

    page=Platform

Begins a new page called "Platform".  The page need only
be specified once, before the first activity on the page.
If you try to put more than 20 activities on a page, the
builder will print a diagnostic.

    title=Wrecking Ball Boy

Begins a new activity with this name.

    author=Justin Bailey

The author or copyright owner of the activity.

    year=2011

The year in which the activity was first published.

    description:
    Use your grappling hook
    to swing over gaps and
    through obstacles.

    + Move
    A: Fire or retract
      grappling hook
    .

Up to 16 lines, each about 25 to 28 characters, describing
the basics of how to play a game.
A colon instead of an equal sign starts a multiple-line value,
and a dot on its own line ends it.  The first dot on any line is
stripped off.  (This escaping method is the same used in SMTP.)

    players=1-2 alt

How many players can play at once.  Acceptable values are
`1`, `2`, `1-2`, `1-2 alt`, `1-3`, `1-4`, `2-4 alt`, `2-6 alt`, and
`2-4`.  `2` means the game is for two players only, like
"Fire Breathers" from _Action 52_.  If omitted, uses `1`.

    screenshot=screenshots/Wrecking Ball Boy.png

A 64x56 pixel screenshot of the activity as described above.

    rom=roms/Wrecking Ball Boy.nes

The path to the ROM containing the activity.

    prgunused3=f700-fff9

Ranges of bytes in the PRG bank that are unused.  The builder will
usually place an exit patch here and may fill these with CHR data,
screenshots, etc.  This MUST be specified for any 32 KiB or bigger
PRG ROM, but it need only be specified in one activity within each
bank of the PRG ROM.

The following are useful primarily for submultis, or ROMs containing
more than one activity:

    mapmode=AE

Advanced: Overrides the detected mapper with a mapper configuration
code. Bit 7 is 0 for CNROM or 1 for other, bits 5-4 control the
game's PRG ROM size (32, 64, 128, or 256 KiB), and bits 3-0 have
nearly the same meaning as on MMC1's control register.
Useful primarily for submultis.

    prgbank=0

Which 32 KiB PRG bank within the PRG ROM is associated with an
activity.  If omitted, uses the first bank for fixed-$8000 (such as
UNROM configured as mapper 180) or the last bank for other mappers.

    chrbank=0

Which 8 KiB bank is associated with an activity.
If omitted, uses the first bank (0).

    entrypoint=C000

Where the activity's code starts if the PRG bank's reset vector
doesn't point there.

    patch3=C03C:F0

One-line fixes to make an activity boot correctly.  These
apply to all activities in one PRG ROM.

    exitmethod=unrom
    exitmethod=none

These control how the game is patched to jump to the menu when
Reset is pressed.  If your game has a menu option to exit, use
`none`; otherwise, the valid options are `nrom`, `unrom`, `cnrom`,
`aorom`, `unrom`, and `unrom180`.

    exitpoint=FF00

Sets the reset vector to $FF00 instead of automatically patching the
ROM to exit to the menu.  Use this if an activity has an `entrypoint`
and is already patched to exit to the main menu on Reset.

Questions
---------
Q. I've added a header to a53menu.prg.  Why does it just hang?

This file contains the code for the menu.  It contains no activities
and thus will not work unless activities are added using a53build.py.

Q. How do I use a collection with more than a dozen or so ROMs
on a PowerPak?

The PowerPak has only enough RAM to simulate 512 KiB of PRG ROM.
You'll need to rebuild some of your activities into submultis and
split your collection into smaller collections.  Action 53 volume 3
(2017), for example, had to be played with two.

Q. How do I play games that use two Zappers?

The menu supports a Zapper in port 2 or a standard controller or
Super NES Mouse in port 1.  PowerPak users can use controller 1 to
navigate to Action 53, swap to the desired controller at the title
screen, press Reset to get the NES to recognize the newly connected
controller, and then use the menu.

Q. Why can't I use [x] controller for the menu?

The vast majority of the menu program is the work of one person,
and he has an NES, not a Famicom.  To get a new NES controller
supported in the menu, make a homebrew game supporting both that
controller and the standard controller, and notify forums.nesdev.com
that you want that game included.

Legal
-----
This manual, as well as the menu and builder, are distributed under
the following terms:

Copyright 2012-2018 Damian Yerrick

Copying and distribution of this file, with or without
modification, are permitted in any medium without royalty provided
the copyright notice and this notice are preserved in all source
code copies.  This file is offered as-is, without any warranty.

(End of terms)

This product is not endorsed by Nintendo or Active Enterprises.
