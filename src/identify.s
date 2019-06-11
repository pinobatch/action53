;
; Identify controllers based on which lines are 0, 1, or serial
;
; Copyright 2016 Damian Yerrick
;
; This software is provided 'as-is', without any express or implied
; warranty.  In no event will the authors be held liable for any damages
; arising from the use of this software.
;
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
;
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software
;    in a product, an acknowledgment in the product documentation would be
;    appreciated but is not required.
; 2. Altered source versions must be plainly marked as such, and must not be
;    misrepresented as being the original software.
; 3. This notice may not be removed or altered from any source distribution.
;
.include "nes.inc"
.include "global.inc"
.import wait36k

.segment "BSS"
detected_pads: .res 1
min4016: .res 1  ; Bitwise minimum of $4016 values over 32 reads
max4016: .res 1  ; Bitwise maximum of $4016 values over 32 reads
min4017: .res 1  ; Bitwise minimum of $4017 values over 32 reads
max4017: .res 1  ; Bitwise maximum of $4017 values over 32 reads

.segment "RODATA"
one_shl_x: .byte $01, $02, $04, $08, $10, $20, $40, $80

.segment "CODE"

.proc identify_controllers
reads9to16 = $02
reads17to24 = $03

  ; Identify which lines are constant 0, constant 1, or serial.
  ; Do this on a blank screen so that the Zapper can be detected
  ; as trigger off (D4=0) and dark (D3=1).
  ldx #1
  stx $4016
  ldy #32  ; allow up to 32 bits of serial
  dex
  stx max4016
  stx max4017
  stx detected_pads
  stx $4016
  dex
  stx min4016
  stx min4017

  loop401x:  ; 53 cycles per iteration
    lda $4016
    tax
    and min4016
    sta min4016
    txa
    ora max4016
    sta max4016
    lda $4017
    tax
    and min4017
    sta min4017
    txa
    ora max4017
    sta max4017
    dey
    bne loop401x

  ; Look for a Zapper in port 2
  lda min4017
  eor max4017  ; A = which bits of port 2 are serial
  and #$18     ; The NES Zapper isn't serial.
  bne not_zapper
  lda max4017
  and #$18
  cmp #$08
  bne not_zapper
    ora detected_pads
    sta detected_pads
  not_zapper:

  ; Look for a Super NES Mouse in port 1
  lda min4016
  eor max4016  ; A = which bits of port 2 are serial
  and #$01
  beq not_snes_mouse  ; D0 must be serial

  ; Wait and reread signature bits (13 to 16 should be 0001 for a mouse)
  jsr wait36k
  lda #1
  sta $4016
  sta reads9to16
  lsr a
  sta $4016

  ; Ignore first 8 reads from port 1
  ldy #8
  loop1to8:
    lda $4016
    dey
    bne loop1to8

  ; Save next 8 reads from port 1 bit 0
  loop9to16:
    lda $4016
    lsr a
    rol reads9to16
    bcc loop9to16

  ; 9-16 and $0F = $01 and responds to speed changes: Super NES Mouse
  lda reads9to16
  and #$0F
  cmp #$01
  bne not_snes_mouse
    ; lda #$01  ; Mouse signature coincidentally matches desired bitmask
    ldx #0  ; Port 1
    jsr ident_mouse
    ora detected_pads
    sta detected_pads
  not_snes_mouse:
  rts
.endproc

;;
; Ensures the Super NES Mouse's sensitivity (report bits 11 and 12)
; can be set to 1 then 0.
; @param X port ID (0: $4016; 1: $4017)
; @param A bit mask ($01: D0; $02: D1)
; @return A = DETECT_1P_MOUSE for mouse or 0 for no mouse
.proc ident_mouse
portid = $00
bitmask = $01
targetspeed = $04
triesleft = $05
  stx portid
  sta bitmask
  lda #1
  sta targetspeed

  targetloop:
    lda #4
    sta triesleft

    tryloop:
      ; To change the speed, send a clock while strobe is on,
      ldy #1
      sty $4016
      lda $4016,x
      dey
      sty $4016

      ; Wait and strobe the mouse normally, then skip bits 1-10
      jsr wait36k
      ldx portid
      ldy #1
      sty $4016
      dey
      sty $4016
      ldy #10
      skip10loop:
        lda $4016,x
        dey
        bne skip10loop

      ; Now read bits 11 and 12
      ldy #0
      lda $4016,x
      and bitmask
      beq :+
        ldy #2
      :
      lda $4016,x
      and bitmask
      beq :+
        iny
      :
      cpy targetspeed
      beq try_success
      dec triesleft
      bne tryloop
    lda #0
    rts

  try_success:
    dec targetspeed
    bpl targetloop

  ; Setting to both 0 and 1 was successful.
  lda #DETECT_1P_MOUSE
  rts
.endproc
