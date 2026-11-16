#!/usr/bin/env python3
"""Generate the game's original, seamless, high-resolution textures.

Every texture is produced from spectral noise so it tiles perfectly. Output is
public domain (CC0) like the rest of the generated assets.

Usage: python3 tools/gen_textures.py game/assets/textures
"""
import os
import sys

import numpy as np
from PIL import Image

N = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "game/assets/textures"
os.makedirs(OUT, exist_ok=True)


def spectral(size, beta, seed, aniso=(1.0, 1.0)):
    """Periodic 1/f^beta noise in [0,1]. aniso stretches frequencies (x, y)."""
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(size, size))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * aniso[1]
    fx = np.fft.fftfreq(size)[None, :] * aniso[0]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    f *= 1.0 / r ** beta
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    out /= out.max()
    return out


def band(size, lo, hi, seed, aniso=(1.0, 1.0)):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.normal(size=(size, size)))
    fy = np.fft.fftfreq(size)[:, None] * aniso[1] * size
    fx = np.fft.fftfreq(size)[None, :] * aniso[0] * size
    r = np.sqrt(fx * fx + fy * fy)
    f *= (r >= lo) & (r <= hi)
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    return out / out.max()


def lerp(a, b, t):
    t = t[..., None]
    return a * (1 - t) + b * t


def ramp(t, stops):
    """Map scalar field t to colour via list of (pos, (r,g,b))."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(p1 - p0, 1e-6))[m][:, None]
        out[m] = np.array(c0) * (1 - k) + np.array(c1) * k
    return out


def save_rgb(name, rgb):
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


def save_rgba(name, rgba):
    img = Image.fromarray(np.clip(rgba * 255, 0, 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


def save_normal(name, height, strength):
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(dx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    save_rgb(name + "_n", n * 0.5 + 0.5)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


# --- Ground ---------------------------------------------------------------
def grass():
    large = spectral(N, 1.6, 1)
    blades = band(N, 120, 400, 2, aniso=(1.0, 4.0))
    fine = band(N, 250, 512, 3)
    t = 0.45 * large + 0.4 * blades + 0.15 * fine
    col = ramp(t, [(0, rgb("26361a")), (0.35, rgb("3d5523")), (0.6, rgb("5b7430")),
                   (0.85, rgb("7f8f3f")), (1, rgb("a49c58"))])
    dry = spectral(N, 2.0, 4)
    col = lerp(col, col * np.array([1.18, 1.05, 0.7]), np.clip((dry - 0.6) * 3, 0, 1))
    save_rgb("grass", col)
    save_normal("grass", blades * 0.6 + fine * 0.4, 6)


def dirt():
    large = spectral(N, 1.8, 10)
    mid = band(N, 30, 120, 11)
    pebbles = band(N, 60, 160, 12)
    peb = np.clip((pebbles - 0.68) * 6, 0, 1)
    t = 0.6 * large + 0.4 * mid
    col = ramp(t, [(0, rgb("2e2219")), (0.4, rgb("4f3b2a")), (0.75, rgb("6d5640")), (1, rgb("8a7458"))])
    col = lerp(col, np.array(rgb("8d8579")), peb * 0.8)
    save_rgb("dirt", col)
    save_normal("dirt", mid * 0.5 + peb * 0.8, 7)


def sand():
    large = spectral(N, 2.0, 20)
    yy, xx = np.mgrid[0:N, 0:N] / N
    warp = spectral(N, 2.2, 21)
    ripples = 0.5 + 0.5 * np.sin(2 * np.pi * (24 * yy + 3 * xx) + warp * 9)
    grain = band(N, 300, 512, 22)
    t = 0.5 * large + 0.3 * ripples + 0.2 * grain
    col = ramp(t, [(0, rgb("9a7a52")), (0.5, rgb("c9a676")), (1, rgb("e6cc9b"))])
    save_rgb("sand", col)
    save_normal("sand", ripples * 0.7 + grain * 0.3, 4)


def snow():
    large = spectral(N, 2.0, 30)
    grain = band(N, 200, 512, 31)
    t = 0.7 * large + 0.3 * grain
    col = ramp(t, [(0, rgb("aab8c8")), (0.5, rgb("dde6ef")), (1, rgb("ffffff"))])
    save_rgb("snow", col)


def rock():
    large = spectral(N, 1.7, 40)
    ridged = 1 - np.abs(spectral(N, 1.5, 41) * 2 - 1)
    strata = 0.5 + 0.5 * np.sin(np.mgrid[0:N, 0:N][0] / N * 2 * np.pi * 14 + large * 8)
    cracks = np.clip((ridged - 0.9) * 10, 0, 1)
    fine = band(N, 150, 512, 42)
    t = 0.45 * large + 0.25 * strata + 0.2 * fine - cracks * 0.4
    col = ramp(t, [(0, rgb("2a2a2c")), (0.4, rgb("555452")), (0.7, rgb("7c7a74")), (1, rgb("a8a49a"))])
    lichen = np.clip((spectral(N, 1.4, 43) - 0.72) * 5, 0, 1)
    col = lerp(col, np.array(rgb("6f7a45")), lichen * 0.5)
    save_rgb("rock", col)
    save_normal("rock", large * 0.4 + strata * 0.2 + fine * 0.3 - cracks, 9)


def asphalt():
    large = spectral(N, 1.8, 50)
    grain = band(N, 200, 512, 51)
    stones = np.clip((band(N, 100, 300, 52) - 0.7) * 5, 0, 1)
    t = 0.4 * large + 0.45 * grain + 0.3 * stones
    col = ramp(t, [(0, rgb("1d1e20")), (0.5, rgb("35363a")), (1, rgb("5f5f60"))])
    cracks = 1 - np.abs(spectral(N, 1.4, 53) * 2 - 1)
    col *= (1 - np.clip((cracks - 0.94) * 12, 0, 0.7))[..., None]
    save_rgb("asphalt", col)
    save_normal("asphalt", grain * 0.6 + stones * 0.4, 5)


# --- Materials ------------------------------------------------------------
def bark():
    streak = band(N, 6, 60, 60, aniso=(1.0, 12.0))
    fine = band(N, 60, 300, 61, aniso=(1.0, 4.0))
    ridges = np.clip(streak * 1.4 - 0.2, 0, 1)
    t = 0.65 * ridges + 0.35 * fine
    col = ramp(t, [(0, rgb("1d140e")), (0.4, rgb("3d2b1e")), (0.75, rgb("5d4632")), (1, rgb("7d6650"))])
    save_rgb("bark", col)
    save_normal("bark", ridges * 0.8 + fine * 0.2, 12)


def planks():
    yy, xx = np.mgrid[0:N, 0:N]
    boards = 8
    bh = N // boards
    row = yy // bh
    grain = band(N, 4, 60, 70, aniso=(14.0, 1.0))
    fine = band(N, 60, 300, 71, aniso=(6.0, 1.0))
    rng = np.random.default_rng(72)
    tint = rng.uniform(0.82, 1.12, size=boards)[row]
    offset = rng.integers(0, N, size=boards)[row]
    seam_y = (yy % bh) < 4
    seam_x = ((xx + offset) % (N // 2)) < 4
    t = 0.6 * grain + 0.4 * fine
    col = ramp(t, [(0, rgb("4a3220")), (0.5, rgb("7a5636")), (1, rgb("a77c52"))]) * tint[..., None]
    seam = seam_y | seam_x
    col[seam] *= 0.35
    save_rgb("planks", col)
    h = t * 0.4
    h[seam] = -0.4
    save_normal("planks", h, 6)


def metal_paint():
    large = spectral(N, 1.9, 80)
    grime = np.clip((spectral(N, 1.6, 81) - 0.55) * 2.2, 0, 1)
    streaks = band(N, 4, 60, 82, aniso=(1.0, 16.0))
    fine = band(N, 300, 512, 83)
    base = np.ones((N, N, 3)) * np.array(rgb("e9e2cf"))
    base *= (0.92 + 0.08 * large + 0.03 * fine)[..., None]
    base = lerp(base, np.array(rgb("6b5a44")), np.clip(grime * 0.55 + (streaks - 0.6) * 0.8, 0, 0.75))
    rust = np.clip((spectral(N, 1.3, 84) - 0.8) * 6, 0, 1)
    base = lerp(base, np.array(rgb("8a4a24")), rust * 0.9)
    save_rgb("rv_paint", base)


def rusty_metal():
    large = spectral(N, 1.6, 90)
    fine = band(N, 150, 512, 91)
    t = 0.6 * large + 0.4 * fine
    col = ramp(t, [(0, rgb("3b2214")), (0.4, rgb("7a3e1d")), (0.7, rgb("a8612e")), (1, rgb("6f6a63"))])
    save_rgb("rust", col)
    save_normal("rust", fine, 5)


def fabric():
    yy, xx = np.mgrid[0:N, 0:N]
    weave = (np.sin(xx / N * 2 * np.pi * 256) * np.sin(yy / N * 2 * np.pi * 256)) * 0.5 + 0.5
    large = spectral(N, 1.9, 100)
    t = 0.3 * weave + 0.7 * large
    col = ramp(t, [(0, rgb("4b5a3c")), (1, rgb("7b8a5c"))])
    save_rgb("canvas", col)


def concrete():
    large = spectral(N, 1.7, 110)
    fine = band(N, 150, 512, 111)
    stains = np.clip((spectral(N, 1.5, 112) - 0.6) * 2, 0, 1)
    t = 0.5 * large + 0.5 * fine
    col = ramp(t, [(0, rgb("6a6966")), (1, rgb("a9a6a0"))])
    col = lerp(col, np.array(rgb("4a4640")), stains * 0.5)
    save_rgb("concrete", col)


def water_normal():
    h = band(N // 2, 6, 40, 120) * 0.6 + band(N // 2, 30, 120, 121) * 0.4
    save_normal("water", h, 3)


# --- Alpha cards ----------------------------------------------------------
def grass_card():
    S = 512
    img = np.zeros((S, S, 4))
    rng = np.random.default_rng(130)
    yy, xx = np.mgrid[0:S, 0:S] / S
    for _ in range(70):
        x0 = rng.uniform(0.08, 0.92)
        h = rng.uniform(0.45, 0.98)
        w = rng.uniform(0.008, 0.018)
        lean = rng.uniform(-0.18, 0.18)
        t = 1 - yy  # 0 bottom, 1 top
        cx = x0 + lean * t * t
        width = w * np.clip(1 - t / h, 0, 1) ** 0.7
        m = (np.abs(xx - cx) < width) & (t < h)
        shade = 0.45 + 0.55 * t / h
        c = np.array(rgb(rng.choice(["4c6b25", "5f7f2c", "7b8f3a", "6a7d2e", "93954a"])))
        img[m, :3] = c * shade[m][:, None]
        img[m, 3] = 1
    save_rgba("grass_card", img)


def leaf_card():
    S = 512
    img = np.zeros((S, S, 4))
    rng = np.random.default_rng(140)
    yy, xx = np.mgrid[0:S, 0:S] / S
    for _ in range(260):
        cx, cy = rng.uniform(0.06, 0.94, 2)
        if (cx - 0.5) ** 2 + (cy - 0.5) ** 2 > 0.2:
            continue
        a = rng.uniform(0, np.pi)
        L = rng.uniform(0.03, 0.06)
        W = L * 0.45
        dx, dy = xx - cx, yy - cy
        u = dx * np.cos(a) + dy * np.sin(a)
        v = -dx * np.sin(a) + dy * np.cos(a)
        m = (u / L) ** 2 + (v / W) ** 2 < 1
        c = np.array(rgb(rng.choice(["2f4a1e", "3e5d24", "4f6e2b", "5c7a33", "6b8438"])))
        img[m, :3] = c * (0.75 + 0.25 * (1 - (v[m] / W) ** 2))[:, None]
        img[m, 3] = 1
    save_rgba("leaf_card", img)


def needle_card():
    S = 512
    img = np.zeros((S, S, 4))
    rng = np.random.default_rng(150)
    yy, xx = np.mgrid[0:S, 0:S] / S
    for i in range(500):
        y0 = rng.uniform(0.05, 0.95)
        half = 0.48 * (1 - abs(y0 - 0.5) * 1.6)
        x0 = 0.5
        x1 = 0.5 + rng.uniform(-half, half)
        y1 = y0 + rng.uniform(0.02, 0.08)
        # line segment distance
        px, py = xx - x0, yy - y0
        dx, dy = x1 - x0, y1 - y0
        ll = dx * dx + dy * dy + 1e-9
        t = np.clip((px * dx + py * dy) / ll, 0, 1)
        d = np.hypot(px - t * dx, py - t * dy)
        m = d < 0.004
        c = np.array(rgb(rng.choice(["1d3520", "264429", "2f5231", "3b5f36"])))
        img[m, :3] = c
        img[m, 3] = 1
    # central twig
    m = np.abs(xx - 0.5) < 0.006
    img[m, :3] = np.array(rgb("3b2a1c"))
    img[m, 3] = 1
    save_rgba("needle_card", img)


for fn in [grass, dirt, sand, snow, rock, asphalt, bark, planks, metal_paint, rusty_metal,
           fabric, concrete, water_normal, grass_card, leaf_card, needle_card]:
    fn()
    print("generated", fn.__name__)


# --- v1.1 material set ------------------------------------------------------
def brushed_metal():
    streak = band(N, 2, 300, 200, aniso=(1.0, 40.0))
    large = spectral(N, 1.8, 201)
    scratches = np.clip((band(N, 200, 512, 202, aniso=(30.0, 1.0)) - 0.8) * 4, 0, 1)
    t = 0.55 * streak + 0.3 * large + 0.15 * scratches
    col = ramp(t, [(0, rgb("6e7175")), (0.5, rgb("a3a7ab")), (1, rgb("d2d5d8"))])
    save_rgb("metal", col)
    save_normal("metal", streak * 0.4 + scratches * 0.3, 3)


def paint_chipped():
    large = spectral(N, 1.7, 210)
    chips = np.clip((spectral(N, 1.2, 211) - 0.72) * 8, 0, 1)
    grime = np.clip((spectral(N, 2.0, 212) - 0.5) * 1.5, 0, 1)
    base = np.ones((N, N, 3)) * (0.88 + 0.12 * large)[..., None]
    base = lerp(base, np.array(rgb("6a6e70")), chips)
    base = lerp(base, np.array(rgb("4a3f33")), grime * 0.35)
    save_rgb("paint", base)
    save_normal("paint", -chips * 0.6 + large * 0.1, 4)


def leather():
    cells = band(N, 60, 200, 220)
    creases = 1 - np.abs(spectral(N, 1.6, 221) * 2 - 1)
    large = spectral(N, 1.8, 222)
    t = 0.4 * cells + 0.4 * large + 0.2 * creases
    col = ramp(t, [(0, rgb("2e1c12")), (0.5, rgb("5a3a24")), (1, rgb("8a6040"))])
    save_rgb("leather", col)
    save_normal("leather", cells * 0.6 + np.clip((creases - 0.9) * 8, 0, 1) * -0.5, 5)


def rubber():
    yy, xx = np.mgrid[0:N, 0:N] / N
    tread = (np.sin(2 * np.pi * (yy * 32 + np.abs(((xx * 4) % 1) - 0.5) * 3)) > 0.2).astype(float)
    grain = band(N, 200, 512, 230)
    col = ramp(0.6 * tread + 0.4 * grain, [(0, rgb("101010")), (1, rgb("2c2c2c"))])
    save_rgb("rubber", col)
    save_normal("rubber", tread * 0.8 + grain * 0.2, 8)


def fur():
    strands = band(N, 30, 400, 240, aniso=(1.0, 6.0))
    clumps = spectral(N, 1.6, 241)
    t = 0.65 * strands + 0.35 * clumps
    col = ramp(t, [(0, rgb("3a3a3a")), (0.5, rgb("8a8a8a")), (1, rgb("e8e8e8"))])
    save_rgb("fur", col)
    save_normal("fur", strands, 6)


def shingles():
    yy, xx = np.mgrid[0:N, 0:N]
    rows = 16
    rh = N // rows
    row = yy // rh
    off = (row % 2) * (N // 16)
    tile_w = N // 8
    edge_y = (yy % rh) / rh
    seam = ((xx + off) % tile_w) < 4
    rng = np.random.default_rng(250)
    tint = rng.uniform(0.75, 1.15, size=(rows, 9))[row, ((xx + off) // tile_w) % 9]
    grain = band(N, 150, 512, 251)
    col = ramp(grain, [(0, rgb("3a3330")), (1, rgb("6a5c52"))]) * tint[..., None]
    col *= (0.65 + 0.35 * edge_y)[..., None]
    col[seam] *= 0.4
    save_rgb("shingles", col)
    h = edge_y * 0.6 + grain * 0.2
    h[seam] -= 0.4
    save_normal("shingles", h, 6)


def logs():
    yy, xx = np.mgrid[0:N, 0:N]
    rows = 8
    rh = N // rows
    v = (yy % rh) / rh
    profile = np.sqrt(np.clip(1 - (2 * v - 1) ** 2, 0, 1))
    grain = band(N, 4, 80, 260, aniso=(16.0, 1.0))
    knots = np.clip((band(N, 20, 60, 261) - 0.85) * 6, 0, 1)
    rng = np.random.default_rng(262)
    tint = rng.uniform(0.85, 1.1, size=rows)[yy // rh]
    t = 0.6 * grain + 0.25 * profile - knots * 0.4
    col = ramp(t, [(0, rgb("3b2616")), (0.5, rgb("7a5232")), (1, rgb("b08356"))]) * tint[..., None]
    col *= (0.45 + 0.55 * profile)[..., None]
    save_rgb("logs", col)
    save_normal("logs", profile * 1.2 + grain * 0.15, 10)


def cardboard():
    yy, xx = np.mgrid[0:N, 0:N] / N
    flutes = 0.5 + 0.5 * np.sin(2 * np.pi * xx * 96)
    large = spectral(N, 1.8, 270)
    col = ramp(0.2 * flutes + 0.8 * large, [(0, rgb("8a6a44")), (1, rgb("c49c6a"))])
    save_rgb("cardboard", col)


def skin():
    large = spectral(N, 2.0, 280)
    pores = band(N, 250, 512, 281)
    col = ramp(0.7 * large + 0.3 * pores, [(0, rgb("a8765a")), (1, rgb("dcab8c"))])
    save_rgb("skin", col)
    save_normal("skin", pores, 2)


def denim():
    yy, xx = np.mgrid[0:N, 0:N]
    twill = ((xx + yy) % 8 < 4).astype(float)
    large = spectral(N, 1.8, 290)
    fine = band(N, 200, 512, 291)
    col = ramp(0.3 * twill + 0.5 * large + 0.2 * fine, [(0, rgb("1e2a3c")), (1, rgb("4a5f80"))])
    save_rgb("denim", col)
    save_normal("denim", twill * 0.5 + fine * 0.5, 3)


def fabric_plaid():
    yy, xx = np.mgrid[0:N, 0:N] / N
    a = (np.sin(2 * np.pi * xx * 8) > 0.3).astype(float)
    b = (np.sin(2 * np.pi * yy * 8) > 0.3).astype(float)
    fine = band(N, 250, 512, 300)
    base = np.ones((N, N, 3)) * np.array(rgb("8a2f2a"))
    base = lerp(base, np.array(rgb("2a2422")), (a * b) * 0.8)
    base = lerp(base, np.array(rgb("b05a40")), (np.maximum(a, b) - a * b) * 0.35)
    base *= (0.9 + 0.1 * fine)[..., None]
    save_rgb("plaid", base)


for fn in [brushed_metal, paint_chipped, leather, rubber, fur, shingles, logs, cardboard, skin, denim, fabric_plaid]:
    fn()
    print("generated", fn.__name__)
