.include "nes.inc"
.include "global.inc"

.code
;;
; Start game: $00 points
.proc start_game
outer_bank_value = $01
clear_ram_ptr = $0E

  ; Fetch outer bank value and save it for later
  ldy #$00
  lda (start_bankptr),y
  sta outer_bank_value

  ; Clear RAM $0100-$01FF and nametables
  lda #$07
  sta clear_ram_ptr+1
  sty clear_ram_ptr
  sty PPUMASK
  sty PPUCTRL
  lda #$20
  sta PPUADDR
  sty PPUADDR
  lda #$FF
  sta $00  ; clear first byte of ZP
  clrnonzploop:
    sta PPUDATA
    sta PPUDATA
    sta ($0E),y
    iny
    bne clrnonzploop
    dec $0F
    bne clrnonzploop

  ; Load trampoline
  ldx #trampoline_code_end - trampoline_code - 3
  copytrampolineloop:
    lda trampoline_code,x
    sta trampoline_entry,x
    dex
    bpl copytrampolineloop
  
  ; Set up trampoline and inner bank
  lda entry_point_lo
  sta trampoline_code_end
  lda entry_point_hi
  sta trampoline_code_end+1

  ; Starting inner PRG bank should be $0F except for mapper 180
  ; where it should be $00.  Bits 3-2 of mapper mode control this.
  lda #$01
  sta $5000
  lda start_mappercfg
  and #$0C
  eor #$08  ; 0: mapper 180; nonzero: mapper 0, 2, 3, 7, 34
  bne :+
    lda #$0F
  :
  sta $8000

  ; Set up outer bank, game size, and starting register
  ; Bit 7 of mapper mode controls whether reg $00 (CHR bank)
  ; or $01 (inner PRG bank) is visible to the program at start.
  lda #$81
  sta $5000
  ldx outer_bank_value
  ldy #0
  
  ; Bit 0 clear: CNROM; use reg $00 (CHR bank)
  lda start_mappercfg
  bpl have_regnum_in_y
    ; Game size 64K+: AOROM/BNROM/UNROM; use reg $01 (PRG inner bank)
    iny
    and #$30
    bne have_regnum_in_y
      ; Game size 32K: NROM (use outer bank)
      ldy #$81
  have_regnum_in_y:

  lda start_mappercfg
  jmp trampoline_entry

  ; Fortunately I can do all this in position-independent
  ; code so I don't need to pollute the link script even more
trampoline_code:
  stx $8000  ; outer bank
  ldx #$80
  stx $5000
  sta $8000  ; game size, mirroring, PRG bank style
  sty $5000  ; which register it uses 
  ldx #$00FC + clrzploop - trampoline_code_end
  lda #$FF
  clrzploop:
    sta $00,x
    dex
    bne clrzploop
  .byte $4C  ; JMP opcode immediately before start_entrypoint
trampoline_code_end:

trampoline_entry = $00FE + trampoline_code - trampoline_code_end
.endproc
