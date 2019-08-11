.include "nes.inc"
.importzp ciBufEnd, ciSrc
ciBlocksLeft = ciBufEnd
.export quadpcm_test, quadpcm_playPages

.segment "CODE"
.proc quadpcm_playPages
y_start = 2
thisSample = 3
lastSample = 4
deEss = 5
  sty y_start
  sta ciSrc+1
  inx
  stx ciBlocksLeft
  lda #$00
  sta ciSrc+0
  lda #64
  sta thisSample
  sta lastSample

next_page:
  dec ciBlocksLeft
  beq return
  jsr read_ciSrc
  sta deEss

wait_20c:
  nop
  nop
  ldx #3
wait_20c_loop:
  dex
  bne wait_20c_loop

play_byte:
  lda (ciSrc),y       ; read but don't increment
  and #$0F
  jsr decode_samples

wait_35c:
  nop
  nop
  ldx #6
wait_35c_loop:
  dex
  bne wait_35c_loop

  jsr read_ciSrc
  ; Fetch upper nibble
  lsr a
  lsr a
  lsr a
  lsr a
  jsr decode_samples

  cpy y_start
  beq next_page

wait_55c:
  nop
  nop
  ldx #10
wait_55c_loop:
  dex
  bne wait_55c_loop

  jmp play_byte

read_ciSrc:
  lda (ciSrc),y
  iny
  ; if Z = 0, 2+2+4 cycles
  ; if Z = 1, 3+5 cycles
  beq inc_ciSrc_hi
  nop
  .byte $2c       ; bit opcode to skip next instruction
inc_ciSrc_hi:
  inc ciSrc+1
return:
  rts

decode_samples:
  tax
  lda quadpcm_deltas,x
  clc
  adc lastSample
  and #$7F
  sta thisSample
interpolate:
  clc
  adc lastSample
  lsr a
  eor deEss
output_samples:
  sta $4011       ; 112 cycles between output samples ~= 15980 hz
; end sample period
wait_102c:
  ldx #19
wait_102c_loop:
  dex
  bne wait_102c_loop
  lda (ciSrc,x)

  lda thisSample
  sta lastSample
  sta $4011       ; 112 cycles between output samples ~= 15980 hz
  rts
.endproc
.assert >quadpcm_playPages = >*, error, "quadpcm_playPages crosses page boundary"

.proc quadpcm_test
  ldy #<selnow_qdp
  lda #>selnow_qdp
  ldx #>(selnow_qdp_end - selnow_qdp)
  jmp quadpcm_playPages
.endproc

.segment "PAGERODATA"
selnow_qdp:
  .incbin "obj/nes/selnow.qdp"
selnow_qdp_end:

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

.segment "RODATA"
quadpcm_deltas:
  .byt 0,1,4,9,16,25,36,49
  .byt 64,<-49,<-36,<-25,<-16,<-9,<-4,<-1
.assert >quadpcm_deltas = >*, error, "quadpcm_deltas crosses page boundary"
