#!/usr/bin/env python3
"""
demo.py - choreography for the demo video and the drawing tests: digits as joystick moves, turned into the
harness's STICK and BTN schedules (MAME frames, 60 per second).

A move is (stick x, stick y, frames, ink): stick values 0..255 with 128 = centre (x 0 = left, y 0 = down).
Each digit: moves, then the pen lifts (the cartridge reads it), a pause to show the answer, button 3 to clear.
   python3 test/demo.py [start_frame]    prints  STICK=... BTN=... END=... EXPECT=...
"""
import sys

HOME = [(0, 255, 45, 0)]                               # stick up-left until the cursor sits in the box's corner
DIGITS = [
    (1, HOME + [(255, 128, 18, 0), (128, 0, 6, 0), (128, 0, 30, 1)]),
    (7, HOME + [(255, 128, 8, 0), (128, 0, 8, 0), (255, 128, 20, 1), (82, 0, 27, 1)]),
    (0, HOME + [(255, 128, 20, 0), (128, 0, 5, 0), (0, 0, 7, 1), (128, 0, 9, 1), (255, 0, 7, 1), (255, 255, 7, 1),
                (128, 255, 9, 1), (0, 255, 7, 1), (0, 0, 2, 1)]),
    (4, HOME + [(255, 128, 8, 0), (128, 0, 5, 0), (128, 0, 16, 1), (255, 128, 18, 1), (128, 255, 1, 0),
                (0, 128, 4, 0), (128, 255, 12, 0), (128, 0, 30, 1)]),
]

def schedule(start=850, digits=DIGITS, pause=110):
    stick, btn, expect, f = [], [], [], start
    for want, moves in digits:
        for x, y, n, ink in moves:
            stick.append(f"{f}-{f + n - 1}:{x}:{y}")
            if ink:
                btn.append(f"{f}-{f + n - 1}:1")
            f += n
        f += pause                                    # the stroke ends: the answer is shown
        expect.append((want, f - 10))                 # (digit, frame to check it)
        btn.append(f"{f}-{f + 2}:3")                  # clear
        f += 20
    return ",".join(stick), ",".join(btn), f, expect

if __name__ == "__main__":
    s, b, end, ex = schedule(int(sys.argv[1]) if len(sys.argv) > 1 else 850)
    print(f"STICK={s}\nBTN={b}\nEND={end}\nEXPECT={' '.join(f'{d}@{f}' for d, f in ex)}")
