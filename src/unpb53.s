;
; PB53 unpacker for 6502 systems
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.export unpb53_some, PB53_outbuf
.export unpb53_block_ay, unpb53_block
.export interbank_fetch, interbank_fetch_buf
.exportzp ciSrc, ciDst, ciBufStart, ciBufEnd

.segment "ZEROPAGE"
ciSrc: .res 2
ciDst: .res 2
ciBufStart: .res 1
ciBufEnd: .res 1
PB53_outbuf = $0100

; the decompressor is less than 176 bytes, useful for loading into
; RAM with a trampoline
.segment "CODE"
.proc unpb53_some
ctrlbyte = 0
bytesLeft = 1
  ldx ciBufStart
loop:
  ldy #0
  lda (ciSrc),y
  inc ciSrc
  bne :+
  inc ciSrc+1
:
  cmp #$82
  bcc twoPlanes
  beq copyLastTile
  cmp #$84
  bcs solidColor

  ; at this point we're copying from the first stream to this one
  ; assuming that we're decoding two streams in parallel and the
  ; first stream's decompression buffer is PB53_outbuf[0:ciBufStart]
  txa
  sec
  sbc ciBufStart
  tay
copyTile_ytox:
  lda #16
  sta bytesLeft
prevStreamLoop:
  lda PB53_outbuf,y
  sta PB53_outbuf,x
  inx
  iny
  dec bytesLeft
  bne prevStreamLoop
tileDone:
  cpx ciBufEnd
  bcc loop
  rts

copyLastTile:
  txa
  cmp ciBufStart
  bne notAtStart
  lda ciBufEnd
notAtStart:
  sec
  sbc #16
  tay
  jmp copyTile_ytox

solidColor:
  pha
  jsr solidPlane
  pla
  lsr a
  jsr solidPlane
  jmp tileDone
  
twoPlanes:
  jsr onePlane
  ldy #0
  lda (ciSrc),y
  inc ciSrc
  bne :+
  inc ciSrc+1
:
  cmp #$82
  bcs copyPlane0to1
  jsr onePlane
  jmp tileDone

copyPlane0to1:
  ldy #8
  and #$01
  beq noInvertPlane0
  lda #$FF
noInvertPlane0:
  sta ctrlbyte
copyPlaneLoop:
  lda a:PB53_outbuf-8,x
  eor ctrlbyte
  sta PB53_outbuf,x
  inx
  dey
  bne copyPlaneLoop
  jmp tileDone

onePlane:
  ora #$00
  bpl pb8Plane
solidPlane:
  ldy #8
  and #$01
  beq solidLoop
  lda #$FF
solidLoop:
  sta PB53_outbuf,x
  inx
  dey
  bne solidLoop
  rts

pb8Plane:
  sec
  rol a
  sta ctrlbyte
  lda #$00
pb8loop:

  ; at this point:
  ; A: previous byte in this plane
  ; C = 0: copy byte from bitstream
  ; C = 1: repeat previous byte
  bcs noNewByte
  lda (ciSrc),y
  iny
noNewByte:
  sta PB53_outbuf,x
  inx
  asl ctrlbyte
  bne pb8loop
  clc
  tya
  adc ciSrc
  sta ciSrc
  bcc :+
  inc ciSrc+1
:
  rts
.endproc

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

.global draw_progress
;;
; decompress X*16 bytes starting at AAYY to PPUDATA
.proc unpb53_block_ay
  sty ciSrc
  sta ciSrc+1
.endproc
.proc unpb53_block
  stx draw_progress
  lda #16
  sta ciBufEnd
  lda #0
  sta ciBufStart
loop:
  jsr unpb53_some
  ldx #0
copyloop:
  lda PB53_outbuf,x
  sta $2007
  inx
  cpx #16
  bcc copyloop
  dec draw_progress
  bne loop
  rts
.endproc

