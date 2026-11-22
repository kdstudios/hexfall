#!/usr/bin/env python3
"""Builds HEXFALL tile art from the concept tile sheet.

Input : tools/source/ConceptTile.png (argv[1]) and ConceptTilePentagon.png (argv[2]);
        ConceptTile.png (transparent sheet: hidden / flag / mine / boom on row 1,
        numbers 1-4 on row 2). Pass its path as argv[1].
Output: assets/tiles/tile_plates.png   4x8 atlas of 256px hex plates (frames only,
                                       glyph-free, mapped onto cells by corner). Rows 0-3 are hexagon
                                       plates, rows 4-7 the same states as pentagon plates.
        assets/tiles/glyph_digits.png  3 rows x 8 white alpha layers (glow/core/hot)
        assets/tiles/glyph_flag.png    upright flag hologram
        tiles/*.png                    flat composited tiles (0-8, flag, mine ...)
Requires numpy, opencv-python, pillow, scipy.  Run from the project root.
"""
import sys, math, colorsys, os
import numpy as np, cv2
from PIL import Image

S = 256; R = 120.0; C = 128.0
SHEET = sys.argv[1] if len(sys.argv) > 1 else 'tools/source/ConceptTile.png'
PENT = sys.argv[2] if len(sys.argv) > 2 else 'tools/source/ConceptTilePentagon.png'
BOX = {'hidden': (45, 15, 301, 238), 'flag': (387, 15, 644, 238), 'mine': (730, 15, 987, 238),
       'boom': (1072, 15, 1329, 238), 'n1': (15, 262, 289, 493), 'n2': (380, 262, 654, 493),
       'n3': (721, 262, 994, 493), 'n4': (1085, 262, 1359, 493)}
os.makedirs('assets/tiles', exist_ok=True); os.makedirs('tiles', exist_ok=True)

yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
RH = np.maximum(np.abs(yy - C) * 2 / math.sqrt(3), np.abs(xx - C) + np.abs(yy - C) / math.sqrt(3)) / R  # hex "radius"

def norm(name):
    sheet = Image.open(SHEET).convert('RGBA')
    c = sheet.crop(BOX[name]).resize((int(2 * R), int(round(math.sqrt(3) * R))), Image.LANCZOS)
    cell = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cell.paste(c, (int(C - R), int(C - c.height / 2)))
    return np.array(cell).astype(np.float32) / 255

def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1); return t * t * (3 - 2 * t)

def bleed(t):
    """Fill transparent pixels with nearby colour so bilinear filtering never shows a dark fringe."""
    a = (t[..., 3] > 0.5).astype(np.uint8)
    rgb = (t[..., :3] * 255).astype(np.uint8)
    for _ in range(6):
        k = np.ones((3, 3), np.uint8)
        dil = cv2.dilate(rgb, k); m = cv2.dilate(a, k)
        rgb = np.where(a[..., None] > 0, rgb, np.where(m[..., None] > 0, dil, rgb)); a = m
    out = t.copy(); out[..., :3] = rgb.astype(np.float32) / 255
    return out

def clean_recess(t):
    """Replace the recess interior (where digits / glyphs sit) by a flat scanlined fill."""
    fill = np.zeros((S, S, 3), np.float32)
    base = np.array([10, 17, 22], np.float32) / 255
    vg = 1.0 - 0.35 * np.clip(RH / 0.6, 0, 1) ** 2
    scan = 1.0 + 0.10 * (((yy.astype(int)) % 2) * 2 - 1)
    fill[:] = base[None, None, :] * (vg * scan)[..., None]
    w = 1.0 - smooth(0.555, 0.595, RH)
    out = t.copy()
    out[..., :3] = t[..., :3] * (1 - w[..., None]) + fill * w[..., None]
    return out

def hue_shift(t, target_h, sat_mul=1.0, val_mul=1.0, desat=None):
    """Shift the hue of saturated, bright pixels (the glow); steel stays steel."""
    rgb = np.clip(t[..., :3], 0, 1)
    hsv = cv2.cvtColor((rgb * 255).astype(np.uint8), cv2.COLOR_RGB2HSV_FULL).astype(np.float32) / 255
    w = smooth(0.18, 0.45, hsv[..., 1]) * smooth(0.18, 0.40, hsv[..., 2])
    h_new = (target_h % 360) / 360.0
    hsv2 = hsv.copy()
    hsv2[..., 0] = np.where(w > 0, h_new, hsv[..., 0])
    hsv2[..., 1] = np.clip(hsv[..., 1] * (1 + (sat_mul - 1) * w), 0, 1)
    hsv2[..., 2] = np.clip(hsv[..., 2] * (1 + (val_mul - 1) * w), 0, 1)
    if desat is not None:  # push glow towards white / grey
        hsv2[..., 1] = hsv2[..., 1] * (1 - w * desat)
        hsv2[..., 2] = np.clip(hsv2[..., 2] * (1 + 0.25 * w * desat), 0, 1)
    # blend so partial-weight pixels (glow falloff) keep their original hue smoothly
    out_rgb = cv2.cvtColor((hsv2 * 255).astype(np.uint8), cv2.COLOR_HSV2RGB_FULL).astype(np.float32) / 255
    res = t.copy()
    res[..., :3] = rgb * (1 - w[..., None]) + out_rgb * w[..., None]
    return res

def gain(t, k):
    r = t.copy(); r[..., :3] = np.clip(r[..., :3] * k, 0, 1); return r

# ---------------------------------------------------------------- plates
hidden = norm('hidden'); flag_src = norm('flag'); mine = norm('mine'); boom = norm('boom')
n = {i: norm(f'n{i}') for i in range(1, 5)}
p = {i: clean_recess(n[i]) for i in range(1, 5)}          # cyan, green, amber, purple frames
plate = {}
plate['hidden'] = hidden
plate['flag'] = hue_shift(p[1], 212, 1.1, 1.25)           # blue frame
plate['flagWrong'] = hue_shift(p[1], 2, 1.1, 1.1)         # red frame (wrong flag after a loss)
plate['mine'] = mine
plate['boom'] = boom
b = hue_shift(p[1], 200, 0.35, 0.65)                       # dim steel-blue: scanned, no mines nearby
plate['blank'] = b
plate[1] = p[1]; plate[2] = p[2]; plate[3] = p[3]; plate[4] = p[4]
plate[5] = hue_shift(p[3], 356, 1.25, 1.05)                   # red-orange
plate[6] = hue_shift(p[2], 174, 1.0, 1.0)                  # teal
plate[7] = hue_shift(p[4], 318, 1.0, 1.05)                 # magenta
plate[8] = hue_shift(p[1], 200, 1.0, 1.1, desat=0.88)      # white
ORDER = ['hidden', 'flag', 'mine', 'boom', 'blank', 1, 2, 3, 4, 5, 6, 7, 8, 'flagWrong']

# ---------------------------------------------------------------- pentagon plates (the 12 pentagon cells)
PR = 120.0
S72, C36 = math.sin(math.radians(72)), math.cos(math.radians(36))
PBOX = {'hidden': (23, 11, 256, 232), 'clean': (291, 7, 524, 228)}
def pent_norm(name):
    sheet = Image.open(PENT).convert('RGBA')
    c = sheet.crop(PBOX[name]).resize((int(round(2 * PR * S72)), int(round(PR * (1 + C36)))), Image.LANCZOS)
    cell = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cell.paste(c, (int(round(C - c.width / 2)), int(round(C - PR))))
    return np.array(cell).astype(np.float32) / 255
def pent_mask(radius_frac, feather):
    pts = np.array([(C + radius_frac * PR * math.cos(math.radians(90 + 72 * k)),
                     C - radius_frac * PR * math.sin(math.radians(90 + 72 * k))) for k in range(5)], np.float32)
    big = np.zeros((S * 4, S * 4), np.uint8)
    cv2.fillPoly(big, [(pts * 4).astype(np.int32)], 255)
    m = cv2.resize(big, (S, S), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    return cv2.GaussianBlur(m, (0, 0), feather) if feather > 0 else m
def pent_hue(t, target_h, sat_mul=2.1, val_mul=1.25, desat=None):
    rgb = np.clip(t[..., :3], 0, 1)
    hsv = cv2.cvtColor((rgb * 255).astype(np.uint8), cv2.COLOR_RGB2HSV_FULL).astype(np.float32) / 255
    w = smooth(0.05, 0.20, hsv[..., 1]) * smooth(0.14, 0.34, hsv[..., 2])
    h2 = hsv.copy(); h2[..., 0] = (target_h % 360) / 360.0
    h2[..., 1] = np.clip(hsv[..., 1] * sat_mul, 0, 1)
    h2[..., 2] = np.clip(hsv[..., 2] * val_mul, 0, 1)
    if desat is not None:
        h2[..., 1] *= (1 - desat); h2[..., 2] = np.clip(h2[..., 2] * 1.25, 0, 1)
    out = cv2.cvtColor((h2 * 255).astype(np.uint8), cv2.COLOR_HSV2RGB_FULL).astype(np.float32) / 255
    res = t.copy(); res[..., :3] = rgb * (1 - w[..., None]) + out * w[..., None]
    return res
def paste_centre(dst, src, radius_px, scale):
    """Paste the middle of src (circular, feathered) onto dst, scaled about the centre."""
    r = int(radius_px); crop = src[int(C) - r:int(C) + r, int(C) - r:int(C) + r].copy()
    n = int(round(2 * r * scale)); crop = cv2.resize(crop, (n, n), interpolation=cv2.INTER_AREA)
    yy2, xx2 = np.mgrid[0:n, 0:n].astype(np.float32); d = np.hypot(xx2 - n / 2, yy2 - n / 2) / (n / 2)
    w = (1 - smooth(0.72, 1.0, d))[..., None] * crop[..., 3:4]
    o = int(C - n / 2); out = dst.copy()
    out[o:o + n, o:o + n, :3] = out[o:o + n, o:o + n, :3] * (1 - w) + crop[..., :3] * w
    return out
pbase = pent_norm('clean'); pplate = {'hidden': pent_norm('hidden')}
pplate['flag'] = pent_hue(pbase, 212)
pplate['flagWrong'] = pent_hue(pbase, 2)
pplate['blank'] = pent_hue(pbase, 200, 1.2, 0.8)
for k, h in {1: 192, 2: 130, 3: 38, 4: 272, 5: 356, 6: 174, 7: 318}.items():
    pplate[k] = pent_hue(pbase, h)
pplate[8] = pent_hue(pbase, 200, desat=0.9)
red = pent_hue(pbase, 2, 2.6, 1.5)
pplate['mine'] = paste_centre(red, mine, 64, 0.80)
dark = red.copy(); dark[..., :3] *= 0.75
pplate['boom'] = paste_centre(dark, boom, 76, 0.74)

atlas = np.zeros((2048, 1024, 4), np.float32)
for idx, key in enumerate(ORDER):
    for base_idx, src in ((0, plate), (16, pplate)):
        r, c = divmod(idx + base_idx, 4)
        atlas[r * S:(r + 1) * S, c * S:(c + 1) * S] = bleed(gain(src[key], 1.12))
Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8)).save('assets/tiles/tile_plates.png', optimize=True)

def add_relief(a):
    """Orientation-independent depth: local contrast (ridges bright, crevices dark),
    a raised outer rim and a shadowed inner groove. Baked, so free at runtime."""
    out = a.copy()
    for r0 in range(0, a.shape[0], S):
        for c0 in range(0, a.shape[1], S):
            t = a[r0:r0 + S, c0:c0 + S]
            L = t[..., :3].max(axis=2)
            d1 = L - cv2.GaussianBlur(L, (0, 0), 2.5)
            d2 = L - cv2.GaussianBlur(L, (0, 0), 7.0)
            dist = cv2.distanceTransform((t[..., 3] > 0.5).astype(np.uint8), cv2.DIST_L2, 5)
            rim = 0.20 * np.exp(-((dist - 1.8) ** 2) / 2.0) - 0.16 * np.exp(-((dist - 7.5) ** 2) / 6.0)
            k = np.clip(1 + 1.9 * d1 + 1.1 * d2 + rim, 0.45, 1.8)
            out[r0:r0 + S, c0:c0 + S, :3] = np.clip(t[..., :3] * k[..., None], 0, 1)
    return out
Image.fromarray((np.clip(add_relief(atlas), 0, 1) * 255).astype(np.uint8)).save('assets/tiles/tile_plates_relief.png', optimize=True)

# ---------------------------------------------------------------- digits (own strokes, one consistent style)
SS = 4; W = 17.0
def arc(cx, cy, rx, ry, a0, a1, n=48):
    return [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))
            for a in np.linspace(a0, a1, n)]
DIG = {
 1: [[(115, 109), (132, 96.5), (132, 159.5)]],
 2: [arc(128, 114, 14.5, 17, 188, 400) + [(113.5, 159.5), (143, 159.5)]],
 3: [arc(128, 112.5, 14, 16, 200, 450) + arc(128, 144.5, 15.5, 16, 270, 520)],
 4: [[(139, 159.5), (139, 96.5), (112, 142), (147, 142)]],
 5: [[(142, 97), (118.5, 97), (115.5, 127)] + arc(128, 143.5, 15.5, 16.5, 232, 500)],
 6: [arc(128, 114.5, 14.5, 18, 322, 180) + [(113.5, 143)] + arc(128, 144, 14.5, 15.5, 180, 540)],
 7: [[(112.5, 97), (143, 97), (122, 160)]],
 8: [arc(128, 112, 13, 15.5, 90, 450), arc(128, 144, 15, 16, 270, 630)],
}
def stroke_mask(paths):
    big = np.zeros((S * SS, S * SS), np.uint8)
    for pts in paths:
        pp = np.array([(x * SS, y * SS) for x, y in pts], np.float32)
        cv2.polylines(big, [pp.astype(np.int32)], False, 255, int(W * SS), cv2.LINE_AA)
        for (x, y) in (pp[0], pp[-1]):
            cv2.circle(big, (int(x), int(y)), int(W * SS / 2), 255, -1, cv2.LINE_AA)
    return cv2.resize(big, (S, S), interpolation=cv2.INTER_AREA).astype(np.float32) / 255

def layers(m):
    glow = np.maximum(cv2.GaussianBlur(m, (0, 0), 5) * 1.2, cv2.GaussianBlur(m, (0, 0), 13) * 0.75)
    glow = np.clip(glow, 0, 1) * (1 - 0.0)
    core = np.clip(cv2.GaussianBlur(m, (0, 0), 0.8), 0, 1)
    dt = cv2.distanceTransform((m > 0.5).astype(np.uint8), cv2.DIST_L2, 5)
    hot = np.clip(cv2.GaussianBlur(np.clip((dt - 1.0) / 4.0, 0, 1), (0, 0), 1.2), 0, 1) * core
    return glow, core, hot

digits = np.zeros((S * 3, S * 8, 4), np.float32); masks = {}
for d in range(1, 9):
    m = stroke_mask(DIG[d]); masks[d] = m
    for row, layer in enumerate(layers(m)):
        digits[row * S:(row + 1) * S, (d - 1) * S:d * S, :3] = 1
        digits[row * S:(row + 1) * S, (d - 1) * S:d * S, 3] = layer
Image.fromarray((digits * 255).astype(np.uint8)).save('assets/tiles/glyph_digits.png', optimize=True)

# ---------------------------------------------------------------- flag glyph (from the concept tile)
fs = flag_src; mx = fs[..., :3].max(axis=2)
region = ((xx > 98) & (xx < 167) & (yy > 80) & (yy < 176)).astype(np.float32)
region = cv2.GaussianBlur(region, (0, 0), 2)
alpha = np.clip((mx - 0.34) * 2.6, 0, 1) * region
rgb = np.clip(fs[..., :3] / np.maximum(alpha[..., None], 0.2), 0, 1)
flag = np.dstack([rgb, alpha])
Image.fromarray((flag * 255).astype(np.uint8)).save('assets/tiles/glyph_flag.png', optimize=True)

# ---------------------------------------------------------------- flat composited tiles for UI / preview
PAL = {1: (0x40, 0xD8, 0xFF), 2: (0x4C, 0xE0, 0x7A), 3: (0xFF, 0xC0, 0x40), 4: (0xB0, 0x7C, 0xFF),
       5: (0xFF, 0x55, 0x3A), 6: (0x20, 0xE0, 0xB8), 7: (0xFF, 0x4F, 0xD8), 8: (0xFF, 0xFF, 0xFF)}
def over(dst, src_rgb, a):
    dst[..., :3] = dst[..., :3] * (1 - a[..., None]) + np.array(src_rgb, np.float32) * a[..., None]
def composite(key, src=None):
    t = gain((src or plate)[key], 1.12).copy()
    if isinstance(key, int) and key > 0:
        col = np.array(PAL[key], np.float32) / 255
        g, c, h = layers(masks[key])
        for lay, k, wt in ((g, col, 0.9), (c, col * 0.75 + 0.25, 1.0), (h, col * 0.25 + 0.75, 1.0)):
            a = lay * wt; over(t, k, a)
    if key in ('flag', 'flagWrong'):
        a = flag[..., 3]; t[..., :3] = t[..., :3] * (1 - a[..., None]) + flag[..., :3] * a[..., None]
    return t
names = {'hidden': 'tile_hidden', 'flag': 'tile_flag', 'flagWrong': 'tile_flag_wrong', 'mine': 'tile_mine',
         'boom': 'tile_exploded', 'blank': 'tile_0'}
for key in ORDER:
    nm = names.get(key, f'tile_{key}')
    Image.fromarray((np.clip(composite(key), 0, 1) * 255).astype(np.uint8)).save(f'tiles/{nm}.png', optimize=True)
for key in ORDER:
    nm = 'pent_' + names.get(key, f'tile_{key}').replace('tile_', '')
    Image.fromarray((np.clip(composite(key, pplate), 0, 1) * 255).astype(np.uint8)).save(f'tiles/{nm}.png', optimize=True)
# contact sheet
sheet = Image.new('RGBA', (S * 7, S * 4), (8, 14, 22, 255))
order2 = ['hidden', 'flag', 'mine', 'boom', 'blank', 'flagWrong', 1, 2, 3, 4, 5, 6, 7, 8]
for i, key in enumerate(order2):
    im = Image.fromarray((np.clip(composite(key), 0, 1) * 255).astype(np.uint8))
    sheet.alpha_composite(im, ((i % 7) * S, (i // 7) * S))
    imp = Image.fromarray((np.clip(composite(key, pplate), 0, 1) * 255).astype(np.uint8))
    sheet.alpha_composite(imp, ((i % 7) * S, (i // 7 + 2) * S))
sheet.save('tiles/contact_sheet.png')
print('ok')
