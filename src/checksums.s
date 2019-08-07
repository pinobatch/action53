.include "nes.inc"
.include "global.inc"

.import coredump_load_gfx
.import ppu_screen_on, ppu_wait_vblank

.export check_header, compute_cart_checksums

.segment "CODE"
.proc check_header
  ldy #4
  check_loop:
    clc
    lda DIRECTORY_HEADER-1, y
    adc header_check_bytes-1, y
    beq byte_checks_out
    check_error:
      rts  ; return Z = 0
    byte_checks_out:
    dey
  bne check_loop
rts  ; return Z = 1
header_check_bytes:
.byte $100-165, $100-65, $100-53, $100-51
.endproc

.proc compute_cart_checksums
crc_hi            = $00
crc_lo            = $01
read_ptr          = $02  ; 2 bytes
read_page_count   = $04
; ram $00 ~ $04 must match paramiters in ram code
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

  lda #$20
  sta nt_ptr+1
  lda #$80
  sta nt_ptr+0
  ;,; lda #$80
  sta read_ptr+1
  ;,; ldy #$00
  sty read_ptr+0

  jsr check_header
  bne db_checksum_fail

  lda #$ff
  jsr compute_16K_block
  lda #$80
  sta read_ptr+1

  lda crc_lo
  ora crc_hi
  bne db_checksum_fail

  lda NEG_NUMBER_OF_BANKS
  sta current_32k_bank

  lda BANK_CHECKSUMS+0
  sta crc_check_ptr+0
  lda BANK_CHECKSUMS+1
  sta crc_check_ptr+1

  next_checksum:
    ldx #string_at-strings_base
    jsr print_cr_and_str
    ;,; ldy #$00

    lda read_ptr+1
    cmp #$c0
    lda current_32k_bank
    rol
    tay
    lda #$00
    rol
    ;,; clc
    jsr print_number

    jsr scroll_screen

    lda current_32k_bank
    jsr compute_16K_block
    ;,; ldy #$00

    jsr read_checksum_byte_from_db
    tay
    jsr read_checksum_byte_from_db
    cpy crc_hi
    bne check_failed
    cmp crc_lo
    beq check_succeed

  check_failed:
    ldx #string_err-strings_base
    jsr print_cr_and_str

    lda crc_hi
    ldy crc_lo
    jsr print_number_both_digits
  advance_nt_ptr:
    clc
    lda nt_ptr+0
    adc #$20
    sta nt_ptr+0
    bcc no_carry
      inc nt_ptr+1
    no_carry:
  check_succeed:

    lda read_ptr+1
    bne not_next_16k_bank
      lda #$80
      sta read_ptr+1
      inc current_32k_bank
    not_next_16k_bank:
  bne next_checksum
done:
  ldx #string_done-strings_base
  .byte $2c   ; BIT opcode to choose what value to load
db_checksum_fail:
  ldx #string_dberr-strings_base
  jsr print_cr_and_str
  jsr scroll_screen

  lda #%11000001
  ldx #4
  end_sfx:
    dex
    sta $4000, x
  bne end_sfx
jam: jmp jam

scroll_screen:
  lda #0
  tax  ;,; ldx #$00
  tay  ;,; ldy #$00
  clc
jmp ppu_screen_on

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

print_number_both_digits:
  sec
print_number:
  jsr print_number_digit
  tya
  sec
print_number_digit:
  bcc skip_first_high_digit
    tax
    lsr
    lsr
    lsr
    lsr
    sta PPUDATA
    txa
  skip_first_high_digit:
  and #$0f
  sta PPUDATA
rts

read_checksum_byte_from_db:
  ldx #$00
  lda (crc_check_ptr, x)
  inc crc_check_ptr+0
  bne not_check_ptr_carry_1
    inc crc_check_ptr+1
  not_check_ptr_carry_1:
rts

compute_16K_block:
  ldy #$00
  sty crc_lo
  sty crc_hi
  ldx #>$4000
  stx read_page_count
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
  sta $8000
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
  lda #$ff
  sta $8000
rts
.endproc
