; written to compile with asm6

;----------------------------------------------------------------
; NES 2.0 header
;----------------------------------------------------------------
INES_MAPPER = 34        ; 0 = NROM, 218 = Single Chip
INES_PRG_COUNT = 1      ; number of 16KB PRG-ROM pages
INES_CHR_COUNT = 0      ; number of 8KB CHR-ROM pages
INES_MIRRORING = %0001  ; %0000 = horizontal, %0001 = vertical,
                        ; %1000 = four-screen

  .db "NES", $1a    ; magic signature
  .db INES_PRG_COUNT
  .db INES_CHR_COUNT
  .db ((INES_MAPPER << 4) & $f0) | INES_MIRRORING
  .db (INES_MAPPER & $f0)
  .dsb 8, $00       ; NES 1.0, no other features

.fillvalue $ff
.org $c000

.org $ffd6

RST:
  ldx #$100-(-ramcode_begin+ramcode_end)
  copy_loop:
    lda ramcode_end-$100,x
    sta 0, x
    inx
  bne copy_loop
  ldy #$80
  sty $5000
  lda #$02
  ldy #$81
  ldx #$ff
  jmp $100-(-ramcode_begin+ramcode_end)
ramcode_begin:
  sta $8000
  sty $5000
  stx $8000
brk
NMI:
IRQ:
  rti
.db $02  ; halt CPU hard in case we get this far.
ramcode_end:

.org $fffa

vectors:
  .dw NMI
  .dw RST
  .dw IRQ
