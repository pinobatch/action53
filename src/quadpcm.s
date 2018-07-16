.include "nes.inc"
.importzp ciBufEnd, ciSrc
ciBlocksLeft = ciBufEnd
.export quadpcm_test, quadpcm_playPages

.segment "CODE"
.align 128
.proc quadpcm_playPages
ciBits = 2
thisSample = 3
lastSample = 4
deEss = 5
  lda #64
  sta thisSample
  sta lastSample

nextPage:
  ; start page
  ldy #0
  lda (ciSrc),y
  sta deEss
  inc ciSrc
  ; waste some time  
  ldx #3
pageWaste:
  dex
  bne pageWaste
  lda $0100

playByte:
  ; Fetch byte
  ldy #0
  lda (ciSrc),y
  inc ciSrc
  sta ciBits
  and #$0F
  jsr decode1
  ; waste time between samples
  ldx #11
midByteWaste:
  dex
  bne midByteWaste
  lda ciBits
  ; Fetch upper nibble
  lda ciBits
  lsr a
  lsr a
  lsr a
  lsr a
  jsr decode1
  ; next byte
  lda ciSrc
  bne notWrap
  ; go to next page
  inc ciSrc+1
  dec ciBlocksLeft
  bne nextPage
  rts
notWrap:
  ; waste some time
  ldx ciBits
  ldx #8
notWrapDelay:
  dex
  bne notWrapDelay
  jmp playByte

decode1:
  ; decode sample
  tax
  lda quadpcm_deltas,x
  clc
  adc lastSample
  and #$7F
  sta thisSample
  ; interpolation
  clc
  adc lastSample
  lsr a
  eor deEss
  sta $4011
  ; end sample period
  ldx #19
endPeriodWait:
  dex
  bne endPeriodWait
  lda (ciSrc,x)
  lda thisSample
  sta lastSample
  sta $4011
  rts
.endproc

.proc quadpcm_test
  lda #<selnow_qdp
  sta ciSrc
  lda #>selnow_qdp
  sta ciSrc+1
  lda #>(selnow_qdp_end - selnow_qdp)
  sta ciBlocksLeft
  jmp quadpcm_playPages
.endproc

.segment "PAGERODATA"
.align 256
.if 0
testdata:
.repeat 2, I
  .repeat 2
    .byt I*$7F
    .repeat 85
      .byt $04,$C0,$00
    .endrepeat
  .endrepeat
  .repeat 2
    .byt I*$7F
    .byt $04,$C0,$00
    .repeat 63
      .byt $04,$00,$0C,$00
    .endrepeat
  .endrepeat
  .repeat 2
    .byt I*$7F
    .repeat 51
      .byt $04,$00,$C0,$00,$00
    .endrepeat
  .endrepeat
.endrepeat
.endif

selnow_qdp:
  .incbin "obj/nes/selnow.qdp"
selnow_qdp_end:

.rodata
.align 16
quadpcm_deltas:
  .byt 0,1,4,9,16,25,36,49
  .byt 64,<-49,<-36,<-25,<-16,<-9,<-4,<-1

