; Activity selection menu for Action 53
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.

.include "nes.inc"
.include "global.inc"
.include "pently.inc"

.export cart_menu, get_titledir_a
.exportzp ciSrc0, ciSrc1
ciSrc0 = tab_data_ptr
ciSrc1 = desc_data_ptr

; Above the break
SPRITE_0_TILE = $01
BLANK_TILE = $02
OVERLINE_TILE = $03
TLCORNER_TILE = $04
TRCORNER_TILE = $05
TABTITLE_LEFT_SIDE = $06
TABTITLE_RIGHT_SIDE = $07
TABTITLE_LEFT_OVERLAP = $08
TABTITLE_RIGHT_OVERLAP = $09
TAB_ARROW_TILE = $0F
TABTITLE_FIRST_TILE = $158

; Below the break
;BLANK_TILE = $02
BLCORNER_TILE = $04
BRCORNER_TILE = $05
SCREENSHOT0_BASE_ADDR = $0200
SCREENSHOT_BASE_ADDR = $1200


.segment "KEYBLOCK"
FF00: .res 20

MAX_TABS = 8
MAX_LINES = 20
.segment "ZEROPAGE"
; During setup this points to the name of a tab.  But while the
; menu is running it points to the start of the tab->title table.
tab_data_ptr: .res 2

; Pointer to the data of the screenshot or description being
; accessed.
desc_data_ptr: .res 2

.segment "BSS"
tab_tilelens: .res MAX_TABS
tab_xoffsets: .res MAX_TABS
tab_title_offsets: .res MAX_TABS
draw_step: .res 1
blit_step: .res 1
draw_progress: .res 1
num_pages: .res 1
cur_page: .res 1
cur_titleno: .res 1

; number of pixels down the screen (>= 192: offscreen)
zapper_y: .res 1
last_trigger:  .res 1

; Number of pixels the Super NES Mouse has moved.
; Wrap X within 0-15 and Y within 0-7 and generate controller presses
; each time it moves.
mouse_x: .res 1
mouse_y: .res 1

; Zero if showing a title list or nonzero if showing a description
showing_description: .res 1

; Bit 7: True if the screenshot is partially loaded
; Bit 6-0: The title whose screenshot is currently loaded
screenshot_titleno: .res 1

screenshot_header:
screenshot_colors: .res 6
screenshot_attributes: .res 7
screenshot_header_end:

; An estimate, in some cases an overestimate, of how many nonblank
; lines are on this title list or description page
num_lines_on_page: .res 1

; The number of nonblank lines on the previous page, so that we
; know how many blank lines to copy
prev_lines_on_page: .res 1

; draw steps
DRAWS_IDLE = 0
DRAWS_TABS = 2
  ; single frame: draw borders under tabs
  ; next step TITLELIST or DESCRIPTION
DRAWS_TITLELIST = 4
  ; draw_progress is line number (0 to MAX_LINES - 1)
  ; next step ARROWCURSOR
DRAWS_DESCRIPTION = 6
  ; draw_progress 0: title; 1: (C) year author; 2: number of players;
  ; 3: blank row; 4+: description
  ; next step ARROW
DRAWS_ARROW = 8
  ; single frame: draw arrow to left of title list
  ; next step SCREENSHOT
DRAWS_SCREENSHOT = 10
  ; draw_progress 0-6: tile row to decompress to SCREENSHOT_BASE_ADDR
  ; next step IDLE

MOUSE_TAB_WIDTH = 32
MOUSE_LISTENTRY_HEIGHT = 8

.segment "CODE"
.proc cart_menu
  jsr ppu_wait_vblank
  jsr setup_card_bg
  lda #0
  sta cur_page
  sta cur_titleno
  sta num_lines_on_page
  sta showing_description
  sta mouse_x
  sta mouse_y
  sta prev_lines_on_page
  lda #$FF
  sta screenshot_titleno
  sta zapper_y

  jsr pently_update
  lda #DRAWS_TABS
  sta draw_step
  lda PAGELIST
  sta tab_data_ptr
  lda PAGELIST+1
  sta tab_data_ptr+1
  jsr pently_update

.if 0
  lda #1
  jsr pently_start_music
.else
  jsr pently_stop_music
.endif

  jsr cartmenu_setup_oam
  jsr hide_screenshot

forever:
  lda #8  ; 0: sprite 0 for timing; 4: arrow sprite
  sta oam_used

  lda screenshot_titleno
  cmp cur_titleno
  bne no_screenshot
    jsr show_screenshot
  no_screenshot:
  jsr wait_sprite_0
  jsr draw_step_dispatch
  jsr ppu_wait_vblank
  ldx #0
  lda #>OAM
  stx OAMADDR
  sta OAM_DMA
  jsr blit_step_dispatch
  ldx #0
  ldy #0
  lda #VBLANK_NMI|BG_1000|OBJ_1000
  sec
  jsr ppu_screen_on
  jsr pently_update
  
; And the rest of the main loop handles the mouse, Zapper, and
; standard controller.  Input from the mouse and the Zapper's
; trigger is translated into keypresses.

  jsr read_pads

  lda detected_pads
  and #DETECT_1P_MOUSE
  beq mouse_no_move
  ldx #0
  jsr read_mouse_with_backward_buttons

  ; Has the mouse moved far enough horizontally?
  lda 3
  bpl :+
  sec
  eor #$7F
  adc #0
:
  clc
  adc mouse_x
  sta mouse_x
  bpl mouse_moved_right
  clc
  adc #MOUSE_TAB_WIDTH
  sta mouse_x
  lda #KEY_LEFT
  ora new_keys
  sta new_keys
  bne mouse_no_move
mouse_moved_right:
  cmp #MOUSE_TAB_WIDTH * 5 / 4
  bcc mouse_no_x_move
  sbc #MOUSE_TAB_WIDTH
  sta mouse_x
  lda #KEY_RIGHT
  ora new_keys
  sta new_keys
  bne mouse_no_move

mouse_no_x_move:

  ; Has the mouse moved far enough vertically?
  lda 2
  bpl :+
  sec
  eor #$7F
  adc #0
:
  clc
  adc mouse_y
  sta mouse_y
  bpl mouse_moved_down
  clc
  adc #MOUSE_LISTENTRY_HEIGHT
  sta mouse_y
  lda #KEY_UP
  ora new_keys
  sta new_keys
  bne mouse_no_move
mouse_moved_down:
  cmp #MOUSE_LISTENTRY_HEIGHT * 5 / 4
  bcc mouse_no_move
  sbc #MOUSE_LISTENTRY_HEIGHT
  sta mouse_y
  lda #KEY_DOWN
  ora new_keys
  sta new_keys
  bne mouse_no_move

mouse_no_move:

  lda showing_description
  bne no_zapper_move
  lda zapper_y
  lsr a
  lsr a
  lsr a
  cmp #MAX_LINES
  bcs no_zapper_move
  ldy cur_page
  beq :+
  adc (tab_data_ptr),y
:
  cmp cur_titleno
  beq no_zapper_move
  iny
  cmp (tab_data_ptr),y
  bcs no_zapper_move
  
  sta cur_titleno
  jsr move_to_page_with_title
no_zapper_move:

  ; Read zapper trigger
  jsr read_zapper_trigger
  ora #$00
  beq no_zapper_trigger

  lda zapper_y
  cmp #168
  bcs zapper_offscreen
  lda #KEY_A
  bne have_zapper_keypresses
zapper_offscreen:
  lda showing_description
  beq zapper_page_switch
  lda #KEY_B
  bne have_zapper_keypresses
zapper_page_switch:
  lda #KEY_RIGHT
have_zapper_keypresses:
  ora new_keys
  sta new_keys
no_zapper_trigger:

  lda new_keys
  lsr a
  bcc notRight
  lda #6
  jsr pently_start_sound
  lda #5
  jsr pently_start_sound
  ldx cur_page
  inx
  cpx num_pages
  bcc :+
  ldx #0
:
  stx cur_page
  jsr move_to_start_of_page
  jmp needTabsDrawn
notRight:

  lsr a
  bcc notLeft
  lda #6
  jsr pently_start_sound
  lda #5
  jsr pently_start_sound
  
  lda cur_page
  bne :+
  lda num_pages
  sta cur_page
:
  dec cur_page
  jsr move_to_end_of_page
needTabsDrawn:
  lda #DRAWS_TABS
  sta draw_step
  bne notUp
notLeft:

  lsr a
  bcc notDown
  inc cur_titleno
  lda cur_titleno
  ldy num_pages
  cmp (tab_data_ptr),y
  bcc notDownWrap
  lda #0
  sta cur_titleno
notDownWrap:
  jsr move_to_page_with_title
  jmp resetMouseX
notDown:

  lsr a
  bcc notUp
  lda cur_titleno
  bne notUpWrap
  ldy num_pages
  lda (tab_data_ptr),y
  sta cur_titleno
notUpWrap:
  dec cur_titleno
  jsr move_to_page_with_title
resetMouseX:
  lda #MOUSE_TAB_WIDTH * 5 / 8
  sta mouse_x
notUp:

  bit new_keys
  bpl notA
  lda showing_description
  bne done
  lda #1
  sta showing_description
  lda #DRAWS_TABS
  sta draw_step
notA:

  bit new_keys
  bvc notB
  lda showing_description
  beq notB
  lda #0
  sta showing_description
  lda #DRAWS_TABS
  sta draw_step
notB:

  lda new_keys
  and #KEY_START
  bne done
  jmp forever
done:
  jsr pently_stop_music
  jsr pently_update
  lda cur_titleno
  rts  
.endproc

.proc move_to_page_with_title
  lda #5
  jsr pently_start_sound
  lda showing_description
  beq not_showing_desc

  ; If showing the description, always reset the draw step to tabs.
  lda #DRAWS_TABS
  bne have_draw_step
not_showing_desc:

  ; If showing the title list, reset the draw step to arrow
  ; unless the current draw step is TITLELIST.
  lda draw_step
  cmp #DRAWS_TITLELIST
  beq noDrawReset
  lda #DRAWS_ARROW
have_draw_step:
  sta draw_step
noDrawReset:

  ; We need to find the first page where the page start is greater
  ; than the titleno, and then use the page before that.
  ldy #1
srchloop:
  lda (tab_data_ptr),y
  cmp cur_titleno
  beq not_found
  bcs found
not_found:
  iny
  cpy num_pages
  bcc srchloop
found:
  dey
  cpy cur_page
  beq right_page
  sty cur_page
  lda #DRAWS_TABS
  sta draw_step
  lda #6
  jsr pently_start_sound
right_page:
  rts
.endproc

.proc move_to_start_of_page
  ldy cur_page
  tya
  beq :+
  lda (tab_data_ptr),y
:
  sta cur_titleno
  rts
.endproc

.proc move_to_end_of_page
  ldy cur_page
  iny
  lda (tab_data_ptr),y
  sec
  sbc #1
  sta cur_titleno
  rts
.endproc


;;
; Point tab_data_ptr at the first tab's title.
.proc iter_tab_titles
  lda PAGELIST
  sta tab_data_ptr
  lda PAGELIST+1
  sta tab_data_ptr+1
  ldy #0
  lda (tab_data_ptr),y
  sta num_pages
  sec
  adc tab_data_ptr
  sta tab_data_ptr
  bcc :+
  inc tab_data_ptr+1
:
  rts
.endproc

.proc setup_card_bg

  ; First fill the palette
  lda #VBLANK_NMI
  sta PPUCTRL
  lda #$3F
  sta PPUADDR
  ldx #$00
  stx PPUADDR
  stx PPUMASK
:
  lda card_palette,x
  sta PPUDATA
  inx
  cpx #32
  bcc :-
  
  ; clear background to black
  lda #$00
  tay
  ldx #$20
  jsr ppu_clear_nt

.if 0
  ; clear tiles used for 10-color screenshot until 10-color
  ; screenshot is implemented
  ldx #>SCREENSHOT0_BASE_ADDR
  jsr ppu_clear_nt
.endif

  ; clear tiles used for tabs
  ldx #TABTITLE_FIRST_TILE >> 4
  jsr ppu_clear_nt

  ; Load non-text tiles used for select screen
  lda #$00
  sta PPUADDR
  sta PPUADDR
  lda #>select_tiles_chr
  ldy #<select_tiles_chr
  ldx #512/64
  jsr donut_block_ayx

  ; Copy the tiles used for sprites 0 and 1 and top tabborders
  ; to the second pattern table tiles $00 through $0F
  lda #$10
  sta PPUADDR
  lda #$00
  sta PPUADDR
  ldx #256/64
  jsr donut_block_x

  ; Steps to get the menu up:
  ; 1. Load the attribute table
  ; 2. Find width of each tab in tiles
  ; 3. Draw text to tabs.
  ; 4. Draw tab headers to nametable.
  ; 5. Draw card including TV frame.
  ; 6. Draw text lines.
  
  ; Attribute table: leftmost 7 units grayscale, rest colored for
  ; 10 lines of text on top and 10 on bottom
  ; 01234567890123456789012345678901
  ; 0 0 0 0 0 0 0 x x x x x x x x x
  lda #$23
  sta PPUADDR
  lda #$C8
  sta PPUADDR
  ldx #0
attrloop:
  lda #$00
  sta PPUDATA
  sta PPUDATA
  sta PPUDATA
  lda card_attrtable,x
  and #%11001100  ; left half zero, right half xx
  sta PPUDATA
  lda card_attrtable,x
  sta PPUDATA
  sta PPUDATA
  sta PPUDATA
  sta PPUDATA
  inx
  cpx #6
  bcc attrloop

  ; Now find the width of each tab's title.
  ; I could pre-cache tab title widths in Python, but I felt like
  ; writing it in 6502 asm instead.  If the menu segment fills up,
  ; I might consider moving it back out to Python instead.
  jsr iter_tab_titles
  ldx #0
calcwid_width = 3
calcwid_strlen = 4
calcwidloop:

  ; First measure in pixels.
  stx draw_progress
  clc
  ldy tab_data_ptr
  lda tab_data_ptr+1
  jsr vwfStrWidth  ; deposits pointer to string in $00-$01
  sta calcwid_width
  sty calcwid_strlen

  ; If the remainder after dividing by 8 is one, see if the
  ; rightmost pixel can be ignored by looking at the glyph.
  and #$07
  cmp #1
  bne notRemainderOne

  ; actually look at the last glyph using vwfGlyphWidth
  ; (which trashes $06-$07)
  dey
  lda ($00),y
  jsr vwfGlyphWidth
cmploop:
  dex
  asl a
  bne cmploop
  cpx #$00
  beq notRemainderOne
  bmi notRemainderOne
  txa
  eor #$FF
  sec
  adc calcwid_width
  sta calcwid_width
notRemainderOne:

  ; Divide by 8 and round up, giving tile count.
  lda calcwid_width
  lsr a
  adc #3
  lsr a
  lsr a
  ldx draw_progress
  sta tab_tilelens,x

  ; Multiply by 8, subtract the width to get X offset.
  asl a
  asl a
  asl a
  sec
  sbc calcwid_width
  lsr a
  sta tab_xoffsets,x
  lda calcwid_strlen
  sec
  adc tab_data_ptr
  sta tab_data_ptr
  bcc :+
  inc tab_data_ptr+1
:
  inx
  cpx num_pages
  bcc calcwidloop

  ; TO DO: Fail if more than 8 tabs, more than 24 tiles, or
  ; if (2 * tabs) + tiles > 28.

  ; Now draw the tabs' text.
  jsr iter_tab_titles
  ldx #0
tab_draw_pass:
tiles_filled_this_pass = 2
drawing_tab = 3
  stx draw_progress  ; at the start of this pass
  stx drawing_tab
  lda #0
  sta tiles_filled_this_pass
  jsr clearLineImg

  ; Now draw as many as will fit in 16 tiles, each at
  ; x = 8 * running tile count so far + X offset
tab_draw_one:

  lda tiles_filled_this_pass
  asl a
  asl a
  asl a
  ldx drawing_tab
  adc tab_xoffsets,x
  sta 0
  clc
  lda tiles_filled_this_pass
  adc tab_tilelens,x
  cmp #16
  bcs this_pass_done
  sta tiles_filled_this_pass
  clc
  ldy tab_data_ptr
  lda tab_data_ptr+1
  ldx 0
  jsr vwfPuts
  iny
  bne :+
  clc
  adc #1
:
  sty tab_data_ptr
  sta tab_data_ptr+1
  inc drawing_tab
  lda drawing_tab
  cmp num_pages
  bcc tab_draw_one
this_pass_done:

  ; Invert tiles (white=1, black=0)
  lda tiles_filled_this_pass
  jsr invertTiles

  ; Set the VRAM destination based on the total tile width of
  ; previous tabs and blit.
  ldx draw_progress
  lda #<TABTITLE_FIRST_TILE
  dex
  bmi noprevtabs
addprevtabs:
  clc
  adc tab_tilelens,x
  dex
  bpl addprevtabs
noprevtabs:
  sta 0
  lda #>TABTITLE_FIRST_TILE
  sec
  rol 0
  rol a
  asl 0
  rol a
  asl 0
  rol a
  asl 0
  rol a
  ldy 0
  jsr copyLineImg

  ldx drawing_tab
  cpx num_pages
  bcc tab_draw_pass
  
  ; End of shit that could (should?) have been done statically
  ; in Python

  ; 2012-10-06: Certain combinations of tab lengths could cause one
  ; of the tab blits to overflow into the text area.  This means we
  ; have to clear the text area after loading the tab labels.
  ldx #VBLANK_NMI
  stx PPUCTRL
  lda #$06
  ldx #$00
  sta PPUADDR
  stx PPUADDR
  lda #$FF
  ldy #MAX_LINES/2
clrtxt:
  sta PPUDATA
  dex
  bne clrtxt
  dey
  bne clrtxt

  jsr pently_update

  ; Now with the tiles set up, we FINALLY get to start
  ; drawing the nametable.
  ; Rows 0-2: black
  ; Row 3: tab headers
  ; Row 4: underline non-selected tabs
  ; Row 5: fullwidth white
  ; Rows 6-25: Card body
  ; Row 26: Bottom of card
  ; Rows 27-29: black

  ; For each tab draw one left side, a number of unique
  ; tiles starting at TABTITLE_FIRST_TILE corresponding to the tile
  ; width, and one right side
  ldx #0
  stx draw_progress
  lda #$20
  sta PPUADDR
  lda #$62
  sta PPUADDR
  ldy #<TABTITLE_FIRST_TILE
  lda #TABTITLE_LEFT_SIDE
each_nttab:
  sta PPUDATA
  lda tab_tilelens,x
  sta 0
nttabloop:
  sty PPUDATA
  iny
  dec 0
  bne nttabloop
  inx
  cpx num_pages
  lda #TABTITLE_RIGHT_OVERLAP
  bcc each_nttab
  lda #TABTITLE_RIGHT_SIDE
  sta PPUDATA

  ; Blank row above card body
  lda #$20
  sta PPUADDR
  lda #$A1
  sta PPUADDR
  lda #BLANK_TILE
  ldx #30
blankrowattoploop:
  sta PPUDATA
  dex
  bne blankrowattoploop

  ; To draw card body:
  ; 31, 0: black
  ; 1-2: white
  ; 3-12: tv
  ; 13: white
  ; 14: arrow
  ; 15-30: text
  ; 31: black
screenshot_tile = $04
  lda #<(SCREENSHOT0_BASE_ADDR >> 4)
  sta screenshot_tile

cardbodyloop:
  stx draw_progress
  lda #$00
  sta PPUDATA
  sta PPUDATA
  lda #$02
  sta PPUDATA
  sta PPUDATA
  cpx #row_below_tv-tv_rows
  bcc :+
  ldx #row_below_tv-tv_rows
:
  ldy tv_rows,x
  ldx #10
tvloop:
  lda tv_shape,y
  bne :+
    lda screenshot_tile
    inc screenshot_tile
  :
  sta PPUDATA
  iny
  dex
  bne tvloop
  ldx #2
  stx PPUDATA
  inx
  stx PPUDATA
  
  ; now we have the left half of this row of the card done;
  ; the rest is the text half
  lda draw_progress
  cmp #MAX_LINES/2
  bcc :+
  sbc #MAX_LINES/2
:
  asl a
  asl a
  asl a
  asl a
  adc #$60
  tax
  ldy #16
texthalfloop:
  stx PPUDATA
  inx
  dey
  bne texthalfloop

  ldx draw_progress
  inx
  cpx #MAX_LINES
  bcc cardbodyloop

  sty PPUDATA
  sty PPUDATA
  lda #BLCORNER_TILE
  sta PPUDATA
  lda #BLANK_TILE
  ldx #28
blankrowatbottomloop:
  sta PPUDATA
  dex
  bne blankrowatbottomloop
  lda #BRCORNER_TILE
  sta PPUDATA
  rts
.endproc

; Updating the screen while the menu is on ;;;;;;;;;;;;;;;;;;;;;;;;;;

;;
; Loads a pointer to a title directory record.
; XY not modified.
;
; The titledir format is
; 0: PRG bank number
; 1: CHR bank number
; 2: Screenshot number
; 3: Year minus 1970
; 4: Number of players type
; 5-7: unused
; 8: 2-byte offset to title and author within the name block
; 10: 2-byte offset to description within the description block
; 12: 2-byte reset vector
; 14-15: unused
; @param A title number
; @return pointer in $00-$01
.proc get_titledir_a
  sta 0
  lda #$00
  sta 1
  lda 0
  .repeat 4
  asl a
  rol 1
  .endrepeat
  adc TITLELIST
  sta 0
  lda 1
  adc TITLELIST+1
  sta 1
  rts
.endproc

.proc wait_sprite_0

waits0_off:
  bit PPUSTATUS
  bvs waits0_off
  lda #$C0  ; End loop at sprite 0 or, if sprite 0 fails, vblank
waits0_on:
  bit PPUSTATUS
  beq waits0_on
  
  lda #VBLANK_NMI|OBJ_1000|BG_0000
  sta PPUCTRL
  rts
.endproc

;;
; Prepares a buffer to be copied to the screen, based on the current
; draw_step and draw_progress.
.proc draw_step_dispatch
  ldx draw_step
  
  ; If the Zapper is present, run measure_zapper more often
  lda detected_pads
  and #DETECT_2P_ZAPPER
  beq not_zapper_periodic
  lda nmis
  and #$03
  bne not_zapper_periodic
    tax
  not_zapper_periodic:

  stx blit_step
  lda steps+1,x
  pha
  lda steps,x
  pha
  rts
steps:
  .addr measure_zapper-1
  .addr draw_step_tabborder-1
  .addr draw_step_titlelist-1
  .addr draw_step_description-1
  .addr measure_zapper-1
  .addr draw_step_screenshot-1
.endproc

;;
; Copies a buffer to the screen, based on the current
; draw_step and draw_progress.
.proc blit_step_dispatch
  ldx blit_step
  lda steps+1,x
  pha
  lda steps,x
  pha
doNothing:
  rts
steps:
  .addr doNothing-1
  .addr blit_step_tabborder-1
  .addr blit_step_vwf-1
  .addr blit_step_vwf-1
  .addr blit_step_arrow-1
  .addr blit_step_screenshot-1
.endproc

;;
; Reads the distance from sprite 0 using the Zapper.
.proc measure_zapper
  lda detected_pads
  and #DETECT_2P_ZAPPER
  beq zapper_is_offscreen

  ; we've hit sprite 0;
  ; now measure how far down the Zapper is
  ldy #168
  jsr zapkernel_yonoff_ntsc

  lda 0  ; Height of Zapper (0=top, 192=bottom)
  ldy 1  ; Height of photodiode signal
  ; If the height of the photodiode activated area is 1-127
  ; then a Zapper is plugged in and pointed at something.
  ; If the height is 0 then the Zapper is pointed offscreen.
  ; If the height >= 128 then the Zapper is unplugged
  ; and the photodiode signal is always on.
  beq zapper_is_offscreen
  bpl zapper_have_y
zapper_is_offscreen:
  lda #255
  sta zapper_y
  rts
zapper_have_y:

  ; Multiply height by 17/16 if on PAL NES
  ; (NTSC and Dendy don't need it)
  ldy tvSystem
  cpy #1
  bne not_pal
  lsr a
  lsr a
  lsr a
  lsr a
  adc 0
not_pal:
  sta zapper_y
  rts
.endproc


;;
; Move sprite 1 below the center of the selected tab.
.proc draw_step_tabborder
  ldx #0
  lda #2
findxloop:
  cpx cur_page
  beq found_x
  clc
  adc tab_tilelens,x
  inx
  adc #1
  bcc findxloop
found_x:
  asl a
  sec
  adc tab_tilelens,x
  asl a
  asl a
  sta OAM+7
  rts
.endproc

TABBORDER_ADDR = $2082
TABBORDER_WIDTH = 28

;;
; Draws the bottom border of each tab, which shows the user
; which pane is selected.
.proc blit_step_tabborder
tabborder_addr_lo = $00
lside = $01

  ; For each tab draw two more than the tile width, in blank ($02)
  ; if the tab is selected or card top border if not.
  lda #VBLANK_NMI
  sta PPUCTRL
  ldx #0
  stx draw_progress
  lda #>TABBORDER_ADDR
  sta PPUADDR
  lda #<TABBORDER_ADDR-1
  sta PPUADDR
  lda #<TABBORDER_ADDR
  sta tabborder_addr_lo
  lda #TLCORNER_TILE
  sta PPUDATA
each_nttab:
  ldy tab_tilelens,x
  iny
  lda #OVERLINE_TILE
  cpx cur_page
  bne nttabloop
    ; The current tab has no bottom border, and it is 1 cell
    ; wider to account for overlap
    iny
    lda tabborder_addr_lo
    sbc #32
    sta lside
    lda #BLANK_TILE
  nttabloop:
  sta PPUDATA
  inc tabborder_addr_lo
  dey
  bne nttabloop
  inx
  cpx num_pages
  bcc each_nttab

  ; fill in extra space to the right of the rightmost tab
;  sec
  lda #<(TABBORDER_ADDR + TABBORDER_WIDTH)
  sbc tabborder_addr_lo
  beq trcorner
  bcc no_extra_overline
  tax
  lda #OVERLINE_TILE
finishloop:
  sta PPUDATA
  dex
  bne finishloop
trcorner:
  lda #TRCORNER_TILE
  sta PPUDATA
no_extra_overline:

  ; If the current tab is not the first, draw the left side tab border
  ldx cur_page
  beq no_loverlap
    lda #>(TABBORDER_ADDR - 32)
    sta PPUADDR
    lda lside
    sta PPUADDR
    lda #TABTITLE_LEFT_OVERLAP
    sta PPUDATA
  no_loverlap:
  inx
  cpx num_pages
  bcs no_roverlap
    lda #>(TABBORDER_ADDR - 32)
    sta PPUADDR
    lda lside
    sec
    adc tab_tilelens-1,x
    sta PPUADDR
    lda #TABTITLE_RIGHT_OVERLAP
    sta PPUDATA
  no_roverlap:

  lda #0
  sta draw_progress

  ; Choose next step
  lda #DRAWS_TITLELIST
  ldy showing_description
  beq have_next_step
  lda #DRAWS_DESCRIPTION
  bne have_next_step

arrow_only:
  lda #0
  sta draw_progress
  lda cur_titleno
  eor screenshot_titleno
  beq have_next_step
  lda #DRAWS_SCREENSHOT
have_next_step:
  sta draw_step
  lda cur_titleno
  ldy cur_page
  cpy #0
  beq :+
  sbc (tab_data_ptr),y
:
  tay  ; Y = number of rows until selected game
  iny

  ; hide the arrow if the description is showing
  lda showing_description
  beq not_hide_for_description
  ldy #0
not_hide_for_description:
  ldx #MAX_LINES
  lda #VBLANK_NMI|VRAM_DOWN
  sta PPUCTRL
  lda #$20
  sta PPUADDR
  lda #$CE
  sta PPUADDR
loop:
  lda #$03
  dey
  bne notArrowHere
  lda #$01
notArrowHere:
  sta PPUDATA
  dex
  bne loop
  rts
.endproc
blit_step_arrow = blit_step_tabborder::arrow_only

.proc draw_step_titlelist
  jsr clearLineImg
  clc
  lda cur_page
  tay
  beq :+
  lda (tab_data_ptr),y
:
  adc draw_progress
  iny
  cmp (tab_data_ptr),y
  bcs past_last_title_on_page
  
  jsr get_titledir_a
have_titledir:
  lda #MAX_LINES
  sta num_lines_on_page
  clc
  ldy #8
  lda NAMESLIST
  adc (0),y
  sta 2
  iny
  lda NAMESLIST+1
  adc (0),y
  ldy 2
  ldx #0
  jsr vwfPuts
  sta desc_data_ptr+1
  sty desc_data_ptr
  jmp line_ready

past_last_title_on_page:
  lda num_lines_on_page
  cmp #MAX_LINES
  bcc line_ready
  lda draw_progress
  sta num_lines_on_page

line_ready:
  ; now copy the line
  lda #16
  jmp invertTiles


.endproc

.proc blit_step_vwf
  lda draw_progress
  
  ; are we finished writing this page's text?
  cmp num_lines_on_page
  bcs done_writing_new_text
  ; if not, log this row as filled
  cmp prev_lines_on_page
  bcc not_last_row
  sta prev_lines_on_page
  inc prev_lines_on_page
  bne not_last_row

done_writing_new_text:  
  ; are we finished clearing out the previous page's text?
  cmp prev_lines_on_page
  bcc not_last_row
  ldy num_lines_on_page
  sty prev_lines_on_page
  ldy #DRAWS_ARROW
  sty draw_step
  
  ; 2014-05-24: Was trying to write a 21st line of text,
  ; corrupting part of the screenshot
  jmp blit_step_arrow  

not_last_row:
  ldy #$00
  cmp #MAX_LINES/2
  bcc not2ndhalf
  sbc #MAX_LINES/2
  clc
  ldy #$08
not2ndhalf:
  adc #$06
  inc draw_progress
  jmp copyLineImg
.endproc

.proc draw_step_description
  jsr clearLineImg
  lda cur_titleno
  jsr get_titledir_a

  lda draw_progress
  beq draw_step_titlelist::have_titledir
  cmp #2
  bcc continue_title     ; 1. year and author
  beq do_players         ; 2. player count
  cmp #4
  bcc line_done          ; 3. blank line
  beq start_description  ; 4. first line of description
  jmp continue_description
continue_title:
  lda screenshot_titleno
  cmp cur_titleno
  beq :+
    jsr hide_screenshot
  :
  ldy #'2'
  sty interbank_fetch_buf
  ldy #'0'
  sty interbank_fetch_buf+1
  ldy #0
  sty interbank_fetch_buf+4
  ldy #3
  lda (0),y
  sec
  sbc #2000-1970
  bcs not_before_2000
  dec interbank_fetch_buf
  ldy #'9'
  sty interbank_fetch_buf+1
  adc #256-100
not_before_2000:
  jsr bcd8bit
  ora #'0'
  sta interbank_fetch_buf+3
  lda 0
  and #$0F
  ora #'0'
  sta interbank_fetch_buf+2
  lda 0
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc interbank_fetch_buf+1
  sta interbank_fetch_buf+1
  lda #>interbank_fetch_buf
  ldy #<interbank_fetch_buf
  ldx #0
  jsr vwfPuts

  lda desc_data_ptr+1
  ldy desc_data_ptr
  ldx #24
  bne have_line_ptr_with_x
do_players:
  ldy #4
  lda (0),y
  asl a
  tax
  lda numplayers_names+1,x
  ldy numplayers_names,x
have_line_ptr:
  ldx #0
have_line_ptr_with_x:
  jsr vwfPuts
line_done:
  lda #16
  jmp invertTiles

start_description:
  ldy #10
  clc
  lda (0),y
  adc DESCSLIST
  sta desc_data_ptr
  iny
  lda (0),y
  adc DESCSLIST+1
  sta desc_data_ptr+1

continue_description:
  lda desc_data_ptr
  sta 0
  lda desc_data_ptr+1
  sta 1
  lda #<DESCSBANK
  sta 2
  lda #>DESCSBANK
  sta 3
  lda #48
  sta 4
  lda #10
  sta interbank_fetch_buf+48
  jsr interbank_fetch
  lda interbank_fetch_buf+0
  bne not_eot
  lda num_lines_on_page
  cmp #MAX_LINES
  bcc line_done
  lda draw_progress
  sta num_lines_on_page
  jmp line_done
not_eot:
  lda #>interbank_fetch_buf
  ldy #<interbank_fetch_buf
  ldx #0
  jsr vwfPuts
  tya
  sec
  sbc #<interbank_fetch_buf
  clc
  adc desc_data_ptr
  sta desc_data_ptr
  bcc line_done
  inc desc_data_ptr+1
  jmp line_done
.endproc

.proc draw_step_screenshot
  ; screenshot id is titledir[0]
  ; screenshot directory entry format:
  ; bank, addr lo, addr hi

ssdiroffset = $00
screenshotent = $02
num_bytes = $04

  ; Put the first bank of the screenshot in screenshotent
  ; so that interbank fetch can retrieve the expected data
  lda cur_titleno
  jsr get_titledir_a
  ldy #TITLE_SCREENSHOT
  lda (0),y  ; A = screenshot ID

  ; Calculate the offset in the screenshot directory
  sta ssdiroffset+0
  ldy #0
  sty ssdiroffset+1
  asl a
  adc ssdiroffset+0
  rol ssdiroffset+1  ; (ssdiroffset+1):A = screenshot ID * 3

  ; And add the pointer
  clc
  adc SCREENSLIST
  sta screenshotent
  lda ssdiroffset+1
  adc SCREENSLIST+1
  sta screenshotent+1

ibfsrc = $00
ibflen = $04

  lda draw_progress
  bne header_already_loaded

    ; Hide the screenshot in OAM
    lda cur_titleno
    ora #$80
    sta screenshot_titleno
    jsr hide_screenshot
    
    ; Seek to the screenshot's header
    ldy #1
    lda (screenshotent),y
    sta ibfsrc
    clc
    adc #screenshot_header_end-screenshot_header
    sta desc_data_ptr
    iny
    lda (screenshotent),y
    sta ibfsrc+1
    adc #0
    sta desc_data_ptr+1
    lda #screenshot_header_end-screenshot_header
    sta ibflen

    ; If bus conflict avoidance needed to search for a $FF byte
    ; to return home, the IBF bank may no longer be correct.
    lda screenshotent+1
    pha
    lda screenshotent+0
    pha
    jsr interbank_fetch
    pla
    sta screenshotent+0
    pla
    sta screenshotent+1

    ; Load palette (bytes 0-5) and sprite attribute table
    ; (bytes 6-12) from screenshot header
    ldx #screenshot_header_end-screenshot_header-1
    loadheaderloop:
      lda interbank_fetch_buf,x
      sta screenshot_header,x
      dex
      bpl loadheaderloop

  header_already_loaded:

  ; Now load some tiles
  lda desc_data_ptr
  sta ibfsrc+0
  lda desc_data_ptr+1
  sta ibfsrc+1
  ; Pointer to bank number already in $02-$03
  lda #65+38  ; 38 is the maximum size for a donut block with 2 blank tiles.
  sta ibflen
  jsr interbank_fetch

  lda #<interbank_fetch_buf
  sta donut_stream_ptr+0
  lda #>interbank_fetch_buf
  sta donut_stream_ptr+1
  ; planes in order 0, 1, 0, 1, 0, 1, 0, 1, 2, 2, 2, 2, -, -, -, -
  ldx #0
  jsr donut_decompress_block
  ;,; ldx #64
  jsr donut_decompress_block
  sec
  lda donut_stream_ptr+0
  sbc #<interbank_fetch_buf
  clc
  adc desc_data_ptr
  sta desc_data_ptr
  bcc :+
  inc desc_data_ptr+1
:

  ; Unpack planes of 10-color screenshot
tile_rows_left = 0
;  rts  ; TODO: Remove this once 10-color screenshots are enabled

  ldx #55  ; number of plane 0/1 bytes - size of plane - 1
  ldy #31  ; number of plane 2 bytes - 1
  plane2tileloop:
    lda #8
    sta tile_rows_left
    plane2byteloop:
      lda PB53_outbuf+64,y
      and PB53_outbuf+8,x
      sta PB53_outbuf+72,x
      lda PB53_outbuf+64,y
      and PB53_outbuf+0,x
      sta PB53_outbuf+64,x
      dex
      dey
      dec tile_rows_left
      bne plane2byteloop
    txa
    sec
    sbc #8
    tax
    bpl plane2tileloop
  rts
.endproc

.proc blit_step_screenshot
dstlo = $00
dsthi = $01

  lda #VBLANK_NMI
  sta PPUCTRL
  ldx #0
  stx dstlo

  ; Calculate offset into screenshot memory = 64 * draw_progress
  lda draw_progress
  lsr a
  ror dstlo
  lsr a
  ror dstlo  ; carry is clear
  sta dsthi

  ; Copy gray layer
  adc #>SCREENSHOT0_BASE_ADDR
  jsr do2planes

  ; Copy color layer
  clc
  lda dsthi
  adc #>SCREENSHOT_BASE_ADDR
  jsr do2planes

  inc draw_progress
  lda draw_progress
  cmp #14
  bcc not_finished
  lda screenshot_titleno
  and #$7F
  sta screenshot_titleno
  lda #DRAWS_IDLE
  sta draw_step
  lda #$3F
  sta PPUADDR
  lda #$11
  sta PPUADDR
  .repeat 3, I
    lda screenshot_colors+I
    sta PPUDATA
  .endrepeat
  bit PPUDATA
  .repeat 3, I
    lda screenshot_colors+3+I
    sta PPUDATA
  .endrepeat
not_finished:
  rts

do2planes:
  sta PPUADDR
  lda dstlo
  sta PPUADDR
  
  .assert <SCREENSHOT_BASE_ADDR = 0, error, "screenshot base must be 16 tile aligned"
  clc
loop:
  ; and coming out of the loop
  .repeat 8, I
    lda PB53_outbuf+I,x
    sta PPUDATA
  .endrepeat
  txa
  adc #8
  tax
  and #$3F
  bne loop
  rts
.endproc

; Sprites are allocated statically.
; 0:
; 1:
; 2-7: Not used
; 8-63: Screenshot

SCREENSHOT_SOLID_PALETTE = $02
SCREENSHOT_OAM_START = 32
SCREENSHOT_LEFT = 32
SCREENSHOT_TOP = 56
.proc cartmenu_setup_oam
tx = $00
ty = $01

  ldx #4
  jsr ppu_clear_oam

  ; Load sprite 0
  ldx #s0data_end-s0data-1
  loop1:
    lda s0data,x
    sta OAM,x
    dex
    bpl loop1

  ; Set XY coords for screenshot
  lda #SCREENSHOT_TOP - 1
  sta ty
  ldx #SCREENSHOT_OAM_START
  rowloop:
    lda #SCREENSHOT_LEFT
    sta tx
    tileloop:
      lda ty
      sta OAM,x
      lda tx
      sta OAM+3,x
      inx
      inx
      inx
      inx
      clc
      adc #8
      sta tx
      cmp #64+SCREENSHOT_LEFT
      bcc tileloop
    lda #7  ; carry set; adding 8
    adc ty
    sta ty
    cmp #55+SCREENSHOT_TOP
    bcc rowloop
  rts
.pushseg
.rodata
s0data:
  .byt 40-1, SPRITE_0_TILE, $A2, 22  ; Sprite 0: above first line of text
  .byt 32-1, TAB_ARROW_TILE, $02     ; Second sprite: arrow
s0data_end:
.popseg
.endproc

.proc show_screenshot
tn = $00
attrbits = $01
  lda #<(SCREENSHOT_BASE_ADDR >> 4)
  sta tn
  sec
  ldx #SCREENSHOT_OAM_START
  ldy #0
  lda #$80
  sta attrbits
  loop:
    lda tn
    sta OAM+1,x
    inc tn
    asl attrbits
    bne :+
      lda screenshot_attributes,y
      iny
      rol a
      sta attrbits
    :
    lda #0
    rol a
    sta OAM+2,x
    inx
    inx
    inx
    inx
    bne loop
  rts
.endproc

.proc hide_screenshot
  ldx #SCREENSHOT_OAM_START
  loop:
    lda #BLANK_TILE
    sta OAM+1,x
    lda #SCREENSHOT_SOLID_PALETTE
    sta OAM+2,x
    inx
    inx
    inx
    inx
    bne loop
  rts
.endproc

.segment "RODATA"
select_tiles_chr: .incbin "obj/nes/select_tiles.chr.donut"
card_palette:
  ;    grayscale        unused           bit 0            bit 1
  .byt $0F,$00,$10,$20, $0F,$16,$16,$16, $0F,$10,$0F,$10, $0F,$0F,$10,$10
  ;    screenshot 4-6   screenshot 7-9   cur tab/blank tv unused
  .byt $0F,$11,$21,$31, $0F,$17,$27,$37, $0F,$00,$02,$16, $0F,$16,$16,$16

tv_shape:
  .byt $08,$09,$09,$09,$09,$09,$09,$09,$09,$0A
  .byt $0B,$00,$00,$00,$00,$00,$00,$00,$00,$0C
  .byt $0D,$00,$00,$00,$00,$00,$00,$00,$00,$0E
  .byt $10,$11,$12,$13,$14,$15,$16,$17,$11,$07
  .byt $18,$19,$1A,$1B,$1C,$1C,$1D,$1E,$1F,$0F
  .byt $02,$02,$02,$02,$02,$02,$02,$02,$02,$02

tv_rows:  ; Offsets into tv_shape for each row of the screen
  .byt 0, 10, 10, 20, 20, 20, 10, 10, 30, 40
row_below_tv:
  .byt 50  ; Last element for rows below the TV
  
card_attrtable:
  .byt $A0,$AA,$AA,$FF,$FF,$0F

.if 0
tab_title_data:
  .byt 5
  .byt 1, 3, 5, 7, 9
  .byt "1-18",0
  .byt "19-36",0
  .byt "37-53",0
  .byt "Toys",0
  .byt "Analysis",0

theme_text:
  .incbin "src/theme.txt"
  .byt 0
.endif

numplayers_names:
  .addr numplayers_1, numplayers_2only, numplayers_12, numplayers_12alt
  .addr numplayers_13, numplayers_14, numplayers_24alt, numplayers_26alt
  .addr numplayers_24fs
numplayers_1:      .byt "1 player",0
numplayers_2only:  .byt "2 players ONLY",0
numplayers_12:     .byt "1 or 2 players",0
numplayers_12alt:  .byt "1 or 2 players alternating",0
numplayers_13:     .byt "1 to 3 players",0
numplayers_14:     .byt "1 to 4 players",0
numplayers_24alt:  .byt "2 to 4 players alternating",0
numplayers_26alt:  .byt "2 to 6 players alternating",0
numplayers_24fs:   .byt "2 to 4 players w/Four Score",0
