; ram.h
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
OAM = $0200

; main.s fields
.globalzp cur_keys, cur_trigger, new_keys, nmis, tvSystem
.global linebuf
USE_TITLE_MSGS = 0
; main.s methods
.global read_mouse_with_backward_buttons, read_zapper_trigger

; title.s methods
.global title_screen, no_games_error

; <mapper>.s ZP variables
start_bankptr    = $00  ; Pointer to the activity's outer bank number
start_entrypoint = $FE  ; Activity's entry point: JMP ($00FE)
start_mappercfg  = $02  ; Mapper configuration byte for this activity
; <mapper>.s methods
.global init_mapper, start_game

; cartmenu.s fields
.global draw_progress
.global tab_tilelens  ; reused as locals for draw_title_strings
; cartmenu.s methods
.global cart_menu, get_titledir_a

; paldetect.s methods
.global getTVSystem

; pads.s methods
.global read_pads

; mouse.s fields
.globalzp cur_mbuttons, new_mbuttons
; mouse.s methods
.global read_mouse, mouse_change_sensitivity

; ppuclear.s fields
.globalzp oam_used
; ppuclear.s methods
.global ppu_clear_nt, ppu_clear_oam, ppu_screen_on, ppu_wait_vblank

; paldetect.s methods
.global getTVSystem

; bcd.s methods
.global bcd8bit

; unpb8.s fields
.globalzp ciSrc, ciBufStart, ciBufEnd
.global PB53_outbuf, interbank_fetch_buf
; unpb8.s methods
.global unpb53_some, unpb53_block_ay, unpb53_block, interbank_fetch

; donut.s methods
.global donut_decompress_block, donut_block_ayx, donut_block_x
; donut.s fields
.global donut_block_buffer
.globalzp donut_stream_ptr, donut_block_count

; undte.s constants
DTE_OUTPUT_LEN = 64
; undte.s fields
dte_output_buf = interbank_fetch_buf + 128
; undte.s methods
.global undte_line, undte_line0

; vwf_draw.s methods
.global vwfStrWidth, vwfGlyphWidth, vwfPuts
.global clearLineImg, copyLineImg, invertTiles
.globalzp lineImgBufLen, FIRST_PRINTABLE_CU

; zapkernels.s methods
.global zapkernel_yonoff_ntsc

; identify.s constants
DETECT_2P_ZAPPER = $08
DETECT_1P_MOUSE = $01
; identify.s fields
.global detected_pads
; identify.s methods
.global identify_controllers

; quadpcm.s methods
.global quadpcm_test

; Directories
CHRDIR_START     = $FF02
SCREENSLIST      = $FF04
TITLELIST        = $FF06
PAGELIST         = $FF08
NAMESLIST        = $FF0A
DESCSLIST        = $FF0C
DESCSBANK        = $FF0E
TITLESCREEN      = $FF10
TITLESTRINGS     = $FF12
DTE_REPLACEMENTS = $FF14

TITLE_PRG_BANK    = $00
TITLE_CHR_BANK    = $01
TITLE_SCREENSHOT  = $02
TITLE_YEAR        = $03
TITLE_PLAYERS_TYPE= $04
TITLE_NAME_OFFSET = $08
TITLE_DESC_OFFSET = $0A
TITLE_ENTRY_POINT = $0C
TITLE_MAPPER_CFG  = $0E

TITLE_BASE_YEAR   = 1970
