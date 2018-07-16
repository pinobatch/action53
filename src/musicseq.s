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

THINK = 0

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
.if THINK
  .byt $05, 1, $00, 0, 0 ; trumpet
  .byt $45, 5, $00, 0, 0  ; acoustic guitar
  .byt $45, 1, $00, 0, 0  ; sax
  .byt $86, 12, $80, 0, 0  ; bloop (organ hits)
.endif

pently_songs:
  .addr thinkintro_conductor
.if THINK
  .addr think_conductor
.endif

pently_patterns:
  ; pattern 0: think (about it)
  .addr think_drums_yeahwhoot
  .addr think_pedalbass
.if THINK
  .addr think_B_bass, think_B_sq1, think_B_sq2
  .addr think_A_sq2, think_A_sq1, think_A_bass
  .addr think_backtoB, think_backtoB_drums
  .addr think_drums
.endif

;____________________________________________________________________
; think (about it) theme

thinkintro_conductor:
  setTempo (116*4)
  playPatNoise 0, 0, 0
  playPatTri 1, 12, 0
  waitRows 96
  fine

think_drums_yeahwhoot:
  .byt KICK, DHAT, HAT, DHAT
  .byt SNARE, DHAT, YEAH, LITESNARE
  .byt HAT, LITESNARE, HAT, DHAT
  .byt SNARE, DHAT, WHOOT, DHAT
  .byt 255

think_pedalbass:
  .byt N_C|D_4, REST|D_D2, 255

think_conductor:
.if THINK
  setTempo (116*4)
  playPatNoise 10, 0, 0
  playPatSq2 5, 15, 0
  playPatSq1 6, 27, 1
  playPatTri 7, 3, 0
  waitRows 192
  playPatNoise 0, 0, 0
  playPatTri 2, 3, 0
  playPatSq1 3, 15, 0
  playPatSq2 4, 15, 0
  waitRows 176
  playPatTri 8, 26, 0
  playPatSq1 8, 33, 1
  playPatSq2 8, 38, 1
  playPatNoise 9, 0, 0
  waitRows 16
  dalSegno

think_drums:
  .byt KICK, DHAT, HAT, DHAT
  .byt SNARE, DHAT, HAT, LITESNARE
  .byt HAT, LITESNARE, HAT, DHAT
  .byt SNARE, DHAT, HAT, DHAT
  .byt 255
think_A_bass:
  .byt N_DH|D_8, N_EH|D_8, N_E|D_4, N_DH|D_D8, N_EH|D_8, REST|D_D8
  .byt 255
think_A_sq1:
  .byt INSTRUMENT, 4, N_D, REST|D_8, N_D
  .byt INSTRUMENT, 2, N_B|D_8
  .byt INSTRUMENT, 4, N_D, REST|D_D8, N_D
  .byt INSTRUMENT, 2, N_B, REST|D_8, N_B, REST
  .byt INSTRUMENT, 4, N_D, REST|D_8, N_D
  .byt INSTRUMENT, 2, N_B|D_8
  .byt INSTRUMENT, 4, N_D, REST
  .byt INSTRUMENT, 1, N_EH|D_D8, N_DH|D_4, REST
  .byt 255
think_A_sq2:
  .byt INSTRUMENT, 3, N_E|D_4, N_G|D_4, N_A|D_4, N_B|D_4
  .byt N_DH|D_8, N_EH|D_8, REST|D_4
  .byt INSTRUMENT, 1, N_GSH|D_D8, N_FSH|D_4, REST
  .byt 255
think_B_bass:
  .byt REST|D_1
  .byt N_GH|D_8, REST, N_GH, REST|D_4, N_FH|D_8, N_GH|D_8, N_G|D_D8, REST
  .byt 255
think_B_sq1:
  .byt REST|D_1
  .byt INSTRUMENT, 1, N_D|D_8, REST, N_D, REST|D_4
  .byt INSTRUMENT, 2, N_A|D_8, N_AS|D_8, N_B|D_4
  .byt 255
think_B_sq2:
  .byt REST|D_1
  .byt INSTRUMENT, 1, N_B|D_8, REST, N_B, REST|D_4
  .byt INSTRUMENT, 2, N_CH|D_8, N_CSH|D_8, N_DH|D_4
  .byt 255
think_backtoB:
  .byt N_C, REST, N_C, REST, N_C, REST, N_C, REST
  .byt N_C, REST, N_C, REST, N_C, REST|D_D8, 255
think_backtoB_drums:
  .byt KICK|D_4, KICK|D_4
  .byt SNARE|D_8, SNARE|D_8, SNARE|D_D8, LITESNARE
  .byt 255
.endif

