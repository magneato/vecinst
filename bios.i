; bios.i - the Vectrex BIOS entry points and RAM locations VecNIST uses (addresses as in the BIOS listing and
; Vide's VECTREX.I).  Every BIOS routine below expects DP = $D0, which Wait_Recal leaves set.
Vec_Btn_State       equ      $C80F                ; buttons now (1 = down): joystick 1 buttons 1-4 = bits 0-3
Vec_Buttons         equ      $C811                ; buttons pressed since the last Read_Btns
Vec_Joy_Resltn      equ      $C81A                ; joystick conversion resolution ($00 = finest)
Vec_Joy_1_X         equ      $C81B                ; joystick 1 left/right, signed
Vec_Joy_1_Y         equ      $C81C                ; joystick 1 up/down, signed
Vec_Joy_Mux_1_X     equ      $C81F                ; which pots Joy_Analog reads (1 / 3 = joystick 1 x / y, 0 = skip)
Vec_Joy_Mux_1_Y     equ      $C820
Vec_Joy_Mux_2_X     equ      $C821
Vec_Joy_Mux_2_Y     equ      $C822
Vec_Misc_Count      equ      $C823                ; must be 0 so Draw_Line_d draws a single vector
Vec_Text_HW         equ      $C82A                ; text height (negative) and width for Print_Str_d
VIA_t1_cnt_lo       equ      $D004                ; the scale: how long a move or a line lasts
VIA_int_flags       equ      $D00D                ; VIA interrupt flags: bit 1 = CA1, which the light pen pulses
Wait_Recal          equ      $F192                ; wait for the frame, zero the beam, DP = $D0
Read_Btns           equ      $F1BA
Joy_Analog          equ      $F1F5
Intensity_a         equ      $F2AB                ; beam brightness = A
Dot_here            equ      $F2C5                ; a dot where the beam is
Moveto_d            equ      $F312                ; move the beam by (A = y, B = x) at the current scale
Reset0Ref           equ      $F354                ; beam back to the centre
Print_Str_d         equ      $F37A                ; text at (A = y, B = x), string at U ending in $80
Draw_Line_d         equ      $F3DF                ; a line by (A = y, B = x) at the current scale
