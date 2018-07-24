.include "nes.inc"
.include "global.inc"
.include "pently.inc"

.code
.proc title_screen
  bit PPUSTATUS
  lda #VBLANK_NMI
  sta PPUCTRL

  lda TITLESCREEN+1
  sta ciSrc+1
  lda TITLESCREEN+0
  sta ciSrc
  
  ; Unpack tiles
  ldy #0
  sty PPUMASK
  sty PPUADDR
  sty PPUADDR
  lda (ciSrc),y
  tax
  inc ciSrc
  bne :+
    inc ciSrc+1
  :
  jsr unpb53_block

  ; Unpack nametable
  lda #$20
  sta PPUADDR
  lda #$00
  sta PPUADDR
  ldx #1024/16
  jsr unpb53_block

  ; fill in the palette
  ldx #$3F
  stx PPUADDR
  sta PPUADDR
  lda nmis
  :
    cmp nmis
    beq :-
palloop:
  lda (ciSrc),y
  sta PPUDATA
  iny
  cpy #16
  bcc palloop
  jsr draw_title_strings

  lda #0
  jsr pently_start_music

title_wait_A:
  lda #VBLANK_NMI|BG_0000
  sta PPUCTRL
  jsr ppu_wait_vblank
  lda #$00
  sta PPUSCROLL
  sta PPUSCROLL
  lda #BG_ON
  sta PPUMASK

  jsr pently_update
  lda pently_music_playing
  beq selnow

  jsr read_pads
  lda detected_pads
  and #DETECT_1P_MOUSE
  beq no_mouse
    ldx #0
    jsr read_mouse_with_backward_buttons
  no_mouse:
  
  jsr read_zapper_trigger
  ora new_keys
  and #KEY_START|KEY_A
  beq title_wait_A
  rts

  ; If time expired, blank the screen and play audio
selnow:
  lda #0
  sta PPUMASK
  jmp quadpcm_test
.endproc

; Each string consists of several parts:
; control and Y byte, X byte, a53-encoded characters, 0 byte
; Terminated by $FF, or otherwise with Y part >= 30
;
; 7654 3210  Control and Y byte
; |||| ||||
; |||+-++++- Vertical position of text
; ||+------- 0: Clear other bitplane; 1: $FF other bitplane
; |+-------- 0: Don't invert; 1: Invert bitplane
; +--------- 0: Affect bit 0; 1: affect bit 1

.proc draw_title_strings
  lda TITLESTRINGS+1
  ldy TITLESTRINGS
.endproc
.proc draw_title_strings_ay
total_tiles = tab_tilelens+0
xand7 = tab_tilelens+1
strstart = tab_tilelens+2
str = $00

  ; Count the total tiles used by title screen strings
  cmp #$FF
  bcc :+
    rts
  :
  sta str+1
  sta strstart+1
  sty str+0
  sty strstart+0
  lda #0
  sta total_tiles
  measureloop:
    ldy #0
    lda (str),y
    and #$1F
    cmp #$1E
    bcs measuredone
    iny

    ; At X position 0 to 7, add 7 to 14 and divide by 8 rounding down
    lda (str),y
    and #$07
    clc
    adc #7
    sta xand7

    ; Measure the string itself
    ;clc  ; previous addition result never exceeds 14
    lda str
    adc #2
    tay
    lda str+1
    adc #0
    jsr vwfStrWidth  ; A = pixel width, X = string length
    clc
    adc xand7
    lsr a
    lsr a
    lsr a
    clc
    adc total_tiles
    sta total_tiles
    
    tya
    sec
    adc str
    sta str
    bcc measureloop
    inc str+1
    bcs measureloop
  measuredone:

  ; Actually draw the strings to the screen
  lda #0
  sec
  sbc total_tiles
  sta total_tiles
  lda strstart+1
  sta str+1
  lda strstart+0
  sta str+0
  drawloop:
    ldy #0
    lda (str),y
    sta ciDst+1
    and #$1F
    cmp #$1E
    bcc drawnotdone
      rts
    drawnotdone:

    jsr clearLineImg
    ldy #1
    lda (str),y
    sta ciDst+0
    and #$07
    tax
    clc
    lda str
    adc #2
    tay
    lda str+1
    adc #0
    jsr vwfPuts
    inc str
    bne :+
      inc str+1
    :
    ; X = horizontal position
    txa
    clc
    adc #7
    lsr a
    lsr a
    lsr a  ; A = number of tiles used
    pha
    bit ciDst+1
    bvc :+
      jsr invertTiles
      pla
      pha
    :

    ; Write tiles to destination in pattern table
    lda ciDst+1
    asl a  ; C = which bitplane (0xx0 or 0xx8)
    lda total_tiles
    rol a
    sta xand7
    lda #0
    rol a
    .repeat 3
      asl xand7
      rol a
    .endrepeat
    pha
    ldy xand7
    jsr copyLineImg

    ; Write other bitplane as $00 or $FF
    jsr clearLineImg
    lda #$20
    and ciDst+1
    beq :+
      lda #16
      jsr invertTiles
    :
    lda xand7
    eor #$08
    tay
    pla
    jsr copyLineImg

    ; Write corresponding tile numbers to nametable
    sec
    lda ciDst+0
    sta xand7
    lda ciDst+1
    and #$1F
    ror a
    ror xand7
    lsr a
    ror xand7
    lsr a
    ror xand7
    sta PPUADDR
    lda xand7
    sta PPUADDR
    lda #VBLANK_NMI
    sta PPUCTRL
    pla
    tax
    drawtileloop:
      lda total_tiles
      inc total_tiles
      sta PPUDATA
      dex
      bne drawtileloop
    jmp drawloop
.endproc

.rodata
COLOR1ON0 = $00
COLOR3ON2 = $20
COLOR0ON1 = $40
COLOR2ON3 = $60
COLOR2ON0 = $80
COLOR3ON1 = $A0
COLOR0ON2 = $C0
COLOR1ON3 = $E0

TITLESTRINGS = $FF12

; Error if no games are added ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.code
.proc no_games_error
  ; Clear tiles 0-63
  lda #0
  tay
  ldx #$00
  jsr ppu_clear_nt
  ldx #$0C
  jsr ppu_clear_nt
  ; and the first nametable
  ldx #$20
  jsr ppu_clear_nt

  ; White text on a black background
  lda #$3F
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #$16
  sta PPUDATA
  lda #$20
  sta PPUDATA

  ; Draw message
  lda #>no_games_title_strings
  ldy #<no_games_title_strings
  jsr draw_title_strings_ay

  ; And display it
  ldx #0
  ldy #0
  lda #VBLANK_NMI
  clc
  jsr ppu_screen_on
forever:
  jmp forever
.endproc

.rodata
no_games_title_strings:
.byte 14+$00,  96, "No games added.",0
.byte $FF
