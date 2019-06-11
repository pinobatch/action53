
.export wait36k, wait1284y

.segment "CODE"

; Based on allpads-nes/src/openbus.s and allpads-nes/src/identify.s,
; this detects a a Super NES Mouse in port 1 or a Zapper in port 2.
; It doesn't attempt to detect an Arkanoid controller or Power Pad
; because the menu does not support them.
.proc wait36k
  ldx #28
  ldy #0
waitloop:
  dey
  bne waitloop
  dex
  bne waitloop
  rts
.endproc
.assert >wait36k = >*, error, "wait36k crosses page boundary"

;;
; Waits for 1284*y + 5*x cycles + 5 cycles, minus 1284 if x is
; nonzero, and then reads bit 7 and 6 of the PPU status port.
; @param X fine period adjustment
; @param Y coarse period adjustment
; @return N=NMI status; V=sprite 0 status; X=Y=0; A unchanged
.proc wait1284y
  dex
  bne wait1284y
  dey
  bne wait1284y
  bit $2002
  rts
.endproc
.assert >wait1284y = >*, error, "wait1284y crosses page boundary"
