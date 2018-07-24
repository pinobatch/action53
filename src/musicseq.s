;
; Music sequence data for Action 53 menu
; Copyright 2010 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
; Translation: Go ahead and make your ReMixes, but credit me.

.include "pentlyseq.inc"

.segment "RODATA"
pently_sfx_table:
  .addr snare2_snd
  .byt 0, 6
  .addr kick2_snd
  .byt 8, 4
  .addr snare_snd
  .byt 12, 8
  .addr snare2_snd
  .byt 0+16*1, 6
  .addr hihat_snd
  .byt 12, 6
  .addr delayhat_snd
  .byt 14, 7
  .addr yeah_snd
  .byt 0, 9
  .addr whoot_hi_snd
  .byt 8, 15
  .addr lite_snare_snd
  .byt 12, 6

; alternating duty/volume and pitch bytes

kick2_snd:
  .byt $8F,27, $8F,25, $8F,22, $8F,17, $8F,15, $8F,13
snare_snd:
  .byt $0C,$06, $0A,$84, $08,$04
  .byt $06,$84, $05,$04, $04,$05, $03,$05, $02,$05
snare2_snd:
  .byt $44,27, $82,26, $41,26, $81,26, $81,26, $81,26
lite_snare_snd:
  .byt $08,$05, $06,$84
  .byt $06,$03, $04,$83, $03,$03, $02,$83
delayhat_snd:  ; hat + delayhat are supposed to simulate a tambourine?
  .byt $02,$03, $04,$83
hihat_snd:
  .byt $06,$03, $04,$83, $03,$03, $02,$83, $01,$03, $01,$83
yeah_snd:
  .byt $06,33, $09,36, $47,36, $47,36, $46,35, $45,34, $44,32
  .byt $43,30, $42,28
whoot_hi_snd:
  .byt $86,60, $86,62, $86,64, $86,65, $86,66, $86,66, $86,66, $86,66
  .byt $86,66, $86,66, $86,65, $86,65, $86,65, $86,64, $86,64
  
; Each drum consists of one or two sound effects.
pently_drums:
  .byt  1,  4
  .byt  2,  3
  .byt  4,<-1
  .byt  5,<-1
  .byt  4,  6
  .byt  4,  7
  .byt  8,  0
KICK  = 0*8
SNARE = 1*8
HAT = 2*8
DHAT = 3*8
YEAH = 4*8
WHOOT = 5*8
LITESNARE = 6*8

pently_instruments:
  ; first byte: initial duty (0/4/8/c) and volume (1-F)
  ; second byte: volume decrease every 16 frames
  ; third byte:
  ; bit 7: cut note if half a row remains
  .byt $88, 2, $00, 0, 0  ; bass

pently_songs:
  .addr intro_conductor

pently_patterns:
  ; pattern 0: drums
  .addr amen_drums_and_yeah

intro_conductor:
  setTempo (128*4)
  playPatNoise 0, 0, 0
  waitRows 60
  playPatNoise 0, 0, 0
  waitRows 4
  fine

amen_drums_and_yeah:
  .byt KICK, DHAT, KICK, DHAT
  .byt SNARE, DHAT, HAT, SNARE
  .byt HAT, LITESNARE, KICK, KICK
  .byt SNARE, DHAT, YEAH, SNARE
  .byt PATEND
