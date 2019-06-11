#
# Linker script for Action 53
# Copyright 2010-2012 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#
MEMORY {
  # Does not add an iNES header.  That will be added by the menu builder
  # (tools/a53build.py).
  ZP:       start = $10, size = $f0, type = rw;
  # use first $10 zeropage locations as locals
  RAM:      start = $0300, size = $0500, type = rw;
  ROM63:    start = $8000, size = $8000, type = ro, file = %O, fill=yes, fillval=$FF;
}

SEGMENTS {
  ZEROPAGE:   load = ZP, type = zp;
  BSS:        load = RAM, type = bss, define = yes, align = $100;
  KEYBLOCK:   load = ROM63, type = ro, start = $8000, optional=yes;
  BFF0:       load = ROM63, type = ro, start = $BFF0;
  PAGERODATA: load = ROM63, type = ro, align = $100;
  CODE:       load = ROM63, type = ro;
  LOWCODE:    load = ROM63, run = RAM, type = rw, define = yes;
  RODATA:     load = ROM63, type = ro;
  FFF0:       load = ROM63, type = ro, start = $FFF0;
}

FILES {
  %O: format = bin;
}

