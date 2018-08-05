; "Donut", NES CHR codec decompressor,
; Copyright (c) 2018  Johnathan Roatch
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.

.export donut_decompress_block, donut_block_ayx, donut_block_x
.exportzp donut_block_buffer
.exportzp donut_stream_ptr
.exportzp donut_block_count

temp = $00  ; 16 bytes are used

donut_block_buffer = $00c0  ; 64 bytes
donut_block_count = temp+4

.segment "ZEROPAGE"
donut_stream_ptr:       .res 2

; Block header:
; MLIiRCpp
; ||||||00-- Another header byte. For each bit starting from MSB
; ||||||       0: 0x00 plane
; ||||||       1: pb8 plane
; ||||||01-- L planes: 0x00, M planes:  pb8
; ||||||10-- L planes:  pb8, M planes: 0x00
; ||||||11-- All planes: pb8
; |||||+---- 1: Clear block buffer, 0: XOR with existing block
; ||||+----- Rotate plane bits (135° reflection)
; |||+------ L planes predict from 0xff
; ||+------- M planes predict from 0xff
; |+-------- L = M XOR L
; +--------- M = M XOR L
; 11111110-- Uncompressed block of 64 bytes
; 11111111-- Reuse previous block (skip block)

.segment "CODE"

.align 256

.proc donut_decompress_block
block_header    = temp+0
plane_def       = temp+1
even_odd        = temp+2
pb8_ctrl        = temp+3
temp_a          = pb8_ctrl
__unused        = temp+4
temp_y          = temp+5
block_offset    = temp+6
loop_counter    = temp+7
plane_buffer    = temp+8  ; 8 bytes
  ldy donut_stream_ptr+0
  lda #$00
  sta donut_stream_ptr+0
  sta block_offset
  lda (donut_stream_ptr), y
    ; read_next_byte is pre-increment
    ; So save last increment until routine is done

  cmp #$c0
  bcc do_normal_block
  do_special_block:
    and #$01
    bne no_raw_block
      ldx #64-1
      raw_block_loop:
        jsr read_next_byte
        sta donut_block_buffer, x
        dex
      bpl raw_block_loop
    no_raw_block:
  jmp end_block
  do_normal_block:
    sta block_header
    and #$55
    sta even_odd
      ; even_odd is a variable that alternates between
      ; even and odd bit of the block header.

    ;,; lda block_header
    and #$04
    beq no_clear_block_buffer
        ; semi-unrolled for speed, as the block buffer is often cleared
      ldx #(64/4)-1
      lda #$00
      clear_block_loop:
        sta donut_block_buffer, x
        sta donut_block_buffer+16, x
        sta donut_block_buffer+32, x
        sta donut_block_buffer+48, x
        dex
      bpl clear_block_loop
    no_clear_block_buffer:

    lda block_header
    and #$03
    tax
    lda donut_decompress_block_table, x
    bne read_plane_def_from_stream
      jsr read_next_byte
    read_plane_def_from_stream:
    sta plane_def

    lda #$100-8
    sta loop_counter
      ; counter is negative so that we can use the
      ; high bits to easily set the V flag later.
    plane_loop:
      lda #$00
      ldx plane_def
        ; don't yet shift out plane_def, we'll use the
        ; bit again to select the cheaper buffer copy later
      bpl pb8_is_all_zero
        jsr read_next_byte
      pb8_is_all_zero:
      sta pb8_ctrl

      lda even_odd
      and #$30
      beq not_predicted_from_ff
        lda #$ff
      not_predicted_from_ff:
        ; else A = 0x00
      ldx #8-1
      pb8_loop:
        asl pb8_ctrl
        bcc pb8_use_prev
          jsr read_next_byte
        pb8_use_prev:
        sta plane_buffer, x
        dex
      bpl pb8_loop

      sty temp_y
        ; use Y for block buffer pointer
      ldy block_offset
      clc
      tya
      adc #8
      sta block_offset
        ; while we have block_offset loaded,
        ; might as well advance it for the next plane.

      lda even_odd
      eor block_header
      sta even_odd
        ; likewise for even_odd
      ;,; lda even_odd
      and #$c0
      bne overlapping_plane
        clv
      bvc no_overlapping_plane  ;,; jmp no_overlapping_planes
      overlapping_plane:
        ;,; lda even_odd
        ;,; and #$80
        bmi dont_temp_subtract_y
          tya
          ;,; sec
          ;,; sbc #08
          sbc #8-1
            ; carry cleared is certain from 'adc #8' above
          tay
        dont_temp_subtract_y:
        bit loop_counter  ; set V
      no_overlapping_plane:

      ldx #$100-8
      asl plane_def
        ; If the entire plane is already all 0 or all 1 bits,
        ; then we know it'll be the same with or without
        ; rotation. So use the faster copy operation.
      bcc without_bit_flip
      lda block_header
      and #$08
      beq without_bit_flip
        flip_bits_loop:
          lsr plane_buffer+0
          ror
          lsr plane_buffer+1
          ror
          lsr plane_buffer+2
          ror
          lsr plane_buffer+3
          ror
          lsr plane_buffer+4
          ror
          lsr plane_buffer+5
          ror
          lsr plane_buffer+6
          ror
          lsr plane_buffer+7
          ror
          jsr write_byte_to_block_buffers
          iny
          inx
        bne flip_bits_loop
      beq end_plane_buffer_copy  ;,; jmp end_plane_buffer_copy
      without_bit_flip:
        copy_plane_loop:
          lda plane_buffer+8, x  ; TODO assert that this is a zeropage opcode.
          beq is_zero_byte
            jsr write_byte_to_block_buffers
          is_zero_byte:
            ; speed improvment by skipping XORing zeros
          iny
          inx
        bne copy_plane_loop
      end_plane_buffer_copy:

      ldy temp_y
        ; Restore Y as input pointer
      inc loop_counter
    bne plane_loop
  end_block:
  jsr read_next_byte
  sty donut_stream_ptr+0
  dec donut_block_count
rts

read_next_byte:
  iny
  bne no_inc_high_byte_2
    inc donut_stream_ptr+1
  no_inc_high_byte_2:
  lda (donut_stream_ptr), y
rts

write_byte_to_block_buffers:
  bvc not_both_planes
    sta temp_a
    eor donut_block_buffer+8, y
    sta donut_block_buffer+8, y
    lda temp_a
  not_both_planes:
  eor donut_block_buffer, y
  sta donut_block_buffer, y
rts

donut_decompress_block_table:
  .byte $00, $55, $aa, $ff
.endproc

;;
; helper subroutine for passing parameters with registers
; decompress X*64 bytes starting at AAYY to PPU_DATA
.proc donut_block_ayx
  sty donut_stream_ptr+0
  sta donut_stream_ptr+1
;,; jmp donut_block_x
.endproc
.proc donut_block_x
PPU_DATA = $2007
  stx donut_block_count
  block_loop:
    jsr donut_decompress_block
    ldx #$100-64
    upload_loop:
      lda donut_block_buffer-$100+64, x
      sta PPU_DATA
      inx
    bne upload_loop
    ldx donut_block_count
  bne block_loop
rts
.endproc
