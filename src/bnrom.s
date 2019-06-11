.include "global.inc"
.segment "LOWCODE"
.proc start_game
  ldy #TITLE_PRG_BANK
  lda (start_bankptr),y
  sta (start_bankptr),y
  jmp (start_entrypoint)
.endproc

.segment "CODE"
.proc init_mapper
  rts
.endproc
