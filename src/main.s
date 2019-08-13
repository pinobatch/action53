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

.import check_header, compute_cart_checksums

.segment "OAM"
OAM:            .res 256

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

load_titledir_chr_rom_chrdir_entry: .res 2
load_titledir_chr_rom_cur_chr_bank: .res 1
load_titledir_chr_rom_num_chr_banks: .res 1

.if 0
.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 2          ; PRG ROM size in 16384 byte units
  .byt 0          ; CHR ROM size in 8192 byte units
  .byt $00        ; mirroring type and mapper number lower nibble
  .byt $00        ; mapper number upper nibble
.endif

.segment "FFF0"
.proc patch_fff0
  sei
ldxinstr:
  ldx #$FF
  nop
  stx ldxinstr+1
  jmp ($FFFC)
  .addr $01fd, reset, irq
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

.segment "RODATA"
;;
; This NMI handler is good enough for a simple "has NMI occurred?"
; vblank-detect loop, like in Lawn Mower or Thwaite.
.proc nmi
  inc nmis
  rti
.endproc

.segment "CODE"
; Action 53 dosn't use IRQ. Use this to catch runaway code that
; hits a BRK opcode. This is also currently used to test the
; full build by having the dummy ROM image simply execute
; BRK while mapped to the menu.
.proc irq
  pha
  txa
  pha
  tsx
  lda $0103, x
  and #$10
  beq ack_apu_frame_counter
    tya
    pha
  jmp coredump
  ack_apu_frame_counter:
  pla
  tax
  pla
  bit $4015
  inc nmis
rti
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
  sta $4017       ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels
  cld  ; Turn off decimal mode for post-patent famiclones

; Configures the Action 53 mapper to behave like oversize BNROM.
; inlined here so that coredump can read it's data in $8000~$BFFF
init_mapper:
  ; Set outer bank to last, so that execution continues across
  ; change in mapper mode
  ldy #$81
  sty $5000
  ;,; ldx #$FF
  stx $8000

  ; Set mapper mode to 32k outer, 32k inner, vertical mirroring
  lda #$80
  sta $5000
  lda #$02
  sta $8000

  ; Finally, set the current register to outer bank
  sty $5000

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
  cpy #KEY_A|KEY_B
  bne not_coredump
    ; since getTVSystem contains at least 2 frames of vblank waiting
    ; vwait1 is moved here as only coredump needs it.
    vwait1:
      bit PPUSTATUS   ; It takes one full frame for the PPU to become
    bpl vwait1      ; stable.  Wait for the first frame's vblank.
    jmp coredump
  not_coredump:

  ; Now that we know we're not running coredump:
  ; set up and use the stack
  ;,; ldx #$ff
  txs  ; Set stack pointer
  ldx #3-1
  load_nmi_routine:
    lda nmi, x
    pha
    dex
  bpl load_nmi_routine
  ;,; ldx #$ff
  tya
  pha  ; save controller read across the ram clear

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
copy_LOWCODE:
  lda #<__LOWCODE_LOAD__
  sta $00
  lda #>__LOWCODE_LOAD__
  sta $01
  lda #<__LOWCODE_RUN__
  sta $02
  lda #>__LOWCODE_RUN__
  sta $03

  ldy #0
  ldx #(>(__LOWCODE_SIZE__-1))+1
  copy_LOWCODE_pages:
    copy_LOWCODE_pages_inner_loop:
      lda ($00), y
      sta ($02), y
      iny
    bne copy_LOWCODE_pages_inner_loop
    inc $00+1
    inc $02+1
    dex
  bne copy_LOWCODE_pages

  ;jsr init_mapper  ; inlined above

  pla  ; get back that inital controller read
  sta cur_keys+0
  sta cur_keys+1

  ; Wait for the second vblank and figure out what TV system we're on.
  ; After this, use only NMI to wait for vblank.
  jsr getTVSystem
  sta tvSystem
  lda #VBLANK_NMI
  sta PPUCTRL

  ldy cur_keys+0
  cpy #KEY_SELECT|KEY_B
  bne skip_checksum
    jmp compute_cart_checksums
  skip_checksum:

  ; Basic checks to see if the menu database exists.
  ; Failure indicates either the user burns the menu bank
  ; by itself without building a ROM, or that the database
  ; wasn't mapped to $8000-$bfff
  jsr check_header
  beq good_header
    jmp no_games_error
  good_header:

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

  jsr title_screen
  lda nmis
  sta music_nmis
  jsr cart_menu

  ldx #16
  stx min_start_timer
  ; Switch over to using APU Frame IRQ for timming
  ; due to donut_decompress_block exceeding a vblank of time.
  ldx #$00
  stx PPUCTRL
  stx PPUMASK
  stx $4017
  cli

  ; game id is in A
  pha
  jsr get_titledir_a
  jsr load_titledir_chr_rom
  ldx #0
  ; jsr ppu_clear_oam  ; Clear OAM because Snail Maze Game doesn't
  ; no point as ram gets cleared at start_game
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

;;
; Loads the CHR bank ID associated with this title.
; @param $0000 pointer to entry in title directory
; @param $8008 pointer to start of CHR directory, where each entry is
; 5 bytes: PRG bank, address low, high, midpoint offset low, high
.proc load_titledir_chr_rom
titleptr = $00
chrdir_entry_zp = $02  ; matches interbank_fetch bank ptr
chrdir_entry = load_titledir_chr_rom_chrdir_entry
cur_chr_bank = load_titledir_chr_rom_cur_chr_bank
num_chr_banks = load_titledir_chr_rom_num_chr_banks

  lda #1
  sta num_chr_banks
  lsr a
  sta cur_chr_bank
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
  lda #$00
  sta PPUADDR
  sta PPUADDR

loop:
  lda ciSrc0
  sta 0
  lda ciSrc0+1
  sta 1
  jsr load_titledir_chr_rom_do4
  adc ciSrc0
  sta ciSrc0
  bcc :+
  inc ciSrc0+1
:

  inc draw_progress
  lda draw_progress
  cmp #128
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
.endproc

.segment "LOWCODE"
.proc load_titledir_chr_rom_do4
chrdir_entry_zp = $02  ; matches interbank_fetch bank ptr
chrdir_entry = load_titledir_chr_rom_chrdir_entry
  lda chrdir_entry
  sta chrdir_entry_zp
  lda chrdir_entry+1
  sta chrdir_entry_zp+1
  sei
  ldy #0
  lda ($02), y
  sta ($02), y
  lda ($00), y
  cmp #$2a
  bne continue_normal_block
    iny
    raw_block_loop:
      lda ($00), y
      iny
      sta PPUDATA
      cpy #65  ; size of a raw block
    bcc raw_block_loop
  bcs block_done
  continue_normal_block:
    ldy $00
    sty donut_stream_ptr+0
    lda $01
    sta donut_stream_ptr+1
    ldx #64
    jsr donut_decompress_block
    ldx #64
    upload_loop:
      lda donut_block_buffer, x
      sta PPUDATA
      inx
    bpl upload_loop
  block_done:
  lda #$ff
  sta $8000   ; forget about the whole bus conflict thing for now
  cli
  sty donut_block_count  ; a safe temp var to store the returned bytes read
  jsr pently_update_lag
  lda donut_block_count
  clc
rts
.endproc

.segment "CODE"
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
