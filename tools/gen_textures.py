#!/usr/bin/env python3
"""wakuVFX texture generator: every texture the runtime uses, white/greyscale RGB + alpha (tinted at runtime).
usage: gen_textures.py <out_dir> [size=512]. Deterministic (fixed seeds); edit the functions to restyle."""
import sys, os
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "textures"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 512
os.makedirs(OUT, exist_ok=True)
y, x = (np.mgrid[0:N, 0:N] + 0.5) / N * 2 - 1           # -1..1, y down
r = np.hypot(x, y)
ang = np.arctan2(y, x)

STRIPS = {"slash_body", "slash_edge", "slash_ink", "slash_rim", "bolt_glow"}

def save(name, alpha, lum=None):
    a = np.clip(alpha, 0, 1)
    if name in STRIPS:
        # Beam textures: Roblox runs the image's vertical axis along the beam's length, so the width profile
        # (authored here along v = rows) goes on the horizontal axis
        a = a.T.copy()
        lum = None if lum is None else np.asarray(lum).T.copy()
    l = np.ones_like(a) if lum is None else np.clip(lum, 0, 1)
    im = np.zeros((N, N, 4), np.uint8)
    im[..., 0] = im[..., 1] = im[..., 2] = (l * 255).astype(np.uint8)
    im[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(im, "RGBA").save(f"{OUT}/{name}.png")
    print(name)

def noise(seed, octaves=5, base=4):
    """tileable-ish value noise, 0..1"""
    rng = np.random.default_rng(seed)
    acc = np.zeros((N, N)); amp = 1.0; tot = 0
    for o in range(octaves):
        g = base * 2 ** o
        grid = rng.random((g + 1, g + 1))
        im = Image.fromarray((grid * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        acc += amp * np.asarray(im) / 255; tot += amp; amp *= 0.5
    return acc / tot

def smooth(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

# soft round glow (dust, flashes)
save("glow_soft", np.exp(-(r / 0.45) ** 2) * (r < 1))

# tapered spark streak, vertical (ParticleOrientation.VelocityParallel aligns +Y with velocity)
w = 0.10 * (1 - np.abs(y)) ** 0.7 + 1e-3
save("spark_streak", np.exp(-(x / w) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 0.5)

# four-point glint star: long tapered rays, hot core, soft halo (blooms at high particle Brightness)
rayx = np.exp(-(y / (0.035 * (1 - np.abs(x)) + 0.004)) ** 2) * np.clip(1 - np.abs(x), 0, 1) ** 1.2
rayy = np.exp(-(x / (0.035 * (1 - np.abs(y)) + 0.004)) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 1.2
diag = np.exp(-((np.abs(x) - np.abs(y)) / 0.02) ** 2) * np.clip(1 - r * 1.8, 0, 1) * 0.5
save("spark_glint", np.clip(np.maximum.reduce([rayx, rayy, diag]) + np.exp(-(r / 0.1) ** 2) + 0.35 * np.exp(-(r / 0.3) ** 2), 0, 1))

# shock ring card: bright thin leading edge, soft trailing inside, broken by noise
n1 = noise(11)
edge = np.exp(-((r - 0.86) / 0.035) ** 2)
trail = smooth(0.35, 0.85, r) * (r < 0.86) * 0.55
save("shock_ring", np.clip(edge + trail * (0.6 + 0.6 * n1), 0, 1) * (r < 0.95))

# ground crack: branching random-walk cracks from the centre (dark ink at runtime, glowing core)
def crack_mask(seed, arms=9, steps=110, width=2.6):
    rng = np.random.default_rng(seed)
    img = Image.new("L", (N, N), 0)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    def walk(px, py, a, n, wid):
        for i in range(n):
            a += rng.normal(0, 0.28)
            nx, ny = px + np.cos(a) * N / 230, py + np.sin(a) * N / 230
            dr.line([(px, py), (nx, ny)], fill=255, width=max(1, int(wid)))
            px, py = nx, ny
            wid *= 0.988
            if rng.random() < 0.035 and wid > 1.2:
                walk(px, py, a + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), int(n * 0.45), wid * 0.7)
            if np.hypot(px - N / 2, py - N / 2) > N * 0.48:
                break
    for k in range(arms):
        walk(N / 2, N / 2, k / arms * 2 * np.pi + rng.uniform(-0.2, 0.2), steps, width * N / 256)
    return np.asarray(img) / 255.0
cm = crack_mask(21)
glow = np.asarray(Image.fromarray((cm * 255).astype(np.uint8)).resize((N // 8, N // 8), Image.BILINEAR).resize((N, N), Image.BICUBIC)) / 255
save("ground_crack", np.clip(cm + glow * 0.9 + np.exp(-(r / 0.16) ** 2) * 0.8, 0, 1) * smooth(1.0, 0.8, r))

# frost ring: broken bright rim, fern frost fringe outside it, crackled see-through inside
nr = noise(31, 6, 6)
rim = np.exp(-((r - 0.82 - (nr - 0.5) * 0.06) / 0.025) ** 2) * smooth(0.25, 0.5, noise(33, 3, 8))
fringe = np.clip(np.abs(np.sin(ang * 61 + nr * 9)) ** 10 * smooth(0.8, 0.86, r) * smooth(0.99, 0.88, r), 0, 1)
inner_cracks = crack_mask(34, arms=26, steps=60, width=1.3) * smooth(0.3, 0.75, r) * (r < 0.82)
haze = smooth(0.4, 0.82, r) * (r < 0.83) * 0.25
save("frost_ring", np.clip(rim + fringe * 0.8 + inner_cracks * 0.8 + haze, 0, 1))

# frost cracks on the ground: fine branching cracks with feathered frost (bright layer + dark copy at runtime)
fc = crack_mask(42, arms=14, steps=95, width=1.8)
feather = np.asarray(Image.fromarray((fc * 255).astype(np.uint8)).resize((N // 6, N // 6), Image.BILINEAR).resize((N, N), Image.BICUBIC)) / 255
save("frost_crack", np.clip(fc + feather * 0.7, 0, 1) * smooth(1.0, 0.75, r))

# soft disc (scorch pools, ground shadows)
save("ground_disc", smooth(1.0, 0.45, r) * (0.85 + 0.15 * noise(71)))

# frost patch on the ground: feathery noise disc
fp = noise(41, 6, 3) * smooth(0.95, 0.35, r)
save("frost_ground", smooth(0.25, 0.7, fp))

# slash strips (Beam texture: U along the arc, V across the width; v = 0 is the OUTER edge of the crescent).
# body: hard bright outer edge, saturated body fading toward the inner edge, brush streaks along the arc
u = (x + 1) / 2; v = (y + 1) / 2
streak = 0.65 + 0.35 * np.asarray(Image.fromarray((noise(51, 3, 2)[:, :1].repeat(N, 1) * 255).astype(np.uint8))) / 255
across = np.exp(-((v - 0.5) / 0.26) ** 2)
brush = 0.55 + 0.45 * np.asarray(Image.fromarray((noise(52, 4, 3)[:, :1].repeat(N, 1) * 255).astype(np.uint8))) / 255
body = smooth(0.0, 0.05, v) * (1 - smooth(0.25, 1.0, v)) ** 1.4 * brush
save("slash_body", body)  # no fade along U: consecutive beam segments must join seamlessly
save("slash_edge", np.exp(-((v - 0.07) / 0.045) ** 2) * np.ones_like(u))
save("slash_ink", smooth(0.0, 0.2, v) * (1 - smooth(0.45, 1.0, v)) * (0.7 + 0.3 * brush))
save("slash_rim", np.exp(-((v - 0.5) / 0.09) ** 2) * np.ones_like(u))

# bolt glow: soft cross-profile for lightning beams
save("bolt_glow", np.exp(-((v - 0.5) / 0.22) ** 2))

# smoke / mist puff: lumpy, lighter top (lum gradient), soft edge
n6 = noise(61, 5, 3)
puff = smooth(0.95, 0.45, r + (n6 - 0.5) * 0.5)
save("smoke_puff", puff * (0.55 + 0.45 * n6), lum=0.75 + 0.25 * (1 - v))

# ice shard: a sharp sliver
sh = (np.abs(x) < 0.32 * (1 - (y + 1) / 2) ** 0.9) * (y > -0.95)
save("ice_shard", sh.astype(float) * (0.7 + 0.3 * (1 - (y + 1) / 2)))
