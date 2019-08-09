.include "nes.inc"
.include "global.inc"

.import coredump_load_gfx
.import ppu_screen_on_scroll_0, ppu_wait_vblank

.export check_header, compute_cart_checksums

.segment "CODE"
.proc check_header
  ldy #4
  check_loop:
    clc
    lda DIRECTORY_HEADER-1, y
    adc header_check_bytes-1, y
    bne check_error  ; rts with Z = 1
    dey
  bne check_loop
  ; rts with Z = 0
check_error:
rts
header_check_bytes:
.byte $100-165, $100-65, $100-53, $100-51
.endproc

.proc compute_cart_checksums
crc_hi            = $00
crc_lo            = $01
read_ptr          = $02  ; 2 bytes
read_page_count   = $04
; ram $00 ~ $04 must match parameters in ram code
current_32k_bank  = $05
nt_ptr            = $06  ; 2 bytes
crc_check_ptr     = $08  ; 2 bytes
  ldx #0
  stx PPUCTRL
  stx PPUMASK

  inx  ;,; ldx #$01
  ldy #$40
  bit _byte_with_b6_set  ;,; set V
  jsr coredump_load_gfx
  ;,; ldy #$00
  ;,; ldx #$00

  ;,; ldy #$00
  sty read_ptr+0
  lda #$80
  sta read_ptr+1

  ;,; lda #$80
  sta nt_ptr+0
  lda #$20
  sta nt_ptr+1

  lda BANK_CHECKSUMS+0
  sta crc_check_ptr+0
  lda BANK_CHECKSUMS+1
  sta crc_check_ptr+1

  lda NEG_NUMBER_OF_BANKS
  sta current_32k_bank

  jsr check_header
  bne db_checksum_fail

  ;,; ldy #$00
  dex ;,; ldx #$ff
  jsr compute_16K_block
  ;,; lda crc_hi
  ;,; ldx crc_lo
  ;,; ldy #$ff

  ;,; lda crc_hi
  ora crc_lo
  bne db_checksum_fail

  ;,; ldy #$00
  ;,; sty read_ptr+0
  lda #$80
  sta read_ptr+1

  next_checksum:
    ldx #string_at-strings_base
    jsr print_cr_and_str
    ;,; ldy #$00

    lda read_ptr+1
    cmp #$c0
    lda current_32k_bank
    rol
    tax
    lda #$00
    rol

    ;,; and #$0f
    sta PPUDATA
    jsr print_byte_x

    lda #0
    clc
    jsr ppu_screen_on_scroll_0

    ;,; ldy #$00
    ldx current_32k_bank
    jsr compute_16K_block
    ;,; ldx crc_lo
    ;,; lda crc_hi
    ;,; ldy #$ff

    iny  ;,; ldy #$00
    ;,; lda crc_hi
    cmp (crc_check_ptr), y
    bne check_failed
    ;,; ldx crc_lo
    txa
    iny
    cmp (crc_check_ptr), y
    beq check_succeed

  check_failed:
    ldx #string_err-strings_base
    jsr print_cr_and_str

    ldx crc_hi
    jsr print_byte_x
    ldx crc_lo
    jsr print_byte_x
  advance_nt_ptr:
    clc
    lda nt_ptr+0
    adc #$20
    sta nt_ptr+0
    bcc no_carry
      inc nt_ptr+1
    no_carry:
  check_succeed:

  clc
  lda crc_check_ptr+0
  adc #$02
  sta crc_check_ptr+0
  bne not_check_ptr_carry
    inc crc_check_ptr+1
  not_check_ptr_carry:

    lda read_ptr+1
  bne next_checksum
    lda #$80
    sta read_ptr+1
    inc current_32k_bank
  bne next_checksum
done:
  ldx #string_done-strings_base
  .byte $2c   ; BIT opcode to choose what value to load
db_checksum_fail:
  ldx #string_dberr-strings_base
  jsr print_cr_and_str
  ;,; ldy #$00

  tya ;,; lda #0
  clc
  jsr ppu_screen_on_scroll_0

  lda #%11000001
  ldx #4
  end_sfx:
    dex
    sta $4000, x
  bne end_sfx
jam: jmp jam

print_cr_and_str:
  lda nt_ptr+1
  sta PPUADDR
  lda nt_ptr+0
  sta PPUADDR
print_str:
  ldy strings_base, x
  inx
  tab_advance_loop:
    lda PPUDATA
    dey
  bne tab_advance_loop
  ldy strings_base, x
  inx
  print_str_loop:
    lda strings_base, x
    sta PPUDATA
    inx
    dey
  bne print_str_loop
_byte_with_b6_set:
rts
strings_base:
string_err:
  .byte 12, 4,  $0E,$16,$16,$20
string_at:
  .byte 4, 3,   $0A,$22,$21
string_done:
  .byte 6, 5,   $20,$18,$15,$24,$17
string_dberr:
  .byte 12, 6,   $0D,$0B,$20,$0E,$16,$16

print_byte_x:
  txa
  lsr
  lsr
  lsr
  lsr
  sta PPUDATA
  txa
  and #$0f
  sta PPUDATA
rts

compute_16K_block:
  ;,; ldy #$00
  sty crc_lo
  sty crc_hi
  lda #>$4000
  sta read_page_count
  jsr compute_cart_checksums_ram_code
  vblank_loop:
    bit PPUSTATUS
  bpl vblank_loop
rts
.endproc

.segment "LOWCODE"
.proc compute_cart_checksums_ram_code
CRCHI = $00          ; Yes, CRC is big endian
CRCLO = $01
READ_PTR = $02
READ_PAGE_COUNT = $04
  stx $8000
  check_16k_outer_loop:
    check_16k_inner_loop:
      lda (READ_PTR),y
    CRC16_F:
    ; http://www.6502.org/source/integers/crc-more.html
      eor CRCHI       ; A contained the data
      sta CRCHI       ; XOR it into high byte
      lsr             ; right shift A 4 bits
      lsr             ; to make top of x^12 term
      lsr             ; ($1...)
      lsr
      tax             ; save it
      asl             ; then make top of x^5 term
      eor CRCLO       ; and XOR that with low byte
      sta CRCLO       ; and save
      txa             ; restore partial term
      eor CRCHI       ; and update high byte
      sta CRCHI       ; and save
      asl             ; left shift three
      asl             ; the rest of the terms
      asl             ; have feedback from x^12
      tax             ; save bottom of x^12
      asl             ; left shift two more
      asl             ; watch the carry flag
      eor CRCHI       ; bottom of x^5 ($..2.)
      sta CRCHI       ; save high byte
      txa             ; fetch temp value
      rol             ; bottom of x^12, middle of x^5!
      eor CRCLO       ; finally update low byte
      ldx CRCHI       ; then swap high and low bytes
      sta CRCHI
      stx CRCLO
      iny
    bne check_16k_inner_loop
    inc READ_PTR+1
    dec READ_PAGE_COUNT
  bne check_16k_outer_loop
  dey ;,; ldy #$ff
  sty $8000
rts
.endproc
