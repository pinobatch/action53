;   Halt program and display the internal RAM on the NES.
;   Copyright (C) 2014  Johnathan Roatch
;
;   Copying and distribution of this file, with or without
;   modification, are permitted in any medium without royalty
;   provided the copyright notice and this notice are preserved
;   in all source code copies.
;
;   This file is offered as-is, without any warranty.

; 2019-08-05: Version 1.6
;   - Removed Serifs from font for reability (and compression).
;   - 408 bytes code + 128 bytes chr data + 8 bytes sfx data.
; 2018-05-26: Version 1.5:
;   - Rewrite, with vastly diffrent tricks from previous versions.
;   - Compressed font.
;   - Displayed Stack Pointer is now updated.
;   - Uses 4 bytes (was 1) in offscreen NT while refreshing screen.
;   - 408 bytes code + 141 bytes chr data + 8 bytes sfx data.
; 2015-12-16: Version 1.4:
;   - Fixed a bug where one can stall the first screen draw on start.
;   - Added button combo for reseting from the controller. (A+B+St+Sl)
;   - 512 bytes code + 168 bytes chr data.
; 2015-10-17: Version 1.3:
;   - Reverted core code to be based on Version 1.1.
;   - Compiles on CA65 instead of ASM6.
;   - Controller reading at boot removed.
;   - The program title is displayed.
;   - Font from Version 1.2.
;   - Free from unoficial opcodes.
;   - 479 bytes code + 168 bytes chr data.
; 2014-08-22: Version 2.0 (aka 1.2, CHR RAM Version)
;   - Heavy use of CHR RAM.
;   - Program separated into a boot backend and a GUI frontend.
;   - [Boot] no longer activated by button combo.
;   - [Boot] captures CPU RAM, Nametables,
;            and palette into CHR RAM.
;   - [GUI] can switch between diffrent memory domains.
;   - [GUI] added exit button for multicarts.
;   - [GUI] New font.
;   - 204 bytes boot code, 859 bytes gui code and data.
; 2014-08-14: Version 1.1
;   - $01 and stack pointer are now preserved in idle frames.
;   - added sounds.
;   - moved stack pointer print out to top right.
;   - 502 bytes code + 128 bytes chr data.
; 2014-08-11: Version 1.0
;   - Initial release.
;   - 485 bytes code + 128 bytes chr data.
;
; If you would like to be able to read the unmodified boot contents
; of the NES RAM, then use the following code snippet between
; the two standard PPU wait loops.
;
;   coredump_at_boot_readpad:
;     ldy #$01
;     lda #$00
;     sty $4016
;     sta $4016
;     @readpad_loop:
;       lda $4017
;       ; Uncomment to read pad 1 as well.
;       ;ora $4016
;       and #%00000011  ; ignore D2-D7
;       cmp #1          ; CLC if A=0, SEC if A>=1
;       tya
;       rol
;       tay
;     bcc @readpad_loop
;     ; A = Y = pad2
;     cpy #%11000000
;     bne @continue_normally
;       jmp coredump
;     @continue_normally:

PPU_CTRL        = $2000
  NT_2000       = %00000000
  NT_2400       = %00000001
  NT_2800       = %00000010
  NT_2C00       = %00000011
PPU_MASK        = $2001
  OBJ_OFF       = %00000000
  OBJ_ON        = %00010100
  BG_OFF        = %00000000
  BG_ON         = %00001010
PPU_STATUS      = $2002
PPU_SCROLL      = $2005
PPU_ADDR        = $2006
PPU_DATA        = $2007

APU_PL1_VOL     = $4000
APU_PL1_SWEEP   = $4001
APU_PL1_LO      = $4002
APU_PL1_HI      = $4003
APU_SND_CHN     = $4015
APU_STATUS      = $4015
JOY_STROBE      = $4016
APU_FRAMECNT    = $4017

JOY_PORT_1      = $4016
JOY_PORT_2      = $4017
  BUTTON_NONE      = %00000000
  BUTTON_A         = %10000000
  BUTTON_B         = %01000000
  BUTTON_SELECT    = %00100000
  BUTTON_START     = %00010000
  BUTTON_UP        = %00001000
  BUTTON_DOWN      = %00000100
  BUTTON_LEFT      = %00000010
  BUTTON_RIGHT     = %00000001

.export coredump
.import compute_cart_checksums

.segment "CODE"
.proc coredump
RAM_PTR = $00
RAM_PTR_LO = RAM_PTR + 0
RAM_PTR_HI = RAM_PTR + 1

hardware_init:
  sei
  ldx #$00
  stx PPU_CTRL
  ;,; ldx #BG_ON|OBJ_OFF
  stx PPU_MASK
  ldy #$40
  sty APU_FRAMECNT
  inx  ;,; ldx #$01
  stx APU_SND_CHN
  ; Wait for video to stop rendering
  bit PPU_STATUS
  @__loop:
    bit PPU_STATUS
  bpl @__loop
  ; this should leave the V flag cleared

;;
; if external code is calling this as a subroutine
; the following MUST be set
; X = $01, Y = $40, V = set
set_palette:
  dey  ;,; ldy #$3f
  sty PPU_ADDR
  lda #$e0
  sta PPU_ADDR
  ; Blue Screen of Death colors.
  ;,; and #$3f ;,; lda #$20
  inx  ;,; ldx #2
  @__loop2:
    stx PPU_DATA
    ldy #$100-(16-1)
    @__loop1:
      sta PPU_DATA
      iny
    bne @__loop1
    dex
  bne @__loop2

upload_chr_ram:
;  lda #$00
;  sta PPU_ADDR
;  lda #$00
;  sta PPU_ADDR
  ;,; ldx #$00
  ;,; ldy #$00
  @__loop3:
    lda coredump_font, x
    inx
    ;,; ldy #$00
    asl
    @__loop1:
      bcc @__skip
        ldy coredump_font, x
        inx
      @__skip:
      sty PPU_DATA
      asl
    bne @__loop1
    ;,; lda #$00
    ldy #$100-9
    @__loop2:
      sta PPU_DATA
      iny
    bne @__loop2
    cpx #coredump_font_END-coredump_font
  bcc @__loop3

clear_nametable:
  lda #$20
  sta PPU_ADDR
  ;,; ldy #$00
  sty PPU_ADDR

  ldx #$100-4
  ;,; ldy #$00
  @__loop2:
    lda #$20
    ;,; ldy #$00
    @__loop1:
      sta PPU_DATA
      iny
    bne @__loop1
    ; also play a startup sfx.
    lda #%10101010
    sta APU_PL1_VOL-$100+4, x
    inx
  bne @__loop2

;;
; The main loop.
; Y = State var, 000xyyyz,
;   x: button was pressed last frame
;   y: page number
;   z: half page
;,; ldy #%00000000
refresh_screen:
  ;,; ldx #$00
save_ram_in_NT:
  lda #$2c
  sta PPU_ADDR
  ;,; ldx #$00
  stx PPU_ADDR
  lda RAM_PTR_LO
  sta PPU_DATA
  lda RAM_PTR_HI
  sta PPU_DATA
  tsx
  stx PPU_DATA
  sty PPU_DATA

print_header:
print_address:
  lda #$20
  sta PPU_ADDR
  lda #$84
  sta PPU_ADDR
and_swap_sp_with_Y:
  ldx #$00
  stx PPU_DATA
  tya
  lsr
  sta PPU_DATA
  txa  ;,; lda #$00
  bcc @__skip
    lda #$08
  @__skip:
  sta PPU_DATA
  ;,; ldx #$00
  stx PPU_DATA

print_title:
;  lda #$20
;  sta PPU_ADDR
;  lda #$88
;  sta PPU_ADDR
  tya
  ldy #$10
  @__loop:
    sty PPU_DATA
    iny
    cpy #$20
  bcc @__loop

print_stack_regester:
;  lda #$20
;  sta PPU_ADDR
;  lda #$98
;  sta PPU_ADDR
  ;,; ldx #$00
  stx PPU_DATA
  inx  ;,; ldx #$01
  stx PPU_DATA
set_up_pointers:
  tsx
  tay  ;,; cmp #$00
  beq setup_for_zero_page
  setup_for_other_pages:
    ;,; tya
    lsr
    sta RAM_PTR_HI
    lda #$00
    ror
    sta RAM_PTR_LO
    txa
    ldx #$ff
  bne end_setup  ;,; jmp end_setup
  setup_for_zero_page:
    txa
    ldx #$00
  end_setup:
  txs
  ldy #$ff

print_page_with_sp:
;  lda #$20
;  sta PPU_ADDR
;  lda #$9a
;  sta PPU_ADDR
  print_byte_loop:
    tax
    lsr
    lsr
    lsr
    lsr
    sta PPU_DATA
    txa
    and #$0f
    sta PPU_DATA
    iny
  insert_blanks:
    tya
    ldx #$28
    and #%00011111
    beq @__skip3
      ldx #$08
      and #%00000111
      beq @__skip2
        ldx #$02
        and #%00000011
        beq @__skip1
          dex  ;,; ldx #$01
        @__skip1:
      @__skip2:
    @__skip3:
    @__loop:
      lda PPU_DATA
      dex
    bne @__loop
    lda RAM_PTR, y
    tsx
    beq @__skip4
      lda (RAM_PTR), y
    @__skip4:
    cpy #$80
  bcc print_byte_loop

restore_ram_from_NT:
  lda #$2c
  sta PPU_ADDR
  ldy #$00
  sty PPU_ADDR

  lda PPU_DATA  ; dummy read
  lda PPU_DATA
  sta RAM_PTR_LO
  lda PPU_DATA
  sta RAM_PTR_HI
  ldx PPU_DATA
  txs
  lda PPU_DATA
set_scroll:
  ;,; ldy #$00
  sty PPU_SCROLL
  sty PPU_SCROLL
  ;,; ldy #NT_2000
  sty PPU_CTRL
set_button_was_pressed_flag:
  ora #%00010000
  tay

main_loop:
  @__loop:
    bit PPU_STATUS
  bpl @__loop

  lda #BG_ON|OBJ_OFF
  sta PPU_MASK

read_pads:
  ldx #$01
  lda #$00
  stx JOY_STROBE
  sta JOY_STROBE
  @__loop:
    lda JOY_PORT_2
    ; Mix in both pads for input.
    ora JOY_PORT_1
    and #%00000011  ; ignore D2-D7
    cmp #1          ; CLC if A=0, SEC if A>=1
    txa
    rol
    tax
  bcc @__loop
  ; A = X = (pad1 | pad2)

  ;,; txa
  and #BUTTON_UP|BUTTON_DOWN

check_for_exit:
  cpx #BUTTON_A|BUTTON_B|BUTTON_START|BUTTON_SELECT
  bne continue_1
    play_exit_sound:
      ldx #$100-4
      @__loop:
        lda exit_sfx_data-$100+4, x
        sta APU_PL1_VOL-$100+4, x
        inx
      bne @__loop
    wait_a_moment_before_reset:
      ldx #$100-24
      @__loop2:
        @__loop1:
          bit PPU_STATUS
        bpl @__loop1
        inx
      bne @__loop2
    exit_coredump_by_reset:
    jmp ($fffc)
  continue_1:
  cpx #BUTTON_LEFT|BUTTON_A
  bne continue_2
    jmp compute_cart_checksums
  continue_2:

  cpy #%00010000   ; C = button pressed last frame
  tax              ; Z = button pressed this frame
  bcc buttons_empty_last_frame
    bne buttons_not_empty_this_frame
      ; if !C and Z then clear last frame flag in Y
      tya
      and #%11101111
      tay
    buttons_not_empty_this_frame:
    bcs main_loop  ;,; jmp main_loop
  buttons_empty_last_frame:
  beq main_loop

  ; if C and !Z then do action and refresh screen.
change_page_number:
  cpx #BUTTON_UP
  bne @__skip1
    dey
  @__skip1:
  cpx #BUTTON_DOWN
  bne @__skip2
    iny
  @__skip2:
  tya
  and #%00001111
  tay

play_sfx:
  ldx #$100-4
  @__loop:
    lda page_sfx_data-$100+4, x
    sta APU_PL1_VOL-$100+4, x
    inx
  bne @__loop
  ; still in vblank.
  ; with page changed, we can refresh the screen
turn_off_screen:
  ;,; ldx #$00  ;,; ldx #BG_OFF|OBJ_OFF
  stx PPU_MASK
jmp refresh_screen
.endproc

.segment "RODATA"

coredump_font:
  .byte %11000011, $38,$6c,                $38     ; 0
  .byte %10000001, $18                             ; 1
  .byte %11011011, $78,$0c,    $38,$60,    $7c     ; 2
  .byte %11011011, $78,$0c,    $38,$0c,    $78     ; 3
  .byte %10011001, $6c,        $7c,$0c             ; 4
  .byte %11011011, $7c,$60,    $78,$0c,    $78     ; 5
  .byte %11011011, $38,$60,    $78,$6c,    $38     ; 6
  .byte %11000001, $7c,$0c                         ; 7
  .byte %11011011, $38,$6c,    $38,$6c,    $38     ; 8
  .byte %11011011, $38,$6c,    $3c,$0c,    $38     ; 9
  .byte %11011001, $3c,$66,    $7e,$66             ; A
  .byte %11011011, $7c,$66,    $7c,$66,    $7c     ; B
  .byte %11000011, $3e,$60,                $3e     ; C
  .byte %11100111, $78,$6c,$66,        $6c,$78     ; D
  .byte %11011011, $7e,$60,    $7e,$60,    $7e     ; E
  .byte %11011001, $7e,$60,    $78,$60             ; F
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00111111,         $38,$6c,$60,$6c,$38     ; c
  .byte %00110011,         $38,$6c,        $38     ; o
  .byte %00111001,         $78,$6c,$60             ; r
  .byte %00111111,         $38,$64,$7c,$60,$3c     ; e
  .byte %10110011, $0c,    $3c,$6c,        $3c     ; d
  .byte %00100011,         $6c,            $34     ; u
  .byte %00111101,         $6c,$7e,$56,$66         ; m
  .byte %00111101,         $78,$6c,$78,$60         ; p
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
  .byte %00000001                                  ; space
; Extra characters for checksum app
  .byte %01110111,     $24,$7e,$24,    $7e,$24     ; #
  .byte %11000001, $7e,$18                         ; T
  .byte %10000011, $60,                    $7e     ; L
  .byte %00110001,         $78,$6c                 ; n
coredump_font_END:
exit_sfx_data:
  .byte %11001111, %11110001, %10010101, %00010000
page_sfx_data:
  .byte %10000000, %10001011, %10010011, %10000000
