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

.segment "ZEROPAGE"
donut_stream_ptr:       .res 2
donut_block_count:      .res 1
block_header:           .res 1
plane_def:              .res 1
pb8_ctrl:               .res 1
block_offset:           .res 1
block_offset_end:       .res 1
temp_y:                 .res 1
even_odd:               .res 1
plane_predict_by:       .res 1
plane_predict_by_xor:   .res 1
is_rotated:             .res 1
plane_buffer:           .res 8
plane_toggle:           .res 1

.segment "CODE"

.proc donut_decompress_block
  txa
  clc
  adc #64
  sta block_offset_end

  ldy #$00
  lda (donut_stream_ptr), y
    ; Reading a byte from the stream pointer will be pre-increment
    ; So save last increment until routine is done

  cmp #$c0
  bcc do_normal_block
  do_special_block:
    and #$01
    bne skip_block
    raw_block:
      raw_block_loop:
        iny
        lda (donut_stream_ptr), y
        sta donut_block_buffer, x
        inx
        cpy #65-1  ; size of a raw block, minus pre-increment
      bcc raw_block_loop
    skip_block:
  jmp end_block
  do_normal_block:
    sta block_header

    stx block_offset

    lda #$55
    sta plane_toggle

    lda block_header
    and #$03
    tax
    lda donut_decompress_block_table, x
    bne read_plane_def_from_stream
      iny
      lda (donut_stream_ptr), y
    read_plane_def_from_stream:
    sta plane_def

    lda block_header
    and #$08
    beq :+
      lda #$ff
    :
    sta is_rotated

    lda block_header
    and #$20
    beq :+
      lda #$ff
    :
    sta plane_predict_by

    lda block_header
    and #$10
    beq :+
      lda #$ff
    :
    eor plane_predict_by
    sta plane_predict_by_xor

    lda block_offset
    plane_loop:
      clc
      adc #8
      sta block_offset
      tax

      asl plane_def
      bcs do_pb8_plane
      do_zero_plane:
        sty temp_y
        lda plane_predict_by
        eor plane_predict_by_xor
        sta plane_predict_by
        ldy #8
        fill_plane_loop:
          dex
          sta donut_block_buffer, x
          dey
        bne fill_plane_loop
        ldy temp_y
      jmp end_plane
      do_pb8_plane:
        iny
        lda (donut_stream_ptr), y
        sta pb8_ctrl

        lda plane_predict_by
        eor plane_predict_by_xor
        sta plane_predict_by
        bit is_rotated
      bpl do_normal_pb8_plane
      do_rotated_pb8_plane:
        ldx #8
        buffered_pb8_loop:
          asl pb8_ctrl
          bcc buffered_pb8_use_prev
            iny
            lda (donut_stream_ptr), y
          buffered_pb8_use_prev:
          dex
          sta plane_buffer, x
        bne buffered_pb8_loop
        sty temp_y
        ldy #8
        ldx block_offset
        flip_bits_loop:
          asl plane_buffer+0
          ror
          asl plane_buffer+1
          ror
          asl plane_buffer+2
          ror
          asl plane_buffer+3
          ror
          asl plane_buffer+4
          ror
          asl plane_buffer+5
          ror
          asl plane_buffer+6
          ror
          asl plane_buffer+7
          ror
          dex
          sta donut_block_buffer, x
          dey
        bne flip_bits_loop
        ldy temp_y
      jmp end_plane
      do_normal_pb8_plane:
        sec
        rol pb8_ctrl
        pb8_loop:
          bcc pb8_use_prev
            iny
            lda (donut_stream_ptr), y
          pb8_use_prev:
          dex
          sta donut_block_buffer, x
          asl pb8_ctrl
        bne pb8_loop
      end_plane:
      asl plane_toggle
      bcc plane_pair_not_done
        bit block_header
        bpl not_xor_l_onto_m
          sty temp_y
          ldy #8
          xor_l_onto_m_loop:
            dex
            lda donut_block_buffer, x
            eor donut_block_buffer+8, x
            sta donut_block_buffer+8, x
            dey
          bne xor_l_onto_m_loop
          ldy temp_y
        not_xor_l_onto_m:
        bvc not_xor_m_onto_l
          sty temp_y
          ldy #8
          xor_m_onto_l_loop:
            dex
            lda donut_block_buffer, x
            eor donut_block_buffer+8, x
            sta donut_block_buffer, x
            dey
          bne xor_m_onto_l_loop
          ldy temp_y
        not_xor_m_onto_l:
      plane_pair_not_done:
      lda block_offset
      cmp block_offset_end
    beq plane_loop_skip
      jmp plane_loop
    plane_loop_skip:
  end_block:
  sec  ;,; iny   clc
  tya
  adc donut_stream_ptr+0
  sta donut_stream_ptr+0
  bcc add_stream_ptr_no_inc_high_byte
    inc donut_stream_ptr+1
  add_stream_ptr_no_inc_high_byte:
  ldx block_offset_end
  dec donut_block_count
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
