#!/usr/bin/env python3
"""
vecnist.py - the PC half of VecNIST: MNIST, made to look like what a Vectrex player draws, a network trained on it,
and the integer twins of everything the Vectrex itself computes.

What the Vectrex does with a drawing (and twin_grid() below does identically, in integers):
  1. strokes are lists of points in screen units (signed bytes, y up);
  2. their bounding box is fitted into 9 x 9 cells: R = RECIP[size] = 2048 // size (size = the longer side, at
     least 16), cell = ((v - min) * R) >> 8.  One MUL, no division;
  3. the box is centred in a 12 x 12 grid, and consecutive points of a stroke are joined by an 8-connected walk
     (step x and y toward the target until both arrive).
MNIST is brought to the same form: each digit is thresholded and thinned to a one-pixel skeleton (Zhang-Suen),
its skeleton pixels become points at 8 screen units per MNIST pixel, and the same steps make its 12 x 12 grid.
Training adds small random rotations, slants and stretches, the way a joystick drawing wobbles.

The network: 144 binary inputs -> 64 hidden (ReLU) -> 10.  On the Vectrex:
  acc[j] = B1[j] + sum of W1[cell][j] over the inked cells       (16-bit, additions only: the inputs are 0/1)
  h[j]   = clamp(acc[j] >> K1, 0, 255)
  out[k] = B2[k] + sum_j h[j] * W2[k][j]                          (24-bit; MUL of h by |W2|, then add or subtract)
twin_infer() is that arithmetic, bit for bit.

Usage:
  python3 train/vecnist.py train [--epochs N]    train, quantise, write weights.i (and build/model.npz)
  python3 train/vecnist.py test                   integer-twin accuracy on the 10,000 MNIST test digits
  python3 train/vecnist.py selftest               twin consistency checks (batch pipeline == per-drawing pipeline)
"""
import os, struct, sys, time
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.environ.get("MNIST_DIR", os.path.join(ROOT, "data"))
BUILD = os.path.join(ROOT, "build")
GRID = 12
BOX = 9                                  # the drawing's longer side spans 9 cells (MNIST: 20 of 28 pixels)
HID = 64
MIN_SIZE = 16
RECIP = [0] * 256
for s in range(256):
    RECIP[s] = (BOX - 1) * 256 // max(s, MIN_SIZE)    # (BOX-1) so that the far edge lands in cell BOX-1
UNIT = 8                                 # screen units per MNIST pixel

# ----------------------------------------------------------------------------
# MNIST
# ----------------------------------------------------------------------------
def load_idx(name):
    d = open(os.path.join(DATA, name), "rb").read()
    magic, n = struct.unpack(">II", d[:8])
    if magic == 2051:
        r, c = struct.unpack(">II", d[8:16])
        return np.frombuffer(d, np.uint8, offset=16).reshape(n, r, c)
    return np.frombuffer(d, np.uint8, offset=8)

def mnist(split):
    if split == "train":
        return load_idx("TRAIN.IDX"), load_idx("TRAINL.IDX")
    return load_idx("TEST.IDX"), load_idx("TESTL.IDX")

# ----------------------------------------------------------------------------
# Zhang-Suen thinning, a whole batch at a time
# ----------------------------------------------------------------------------
def thin(images, threshold=96):
    """(N, 28, 28) uint8 -> (N, 28, 28) bool skeletons"""
    b = np.pad(images > threshold, ((0, 0), (1, 1), (1, 1)))
    while True:
        changed = False
        for step in (0, 1):
            P = b
            p2, p3, p4 = P[:, :-2, 1:-1], P[:, :-2, 2:], P[:, 1:-1, 2:]
            p5, p6, p7 = P[:, 2:, 2:], P[:, 2:, 1:-1], P[:, 2:, :-2]
            p8, p9 = P[:, 1:-1, :-2], P[:, :-2, :-2]
            c = P[:, 1:-1, 1:-1]
            nb = [p2, p3, p4, p5, p6, p7, p8, p9]
            B = sum(x.astype(np.int8) for x in nb)
            A = sum(((~nb[i]) & nb[(i + 1) % 8]).astype(np.int8) for i in range(8))
            if step == 0:
                m = c & (B >= 2) & (B <= 6) & (A == 1) & ~(p2 & p4 & p6) & ~(p4 & p6 & p8)
            else:
                m = c & (B >= 2) & (B <= 6) & (A == 1) & ~(p2 & p4 & p8) & ~(p2 & p6 & p8)
            if m.any():
                changed = True
                b = b.copy()
                b[:, 1:-1, 1:-1] &= ~m
        if not changed:
            return b[:, 1:-1, 1:-1]

# ----------------------------------------------------------------------------
# the Vectrex's preprocessing: the per-drawing twin and the batch version used for training
# ----------------------------------------------------------------------------
def twin_grid(strokes):
    """strokes: list of lists of (x, y) signed screen units -> 12 x 12 uint8 grid (row 0 = top), exactly as the 6809"""
    pts = [p for s in strokes for p in s]
    g = np.zeros((GRID, GRID), np.uint8)
    if not pts:
        return g
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    w, h = maxx - minx, maxy - miny
    R = RECIP[max(w, h)]
    ox = (GRID - (((w * R) >> 8) + 1)) >> 1
    oy = (GRID - (((h * R) >> 8) + 1)) >> 1
    def cell(p):
        return (((maxy - p[1]) * R) >> 8) + oy, (((p[0] - minx) * R) >> 8) + ox
    for s in strokes:
        if not s:
            continue
        r, c = cell(s[0]); g[r, c] = 1
        for p in s[1:]:
            tr, tc = cell(p)
            while (r, c) != (tr, tc):
                if r != tr: r += 1 if tr > r else -1
                if c != tc: c += 1 if tc > c else -1
                g[r, c] = 1
    return g

def skeleton_points(skel):
    """one MNIST skeleton -> its pixels as single-point strokes in screen units"""
    ys, xs = np.nonzero(skel)
    return [[(int(x) * UNIT - 112, (27 - int(y)) * UNIT - 112)] for y, x in zip(ys, xs)]

RECIP_NP = np.array(RECIP, np.int64)
def batch_grids(skels, rng=None, aug=0.0):
    """(N, 28, 28) skeletons -> (N, 144) float32 grids through the Vectrex's arithmetic, optionally with a random
    affine wobble (rotation, slant, stretch) applied to the skeleton points first"""
    N = len(skels)
    n_idx, yy, xx = np.nonzero(skels)
    x = xx.astype(np.float64) - 13.5
    y = 13.5 - yy.astype(np.float64)
    if aug and rng is not None:
        ang = rng.normal(0, 0.18 * aug, N); shear = rng.normal(0, 0.20 * aug, N)
        sx = np.exp(rng.normal(0, 0.12 * aug, N)); sy = np.exp(rng.normal(0, 0.12 * aug, N))
        ca, sa = np.cos(ang)[n_idx], np.sin(ang)[n_idx]
        x1 = (x + shear[n_idx] * y) * sx[n_idx]
        y1 = y * sy[n_idx]
        x, y = ca * x1 - sa * y1, sa * x1 + ca * y1
    X = np.clip(np.round(x * UNIT - 4), -127, 127).astype(np.int64)
    Y = np.clip(np.round(y * UNIT - 4), -127, 127).astype(np.int64)
    big = 1 << 20
    minx = np.full(N, big); maxx = np.full(N, -big); miny = np.full(N, big); maxy = np.full(N, -big)
    np.minimum.at(minx, n_idx, X); np.maximum.at(maxx, n_idx, X)
    np.minimum.at(miny, n_idx, Y); np.maximum.at(maxy, n_idx, Y)
    empty = minx == big
    minx[empty] = maxx[empty] = miny[empty] = maxy[empty] = 0
    w, h = maxx - minx, maxy - miny
    R = RECIP_NP[np.maximum(w, h)]
    ox = (GRID - (((w * R) >> 8) + 1)) >> 1
    oy = (GRID - (((h * R) >> 8) + 1)) >> 1
    r = (((maxy[n_idx] - Y) * R[n_idx]) >> 8) + oy[n_idx]
    c = (((X - minx[n_idx]) * R[n_idx]) >> 8) + ox[n_idx]
    g = np.zeros((N, GRID * GRID), np.float32)
    g[n_idx, r * GRID + c] = 1.0
    return g

# ----------------------------------------------------------------------------
# the network: float training, integer quantisation, the integer twin
# ----------------------------------------------------------------------------
def train(epochs=12, seed=1982):
    rng = np.random.default_rng(seed)
    t0 = time.time()
    xtr, ytr = mnist("train")
    xte, yte = mnist("test")
    print(f"  thinning {len(xtr)} + {len(xte)} digits ...", flush=True)
    str_ = thin(xtr); ste = thin(xte)
    Gte = batch_grids(ste)
    W1 = rng.normal(0, np.sqrt(2.0 / 144), (144, HID)).astype(np.float32); b1 = np.zeros(HID, np.float32)
    W2 = rng.normal(0, np.sqrt(2.0 / HID), (HID, 10)).astype(np.float32); b2 = np.zeros(10, np.float32)
    params = [W1, b1, W2, b2]
    m = [np.zeros_like(p) for p in params]; v = [np.zeros_like(p) for p in params]
    lr, b1m, b2m, eps, step = 2e-3, 0.9, 0.999, 1e-8, 0
    Y1 = np.eye(10, dtype=np.float32)
    for ep in range(epochs):
        G = batch_grids(str_, rng, aug=1.0)
        order = rng.permutation(len(G))
        for i in range(0, len(G), 128):
            idx = order[i:i + 128]
            x, t = G[idx], Y1[ytr[idx]]
            z1 = x @ W1 + b1; h = np.maximum(z1, 0)
            z2 = h @ W2 + b2
            p = np.exp(z2 - z2.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
            d2 = (p - t) / len(idx)
            gW2 = h.T @ d2; gb2 = d2.sum(0)
            dh = d2 @ W2.T * (z1 > 0)
            gW1 = x.T @ dh; gb1 = dh.sum(0)
            step += 1
            for k, (pp, g) in enumerate(zip(params, [gW1, gb1, gW2, gb2])):
                m[k] = b1m * m[k] + (1 - b1m) * g; v[k] = b2m * v[k] + (1 - b2m) * g * g
                pp -= lr * (m[k] / (1 - b1m ** step)) / (np.sqrt(v[k] / (1 - b2m ** step)) + eps)
        if ep == epochs // 2: lr *= 0.4
        if ep == epochs * 3 // 4: lr *= 0.4
        acc = (np.argmax(np.maximum(Gte @ W1 + b1, 0) @ W2 + b2, 1) == yte).mean()
        print(f"  epoch {ep + 1:2d}/{epochs}: float test accuracy {100 * acc:.2f}%  ({time.time() - t0:.0f} s)", flush=True)
    return quantise(W1, b1, W2, b2, batch_grids(str_[:20000])), Gte, yte

def quantise(W1, b1, W2, b2, Gcal):
    S1 = 127.0 / np.abs(W1).max()
    W1q = np.round(W1 * S1).astype(np.int64); B1q = np.round(b1 * S1).astype(np.int64)
    acc = Gcal.astype(np.int64) @ W1q + B1q
    assert np.abs(acc).max() < 32768, "layer 1 sums must fit 16 bits"
    hi = np.percentile(acc[acc > 0], 99.9)
    K1 = max(0, int(np.ceil(np.log2(max(hi, 1) / 255.0))))
    S2 = 127.0 / np.abs(W2).max()
    W2q = np.round(W2 * S2).astype(np.int64)                     # (HID, 10)
    B2q = np.round(b2 * S2 * S1 / (1 << K1)).astype(np.int64)
    # one logit unit is S1*S2/2^K1 in the 24-bit scores: the score bars shift by about that much (x2 per bar step)
    BAR = max(0, int(np.round(np.log2(S1 * S2 / (1 << K1)))) - 2)
    return dict(W1=W1q, B1=B1q, W2=W2q, B2=B2q, K1=K1, BAR=BAR)

def twin_infer(q, grid):
    """the 6809's arithmetic: grid (144,) of 0/1 -> (out[10] as signed 24-bit ints, h[64])"""
    acc = q["B1"].copy()
    for cell in np.nonzero(np.asarray(grid).reshape(-1))[0]:
        acc = acc + q["W1"][cell]
    acc = ((acc + 32768) % 65536) - 32768                        # 16-bit wrap (never happens: asserted in quantise)
    h = np.clip(acc >> q["K1"], 0, 255)
    out = q["B2"] + h @ q["W2"]
    return out, h

def twin_infer_batch(q, G):
    acc = G.astype(np.int64) @ q["W1"] + q["B1"]
    h = np.clip(acc >> q["K1"], 0, 255)
    return h @ q["W2"] + q["B2"]

# ----------------------------------------------------------------------------
# the ROM's tables
# ----------------------------------------------------------------------------
def fcb(rows, per=16):
    out = []
    for i in range(0, len(rows), per):
        out.append("                    fcb      " + ",".join(str(int(v) & 0xFF) for v in rows[i:i + per]))
    return "\n".join(out)

def write_weights(q, path, info):
    W1, B1, W2, B2, K1 = q["W1"], q["B1"], q["W2"], q["B2"], q["K1"]
    assert np.abs(B2).max() < (1 << 23)
    L = ["; weights.i - generated by train/vecnist.py from MNIST: do not edit",
         f"; {info}",
         f"K1                  equ      {K1}                  ; hidden activation = clamp(acc >> K1, 0, 255)",
         f"HID                 equ      {HID}",
         f"BAR_SHIFT           equ      {q['BAR']}                  ; score bars: (best - score) >> BAR_SHIFT, a quarter logit per step",
         "; W1: 144 rows (one per grid cell, row-major from the top left), 64 signed bytes each",
         "W1:"]
    for cell in range(144):
        L.append(fcb(W1[cell], 64 if False else 16))
    L.append("; B1: 64 signed words")
    L.append("B1:")
    for i in range(0, HID, 8):
        L.append("                    fdb      " + ",".join(str(int(v) & 0xFFFF) for v in B1[i:i + 8]))
    L.append("; W2: 10 rows (one per digit), 64 signed bytes each")
    L.append("W2:")
    for k in range(10):
        L.append(fcb(W2[:, k]))
    L.append("; B2: 10 signed 24-bit values, big-endian")
    L.append("B2:")
    L.append(fcb([b for v in B2 for b in ((int(v) >> 16) & 255, (int(v) >> 8) & 255, int(v) & 255)], 15))
    L.append("; RECIP: (BOX-1)*256 // max(size, 16): fits a drawing's longer side into 9 cells with one MUL")
    L.append("RECIP:")
    L.append(fcb(RECIP))
    open(path, "w").write("\n".join(L) + "\n")

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "train"
    os.makedirs(BUILD, exist_ok=True)
    if cmd == "train":
        epochs = int(sys.argv[sys.argv.index("--epochs") + 1]) if "--epochs" in sys.argv else 12
        q, Gte, yte = train(epochs)
        out = twin_infer_batch(q, Gte)
        acc = (np.argmax(out, 1) == yte).mean()
        info = f"integer twin: {100 * acc:.2f}% on the 10,000 MNIST test digits; K1={q['K1']}"
        print("  " + info)
        np.savez(os.path.join(BUILD, "model.npz"), **q)
        write_weights(q, os.path.join(ROOT, "weights.i"), info)
        print("  wrote weights.i")
    elif cmd == "test":
        q = dict(np.load(os.path.join(BUILD, "model.npz")))
        q["K1"] = int(q["K1"]); q["BAR"] = int(q["BAR"])
        xte, yte = mnist("test")
        out = twin_infer_batch(q, batch_grids(thin(xte)))
        print(f"  integer twin: {100 * (np.argmax(out, 1) == yte).mean():.2f}% on the 10,000 MNIST test digits")
    elif cmd == "selftest":
        xte, _ = mnist("test")
        sk = thin(xte[:300])
        G = batch_grids(sk)
        for i in range(300):
            assert (twin_grid(skeleton_points(sk[i])).reshape(-1) == G[i]).all(), i
        # strokes: a diagonal and a corner become connected walks
        g = twin_grid([[(-50, 50), (50, -50)], [(-50, -50), (-50, 50)]])
        assert g.sum() > 9
        print("  selftest ok: batch pipeline == per-drawing pipeline on 300 digits")
    else:
        print(__doc__); sys.exit(2)

if __name__ == "__main__":
    main()
