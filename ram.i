; ram.i - where everything lives in the Vectrex's 1 KB.  $C800-$C87F is the BIOS's, $C880-$CBEA is ours, and the
; stack grows down from $CBEA, so the stroke list stops at $CB64 to leave it 134 bytes.
; The harness (test/harness.lua) reads and writes some of these by address: keep them in step with it.
cur_x               equ      $C880                ; cursor, 8.8 fixed point (screen units . fraction), x then y
cur_y               equ      $C882
npts                equ      $C884                ; points in the stroke list (a $80 y marks the start of a new stroke)
pen_was             equ      $C885                ; 1 while a stroke is being drawn
mode                equ      $C886                ; 0 = joystick, 1 = light pen
lp_state            equ      $C887                ; light pen: 0 = searching, else frames left before the pen counts as lifted
lp_y                equ      $C888                ; light pen: where it was last seen
lp_x                equ      $C889
result              equ      $C88A                ; the digit read, $FF = none yet
test_cmd            equ      $C88B                ; harness: 1 = read the grid as it is, 2 = rasterise the points first
cnt                 equ      $C88C
cnt2                equ      $C88D
tmp                 equ      $C88E                ; 2 bytes
tmp2                equ      $C890                ; 2 bytes
minx                equ      $C892                ; the drawing's bounding box
maxx                equ      $C893
miny                equ      $C894
maxy                equ      $C895
rcp                 equ      $C896                ; RECIP[longer side]: cells per screen unit, x 256
ox                  equ      $C897                ; offsets that centre the box in the 12 x 12 grid
oy                  equ      $C898
cr                  equ      $C899                ; the stroke walk: current row and column, target row and column
cc                  equ      $C89A
tr                  equ      $C89B
tc                  equ      $C89C
bits                equ      $C89D                ; 2 bytes: one grid row being scanned
best                equ      $C89F                ; 3 bytes: the best score
hy0                 equ      $C8A2                ; light pen: rows and columns of the dots that saw it
hy1                 equ      $C8A3
hx0                 equ      $C8A4
hx1                 equ      $C8A5
hits                equ      $C8A6
srow                equ      $C8A7                ; light pen scan: row and column of the dot being drawn
scol                equ      $C8A8
lasty               equ      $C8A9                ; the last point recorded
lastx               equ      $C8AA
frame               equ      $C8AB
bars                equ      $C8AC                ; 10 bytes: score bar lengths
grid                equ      $C8B6                ; 24 bytes: 12 rows x 16 bits, bit 15 = column 0
acc                 equ      $C8CE                ; 128 bytes: 64 hidden sums, 16-bit
hbuf                equ      $C94E                ; 64 bytes: hidden activations, 0..255
out                 equ      $C98E                ; 30 bytes: 10 scores, 24-bit
pts                 equ      $C9AC                ; the stroke list: (y, x) pairs
MAXPTS              equ      220                  ; ... up to $CB64
RAM_END             equ      $C9AC                ; start-up clears $C880 up to here
