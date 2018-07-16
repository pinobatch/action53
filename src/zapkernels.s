;
; Zapper reading kernels (NTSC)
; Copyright 2011 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
; 2012-02-04: Removed xyon and yon2p kernels, used by Zap Ruder but
;             not by the a53 menu
;
.include "nes.inc"

; $4017.D4: Trigger switch (1: pressed)
; $4017.D3: Light detector (0: bright)
;
; One kernel is included in this version:
; NTSC single player (X, Y) kernel

.export zapkernel_yonoff_ntsc

.align 128
;;
; @param Y number of scanlines to watch
; @return 0: number of lines off, 1: number of lines on
.proc zapkernel_yonoff_ntsc
off_lines = 0
on_lines = 1
subcycle = 2
DEBUG_THIS = 0
  lda #0
  sta off_lines
  sta on_lines
  sta subcycle

; Wait for photosensor to turn ON
lineloop_on:
  ; 8
  lda #$08
  and $4017
  beq hit_on

  ; 72
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12

  ; 11
  lda off_lines
  and #LIGHTGRAY
  ora #BG_ON|OBJ_ON
.if DEBUG_THIS
  sta PPUMASK
.else
  bit $0100
.endif

  ; 12.67
  clc
  lda subcycle
  adc #$AA
  sta subcycle
  bcs :+
:

  ; 10
  inc off_lines
  dey
  bne lineloop_on
  jmp bail

; Wait for photosensor to turn ON
lineloop_off:
  ; 8
  lda #$08
  and $4017
  bne hit_off

hit_on:
  ; 72
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12
  jsr waste_12

  ; 11
  lda off_lines
  and #LIGHTGRAY
  ora #BG_ON|OBJ_ON
.if DEBUG_THIS
  sta PPUMASK
.else
  bit $0100
.endif

  ; 12.67
  clc
  lda subcycle
  adc #$AA
  sta subcycle
  bcs :+
:

  ; 10
  inc on_lines
  dey
  bne lineloop_off

hit_off:
bail:
waste_12:
  rts
.endproc
