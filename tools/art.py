#!/usr/bin/env python3
"""
art.py - the pictures for the web page and the repository, made from real frames of the demo (vecinst.mp4).

  overlay/vecnist.png     a Vectrex overlay (the translucent coloured film every Vectrex game came with): title band,
                          tinted play areas, the four buttons' jobs along the bottom.  768 x 1024 with alpha, in the
                          shape of the screen; Vide's overlay folder takes it as it is.
  art/screen_N.png        a captured frame seen through the overlay (vectors take the film's colour, the way white
                          lines do under coloured plastic), for N = the digits of the demo
  social-preview.png      1280 x 640: a 1983 computer advertisement, by way of a war-room terminal

   python3 tools/art.py              (needs build/answer_*.png: ./run.sh --video vecinst.mp4 makes them)
"""
import glob, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F_BLACK = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBlack.ttf"
F_BOLD = "/usr/share/fonts/truetype/noto/NotoSans-CondensedBold.ttf"
F_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
W, H = 768, 1024                                    # the screen, portrait, as MAME records it here
BOX = (48, 352, 452, 760)                           # the drawing box on the captured frames
PANEL = (500, 330, 750, 640)                        # bars and the answer

def font(path, size): return ImageFont.truetype(path, size)

def pixel_text(text, size, fill, scale=3):
    """text drawn small and blown up with nearest-neighbour: the chunky pixels of a 1983 terminal"""
    f = font(F_MONO, size)
    w = int(f.getlength(text)) + 4
    im = Image.new("RGBA", (w, size + 6), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((2, 1), text, font=f, fill=fill)
    return im.resize((w * scale, (size + 6) * scale), Image.NEAREST)

def vgradient(w, h, top, bottom):
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, float)[None, None, :] * (1 - t) + np.array(bottom, float)[None, None, :] * t
    return Image.fromarray(np.repeat(a, w, axis=1).astype(np.uint8))

def chrome_text(text, size, w, h, colors=((255, 245, 180), (255, 150, 30), (230, 40, 90), (120, 20, 160))):
    """an 80s chrome/sunset fill clipped to the letters, with a dark outline and glow"""
    f = font(F_BLACK, size)
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    tw = d.textlength(text, font=f)
    x = (w - tw) / 2
    d.text((x, 0), text, font=f, fill=255)
    stops = np.linspace(0, h, len(colors))
    ys = np.arange(h)
    grad = np.stack([np.interp(ys, stops, [c[k] for c in colors]) for k in range(3)], axis=1)
    fill = Image.fromarray(np.repeat(grad[:, None, :], w, axis=1).astype(np.uint8))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    edge = mask.filter(ImageFilter.MaxFilter(7))
    out.paste((20, 0, 40, 255), (0, 0), edge)
    out.paste(fill, (0, 0), mask)
    glow = mask.filter(ImageFilter.GaussianBlur(10))
    g = Image.new("RGBA", (w, h), (255, 60, 180, 0)); g.putalpha(glow.point(lambda v: v // 2))
    return Image.alpha_composite(g, out)

# ----------------------------------------------------------------------------
# the overlay: tint (multiplies the beam) and artwork (sits on top)
# ----------------------------------------------------------------------------
def make_overlay():
    tint = Image.new("RGB", (W, H), (190, 120, 255))                     # violet film over the whole screen
    d = ImageDraw.Draw(tint)
    d.rectangle(BOX, fill=(120, 255, 240))                               # cyan over the drawing box
    pan = vgradient(PANEL[2] - PANEL[0], PANEL[3] - PANEL[1], (255, 210, 90), (255, 90, 200))
    tint.paste(pan, PANEL[:2])                                           # amber to magenta over the scores
    d.rectangle((40, 190, 740, 235), fill=(255, 235, 140))               # warm yellow over the title line
    art = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    a = ImageDraw.Draw(art)
    # the title band: deep blue with the logo
    band = vgradient(W, 176, (10, 8, 40), (40, 10, 70)).convert("RGBA")
    art.paste(band, (0, 0))
    art.alpha_composite(chrome_text("VECNIST", 132, W, 150), (0, 4))
    sub = pixel_text("NEURAL DIGIT READER  *  STOCK 1982 HARDWARE", 11, (120, 255, 200, 255), 2)
    art.alpha_composite(sub, ((W - sub.width) // 2, 146))
    for i, c in enumerate([(255, 60, 60), (255, 150, 30), (255, 220, 40), (60, 220, 120), (60, 160, 255)]):
        a.rectangle((0, 176 + i * 3, W, 177 + i * 3), fill=c + (255,))  # the stripes of every 1983 computer ad
    # the bottom band: what the four buttons do, as on every Vectrex overlay
    art.paste(vgradient(W, 176, (40, 10, 70), (10, 8, 40)).convert("RGBA"), (0, H - 176))
    for i, c in enumerate([(60, 160, 255), (60, 220, 120), (255, 220, 40), (255, 150, 30), (255, 60, 60)]):
        a.rectangle((0, H - 176 + i * 3, W, H - 175 + i * 3), fill=c + (255,))
    labels = [("1", "INK"), ("2", "READ"), ("3", "CLEAR"), ("4", "PEN")]
    pw = (W - 5 * 24) // 4
    for i, (n, t) in enumerate(labels):
        x0 = 24 + i * (pw + 24); y0 = H - 140
        a.rounded_rectangle((x0, y0, x0 + pw, y0 + 96), radius=18, fill=(0, 0, 0, 200), outline=(255, 90, 200, 255), width=4)
        a.ellipse((x0 + 12, y0 + 22, x0 + 64, y0 + 74), fill=(230, 40, 60, 255), outline=(255, 200, 200, 255), width=3)
        a.text((x0 + 38, y0 + 48), n, font=font(F_BLACK, 34), fill=(255, 255, 255, 255), anchor="mm")
        a.text((x0 + 74, y0 + 48), t, font=font(F_BLACK, 30), fill=(255, 235, 140, 255), anchor="lm")
    tag = pixel_text("NO FRAME BUFFER  *  1 KB RAM  *  6809 @ 1.5 MHZ", 10, (120, 255, 200, 255), 2)
    art.alpha_composite(tag, ((W - tag.width) // 2, H - 34))
    return tint, art

def through_overlay(frame, tint, art):
    """what a captured frame looks like through the film: beam x tint, then the printed artwork"""
    f = np.asarray(frame.convert("RGB"), float) / 255.0
    t = np.asarray(tint, float) / 255.0
    lit = np.clip(f * t * 1.25 + (t * 0.10) * 0.35, 0, 1)                 # a lit film glows faintly even where dark
    img = Image.fromarray((lit * 255).astype(np.uint8)).convert("RGBA")
    return Image.alpha_composite(img, art).convert("RGB")

# ----------------------------------------------------------------------------
# the social card: a 1983 ad by way of a war-room terminal
# ----------------------------------------------------------------------------
def social(screen):
    card = Image.new("RGB", (1280, 640), (2, 6, 4))
    d = ImageDraw.Draw(card)
    for y in range(0, 640, 3):                                          # phosphor scanlines
        d.line((0, y, 1280, y), fill=(4, 14, 8))
    cx, cy, r = 380, 300, 250                                           # a wireframe globe, drawn the vector way
    for k in range(-80, 81, 20):
        rr = r * np.cos(np.radians(k)); yy = cy - r * np.sin(np.radians(k))
        d.ellipse((cx - rr, yy - rr * 0.18, cx + rr, yy + rr * 0.18), outline=(0, 70, 30))
    for k in range(0, 180, 20):
        rx = abs(r * np.cos(np.radians(k)))
        d.ellipse((cx - rx, cy - r, cx + rx, cy + r), outline=(0, 70, 30))
    term = [("LOGON:  VECNIST", (60, 255, 120)), ("", None),
            ("> SHALL WE READ A DIGIT?", (60, 255, 120)), ("", None),
            ("  CPU ........ MOTOROLA 6809 @ 1.5 MHZ", (40, 200, 90)),
            ("  RAM ........ 1 KB", (40, 200, 90)),
            ("  FRAME BUFFER  NONE. THE BEAM IS STEERED.", (255, 190, 40)),
            ("  NETWORK .... 144 > 64 > 10, 10 KB OF WEIGHTS", (40, 200, 90)),
            ("  MNIST ...... 93.2% (10,000 TEST DIGITS)", (40, 200, 90)),
            ("  ADD-ONS .... NONE. NO PITREX. NO VECFEVER.", (255, 190, 40)),
            ("                     NO VECTREX32.", (255, 190, 40))]
    y = 178
    for t, c in term:
        if t:
            im = pixel_text(t, 9, c + (255,), 2)
            glow = im.filter(ImageFilter.GaussianBlur(4))
            card.paste(glow, (48, y), glow); card.paste(im, (48, y), im)
        y += 28 if t else 14
    size = 90                                                           # the headline, as large as fits
    while font(F_BLACK, size).getlength("IT READS YOUR HANDWRITING.") > 790:
        size -= 2
    head = chrome_text("IT READS YOUR HANDWRITING.", size, 800, size + 24)
    card.paste(head, (16, 20), head)
    sub = pixel_text("A NEURAL NETWORK ON A STOCK 1982 VECTREX", 12, (255, 235, 140, 255), 2)
    card.paste(sub, (48, 32 + size + 12), sub)
    for i, c in enumerate([(255, 60, 60), (255, 150, 30), (255, 220, 40), (60, 220, 120), (60, 160, 255)]):
        d.rectangle((0, 584 + i * 9, 820, 590 + i * 9), fill=c)           # the stripes
    chips = ["12 KB ROM", "400/400 BYTE-EXACT", "VIDE PROJECT", "RUNS IN MAME"]
    x = 48
    for t in chips:
        f = font(F_BLACK, 22)
        w = int(f.getlength(t)) + 30
        d.rounded_rectangle((x, 528, x + w, 564), radius=10, fill=(10, 10, 30), outline=(255, 90, 200), width=3)
        d.text((x + 15, 546), t, font=f, fill=(255, 235, 140), anchor="lm")
        x += w + 14
    # the console: a dark bezel with the screen seen through the overlay
    bez = (840, 14, 1262, 626)
    d.rounded_rectangle(bez, radius=28, fill=(18, 18, 22), outline=(70, 70, 80), width=4)
    sh = bez[3] - bez[1] - 36
    sw = int(sh * W / H)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    card.paste(scr, (bez[0] + (bez[2] - bez[0] - sw) // 2, bez[1] + 18))
    return card

def main():
    frames = sorted(glob.glob(os.path.join(ROOT, "build", "answer_*.png")), key=lambda p: float(p.split("_")[-1][:-4]))
    if not frames:
        sys.exit("no build/answer_*.png: run ./run.sh --video vecinst.mp4 first")
    tint, art = make_overlay()
    os.makedirs(os.path.join(ROOT, "overlay"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "art"), exist_ok=True)
    film = tint.convert("RGBA"); film.putalpha(90)                     # the overlay as Vide/ParaJVE take it
    Image.alpha_composite(film, art).save(os.path.join(ROOT, "overlay", "vecnist.png"))
    digits = os.environ.get("DEMO_DIGITS", "1704")
    shots = []
    for dgt, f in zip(digits, frames):
        im = through_overlay(Image.open(f).resize((W, H)), tint, art)
        im.save(os.path.join(ROOT, "art", f"screen_{dgt}.png"))
        shots.append(im)
    social(shots[1] if len(shots) > 1 else shots[0]).save(os.path.join(ROOT, "social-preview.png"))
    print(f"  overlay/vecnist.png, art/screen_{{{','.join(digits[:len(shots)])}}}.png, social-preview.png")

if __name__ == "__main__":
    main()
