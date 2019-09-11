#!/usr/bin/make -f
#
# Makefile for Action 53 multicart engine
# Copyright 2012-2018 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#

# These are used in the title of the NES program and the zip file.
title := a53menu
version := 0.06wip2
cfgtitle := demo
othercfgs := # demo
cfgversion := page1

# Space-separated list of assembly language files that make up the
# PRG ROM.  If it gets too long for one line, you can add a backslash
# (the \ character) at the end of the line and continue on the next.
objlist := \
  vwf7 wait_loops vwf_draw quadpcm bcd paldetect zapkernels \
  a53mapper main title cartmenu coredump donut \
  interbank_fetch pads mouse ppuclear identify undte \
  pentlysound pentlymusic checksums

AS65 = ca65
LD65 = ld65
CFLAGS65 := -DDPCM_UNSAFE=1
objdir = obj/nes
srcdir = src
imgdir = tilesets

# Needs FCEUX 2.2.2 or later, or preferably SVN version
EMU := fceux
DEBUGEMU := ~/.wine/drive_c/Program\ Files\ \(x86\)/FCEUX/fceux.exe

# Flags for native tools written in C
CC := gcc
CFLAGS := -std=gnu99 -Wall -Wextra -DNDEBUG -Os

# Windows needs .exe suffixed to the names of executables; UNIX does
# not.  COMSPEC will be set to the name of the shell on Windows and
# not defined on UNIX.  Also the Windows Python installer puts
# py.exe in the path, but not python3.exe, which confuses MSYS Make.
ifdef COMSPEC
DOTEXE:=.exe
PY:=py
else
DOTEXE:=
PY:=
endif

.PHONY: run all debug dist zip 7z clean

run: $(cfgtitle).nes
	$(EMU) $<
debug: $(cfgtitle).nes
	$(DEBUGEMU) $<

tools/donut$(DOTEXE): tools/donut.c
	$(CC) -static $(CFLAGS) -o $@ $^

tools/dte$(DOTEXE): tools/dte.c
	$(CC) -static $(CFLAGS) -o $@ $^

tools/dtefe.py: tools/dte$(DOTEXE)

%.nes: collections/%/a53.cfg $(title).prg tools/a53build.py \
  tools/ines.py tools/innie.py tools/a53charset.py tools/a53screenshot.py \
  tools/dtefe.py tools/donut$(DOTEXE)
	$(PY) tools/a53build.py $< $@

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Actually the zipfile depends on every
# single file in zip.in, but currently we use changes to the compiled
# program, makefile, and README as a heuristic for when something was
# changed.  It won't see changes to docs or tools, but usually when
# docs changes, README also changes, and when tools changes, the
# makefile changes.
dist: zip 7z

zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in all README.md CHANGES.txt $(objdir)/index.txt
	tools/zip12to0.sh -9u $@ -@ < $<

7z: $(cfgtitle)-$(cfgversion).7z
$(cfgtitle)-$(cfgversion).7z: $(cfgtitle).nes $(foreach o,$(othercfgs),$(o).nes)
	7za a $@ $^

all: $(title).prg

clean:
	-rm $(objdir)/*.o $(objdir)/*.sav $(objdir)/*.s $(objdir)/*.chr $(objdir)/*.nam $(objdir)/*.pb53 $(objdir)/*.donut $(objdir)/*.qdp tools/donut$(DOTEXE) tools/dte$(DOTEXE)

$(objdir)/index.txt: makefile
	echo Files produced by build tools go here, but caulk goes where? > $@

# Rules for PRG ROM

objlistntsc := $(foreach o,$(objlist),$(objdir)/$(o).o)

map.txt $(title).prg: lastbank.x $(objlistntsc) $(objdir)/musicseq.o
	$(LD65) -o $(title).prg -m map.txt -C $^

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files depending on extra headers
$(objdir)/main.o $(objdir)/cartmenu.o: $(srcdir)/pentlyconfig.inc
$(objdir)/pentlysound.o $(objdir)/pentlymusic.o: \
  $(srcdir)/pentlyconfig.inc $(objdir)/pentlybss.inc

# Files that depend on .incbin'd files
$(objdir)/cartmenu.o: $(objdir)/select_tiles.chr.donut
$(objdir)/quadpcm.o: $(objdir)/selnow.qdp
$(objdir)/selnow.qdp: tools/quadanalyze.py audio/selnow.wav
	$(PY) $^ $@

# Rules for CHR data

$(objdir)/%.pb53: $(objdir)/%
	$(PY) tools/pb53.py --raw $< $@

$(objdir)/%.donut: $(objdir)/% tools/donut$(DOTEXE)
	tools/donut$(DOTEXE) -fq $< $@

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@

$(objdir)/%16.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py -H 16 $< $@

$(objdir)/%.s: tools/vwfbuild.py tilesets/%.png
	$(PY) $^ $@

# Build RAM map for pently
$(objdir)/pentlybss.inc: tools/pentlybss.py $(srcdir)/pentlyconfig.inc
	$(PY) $^ pentlymusicbase -o $@

# Translate music project
$(objdir)/%.s: tools/pentlyas.py src/%.pently
	$(PY) $^ -o $@ --periods 76
$(objdir)/%-rmarks.s: tools/pentlyas.py src/%.pently
	$(PY) $^ -o $@ --periods 76 --rehearse
