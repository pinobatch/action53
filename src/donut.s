; "Donut", NES CHR codec decompressor,
; Copyright (c) 2018  Johnathan Roatch
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
; Version History:
; 2018-08-13: Changed the format of raw blocks to not be reversed.
;             Register X is now an argument for the buffer offset.
; 2018-04-30: Initial release.
;

.export donut_decompress_block, donut_block_ayx, donut_block_x
.export donut_block_buffer
.exportzp donut_stream_ptr
.exportzp donut_block_count

temp = $00  ; 16 bytes are used

donut_block_buffer = $0100  ; 64 bytes
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
  stx block_offset
  ldy #$00
  lda (donut_stream_ptr), y
    ; Reading a byte from the stream pointer will be pre-increment
    ; So save last increment until routine is done

  cmp #$c0
  bcc do_normal_block
  do_special_block:
    and #$01
    bne no_raw_block
      ;,; ldx block_offset
      raw_block_loop:
        iny
        lda (donut_stream_ptr), y
        sta donut_block_buffer, x
        inx
        cpy #65-1  ; size of a raw block, minus pre-increment
      bcc raw_block_loop
    no_raw_block:
    ;,; sec
    lda block_offset  ; add 64 to X even if it's a skip block
    adc #64-1
    tax
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
      tya  ;,; lda #$00
      ldy #(64/4)
      ; It's fine to count down to zero with Y, Because Y
      ; was certain to be $00 anyway due to the pre-increment setup.
      clear_block_loop:
        sta donut_block_buffer, x
        sta donut_block_buffer+16, x
        sta donut_block_buffer+32, x
        sta donut_block_buffer+48, x
        inx
        dey
      bne clear_block_loop
      ;,; ldy #$00
      ; no need to restore X now as it was already saved to block_offset
    no_clear_block_buffer:

    lda block_header
    and #$03
    tax
    lda donut_decompress_block_table, x
    bne read_plane_def_from_stream
      iny
      lda (donut_stream_ptr), y
    read_plane_def_from_stream:
    sta plane_def

    lda #$100-8
    sta loop_counter
      ; counter is negative so that we can use the
      ; high bits to easily set the V flag later.
    plane_loop:
      asl plane_def
      bcc do_zero_plane
      read_pb8:
        iny
        lda (donut_stream_ptr), y
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
            iny
            lda (donut_stream_ptr), y
          pb8_use_prev:
          sta plane_buffer, x
          dex
        bpl pb8_loop

        jsr setup_for_block_writing

        ldx #$100-8
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
            bvc not_both_planes_1
              sta temp_a
              eor donut_block_buffer+8, y
              sta donut_block_buffer+8, y
              lda temp_a
            not_both_planes_1:
            eor donut_block_buffer, y
            sta donut_block_buffer, y
            iny
            inx
          bne flip_bits_loop
        beq end_plane_buffer_copy  ;,; jmp end_plane_buffer_copy
        without_bit_flip:
          copy_plane_loop:
            bvc not_both_planes_2
              lda donut_block_buffer+8, y
              eor plane_buffer+8, x
              sta donut_block_buffer+8, y
            not_both_planes_2:
            lda donut_block_buffer, y
            eor plane_buffer+8, x  ; TODO assert that this is a zeropage opcode.
            sta donut_block_buffer, y
            iny
            inx
          bne copy_plane_loop
        end_plane_buffer_copy:
        ldy temp_y
          ; Restore Y as input pointer
        inc loop_counter
      bne plane_loop
    beq end_planes  ;,; jmp end_planes
      do_zero_plane:
        jsr setup_for_block_writing

        lda even_odd
        eor block_header
        and #$30
        beq not_fully_inverting_planes
          ldx #$100-8
          fill_plane_loop:
            bvc not_both_planes_3
              lda donut_block_buffer+8, y
              eor #$ff
              sta donut_block_buffer+8, y
            not_both_planes_3:
            lda donut_block_buffer, y
            eor #$ff
            sta donut_block_buffer, y
            iny
            inx
          bne fill_plane_loop
        not_fully_inverting_planes:
        ldy temp_y
          ; Restore Y as input pointer
        inc loop_counter
      beq long_jump_plane_loop
        jmp plane_loop
      long_jump_plane_loop:
    end_planes:
    ldx block_offset
  end_block:
  sec  ;,; iny   clc
  tya
  adc donut_stream_ptr+0
  sta donut_stream_ptr+0
  bcc add_stream_ptr_no_inc_high_byte
    inc donut_stream_ptr+1
  add_stream_ptr_no_inc_high_byte:
  dec donut_block_count
rts

donut_decompress_block_table:
  .byte $00, $55, $aa, $ff

setup_for_block_writing:
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
rts
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
    ldx #64
    jsr donut_decompress_block
    ldx #64
    upload_loop:
      lda donut_block_buffer, x
      sta PPU_DATA
      inx
    bpl upload_loop
    ldx donut_block_count
  bne block_loop
rts
.endproc
