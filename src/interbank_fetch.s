;
; Fetch bytes from another bank
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
; Separated out from unpb53.s

.export interbank_fetch, interbank_fetch_buf

.segment "BSS"
; The largest thing we'll fetch out of another bank at once is
; the compressed data for 10 tiles, and that's no bigger than 180.
interbank_fetch_buf: .res 192

.segment "LOWCODE"
;;
; Copies data from another bank to the interbank fetch buffer
; and returns to bank $FF.
; 0-1: address of the data
; 2-3: address in ROM of the bank number (NOT the bank number itself;
; we need this address to avoid a data bus conflict)
; 4: number of bytes
.proc interbank_fetch
  ldy #0
  lda (2),y  ; must write the bank number to a location
  sta (2),y  ; that already has the bank number
copyloop:
  lda ($00),y
  sta interbank_fetch_buf,y
  iny
  cpy 4
  bne copyloop

  ; That was the easy part.  The hard part is getting back home:
  ; we need to find $FF somewhere in the bank.  Fortunately, we
  ; ordinarily see $FF very early in the reset patch.
  lda #$FF
  cmp $FFFD
  bne ff_not_in_reset
  sta $FFFD
  rts
ff_not_in_reset:
  ldy $FFFC
  sty 2
  ldy $FFFD
  sty 3
  ldy #0
  lda #$FF
homeloop:
  cmp (2),y
  beq found_ff
  iny
  bne homeloop
found_ff:
  sta (2),y
  rts
.endproc

.if 0
; example of use:
  lda #$00
  sta 0
  lda #$80
  sta 1
  sta 4
  lda #<(addr_with_bank+1)
  sta 2
  lda #>(addr_with_bank+1)
addr_with_bank:
  sta 3
  jsr interbank_fetch
.endif
