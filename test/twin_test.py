#!/usr/bin/env python3
"""
twin_test.py - the cartridge against its Python twin, byte for byte.

  G items: 300 MNIST test digits as 12 x 12 grids, poked straight into the grid (test_cmd = 1): the cartridge's
           answer and all ten 24-bit scores must equal twin_infer()'s.
  P items: 100 drawings as stroke lists, poked into the point list (test_cmd = 2): the cartridge rasterises them
           itself, so its grid must equal twin_grid()'s, and its answer and scores twin_infer()'s on that grid.
           Half are MNIST skeletons (one-point strokes), half random multi-point strokes (they exercise the walk).
Usage: python3 test/twin_test.py      (needs build/vecnist.bin and build/model.npz)
"""
import os, re, subprocess, sys
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "train"))
import vecnist as V

def grid_bytes(g):
    g = np.asarray(g).reshape(12, 12)
    out = []
    for r in range(12):
        v = 0
        for c in range(12):
            if g[r, c]: v |= 1 << (15 - c)
        out += [v >> 8, v & 255]
    return bytes(out)

def out_bytes(out):
    return bytes(b for v in out for b in ((int(v) >> 16) & 255, (int(v) >> 8) & 255, int(v) & 255))

def main():
    q = dict(np.load(os.path.join(ROOT, "build", "model.npz")))
    q["K1"] = int(q["K1"])
    x, _ = V.mnist("test")
    rng = np.random.default_rng(6809)
    idx = rng.choice(len(x), 360, replace=False)
    sk = V.thin(x[idx])
    items, expect = [], []
    G = V.batch_grids(sk[:300])
    for g in G:
        out, _ = V.twin_infer(q, g)
        items.append("G " + grid_bytes(g).hex())
        expect.append((int(np.argmax(out)), out_bytes(out), None))
    def strokes_item(strokes):
        flat = []
        for i, s in enumerate(strokes):
            if i: flat.append((-128, 0))
            flat += [(y, x_) for (x_, y) in s]
        flat = flat[:V.__dict__.get("MAXPTS", 220)]
        hx = bytes(b for (y, x_) in flat for b in (y & 255, x_ & 255)).hex()
        # the cartridge sees exactly these points: rebuild the strokes from the (possibly cut) list
        st, cur = [], []
        for (y, x_) in flat:
            if y == -128:
                st.append(cur); cur = []
            else:
                cur.append((x_, y))
        st.append(cur)
        g = V.twin_grid(st)
        out, _ = V.twin_infer(q, g)
        items.append(f"P {len(flat)} {hx}")
        expect.append((int(np.argmax(out)), out_bytes(out), grid_bytes(g)))
    for s in sk[300:350]:
        pts = V.skeleton_points(s)[:110]
        strokes_item(pts)
    for _ in range(50):
        strokes = []
        for _ in range(rng.integers(1, 4)):
            n = rng.integers(2, 12)
            p = rng.integers(-110, 110, 2)
            s = [(int(p[0]), int(p[1]))]
            for _ in range(n):
                p = np.clip(p + rng.integers(-30, 31, 2), -120, 120)
                s.append((int(p[0]), int(p[1])))
            strokes.append(s)
        strokes_item(strokes)
    path = os.path.join(ROOT, "build", "batch.txt")
    open(path, "w").write("\n".join(items) + "\n")
    env = dict(os.environ, BATCH=path, BATCH_GRID="1", BATCH_FROM="820", TIMEOUT="600")
    r = subprocess.run([os.path.join(ROOT, "test", "mv.sh"), "-video", "none"], env=env, capture_output=True, text=True)
    ans = re.findall(r"ANS (\d+) ([0-9A-F]+)\nGRID ([0-9A-F]+)", r.stdout)
    if len(ans) != len(items):
        print(f"  the cartridge answered {len(ans)} of {len(items)} items"); print(r.stdout[-500:]); sys.exit(1)
    bad_g = bad_s = bad_r = 0
    for (res, outh, gridh), (er, eo, eg) in zip(ans, expect):
        if bytes.fromhex(outh) != eo: bad_s += 1
        if int(res) != er: bad_r += 1
        if eg is not None and bytes.fromhex(gridh) != eg: bad_g += 1
    print(f"  {len(items)} items: answers {len(items) - bad_r}/{len(items)}, scores {len(items) - bad_s}/{len(items)} "
          f"byte-identical, rasterised grids {100 - bad_g}/100 identical")
    sys.exit(0 if not (bad_g or bad_s or bad_r) else 1)

if __name__ == "__main__":
    main()
