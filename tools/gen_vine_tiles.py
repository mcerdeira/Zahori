"""Genera los tiles 16x16 de la zona final, el interior de la planta (paleta gameboy-color-type1).

Sólidos (raíces y tallos entretejidos, tileables):
- floor_vine, floor_vine_alt, floor_vine_vein: rellenos intercambiables.
- floor_vine_top/bottom/left/right: bordes con un tallo grueso y hojas.
- floor_vine_tl/tr/bl/br: esquinas exteriores.
Decorativos (sin colisión):
- bg_vine: pared del fondo, oscura, para que el player se distinga.
- deco_vine_hang: enredadera colgante (se repite en vertical).
- deco_vine_hang_end: punta de la enredadera colgante.

Uso: python3 tools/gen_vine_tiles.py [preview.png]
"""
import math
import sys
from pathlib import Path

from PIL import Image

S = 16
OUT = Path(__file__).resolve().parent.parent / "sprites"


def C(*a):
    return a + (255,)


T = (0, 0, 0, 0)
K = C(0, 0, 0)
D = C(0, 131, 0)
L = C(123, 255, 48)
M = C(91, 49, 91)
R = C(230, 0, 0)
P = C(255, 133, 132)


def basket(flip=False, knot=False, dark=D, light=L, line=K):
    """Tallos trenzados de a pares en dos hileras de 8 px, desfasadas entre sí (tileable)."""
    im = Image.new("RGBA", (S, S), line)
    for y in range(S):
        for x in range(S):
            row = y // 8
            phase = 2 * math.pi * (x + (4 if row else 0) + (8 if flip else 0)) / S
            best, color = -9.0, line
            for sign in (1, -1):
                d = (y % 8) + 0.5 - (4 + sign * 2.1 * math.sin(phase))
                if abs(d) > 2.25:
                    continue
                z = sign * math.cos(phase)  # la hebra que va por encima se alterna en cada cruce
                if z > best:
                    best = z
                    if abs(d) > 1.55:
                        color = line
                    elif d < -0.35 and (x + row * 2) % 4:
                        color = light
                    else:
                        color = dark
            im.putpixel((x, y), color)
    if knot:  # brote que rompe la repetición
        for x, y, c in [(10, 2, line), (11, 2, line), (12, 2, line), (9, 3, line), (10, 3, light),
                        (11, 3, light), (12, 3, dark), (13, 3, line), (9, 4, line), (10, 4, light),
                        (11, 4, dark), (12, 4, dark), (13, 4, line), (10, 5, line), (11, 5, line),
                        (12, 5, line)]:
            im.putpixel((x, y), c)
    return im


def rotated(im, turns):
    return im.rotate(-90 * turns, expand=False) if turns else im.copy()


def add_vein(im):
    """Vena roja que late bajo el tejido: entra y sale por los bordes a la misma altura."""
    out = im.copy()
    path = [(0, 9), (1, 9), (2, 8), (3, 8), (4, 7), (5, 7), (6, 8), (7, 9), (8, 9), (9, 8),
            (10, 7), (11, 6), (12, 7), (13, 8), (14, 8), (15, 9)]
    for x, y in path:
        out.putpixel((x, y - 1), K)
        out.putpixel((x, y + 1), K)
    for i, (x, y) in enumerate(path):
        out.putpixel((x, y), P if i % 5 == 1 else R)
    return out


def edge_top(base):
    """Tallo grueso sobre el borde superior, con hojitas y sombra que cae sobre el relleno."""
    im = base.copy()
    for x in range(S):
        bump = 1 if x % 8 in (2, 3, 4) else 0
        for y in range(0, 5 + bump):
            if y == 4 + bump:
                c = K
            elif y == 0:
                c = L if (x + 1) % 7 else D
            elif y == 1:
                c = L if x % 8 in (0, 1, 5) else D
            else:
                c = D
            im.putpixel((x, y), c)
        if (x + bump) % 2 == 0:
            im.putpixel((x, 5 + bump), K)
    for x, y in [(3, 1), (4, 2), (11, 1), (12, 2)]:
        im.putpixel((x, y), K)
    return im


def corner(base):
    """Esquina arriba-izquierda: combina los dos bordes y redondea la punta."""
    im = edge_top(base)
    side = rotated(edge_top(base), 3)
    for y in range(S):
        for x in range(6):
            if x <= 4 or y >= 6:
                im.putpixel((x, y), side.getpixel((x, y)))
    for x in range(5):
        for y in range(5):
            if x + y <= 3:
                im.putpixel((x, y), K if x + y == 3 else D)
            elif x + y == 4:
                im.putpixel((x, y), L)
    im.putpixel((0, 0), K)
    return im


def background():
    """Trenza apagada en violeta: se lee como fondo y no compite con los sólidos."""
    return basket(flip=True, dark=K, light=M, line=K)


def hang():
    im = Image.new("RGBA", (S, S), T)
    for y in range(S):
        cx = 7.5 + 1.6 * math.sin(2 * math.pi * y / S)
        left = round(cx - 1.5)
        for i in range(-1, 4):
            x = left + i
            im.putpixel((x, y), K if i in (-1, 3) else (L if i == 0 else D))
    leaf = [(10, 3, K), (11, 3, K), (12, 3, K), (10, 4, L), (11, 4, D), (12, 4, D), (13, 4, K),
            (10, 5, K), (11, 5, K), (12, 5, K), (5, 11, K), (4, 11, K), (3, 11, K), (5, 12, D),
            (4, 12, D), (3, 12, L), (2, 12, K), (5, 13, K), (4, 13, K), (3, 13, K)]
    for x, y, c in leaf:
        im.putpixel((x, y), c)
    return im


def hang_end():
    im = Image.new("RGBA", (S, S), T)
    widths = [3, 3, 3, 3, 3, 3, 2, 2, 2, 1, 1, 1]
    for y, w in enumerate(widths):
        cx = 7.5 + 1.6 * math.sin(2 * math.pi * y / S)
        left = round(cx - w / 2)
        im.putpixel((left - 1, y), K)
        for i in range(w):
            im.putpixel((left + i, y), L if i == 0 else D)
        im.putpixel((left + w, y), K)
    im.putpixel((round(7.5 + 1.6 * math.sin(2 * math.pi * 12 / S)), 12), K)
    return im


def build():
    fill = basket()
    alt = basket(knot=True)
    # Los bordes se rotan sueltos y recién ahí se apoyan sobre el relleno, que no rota
    empty = Image.new("RGBA", (S, S), T)
    edge = edge_top(empty)
    tip = corner(empty)

    def over(band, turns):
        im = fill.copy()
        im.alpha_composite(rotated(band, turns))
        return im

    return {
        "floor_vine": fill,
        "floor_vine_alt": alt,
        "floor_vine_vein": add_vein(fill),
        "floor_vine_top": over(edge, 0),
        "floor_vine_right": over(edge, 1),
        "floor_vine_bottom": over(edge, 2),
        "floor_vine_left": over(edge, 3),
        "floor_vine_tl": over(tip, 0),
        "floor_vine_tr": over(tip, 1),
        "floor_vine_br": over(tip, 2),
        "floor_vine_bl": over(tip, 3),
        "bg_vine": background(),
        "deco_vine_hang": hang(),
        "deco_vine_hang_end": hang_end(),
    }


def preview(t, path):
    """Una masa de tiles con hueco, fondo y colgantes, para ver cómo empalman."""
    plan = [
        "BBBBBBBBBBBBBBBBBBBB",
        "BaqqqqqqqqqqqqqqqqsB",
        "BwffvfgffvffgffvffeB",
        "BzxxxxcffffgfdxxxxuB",
        "BBBHBBwfgffvfeBBHBBB",
        "BBBNBBzxxxxxxuBBHBBB",
        "BBBBBBBBHBBBBBBBNBBB",
        "BBBBBBBBNBBBBBBBBBBB",
        "qqqqqqsBBBBBBaqqqqqq",
        "fgfvffeBBBBBBwffgfvf",
        "ffffgfmqqqqqqnfvffff",
        "fvffffgfvffffgffffgf",
    ]
    names = {"B": "bg_vine", "a": "floor_vine_tl", "s": "floor_vine_tr", "z": "floor_vine_bl",
             "u": "floor_vine_br", "q": "floor_vine_top", "x": "floor_vine_bottom",
             "w": "floor_vine_left", "e": "floor_vine_right", "f": "floor_vine",
             "g": "floor_vine_alt", "v": "floor_vine_vein", "c": "floor_vine", "d": "floor_vine",
             "m": "floor_vine", "n": "floor_vine"}
    w, h = len(plan[0]), len(plan)
    im = Image.new("RGBA", (w * S, h * S), K)
    for j, row in enumerate(plan):
        for i, ch in enumerate(row):
            if ch in "HN":
                im.paste(t["bg_vine"], (i * S, j * S))
                over = t["deco_vine_hang" if ch == "H" else "deco_vine_hang_end"]
                im.alpha_composite(over, (i * S, j * S))
            else:
                im.paste(t[names[ch]], (i * S, j * S))
    im.resize((w * S * 3, h * S * 3), Image.NEAREST).save(path)


if __name__ == "__main__":
    tiles = build()
    for name, tile in tiles.items():
        tile.save(OUT / f"{name}_spr_0.png")
    if len(sys.argv) > 1:
        preview(tiles, sys.argv[1])
