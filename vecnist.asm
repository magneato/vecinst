;***************************************************************************
; VECNIST.ASM - draw a digit on a Vectrex and it reads it.
;
; Draw with the joystick (hold button 1 to ink) or with a light pen (button 4 switches).  Every time a stroke ends
; the drawing is fitted into a 12 x 12 grid and a network trained on MNIST (train/vecnist.py, on the PC) reads it:
; 144 inputs -> 64 hidden -> 10.  The first layer is additions only (the inputs are 0 or 1), the second one MUL
; per weight, and nothing on the 6809 divides: the drawing is scaled by a reciprocal table.
;
; Buttons (joystick 1): 1 = ink, 2 = read now, 3 = clear, 4 = joystick / light pen.
;
; Assembles with Vide's own assembler and with lwasm, byte for byte the same (tools/build.sh checks both).
;***************************************************************************
                    include  "bios.i"
                    include  "ram.i"

BOX_X0              equ      -120                 ; the drawing area, in screen units (144 x 144)
BOX_X1              equ      24
BOX_Y0              equ      -88
BOX_Y1              equ      56
DRAW_SCALE          equ      $20                  ; strokes are drawn at scale $20 with deltas x 4 (4 x 32 ~ 127)
PEN_LOST            equ      6                    ; frames without a sighting before the pen counts as lifted
BAR_X               equ      64                   ; the score bars
BAR_Y               equ      50
BAR_MAX             equ      40
GRID_X              equ      62                   ; the network's-eye view of the drawing
GRID_Y              equ      -36
GRID_STEP           equ      5

;***************************************************************************
; the cartridge header: the BIOS checks the copyright line, plays the music and shows the title
;***************************************************************************
                    org      0
                    fcc      "g GCE 2026"
                    fcb      $80
                    fdb      $FD0D                ; music from the BIOS
                    fcb      $F8,$50,$20,-$38     ; title height, width, y, x
                    fcc      "VECNIST"
                    fcb      $80
                    fcb      0                    ; end of the header

;***************************************************************************
; start-up
;***************************************************************************
start               lda      #1
                    sta      Vec_Joy_Mux_1_X      ; Joy_Analog reads joystick 1, both axes, finest resolution
                    lda      #3
                    sta      Vec_Joy_Mux_1_Y
                    clr      Vec_Joy_Mux_2_X
                    clr      Vec_Joy_Mux_2_Y
                    clr      Vec_Joy_Resltn
                    ldx      #cur_x
st_clr              clr      ,x+
                    cmpx     #RAM_END
                    bne      st_clr
                    lda      #$FF
                    sta      result
                    lda      #-32                 ; cursor in the middle of the box
                    sta      cur_x
                    lda      #-16
                    sta      cur_y

;***************************************************************************
; the frame loop
;***************************************************************************
main                jsr      Wait_Recal           ; DP = $D0 from here on: our variables use extended addressing
                    clr      Vec_Misc_Count
                    jsr      Read_Btns
                    jsr      Joy_Analog
                    inc      frame
                    lda      test_cmd             ; the test harness asks for a reading
                    beq      mn_btn
                    cmpa     #2
                    bne      mn_tinf
                    jsr      rasterise
mn_tinf             jsr      infer
                    clr      test_cmd
mn_btn              lda      Vec_Buttons
                    bita     #$04                 ; button 3: clear
                    beq      mn_b4
                    jsr      clear_all
mn_b4               lda      Vec_Buttons
                    bita     #$08                 ; button 4: joystick <-> light pen
                    beq      mn_b2
                    lda      mode
                    eora     #1
                    sta      mode
                    clr      lp_state
                    clr      pen_was
                    lda      #(BOX_Y0+BOX_Y1)/2   ; the pen's patch starts in the middle of the box
                    sta      lp_y
                    lda      #(BOX_X0+BOX_X1)/2
                    sta      lp_x
mn_b2               lda      Vec_Buttons
                    bita     #$02                 ; button 2: read it now
                    beq      mn_in
                    jsr      classify
mn_in               lda      mode
                    bne      mn_pen
                    jsr      stick_input
                    bra      mn_show
mn_pen              jsr      pen_input
mn_show             jsr      show
                    bra      main

clear_all           clr      npts
                    clr      pen_was
                    lda      #$FF
                    sta      result
                    ldx      #grid
ca_l                clr      ,x+
                    cmpx     #grid+24
                    bne      ca_l
                    rts

;***************************************************************************
; the joystick: deflection moves the cursor (8.8 fixed point), button 1 inks
;***************************************************************************
stick_input         ldb      Vec_Joy_1_X
                    jsr      deadzone
                    sex
                    aslb
                    rola
                    aslb
                    rola
                    aslb
                    rola                          ; full deflection: about 4 units a frame
                    addd     cur_x
                    cmpa     #BOX_X0
                    bge      si_x1
                    lda      #BOX_X0
                    clrb
si_x1               cmpa     #BOX_X1
                    ble      si_x2
                    lda      #BOX_X1
                    clrb
si_x2               std      cur_x
                    ldb      Vec_Joy_1_Y
                    jsr      deadzone
                    sex
                    aslb
                    rola
                    aslb
                    rola
                    aslb
                    rola
                    addd     cur_y
                    cmpa     #BOX_Y0
                    bge      si_y1
                    lda      #BOX_Y0
                    clrb
si_y1               cmpa     #BOX_Y1
                    ble      si_y2
                    lda      #BOX_Y1
                    clrb
si_y2               std      cur_y
                    lda      Vec_Btn_State
                    bita     #$01
                    beq      pen_lifted
                    lda      cur_y
                    ldb      cur_x
                    bra      ink_point

; the pen came off the paper: if a stroke was being drawn, read the drawing
pen_lifted          tst      pen_was
                    beq      pl_done
                    clr      pen_was
                    jsr      classify
pl_done             rts

deadzone            cmpb     #10
                    bge      dz_ok
                    cmpb     #-10
                    ble      dz_ok
                    clrb
dz_ok               rts

; record the point (A = y, B = x): a new stroke starts with a marker, and a point is only kept once the pen has
; moved 2 units, so the list holds the shape and not the dwell
ink_point           std      tmp
                    tst      pen_was
                    bne      ip_near
                    lda      #1
                    sta      pen_was
                    tst      npts
                    beq      ip_add
                    ldd      #$8000               ; marker: a new stroke begins
                    jsr      put_point
                    bra      ip_add
ip_near             lda      tmp
                    suba     lasty
                    bpl      ip_ay
                    nega
ip_ay               cmpa     #2
                    bhs      ip_add
                    lda      tmp+1
                    suba     lastx
                    bpl      ip_ax
                    nega
ip_ax               cmpa     #2
                    blo      ip_done
ip_add              ldd      tmp
                    sta      lasty
                    stb      lastx
                    bra      put_point
ip_done             rts

put_point           pshs     d
                    lda      npts
                    cmpa     #MAXPTS
                    bhs      pp_full
                    ldx      #pts
                    ldb      npts
                    abx
                    abx
                    puls     d
                    std      ,x
                    inc      npts
                    rts
pp_full             puls     d
                    rts

;***************************************************************************
; the light pen.  The pen pulses the VIA's CA1 line when the beam lights up under it, so: draw dots, and after
; each one look at the CA1 flag.  A pen only sees the beam within a couple of units, far too close to search the
; whole box every frame, so it works the way light pens always did: it locks on.  A 7 x 7 patch of dots 2 units
; apart is the pen's cursor; touch the pen to it and the patch follows the pen, re-centring on the dots that saw
; it.  Button 1 inks, as with the stick.  Unseen for PEN_LOST frames: the pen was lifted, and the patch waits.
; Every dot is reached by its own move from the centre: the position a sighting is credited to must be exact.
;***************************************************************************
pen_input           lda      #$40
                    jsr      Intensity_a
                    lda      lp_y                 ; the patch, centred on the pen
                    adda     #6
                    ldb      lp_x
                    subb     #6
                    std      tmp2
                    lda      #7
                    ldb      #2
                    jsr      dot_grid
                    tst      hits
                    beq      pi_miss
                    lda      hy0                  ; middle of the dots that saw the pen (halves first: signed)
                    asra
                    ldb      hy1
                    asrb
                    pshs     b
                    adda     ,s+
                    cmpa     #BOX_Y0+6            ; the pen draws only inside the box
                    bge      pi_c1
                    lda      #BOX_Y0+6
pi_c1               cmpa     #BOX_Y1-6
                    ble      pi_c2
                    lda      #BOX_Y1-6
pi_c2               sta      lp_y
                    lda      hx0
                    asra
                    ldb      hx1
                    asrb
                    pshs     b
                    adda     ,s+
                    cmpa     #BOX_X0+6
                    bge      pi_c3
                    lda      #BOX_X0+6
pi_c3               cmpa     #BOX_X1-6
                    ble      pi_c4
                    lda      #BOX_X1-6
pi_c4               sta      lp_x
                    lda      #PEN_LOST
                    sta      lp_state
                    lda      lp_y
                    ldb      lp_x
                    stb      cur_x                ; the stick's cursor follows the pen
                    sta      cur_y
                    lda      Vec_Btn_State        ; button 1 inks, as with the stick
                    bita     #$01
                    lbeq     pen_lifted
                    lda      lp_y
                    ldb      lp_x
                    jmp      ink_point
pi_miss             tst      lp_state
                    beq      pi_none
                    dec      lp_state
                    bne      pi_none
                    jmp      pen_lifted
pi_none             rts

; dot_grid: A x A dots, B = spacing (screen units), top-left (y, x) in tmp2.  Each dot that sees the pen widens
; the hit box hy0..hy1, hx0..hx1.
dot_grid            sta      cnt2
                    stb      tmp
                    clr      hits
                    lda      #127
                    sta      hy0
                    sta      hx0
                    lda      #-128
                    sta      hy1
                    sta      hx1
                    lda      tmp2
                    sta      tr                   ; (the stroke walk's tr/tc are free here)
                    lda      cnt2
                    sta      srow
dt_row              lda      tmp2+1
                    sta      tc
                    lda      cnt2
                    sta      scol
dt_dot              jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      tr
                    ldb      tc
                    jsr      Moveto_d
                    lda      #$02
                    sta      VIA_int_flags        ; clear CA1
                    jsr      Dot_here
                    lda      VIA_int_flags
                    bita     #$02
                    beq      dt_next
                    inc      hits                 ; the pen saw this dot
                    lda      tr
                    cmpa     hy0
                    bge      dt_h1
                    sta      hy0
dt_h1               cmpa     hy1
                    ble      dt_h2
                    sta      hy1
dt_h2               lda      tc
                    cmpa     hx0
                    bge      dt_h3
                    sta      hx0
dt_h3               cmpa     hx1
                    ble      dt_next
                    sta      hx1
dt_next             lda      tc
                    adda     tmp
                    sta      tc
                    dec      scol
                    bne      dt_dot
                    lda      tr
                    suba     tmp
                    sta      tr
                    dec      srow
                    bne      dt_row
                    rts

;***************************************************************************
; RASTERISE: the stroke list -> the 12 x 12 grid, the way train/vecnist.py twin_grid() does it
;   box: the longer side fits 9 cells, cell = ((v - min) x RECIP[side]) >> 8, centred in the grid
;   strokes: consecutive points joined by an 8-connected walk
;***************************************************************************
rasterise           ldx      #grid
rs_clr              clr      ,x+
                    cmpx     #grid+24
                    bne      rs_clr
                    lda      npts
                    lbeq     rs_done
                    lda      #127                 ; the bounding box
                    sta      minx
                    sta      miny
                    lda      #-128
                    sta      maxx
                    sta      maxy
                    ldx      #pts
                    lda      npts
                    sta      cnt
rs_box              lda      ,x
                    cmpa     #$80
                    beq      rs_bn
                    cmpa     miny
                    bge      rs_b1
                    sta      miny
rs_b1               cmpa     maxy
                    ble      rs_b2
                    sta      maxy
rs_b2               lda      1,x
                    cmpa     minx
                    bge      rs_b3
                    sta      minx
rs_b3               cmpa     maxx
                    ble      rs_bn
                    sta      maxx
rs_bn               leax     2,x
                    dec      cnt
                    bne      rs_box
                    lda      maxx                 ; w and h (unsigned), the longer side picks the scale
                    suba     minx
                    sta      tmp
                    lda      maxy
                    suba     miny
                    sta      tmp+1
                    cmpa     tmp
                    bhs      rs_big
                    lda      tmp
rs_big              ldx      #RECIP
                    tfr      a,b
                    abx
                    lda      ,x
                    sta      rcp
                    ldb      tmp                  ; ox = (12 - ((w x R) >> 8 + 1)) >> 1
                    mul
                    inca
                    nega
                    adda     #12
                    lsra
                    sta      ox
                    lda      tmp+1
                    ldb      rcp
                    mul
                    inca
                    nega
                    adda     #12
                    lsra
                    sta      oy
                    ldx      #pts                 ; walk the strokes
                    lda      npts
                    sta      cnt
rs_new              ldd      ,x                   ; a stroke's first point: just its cell
                    cmpa     #$80
                    beq      rs_skip
                    jsr      map_point
                    lda      tr
                    sta      cr
                    lda      tc
                    sta      cc
                    jsr      set_cell
rs_next             leax     2,x
                    dec      cnt
                    beq      rs_done
                    ldd      ,x
                    cmpa     #$80
                    beq      rs_skip
                    jsr      map_point
rs_walk             lda      cr                   ; step row and column toward the target, ink each cell
                    cmpa     tr
                    beq      rs_wc
                    blo      rs_rinc
                    dec      cr
                    bra      rs_wc
rs_rinc             inc      cr
rs_wc               lda      cc
                    cmpa     tc
                    beq      rs_ws
                    blo      rs_cinc
                    dec      cc
                    bra      rs_ws
rs_cinc             inc      cc
rs_ws               lda      cr
                    cmpa     tr
                    bne      rs_wset
                    lda      cc
                    cmpa     tc
                    bne      rs_wset
                    jsr      set_cell
                    bra      rs_next
rs_wset             jsr      set_cell
                    bra      rs_walk
rs_skip             leax     2,x                  ; a marker: the next point starts a stroke
                    dec      cnt
                    bne      rs_new
rs_done             rts

; (A = y, B = x) -> tr = row, tc = column
map_point           pshs     a
                    subb     minx
                    lda      rcp
                    mul
                    adda     ox
                    sta      tc
                    ldb      maxy
                    subb     ,s+
                    lda      rcp
                    mul
                    adda     oy
                    sta      tr
                    rts

; ink grid cell (cr, cc): row r is 2 bytes, column 0 is the top bit
set_cell            pshs     x
                    lda      cr
                    asla
                    ldb      cc
                    lsrb
                    lsrb
                    lsrb
                    pshs     b
                    adda     ,s+
                    ldx      #grid
                    leax     a,x
                    ldb      cc
                    andb     #7
                    pshs     x
                    ldx      #bitmask
                    lda      b,x
                    puls     x
                    ora      ,x
                    sta      ,x
                    puls     x
                    rts
bitmask             fcb      $80,$40,$20,$10,$08,$04,$02,$01

;***************************************************************************
; INFER: grid -> scores -> result, the way train/vecnist.py twin_infer() does it
;   acc[j] = B1[j] + sum of W1[cell][j] over the inked cells        (16-bit, additions only)
;   h[j]   = clamp(acc[j] >> K1, 0, 255)
;   out[k] = B2[k] + sum of h[j] x W2[k][j]                          (24-bit: MUL by |w|, add or subtract)
;***************************************************************************
infer               ldx      #B1
                    ldu      #acc
                    lda      #HID
                    sta      cnt
in_b                ldd      ,x++
                    std      ,u++
                    dec      cnt
                    bne      in_b
                    ldx      #W1                  ; one 64-byte row of W1 per cell, in grid order
                    ldy      #grid
                    lda      #12
                    sta      cnt2
in_row              ldd      ,y++
                    std      bits
                    lda      #12
                    sta      tmp2
in_col              lsl      bits+1
                    rol      bits
                    bcc      in_skip
                    ldu      #acc                 ; an inked cell: add its row of weights
                    lda      #HID
                    sta      cnt
in_add              ldb      ,x+
                    sex
                    addd     ,u
                    std      ,u++
                    dec      cnt
                    bne      in_add
                    bra      in_nxt
in_skip             leax     HID,x
in_nxt              dec      tmp2
                    bne      in_col
                    dec      cnt2
                    bne      in_row
                    ldx      #acc                 ; activations
                    ldu      #hbuf
                    lda      #HID
                    sta      cnt
in_act              ldd      ,x++
                    bpl      in_pos
                    clrb
                    bra      in_put
in_pos              std      tmp
                    lda      #K1
                    sta      tmp2
in_sh               tst      tmp2
                    beq      in_shd
                    lsr      tmp
                    ror      tmp+1
                    dec      tmp2
                    bra      in_sh
in_shd              ldd      tmp
                    tsta
                    beq      in_put
                    ldb      #255
in_put              stb      ,u+
                    dec      cnt
                    bne      in_act
                    ldx      #W2                  ; the ten scores
                    ldu      #out
                    ldy      #B2
                    lda      #10
                    sta      cnt2
in_k                ldd      ,y++
                    std      ,u
                    lda      ,y+
                    sta      2,u
                    pshs     y
                    ldy      #hbuf
                    lda      #HID
                    sta      cnt
in_j                lda      ,y+
                    ldb      ,x+
                    tsta
                    beq      in_jn
                    tstb
                    bmi      in_neg
                    mul
                    addd     1,u
                    std      1,u
                    bcc      in_jn
                    inc      ,u
                    bra      in_jn
in_neg              negb
                    mul
                    std      tmp
                    ldd      1,u
                    subd     tmp
                    std      1,u
                    bcc      in_jn
                    dec      ,u
in_jn               dec      cnt
                    bne      in_j
                    puls     y
                    leau     3,u
                    dec      cnt2
                    bne      in_k
                    ldu      #out                 ; the highest score wins
                    clr      result
                    ldd      ,u
                    std      best
                    lda      2,u
                    sta      best+2
                    lda      #1
                    sta      cnt
                    leau     3,u
am_l                lda      ,u
                    cmpa     best
                    bgt      am_new
                    blt      am_nx
                    ldd      1,u
                    cmpd     best+1
                    bls      am_nx
am_new              ldd      ,u
                    std      best
                    lda      2,u
                    sta      best+2
                    lda      cnt
                    sta      result
am_nx               leau     3,u
                    inc      cnt
                    lda      cnt
                    cmpa     #10
                    bne      am_l
                    ldu      #out                 ; bars: BAR_MAX - (best - score) >> BAR_SHIFT, at least 0
                    ldx      #bars
                    lda      #10
                    sta      cnt
bs_l                ldd      best+1
                    subd     1,u
                    std      tmp
                    lda      best
                    sbca     ,u
                    sta      tmp2
                    lda      #BAR_SHIFT
                    sta      tmp2+1
bs_sh               tst      tmp2+1
                    beq      bs_shd
                    lsr      tmp2
                    ror      tmp
                    ror      tmp+1
                    dec      tmp2+1
                    bra      bs_sh
bs_shd              tst      tmp2
                    bne      bs_zero
                    tst      tmp
                    bne      bs_zero
                    lda      #BAR_MAX
                    suba     tmp+1
                    bhi      bs_put
bs_zero             clra
bs_put              sta      ,x+
                    leau     3,u
                    dec      cnt
                    bne      bs_l
                    rts

classify            tst      npts
                    beq      cl_none
                    jsr      rasterise
                    jmp      infer
cl_none             lda      #$FF
                    sta      result
                    rts

;***************************************************************************
; SHOW: the box, the strokes, the cursor, the answer, the scores and the network's-eye view
;***************************************************************************
show                lda      #$5F
                    jsr      Intensity_a
                    jsr      Reset0Ref            ; the box: 8 lines of 72
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      #BOX_Y1
                    ldb      #BOX_X0
                    jsr      Moveto_d
                    ldx      #box_lines
                    lda      #8
                    sta      cnt
sh_box              ldd      ,x++
                    pshs     x
                    jsr      Draw_Line_d
                    puls     x
                    dec      cnt
                    bne      sh_box
                    lda      #$7F
                    jsr      Intensity_a
                    jsr      draw_strokes
                    tst      mode
                    bne      sh_text
                    jsr      Reset0Ref            ; the cursor: a small cross
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      cur_y
                    ldb      cur_x
                    jsr      Moveto_d
                    lda      #$10
                    sta      VIA_t1_cnt_lo
                    ldd      #$00E8
                    jsr      Moveto_d
                    ldd      #$0030
                    jsr      Draw_Line_d
                    ldd      #$18E8
                    jsr      Moveto_d
                    ldd      #$D000
                    jsr      Draw_Line_d
sh_text             ldd      #$F850               ; text: title and help
                    std      Vec_Text_HW
                    jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    ldu      #str_title
                    lda      #110
                    ldb      #-120
                    jsr      Print_Str_d
                    ldd      #$FC38
                    std      Vec_Text_HW
                    ldu      #str_help
                    lda      #-104
                    ldb      #-120
                    jsr      Print_Str_d
                    ldu      #str_stick
                    tst      mode
                    beq      sh_mode
                    ldu      #str_pen
sh_mode             lda      #110
                    ldb      #20
                    jsr      Print_Str_d
                    lda      result
                    cmpa     #$FF
                    beq      sh_done
                    ldd      #$E040               ; the answer, big
                    std      Vec_Text_HW
                    lda      result
                    ldb      #3
                    mul
                    ldu      #digits
                    leau     b,u
                    lda      #100
                    ldb      #76
                    jsr      Print_Str_d
                    jsr      draw_bars
                    jsr      draw_grid
sh_done             rts

box_lines           fcb      0,72,0,72,-72,0,-72,0,0,-72,0,-72,72,0,72,0

; strokes: a move to each stroke's start at scale $7F, then its segments at scale $20 with deltas x 4
draw_strokes        lda      npts
                    beq      ds_done
                    sta      cnt
                    ldx      #pts
ds_new              ldd      ,x
                    cmpa     #$80
                    beq      ds_brk
                    std      tmp
                    pshs     x
                    jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    ldd      tmp
                    jsr      Moveto_d
                    jsr      Dot_here
                    lda      #DRAW_SCALE
                    sta      VIA_t1_cnt_lo
                    puls     x
ds_seg              leax     2,x
                    dec      cnt
                    beq      ds_done
                    lda      ,x
                    cmpa     #$80
                    beq      ds_brk
                    suba     tmp
                    ldb      1,x
                    subb     tmp+1
                    asla
                    asla
                    aslb
                    aslb
                    pshs     x
                    jsr      Draw_Line_d
                    puls     x
                    ldd      ,x
                    std      tmp
                    bra      ds_seg
ds_brk              leax     2,x
                    dec      cnt
                    bne      ds_new
ds_done             rts

; ten bars, one per digit, longest for the answer
draw_bars           ldd      #$FC30
                    std      Vec_Text_HW
                    clr      cnt2
db_l                jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      cnt2                 ; y = BAR_Y - 9 x digit
                    ldb      #9
                    mul
                    negb
                    addb     #BAR_Y
                    stb      tmp
                    lda      cnt2
                    ldb      #3
                    mul
                    ldu      #digits
                    leau     b,u
                    lda      tmp
                    adda     #3
                    ldb      #BAR_X-12
                    jsr      Print_Str_d
                    jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      tmp
                    ldb      #BAR_X
                    jsr      Moveto_d
                    ldx      #bars
                    ldb      cnt2
                    lda      b,x
                    beq      db_nx
                    tfr      a,b
                    clra
                    jsr      Draw_Line_d
db_nx               inc      cnt2
                    lda      cnt2
                    cmpa     #10
                    bne      db_l
                    rts

; the 12 x 12 grid the network saw, a dot per inked cell
draw_grid           lda      #$5F
                    jsr      Intensity_a
                    ldy      #grid
                    clr      cr
dg2_row             ldd      ,y++
                    std      bits
                    clr      cc
dg2_col             lsl      bits+1
                    rol      bits
                    bcc      dg2_nx
                    jsr      Reset0Ref
                    lda      #$7F
                    sta      VIA_t1_cnt_lo
                    lda      cr
                    ldb      #GRID_STEP
                    mul
                    negb
                    addb     #GRID_Y
                    stb      tmp
                    lda      cc
                    ldb      #GRID_STEP
                    mul
                    addb     #GRID_X
                    lda      tmp
                    jsr      Moveto_d
                    jsr      Dot_here
dg2_nx              inc      cc
                    lda      cc
                    cmpa     #12
                    bne      dg2_col
                    inc      cr
                    lda      cr
                    cmpa     #12
                    bne      dg2_row
                    rts

str_title           fcc      "VECNIST"
                    fcb      $80
str_help            fcc      "1 INK 2 READ 3 CLEAR 4 PEN"
                    fcb      $80
str_stick           fcc      "STICK"
                    fcb      $80
str_pen             fcc      "LIGHT PEN"
                    fcb      $80
; one digit each, padded with a space: the BIOS's Print_Str misbehaves on one-character strings (its row delay is
; (length - 2) x 2, and a zero runs DECB / BNE round 256 times)
digits              fcc      "0 "
                    fcb      $80
                    fcc      "1 "
                    fcb      $80
                    fcc      "2 "
                    fcb      $80
                    fcc      "3 "
                    fcb      $80
                    fcc      "4 "
                    fcb      $80
                    fcc      "5 "
                    fcb      $80
                    fcc      "6 "
                    fcb      $80
                    fcc      "7 "
                    fcb      $80
                    fcc      "8 "
                    fcb      $80
                    fcc      "9 "
                    fcb      $80

;***************************************************************************
; the trained network (train/vecnist.py writes it)
;***************************************************************************
                    include  "weights.i"
rom_end
