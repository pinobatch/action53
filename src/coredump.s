;   Halt program and display the internal RAM on the NES.
;   Copyright (C) 2014  Johnathan Roatch
;
;   Copying and distribution of this file, with or without
;   modification, are permitted in any medium without royalty
;   provided the copyright notice and this notice are preserved
;   in all source code copies.
;
;   This file is offered as-is, without any warranty.

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
; 2014-08-22: Version 1.2 (CHR RAM Version)
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
; the primary trick I employ to be able to interactively browse
; RAM without corrupting it is saving byte $01 in the Stack pointer,
; and byte $00 in X, so that I can use the pair to do a load indirect.
; In v1.1 the stack pointer was restored by reading back printed
; hexadecimal text. v1.3 puts a raw byte into the hidden top-left corner.
;
; The rest of the code is all about sequencing PPU_ADDR and PPU_DATA
;
; This version omits the boot functions present in previous versions.
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

.segment "CODE"
.proc coredump
RAM_PTR = $00
RAM_PTR_LO = RAM_PTR + 0
RAM_PTR_HI = RAM_PTR + 1
STATE_VAR = RAM_PTR_HI
  ; Disable IRQ and NMI interrupts
  sei
  ldx #$00
  stx PPU_CTRL
  ; Disable rendering
  stx PPU_MASK
  lda #$40
  sta APU_FRAMECNT
  lda #$01
  sta APU_SND_CHN

  ; Wait for video to stop rendering
  lda PPU_STATUS
  @__loop1:
    lda PPU_STATUS
  bpl @__loop1

set_palette:
  lda #$3f
  sta PPU_ADDR
  lda #$0d
  sta PPU_ADDR
  ; Blue Screen of Death colors.
  lda #$01
  ldy #$20
  ldx #$100-3
  @__loop2:
    sty PPU_DATA
    inx
  bne @__loop2
  sta PPU_DATA
clear_nametable:
  ;,; ldy #$20
  sty PPU_ADDR
  ;,; ldx #$00
  stx PPU_ADDR

  ; Save stack regester in top-left corner.
  tsx
  stx PPU_DATA

  ldx #$01
  ldy #$100-4
  @__loop3:
    lda #$ff
    @__loop4:
      sta PPU_DATA
      inx
    bne @__loop4
    ; also play a startup sfx.
    lda #%10101010
    sta APU_PL1_VOL-$100+4, y
    iny
  bne @__loop3

; upload hexdecimal font to the first 16 tiles, and clear tile 255
upload_chr_ram:
blank_tile:
  lda #$0f
  sta PPU_ADDR
  ldy #$f0
  sty PPU_ADDR
  ;,; ldy #$f0  ;,; ldy #-$10
  @__loop5:
    stx PPU_DATA
    iny
  bne @__loop5
number_tiles:
  ;,; ldx #$00
  stx PPU_ADDR
  ;,; ldx #$00
  stx PPU_ADDR
  ;,; ldx #$00
  ;,; ldy #$00

  @__loop6:
    ldy #$100-7
    @__loop7:
      lda coredump_font, x
      inx
      sta PPU_DATA
      iny
    bne @__loop7
    lda #$00
    ldy #$100-9
    @__loop8:
      sta PPU_DATA
      iny
    bne @__loop8
    cpx #(16+8)*7
  bne @__loop6
END_upload_chr_ram:

print_title:
  lda #$20
  sta PPU_ADDR
  lda #$8c
  sta PPU_ADDR
  ldx #$10
  @__loop9:
    stx PPU_DATA
    inx
    cpx #$18
  bne @__loop9
  ldx #$100-4
  @__loop10:
    lda PPU_DATA
    inx
  bne @__loop10

print_stack_regester:
  tsx
write_stack_ptr:
  ;,; ldy #$00
  sty PPU_DATA
  lda #$01
  sta PPU_DATA
  txa
  lsr
  lsr
  lsr
  lsr
  sta PPU_DATA
  txa
  and #$0f
  sta PPU_DATA

  ; CPU has 4 mirrors From $0000 to $1fff
  ; State var, a00xyzzz,
  ;   a: screen needs to redraw.
  ;   x: add half to page number
  ;   y: button was pressed last frame
  ;   z: page number

  ldy #%10001000

main_loop:
  @__loop11:
    bit PPU_STATUS
  bpl @__loop11

  lda #BG_ON|OBJ_OFF
  sta PPU_MASK

check_for_page_switch:
read_pads:
  ldx #$01
  lda #$00
  stx JOY_STROBE
  sta JOY_STROBE
  @__loop12:
    lda JOY_PORT_2
    ; Mix in both pads for as input.
    ora JOY_PORT_1
    and #%00000011  ; ignore D2-D7
    cmp #1          ; CLC if A=0, SEC if A>=1
    txa
    rol
    tax
  bcc @__loop12
  ; A = X = (pad1 | pad2)

modify_state:
  and #BUTTON_UP|BUTTON_DOWN      ; mask all buttons but up and down
  beq no_button_was_pressed
  tax
  tya
  bit byte_08+1  ;,; bit #%00001000
  bne store_state           ; button needs to be not pressed last frame.
  ;,; and #%00011111        ; upper 3 bits are assumed 0
  cmp #%00010000            ; rotate the 5 bit field
  rol
  cpx #BUTTON_UP
  bne @__skip1
    ;,; sec  ; from cpx being equal.
    sbc #$01  ; alternatively adc #$fe
  @__skip1:
  cpx #BUTTON_DOWN
  bne @__skip2
    ;,; sec  ; from cpx being equal.
    adc #$00  ; alternatively sbc #$ff
  @__skip2:
  and #%00001111    ; mask button pressed and overflow bits.
  lsr
  ora #%10001000
  bcc @__skip3
    ora #%00010000
  @__skip3:

play_sfx:
  ldx #%10001011
  stx APU_PL1_SWEEP
  sta APU_PL1_LO    ; pitch varies for each page.
  ldx #%10000000
  stx APU_PL1_VOL
  stx APU_PL1_HI

  bne store_state   ;,; jmp store_state
exit_coredump:
  ldx #$100-4
  @__loop13:
    lda exit_sfx_data-$100+4, x
    sta APU_PL1_VOL-$100+4, x
    inx
  bne @__loop13
wait_a_moment_then_reset:
  ldx #$100-24
  @__loop14:
    @__loop15:
      bit PPU_STATUS
    bpl @__loop15
    inx
  bne @__loop14
jmp ($fffc)

no_button_was_pressed:
  tya
  and #%11110111
  bmi @__skip4      ; skip if redraw is still needed.
    cpx #BUTTON_A|BUTTON_B|BUTTON_START|BUTTON_SELECT
    beq exit_coredump
  @__skip4:
store_state:
  tay
END_modify_state:
END_check_for_page_switch:

  ; still in vblank.
  ;,; tya
bpl main_loop

print_current_half_page:
save_ram:
  ldx RAM_PTR_HI
  txs               ; save high byte to SP
  ldx RAM_PTR_LO    ; and low byte to X
clear_draw_flag:
  ;,; tya
  and #%01111111
  sta STATE_VAR
turn_off_screen:
  ldy #BG_OFF|OBJ_OFF   ;,; ldy #$00
  sty PPU_MASK
unpack_STATE_VAR:
  ;,; lda STATE_VAR
  asl
  asl
  asl
  and #%10000000
  sta RAM_PTR_LO

print_address:
  lda #$20
  sta PPU_ADDR
  lda #$84
  sta PPU_ADDR
  ;,; ldy #$00
  sty PPU_DATA
  lda RAM_PTR_HI
  and #%00000111
  sta PPU_DATA
  lda RAM_PTR_LO
  beq __skip5
byte_08:
    lda #$08
  __skip5:
  sta PPU_DATA
  ;,; ldy #$00
  sty PPU_DATA

  lda #$20
  sta PPU_ADDR
  lda #$c4
  sta PPU_ADDR

  ; First page has special needs to print
  ;   the two saved bytes in X and SP.
  lda STATE_VAR
  and #%00010111
  bne END_print_special_bytes
  print_special_bytes:
    txa
    tay
    tsx
    ;,; tya
    lsr
    lsr
    lsr
    lsr
    sta PPU_DATA
    tya
    and #$0f
    sta PPU_DATA
    lda PPU_DATA
    inc RAM_PTR_LO
    txa
    lsr
    lsr
    lsr
    lsr
    sta PPU_DATA
    txa
    and #$0f
    sta PPU_DATA
    lda PPU_DATA
    inc RAM_PTR_LO
    ;,; txs
    tya
    tax
  END_print_special_bytes:

  print_byte_loop:
    ldy #$00
    lda (RAM_PTR), y
    lsr
    lsr
    lsr
    lsr
    sta PPU_DATA
    lda (RAM_PTR), y
    and #$0f
    sta PPU_DATA
    inc RAM_PTR_LO
  insert_blanks:
    ldy #$01
    lda RAM_PTR_LO
    and #%00000011
    bne @__skip6
      iny   ;,; ldy #2
      lda RAM_PTR_LO
      and #%00000111
      bne @__skip7
        ldy #$08
        lda RAM_PTR_LO
        and #%00011111
        bne @__skip8
          ldy #$28
        @__skip8:
      @__skip7:
    @__skip6:
    @__loop16:
      lda PPU_DATA
      dey
    bne @__loop16
    lda RAM_PTR_LO
    and #%01111111
  bne print_byte_loop
restore_ram:
  lda #$20
  sta PPU_ADDR
  ;,; ldy #$00
  sty PPU_ADDR

  stx RAM_PTR_LO
  ldy STATE_VAR
  tsx
  stx RAM_PTR_HI
  ldx PPU_DATA  ; dummy read
  ldx PPU_DATA
  txs
set_scroll:
  ldx #$00
  stx PPU_SCROLL
  stx PPU_SCROLL
END_print_current_half_page:

jmp main_loop
exit_sfx_data:
  .byte %11001111, %11110001, %10010101, %00010000
END_coredump:
.endproc

.segment "RODATA"

coredump_font:
  .byte $38,$6c,$6c,$6c,$6c,$6c,$38     ; 0
  .byte $18,$38,$18,$18,$18,$18,$18     ; 1
  .byte $38,$6c,$0c,$38,$60,$6c,$7c     ; 2
  .byte $38,$6c,$0c,$38,$0c,$6c,$38     ; 3
  .byte $6c,$6c,$6c,$7c,$0c,$0c,$0c     ; 4
  .byte $7c,$6c,$60,$78,$0c,$6c,$38     ; 5
  .byte $38,$6c,$60,$78,$6c,$6c,$38     ; 6
  .byte $7c,$6c,$6c,$0c,$0c,$0c,$0c     ; 7
  .byte $38,$6c,$6c,$38,$6c,$6c,$38     ; 8
  .byte $38,$6c,$6c,$3c,$0c,$6c,$38     ; 9
  .byte $3c,$66,$66,$7e,$66,$66,$66     ; A
  .byte $7c,$66,$66,$7c,$66,$66,$7c     ; B
  .byte $3c,$66,$60,$60,$60,$66,$3c     ; C
  .byte $78,$6c,$66,$66,$66,$6c,$78     ; D
  .byte $7e,$60,$60,$7e,$60,$60,$7e     ; E
  .byte $7e,$60,$60,$78,$60,$60,$60     ; F
  .byte $00,$00,$38,$6c,$60,$6c,$38     ; c
  .byte $00,$00,$38,$6c,$6c,$6c,$38     ; o
  .byte $00,$00,$78,$6c,$60,$60,$60     ; r
  .byte $00,$00,$38,$64,$7c,$60,$3c     ; e
  .byte $0c,$0c,$3c,$6c,$6c,$6c,$3c     ; d
  .byte $00,$00,$6c,$6c,$6c,$6c,$34     ; u
  .byte $00,$00,$6c,$7e,$56,$66,$66     ; m
  .byte $00,$00,$78,$6c,$78,$60,$60     ; p
