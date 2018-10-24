;
; Action 53 title screen and game loader
; Copyright 2011-2014 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "nes.inc"
.include "global.inc"
.include "pently.inc"

.import interbank_fetch, interbank_fetch_buf
.import coredump
.importzp lineImgBufLen
.export pently_zptemp
;.export PB53_outbuf
;.exportzp ciSrc, ciBufStart, ciBufEnd

; ld65 manual says LOWCODE is for stuff guaranteed not to be
; banked out, good for irq handlers, but it's also good for
; anything that must access data from multiple banks
.import __LOWCODE_RUN__, __LOWCODE_LOAD__
.import __LOWCODE_SIZE__

OAM = $0200

.segment "ZEROPAGE"
nmis:          .res 1
oam_used:      .res 1

; Used by pads.s
cur_keys:  .res 2
new_keys:  .res 2
cur_trigger: .res 1

; Used by music engine
tvSystem:   .res 1
music_nmis: .res 1
pently_zptemp: .res 5

; Used by serial byte streams
ciSrc: .res 2
ciBufStart: .res 1
ciBufEnd: .res 1
PB53_outbuf = $0100

; timer to let "start activity" sfx play for CHR-RAM activities
min_start_timer: .res 1

.segment "BSS"
linebuf: .res 40
ciBlocksLeft = linebuf

.if 0
.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 2          ; PRG ROM size in 16384 byte units
  .byt 0          ; CHR ROM size in 8192 byte units
  .byt $00        ; mirroring type and mapper number lower nibble
  .byt $00        ; mapper number upper nibble
.endif

.segment "BFF0"
.proc patch_bff0
  sei
ldxinstr:
  ldx #$FF
  nop
  stx ldxinstr+1
  jmp ($FFFC)
.endproc

.segment "FFF0"
.proc patch_fff0
  sei
ldxinstr:
  ldx #$FF
  nop
  stx ldxinstr+1
  jmp ($FFFC)
  .addr nmi, reset, irq
.endproc

; Add this only when copying hex into the patcher
.if 0
.segment "CODE"
.proc patch21
  sei
  ldx #copied_end - copied - 1
:
  lda copied,x
  sta $00,x
  dex
  bpl :-
  jmp $0000
copied:
  stx copied+5
  jmp ($FFFC)
copied_end:
.endproc
.endif

.segment "CODE"
;;
; This NMI handler is good enough for a simple "has NMI occurred?"
; vblank-detect loop, like in Lawn Mower or Thwaite.
.proc nmi
  inc nmis
  rti
.endproc

; Action 53 dosn't use IRQ. Use this to catch runaway code that
; hits a BRK opcode. This is also currently used to test the
; full build by having the dummy ROM image simply execute
; BRK while mapped to the menu.
.proc irq
  pha
  txa
  pha
  tya
  pha
jmp coredump
.endproc

; 
.proc reset
  ; The very first thing to do when powering on is to put all sources
  ; of interrupts into a known state.  But the coredump feature
  ; requires all this to be done without writing to memory or the
  ; stack pointer.
  sei             ; Disable interrupts
  ldx #$00
  stx PPUCTRL     ; Disable NMI and set VRAM increment to 32
  stx PPUMASK     ; Disable rendering
  stx $4010       ; Disable DMC IRQ
  dex             ; Leave for later TXS
  bit PPUSTATUS   ; Acknowledge stray vblank NMI across reset
  bit SNDCHN      ; Acknowledge DMC IRQ
  lda #$40
  sta P2          ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels

vwait1:
  bit PPUSTATUS   ; It takes one full frame for the PPU to become
  bpl vwait1      ; stable.  Wait for the first frame's vblank.

coredump_at_boot_readpad:
  ldy #$01
  lda #$00
  sty $4016
  sta $4016
  @readpad_loop:
    lda $4017
    ora $4016
    and #%00000011  ; ignore D2-D7
    cmp #1          ; CLC if A=0, SEC if A>=1
    tya
    rol
    tay
  bcc @readpad_loop
  ; A = Y = pad2
  cpy #%11000000
  bne @not_coredump
    jmp coredump
  @not_coredump:

  ; Now that we know we're not running coredump:
  txs  ; Set stack pointer
  cld  ; Turn off decimal mode for post-patent famiclones

  ; Clear zeropage and OAM, to prevent uninitialized reads in nmis, etc.
  ldy #$00
  txa ;,; lda #$ff
  inx ;,; ldx #$00
  clear_zp_and_oam_loop:
    sty $00, x
    sta OAM, x
    inx
  bne clear_zp_and_oam_loop

  ; Copy the CHR decompression code to RAM.
  .assert __LOWCODE_SIZE__ < 256, error, "LOWCODE too big"
  ldx #0
copy_LOWCODE:
  lda __LOWCODE_LOAD__,x
  sta __LOWCODE_RUN__,x
  inx
  cpx #<__LOWCODE_SIZE__
  bne copy_LOWCODE

  jsr init_mapper

  ; Wait for the second vblank and figure out what TV system we're on.
  ; After this, use only NMI to wait for vblank.
  jsr getTVSystem
  sta tvSystem
  lda #VBLANK_NMI
  sta PPUCTRL

  ; Blank the screen, wait for vblank, and wait a bit more,
  ; so that the Zapper's photodiode is detected as dark during
  ; the entire detection routine.
  lda #$3F
  ldy #$00
  sta PPUADDR
  sty PPUADDR
  sta PPUDATA
  sty PPUADDR
  sty PPUADDR
  jsr ppu_wait_vblank
  jsr pently_init
  jsr identify_controllers

  ; Prime the controller reading, so that holding a button during
  ; power-on doesn't close the title screen.
  jsr read_zapper_trigger
  jsr read_pads

  ; If the title screen pointer is in $FF00-$FFFF, no games are
  ; loaded.  This could happen if the user burns the menu bank
  ; by itself without building a ROM.
  ldy TITLESCREEN+1
  iny
  bne has_games
    jmp no_games_error
  has_games:

  jsr title_screen
  lda nmis
  sta music_nmis
  jsr cart_menu

  ldy #16
  sty min_start_timer

  ; game id is in A
  pha
  jsr get_titledir_a
  jsr load_titledir_chr_rom
  ldx #0
  jsr ppu_clear_oam  ; Clear OAM because Snail Maze Game doesn't
  pla

  ; CHR data is loaded.
titleptr = $00
  jsr get_titledir_a  ; refetch because CHR ROM loading clobbered it
  ldy #TITLE_ENTRY_POINT
  lda (titleptr),y
  sta start_entrypoint+0
  iny
  lda (titleptr),y
  sta start_entrypoint+1
  iny
  .assert TITLE_ENTRY_POINT + 2 = TITLE_MAPPER_CFG, error, "title dir field order changed"
  lda (titleptr),y
  sta start_mappercfg

  :
  lda min_start_timer
  beq :+
    jsr pently_update_lag
    jmp :-
  :

  ldx #0
  stx SNDCHN
  jmp start_game
.endproc

.importzp ciSrc0, ciSrc1
.import interbank_fetch, interbank_fetch_buf

; Temporary measure during debugging to keep Sinking Feeling-only ROM
; from reading off the end.  Once this is working, I'll try adding
; the CHR ROM size to the title directory.
CNROM_MAX_SIZE = 4

;;
; Loads the CHR bank ID associated with this title.
; @param $0000 pointer to entry in title directory
; @param $FF02 pointer to start of CHR directory, where each entry is
; 5 bytes: PRG bank, address low, high, midpoint offset low, high
.proc load_titledir_chr_rom
titleptr = $00
chrdir_entry_zp = $02  ; matches interbank_fetch bank ptr
chrdir_entry = interbank_fetch_buf+72
cur_chr_bank = interbank_fetch_buf+74
num_chr_banks = interbank_fetch_buf+75

  lda #1
  sta num_chr_banks
  lsr a
  sta cur_chr_bank
  sta PPUMASK
;  sta PPUCTRL
  ldy #TITLE_CHR_BANK
  lda (titleptr),y
  bpl is_chr_rom  ; CHR bank >= $80 means absent
    rts
  is_chr_rom:

  ; A = starting CHR bank number, 0 to 127.
  ; Calculate offset into chrdir as 5 * A + CHRDIR_START
  .if ::TITLE_CHR_BANK <> 1
    ldy #1
  .endif
  dey
  sty chrdir_entry_zp+1
  sta chrdir_entry_zp
  asl a
  asl a
  rol chrdir_entry_zp+1
  adc chrdir_entry_zp
  bcc :+
    inc chrdir_entry_zp+1
    clc
  :
  adc CHRDIR_START
  sta chrdir_entry
  lda CHRDIR_START+1
  adc chrdir_entry_zp+1
  sta chrdir_entry+1

  ldy #TITLE_NUMBER_OF_CHR
  lda (titleptr),y
  sta num_chr_banks
nextbank:
  lda #$00
  sta $5000
  lda cur_chr_bank
  sta $8000
  inc cur_chr_bank
  lda #$81
  sta $5000
  lda chrdir_entry
  sta chrdir_entry_zp
  lda chrdir_entry+1
  sta chrdir_entry_zp+1
  ldy #0
  sty draw_progress
  iny
  lda (chrdir_entry_zp),y
  iny
  sta ciSrc0
  lda (chrdir_entry_zp),y
  iny
  sta ciSrc0+1
  clc
  lda (chrdir_entry_zp),y
  iny
  adc ciSrc0
  sta ciSrc1
  lda (chrdir_entry_zp),y
  adc ciSrc0+1
  sta ciSrc1+1

  ; At this point:
  ; 2: pointer to bank number
  ; ciSrc0: Address of first 4 KiB
  ; ciSrc1: Address of second 4 KiB
  ; drawProgress: number of blocks already drawn
loop:
  lda draw_progress
  lsr a
  ror 0
  lsr a
  ror 0
  sta PPUADDR
  lda 0
  and #$c0
  sta PPUADDR

  lda ciSrc0
  sta 0
  lda ciSrc0+1
  sta 1
  jsr do4
  adc ciSrc0
  sta ciSrc0
  bcc :+
  inc ciSrc0+1
:

  lda draw_progress
  lsr a
  ror 0
  lsr a
  ror 0
  eor #$10
  sta PPUADDR
  lda 0
  and #$c0
  sta PPUADDR

  lda ciSrc1
  sta 0
  lda ciSrc1+1
  sta 1
  jsr do4
  adc ciSrc1
  sta ciSrc1
  bcc :+
  inc ciSrc1+1
:

  inc draw_progress
  lda draw_progress
  cmp #64
  bcc loop

  dec num_chr_banks
  beq no_more_chr_banks
    clc
    lda #5
    adc chrdir_entry
    sta chrdir_entry
    bcc :+
      inc chrdir_entry+1
    :
    jmp nextbank
  no_more_chr_banks:
  rts

;;
; @param A start of buffer (0 or 64)
; @return A number of compressed bytes read
do4:
  lda #65  ; block of 4 tiles, max 64 + 1 bytes
  sta 4
  lda chrdir_entry
  sta chrdir_entry_zp
  lda chrdir_entry+1
  sta chrdir_entry_zp+1
  lda #0
  sta PPUCTRL
  bit PPUSTATUS
  jsr interbank_fetch
  lda #VBLANK_NMI
  sta PPUCTRL
  ldy #<interbank_fetch_buf
  lda #>interbank_fetch_buf
  ldx #1
  jsr donut_block_ayx
  jsr pently_update_lag
  lda donut_stream_ptr+0
  sec
  sbc #<interbank_fetch_buf
  clc
  rts
.endproc

;;
; Reads a mouse and maps presses of L to A and R to B
; in new_keys.
; @param X port number of mouse to read (0 or 1)
.proc read_mouse_with_backward_buttons
  jsr read_mouse
  lda new_mbuttons,x
  and #KEY_B|KEY_A
  asl a  ; bit 7: LMB; carry: RMB
  bcc :+
    ora #KEY_B
  :
  ora new_keys,x
  sta new_keys,x

  lda #0
no_mouse:
  rts
.endproc

;;
; @return nonzero if there was a 1-to-0 transition on the Zapper trigger
.proc read_zapper_trigger
  lda detected_pads
  and #DETECT_2P_ZAPPER
  beq no_zapper
    lda $4017
    and #$10
    tay
    eor #$10
    and cur_trigger
    sty cur_trigger
  no_zapper:
  rts
.endproc

.proc pently_update_lag
  lda nmis
  cmp music_nmis
  beq caught_up
    jsr pently_update
    inc music_nmis
    lda min_start_timer
    beq :+
      dec min_start_timer
    :
    jmp pently_update_lag
  caught_up:
  rts
.endproc

; historic a53 volumes
; Emulator: http://www.fceux.com/web/download.html
; Volume 1: https://forums.nesdev.com/viewtopic.php?p=109907#p109907
; Volume 2: https://forums.nesdev.com/viewtopic.php?p=148343#p148343
; Volume 3 (work in progress): https://forums.nesdev.com/download/file.php?id=8115
