; Self-clearing Action 53 trampoline
; By jroatch, 2018-09-09

.include "nes.inc"
.include "global.inc"

.segment "CODE"
;;
; Clears all but the top few stack bytes and starts the chosen
; activity.  NMI and rendering must be turned off.
; @param start_entrypoint activity's entry point
; @param start_mappercfg activity's starting mapper configuration
.proc start_game
  ; A53 Mapper register write sequence:
  ;
  ;  $$00 = 0x00
  ;    Meaning; $5000 = 0x00, $8000 = 0x00
  ;    Which could expand to the cpu code;
  ;      lda #$00   sta $5000   sta $8000
  ;  $$01 = start_mappercfg & 0x0C if fixed-lo else start_mappercfg & 0x0F
  ;  $$80 = start_mappercfg
  ;  $$81 = (start_bankptr),TITLE_PRG_BANK
  ;  $5000 = 0x00 if start_mappercfg & 0x80
  ;          0x01 if start_mappercfg & 0x30
  ;          else 0x81

  ; load_titledir_chr_rom already disabled NMI and rendering

  ; Copy trampoline code to the end of the stack page with 'pha'
  ; so that the stack pointer ends up on its parameter stack
  ldx #$ff
  txs
  lda start_entrypoint+1
  pha
  lda start_entrypoint+0
  pha
  ldx #trampoline_code_size
  copy_trampoline_loop:
    lda trampoline_code_begin-1, x
    pha
    dex
  bne copy_trampoline_loop

  ; Compute parameters, in reverse order of register writing,
  ; and push them to the stack.

  ; Last thing first, set the final register select for game execution.
  ; Rules for setting final register in $5000 for game execution:
  ; If CNROM, and CHR loader supports CNROM, use $00 (CHR bank).
  ; If game is 32K, use $81 (outer PRG bank) so that simple
  ; reset code works.
  ; Otherwise, use $01 (inner PRG bank).
  ldy #0
  lda start_mappercfg
  bpl have_exe_mode_in_y
    ; Game size 64K+: AOROM/BNROM/UNROM; use reg $01 (PRG inner bank)
    iny
    and #$30
    bne have_exe_mode_in_y
      ; Game size 32K: NROM (use outer bank)
      ldy #$81
  have_exe_mode_in_y:
  tya
  pha

  ; Outer bank register
  ldy #TITLE_PRG_BANK
  lda (start_bankptr),y
  pha

  ; Now the outer bank and reset vector are correct, and the mapper
  ; configuration has been saved in a variable.  Now interpret the
  ; mapper configuration in reg $80 format:
  ; 76543210
  ; | ||||||
  ; | ||||++- Nametable mirroring (0=AAAA, 2=ABAB, 3=AABB)
  ; | ||++--- PRG bank mode (0=32k, 2=fixed $8000, 3=fixed $C000)
  ; | ++----- Game size (0=32k, 1=64k, 2=128k, 3=256k)
  ; +-------- If set, game isn't CNROM
  lda start_mappercfg
  pha

  ; Starting inner PRG bank should be $0F except for mapper 180
  ; where it should be $00.  Bits 3-2 of mapper mode control this.
  ;,;lda start_mappercfg
  and #$0C
  eor #$08  ; 0: mapper 180; nonzero: mapper 0, 2, 3, 7, 34
  bne :+
    lda #$0F
  :
  pha

  ; Before commiting to mapper writes, Clear RAM and Nametables
  ; while avoiding the trampoline area in stack page.
  ; TODO: Code golf this to take less ROM bytes.
  lda #$20
  ldx #$00
  sta PPUADDR
  stx PPUADDR
  txa
  clear_memory_loop:
    sta $00,x
    ; leave stack page for the ram code to clear.
    sta $0200,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    ldy #16
    clear_part_nt_loop:
      sta PPUDATA
      dey
    bne clear_part_nt_loop
    inx
  bne clear_memory_loop

  ; Start with CHR bank 0
  ; ldx #$00  ; set by previous inx/bne pair
  stx $5000
  stx $8000

  ; Prepare trampoline to set starting inner PRG bank (reg $01)
  ; and pop game mode and outer bank values (regs $80 and $81)
  inx
  stx $5000
  pla
  ldx #$80
jmp trampoline_enter

; Fortunately this part is all position-independent code
; so the link script isn't polluted more.
trampoline_code_begin:
  sta $8000
  loop:
    stx $5000
    pla
    sta $8000
    inx
    cpx #$82
  bcc loop
  pla
  sta $5000
  ldx #$ff-((trampoline_code_end + 2) - clr_sp_loop)
  txs
  lda #$00
  inx
  clr_sp_loop:
    dex
    pha
  bne clr_sp_loop
  ; This should also leave the stack pointer at the bottom.
.byte $4C  ; JMP opcode immediately before start_entrypoint
trampoline_code_end:

trampoline_code_size = trampoline_code_end - trampoline_code_begin
trampoline_enter = $0200 - ((trampoline_code_end+2) - trampoline_code_begin)
.endproc


.segment "CODE"
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
