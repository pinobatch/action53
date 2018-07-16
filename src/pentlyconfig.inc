; Configuration settings for Pently

; Disable features to save ROM space.
; These make it roughly equivalent to Pently 3.
PENTLY_USE_PAL_ADJUST = 1
PENTLY_USE_ROW_CALLBACK = 0
PENTLY_USE_VIBRATO = 0
PENTLY_USE_ARPEGGIO = 0
PENTLY_USE_BPMMATH = 0
PENTLY_USE_ATTACK_TRACK = 0
PENTLY_USE_ATTACK_PHASE = 0
PENTLY_USE_SQUARE_POOLING = 0
PENTLY_USE_MUSIC_IF_LOUDER = 0
PENTLY_USE_CHANNEL_VOLUME = 0

; Five bytes of scratch space on zero page that need not be preserved
; across calls.  This needs to be either an = or an .importzp

pently_zptemp = $0000
; .importzp pently_zptemp

.define PENTLY_CODE "CODE"
.define PENTLY_RODATA "RODATA"
