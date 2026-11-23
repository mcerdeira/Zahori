"""Genera el "corazón" del jefe final, 192x192 = 12 celdas (paleta gameboy-color-type1).

No tiene forma de corazón: es un bulbo vegetal enorme y asimétrico, cubierto de escamas carnosas
superpuestas (como un alcaucil), con raíces gruesas. Late desde adentro: al dilatarse las escamas
se separan y entre ellas se ve la savia encendida.
- boss_heart_beat_spr_0..3: de reposo (0) a máxima dilatación (3).
- boss_heart_glow_spr_0: halo tramado que el juego suma en modo aditivo.

Uso: python3 tools/gen_boss_heart.py [preview.png]
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image

S = 192
OUT = Path(__file__).resolve().parent.parent / "sprites"
CX, CY = 96.0, 98.0  # centro del bulbo (px)
RX, RY = 62.0, 70.0  # radios del bulbo en reposo (px)


def C(*a):
    return a + (255,)


T = (0, 0, 0, 0)
K = C(0, 0, 0)
M = C(91, 49, 91)
V = C(83, 82, 140)
B = C(148, 58, 58)
R = C(230, 0, 0)
O = C(255, 66, 0)
Y = C(255, 222, 0)
W = C(255, 231, 197)
P = C(255, 133, 132)
D = C(0, 131, 0)
BR = C(58, 40, 2)
BM = C(125, 73, 0)

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# Raíces: (x0, y0, x1, y1, curva, ancho), del bulbo hacia el borde del sprite.
ROOTS = [
    (62, 145, 14, 191, -16, 13), (84, 155, 62, 191, -6, 12), (108, 155, 124, 191, 7, 13),
    (132, 145, 182, 191, 17, 12), (42, 128, 1, 165, 9, 9), (152, 124, 191, 158, -10, 9),
    (82, 40, 62, 1, -8, 10), (100, 36, 104, 1, 5, 11), (118, 44, 146, 1, 10, 8),
]


def half_width(y):
    """Medio ancho del bulbo a la altura y (-1 arriba, 1 abajo): panzón abajo y con cuello."""
    if abs(y) >= 1:
        return 0.0
    bumps = 0.035 * math.sin(y * 7.3 + 1.0) + 0.02 * math.sin(y * 13.0)
    return math.sqrt(1 - y * y) * (0.80 + 0.20 * y + bumps)


def lean(y):
    """Inclina el eje del bulbo para que no quede simétrico."""
    return 0.10 * math.sin(y * 2.2 + 0.5)


def draw_roots(im):
    px = im.load()
    for pass_ in (0, 1):
        for x0, y0, x1, y1, bend, width in ROOTS:
            dx, dy = x1 - x0, y1 - y0
            length = math.hypot(dx, dy)
            nx, ny = -dy / length, dx / length
            steps = int(length * 3)
            for i in range(steps + 1):
                t = i / steps
                off = bend * math.sin(math.pi * t) + 2.0 * math.sin(t * 11 + x0)
                cx, cy = x0 + dx * t + nx * off, y0 + dy * t + ny * off
                w = width * (1.0 - 0.62 * t) + (1.4 if pass_ == 0 else 0.0)
                for yy in range(int(cy - w - 1), int(cy + w + 2)):
                    for xx in range(int(cx - w - 1), int(cx + w + 2)):
                        if not (0 <= xx < S and 0 <= yy < S) or math.hypot(xx - cx, yy - cy) > w:
                            continue
                        if pass_ == 0:
                            px[xx, yy] = K
                            continue
                        side = (xx - cx) * nx + (yy - cy) * ny
                        fiber = int(t * length / 4 + side * 0.8) % 5 == 0
                        if fiber:
                            px[xx, yy] = BR
                        elif side < -w * 0.35:
                            px[xx, yy] = D
                        else:
                            px[xx, yy] = BM if side < w * 0.25 else BR


def make_scales():
    """Escamas de arriba hacia abajo: cada hilera tapa la base de la anterior."""
    rng = random.Random(11)
    scales = []
    rows = 6
    for r in range(rows):
        y = -0.86 + 1.72 * r / (rows - 1)
        hw = max(half_width(y), 0.22)
        count = max(3, round(hw * 4.6))
        for i in range(count + 1):
            k = (i + (0.5 if r % 2 else 0.0)) / count
            lon = -math.pi / 2 + math.pi * k
            if lon > math.pi / 2 + 0.05:
                continue
            scales.append({
                "lon": lon + rng.uniform(-0.05, 0.05),
                "y": y + rng.uniform(-0.018, 0.018),
                "a": rng.uniform(0.92, 1.12),
                "b": rng.uniform(0.92, 1.14),
                "tilt": rng.uniform(-0.22, 0.22),
            })
    scales.sort(key=lambda sc: (round(sc["y"], 1), abs(sc["lon"])))
    return scales


def core_color(x, y, dist, s):
    """Savia del interior, visible entre las escamas: más viva hacia el centro y con el latido."""
    heat = s * (1.25 - dist) + (BAYER[y % 4][x % 4] / 16 - 0.5) * 0.16
    if heat < 0.10:
        return K
    if heat < 0.30:
        return M
    if heat < 0.52:
        return R
    if heat < 0.78:
        return O
    if heat < 0.98:
        return Y
    return W


def frame(s, scales):
    """s: 0 en reposo, 1 en la máxima dilatación."""
    im = Image.new("RGBA", (S, S), T)
    draw_roots(im)
    px = im.load()
    rx, ry = RX + 5.0 * s, RY + 3.0 * s

    def inside(x, y):
        v = (y + 0.5 - CY) / ry
        hw = half_width(v)
        return hw > 0 and abs((x + 0.5 - CX) / rx - lean(v)) < hw

    mask = [[inside(x, y) for x in range(S)] for y in range(S)]
    for y in range(S):
        for x in range(S):
            if mask[y][x]:
                dist = math.hypot((x + 0.5 - CX) / rx, (y + 0.5 - CY) / ry)
                px[x, y] = core_color(x, y, dist, s)

    # Las escamas se achican al dilatarse el bulbo y dejan ver la savia entre ellas
    shrink = 1.0 - 0.20 * s
    for sc in scales:
        hw = half_width(sc["y"])
        sx = CX + rx * (lean(sc["y"]) + hw * math.sin(sc["lon"]))
        sy = CY + ry * sc["y"]
        foreshorten = max(0.42, math.cos(sc["lon"]))
        a = 24.0 * sc["a"] * foreshorten * shrink
        b = 29.0 * sc["b"] * shrink
        tilt = sc["tilt"] + sc["lon"] * 0.34
        co, si = math.cos(tilt), math.sin(tilt)
        for yy in range(max(0, int(sy - b - 3)), min(S, int(sy + b + 4))):
            for xx in range(max(0, int(sx - b - 3)), min(S, int(sx + b + 4))):
                if not mask[yy][xx]:
                    continue
                dx, dy = xx + 0.5 - sx, yy + 0.5 - sy
                p = (dx * co + dy * si) / a
                q = (-dx * si + dy * co) / b
                if not -1.0 <= q <= 1.0:
                    continue
                t = (q + 1) / 2  # 0 en la punta (arriba), 1 en la base
                width = math.sin(math.pi * t ** 0.62) ** 0.8
                if abs(p) > width:
                    continue
                edge = width - abs(p)
                if edge < 0.14 or t < 0.05:
                    px[xx, yy] = K
                    continue
                light = 0.72 - t * 0.55 - p * 0.28 + (-sc["lon"] * 0.20) + 0.10 * s
                light += (BAYER[yy % 4][xx % 4] / 16 - 0.5) * 0.12
                nerve = abs(p) < 0.055 and t < 0.72
                if nerve:
                    c = O if s > 0.6 else (B if s > 0.25 else K)
                elif t < 0.17:
                    c = P if p < 0.1 else B  # punta clara
                elif light > 0.62:
                    c = P if edge < 0.34 and p < 0 else B
                elif light > 0.30:
                    c = B if light > 0.46 else M
                elif light > 0.05:
                    c = M
                else:
                    c = V if (xx + yy) % 2 else M
                px[xx, yy] = c

    # Contorno del bulbo
    for y in range(S):
        for x in range(S):
            if mask[y][x]:
                continue
            if any(0 <= x + i < S and 0 <= y + j < S and mask[y + j][x + i]
                   for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = K
    return im


def glow():
    im = Image.new("RGBA", (S, S), T)
    px = im.load()
    for y in range(S):
        for x in range(S):
            d = math.hypot((x + 0.5 - CX) / 94, (y + 0.5 - CY) / 94)
            level = max(0.0, 1.0 - d)
            if level * 1.8 > (BAYER[y % 4][x % 4] + 0.5) / 16:
                px[x, y] = R if level > 0.34 else B
    return im


if __name__ == "__main__":
    all_scales = make_scales()
    frames = [frame(i / 3, all_scales) for i in range(4)]
    for i, f in enumerate(frames):
        f.save(OUT / f"boss_heart_beat_spr_{i}.png")
    glow().save(OUT / "boss_heart_glow_spr_0.png")
    if len(sys.argv) > 1:
        sheet = Image.new("RGBA", (S * 4, S), C(20, 12, 24))
        for i, f in enumerate(frames):
            sheet.alpha_composite(f, (i * S, 0))
        sheet.resize((S * 8 // 2, S * 2 // 2), Image.NEAREST).save(sys.argv[1])
