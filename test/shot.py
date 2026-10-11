#!/usr/bin/env python3
"""shot.py - MAME's vector screen refreshes at 60 Hz and the Vectrex draws at 50, so one snapshot holds part of a
frame.  Merge consecutive snapshots (the brightest pixel wins) into one picture of the whole screen.
   python3 test/shot.py OUT.png snap1.png snap2.png ..."""
import sys
from PIL import Image, ImageChops
ims = [Image.open(p).convert("RGB") for p in sys.argv[2:]]
m = ims[0]
for im in ims[1:]:
    m = ImageChops.lighter(m, im)
m.save(sys.argv[1])
