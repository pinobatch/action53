.include "global.inc"

.segment "LOWCODE"
.proc start_game
  ldy #TITLE_PRG_BANK
  lda (start_bankptr),y
  sta (start_bankptr),y

  ; Now the outer bank and reset vector are correct, and the mapper
  ; configuration has been saved in a variable.  Now interpret the
  ; mapper configuration in reg $80 format:
  ; 76543210
  ; | ||||||
  ; | ||||++- Nametable mirroring (0=AAAA, 2=ABAB, 3=AABB)
  ; | ||++--- PRG bank mode (0=32k, 2=fixed $8000, 3=fixed $C000)
  ; | ++----- Game size (0=32k, 1=64k, 2=128k, 3=256k)
  ; +-------- If set, game isn't CNROM
  ; Rules for setting final reg in $5000:
  ; If CNROM, and CHR loader supports CNROM, use $00 (CHR bank).
  ; If game is 32K, use $81 (outer PRG bank) so that simple
  ; reset code works.
  ; Otherwise, use $01 (inner PRG bank).

  ldx #$80
  stx $5000
  lda start_mappercfg
  sta $8000
    
  ; Set the inner bank: $00 for fixed-lo or $0F otherwise
  ldy #$01
  sty $5000
  dey
  and #$0C
  cmp #$08
  beq :+
    ldy #$0F
  :
  sty $8000
    
  ; Set the reg that the program writes to.
  ; For CNROM, use $00 (CHR bank)
  ldx #$00
  lda start_mappercfg
  bpl have_regnum_in_x

  ; For games larger than 32K, use $01 (PRG inner bank)
  inx
  and #$30
  bne have_regnum_in_x

  ; Otherwise use $81 (PRG outer bank)
  ldx #$81
have_regnum_in_x:
  stx $5000

  ; and launch.
  jmp (start_entrypoint)
.endproc

.code
;;
; Configures the Action 53 mapper to behave like oversize BNROM.
.proc init_mapper
  ; Set outer bank to last, so that execution continues across
  ; change in mapper mode
  ldx #$81
  stx $5000
  lda #$FF
  sta $8000

  ; Set mapper mode to 32k outer, 32k inner, vertical mirroring
  lda #$80
  sta $5000
  lda #$02
  sta $8000

  ; Finally, set the current register to outer bank
  stx $5000
  rts
.endproc
