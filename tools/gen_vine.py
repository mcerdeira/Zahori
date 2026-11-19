"""Genera los sprites 16x16 de la enredadera enemiga (paleta gameboy-color-type1) en sprites/.

Todas las piezas se dibujan en una sola orientación y el juego las rota de a 90°:
- vine_stem: tramo recto que conecta IZQUIERDA y DERECHA.
- vine_corner: curva que conecta IZQUIERDA y ABAJO.
- vine_root: nudo de raíces del que nace, con el tallo saliendo a la DERECHA.
- vine_head_spr_0..3: la cabeza (planta carnívora) mirando a la DERECHA, con el tallo entrando
  por la IZQUIERDA; los frames abren y cierran las fauces.
- vine_sprig_spr_0..1: ramita decorativa que nace del centro de la celda (borde izquierdo del
  sprite) y se enrula hacia la derecha; dos frames de vaivén.
El tallo mide 6 px (filas 5..10) para que encaje igual en las cuatro rotaciones.

Uso: python3 tools/gen_vine.py
"""
import math
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
R = C(230, 0, 0)
P = C(255, 133, 132)
W = C(255, 255, 255)
M = C(91, 49, 91)


def new():
    return Image.new("RGBA", (S, S), T)


def put(im, x, y, c):
    if 0 <= x < S and 0 <= y < S:
        im.putpixel((x, y), c)


def stem_fill(x, row):
    """Color del relleno del tallo (filas 0..3 del relleno): soga retorcida con rayas diagonales."""
    if row == 0 and x % 8 in (1, 2):
        return L
    if row == 1 and x % 8 in (3, 4):
        return L
    return D


def stem():
    im = new()
    for x in range(S):
        put(im, x, 5, K)
        put(im, x, 10, K)
        for r in range(4):
            put(im, x, 6 + r, stem_fill(x, r))
    # Espinas: negras con la punta roja
    put(im, 5, 4, K); put(im, 5, 3, R)
    put(im, 12, 11, K); put(im, 12, 12, R)
    return im


def corner():
    """Cuarto de anillo con centro en la esquina inferior izquierda: radios 5..11 = el tallo."""
    im = new()
    for y in range(S):
        for x in range(S):
            dx, dy = x + 0.5, 16 - (y + 0.5)
            d = math.hypot(dx, dy)
            if d < 5 or d >= 11:
                continue
            if d < 6 or d >= 10:
                put(im, x, y, K)
                continue
            arc = int(math.atan2(dy, dx) * 9)  # largo de arco aproximado
            row = int(10 - d)  # 0 = borde exterior (como la fila de arriba del tramo recto)
            put(im, x, y, stem_fill(arc, row))
    put(im, 9, 7, K); put(im, 10, 6, R)
    return im


def root():
    im = new()
    # Tallo hacia la derecha
    for x in range(8, S):
        put(im, x, 5, K)
        put(im, x, 10, K)
        for r in range(4):
            put(im, x, 6 + r, stem_fill(x, r))
    # Nudo: bulbo oscuro con vetas
    cx, cy = 6.5, 8.5
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 1.15)
            if d < 5.2:
                put(im, x, y, K if d >= 4.2 else (M if (x + y) % 3 else D))
    # Raicillas
    for x, y in [(1, 12), (0, 13), (3, 13), (3, 14), (9, 13), (10, 14), (2, 3), (1, 2), (8, 3), (9, 2)]:
        put(im, x, y, K)
    put(im, 5, 7, L); put(im, 6, 6, L)
    return im


def head(open_deg):
    im = new()
    # Tallo entrando por la izquierda
    for x in range(0, 5):
        put(im, x, 5, K)
        put(im, x, 10, K)
        for r in range(4):
            put(im, x, 6 + r, stem_fill(x, r))
    cx, cy, rad = 9.0, 8.0, 6.6
    half = math.radians(open_deg) / 2
    for y in range(S):
        for x in range(S):
            px, py = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(px, py)
            if d >= rad:
                continue
            ang = abs(math.atan2(py, px))  # 0 = hacia la derecha (la boca)
            if ang < half:
                # Interior de la boca: rojo, con dientes blancos sobre el borde de cada fauce
                put(im, x, y, W if ang > half - 0.28 and d > 2.5 and (x % 2 == 0) else R)
                if d < 2.0:
                    put(im, x, y, K)  # garganta
                continue
            if d >= rad - 1.1 or (half > 0 and ang < half + 0.22):
                put(im, x, y, K)  # contorno y labios
            else:
                put(im, x, y, L if (py < -2.5 and px < 1) else D)
    # Cilios de las fauces (como una venus atrapamoscas): pinchos radiales cerca de la boca
    for side in (-1, 1):
        for extra in (0.25, 0.75, 1.3):
            a = side * (half + extra)
            for r, col in ((rad - 0.2, K), (rad + 0.9, K if extra > 1 else R)):
                put(im, int(cx + math.cos(a) * r), int(cy + math.sin(a) * r), col)
    if open_deg == 0:
        for x in range(10, 16):
            put(im, x, 8, K)  # boca cerrada: una línea
        for x in (11, 13):
            put(im, x, 9, W)  # colmillos asomando
    # Ojo: rojo con brillo, arriba
    put(im, 7, 4, R); put(im, 8, 4, R); put(im, 7, 5, R); put(im, 8, 5, K); put(im, 7, 4, P)
    # Espinas en la nuca
    put(im, 4, 3, K); put(im, 3, 2, R)
    put(im, 5, 13, K); put(im, 4, 14, R)
    return im


SPRIG = [
    # 0123456789012345
    "................",
    "................",
    "................",
    "...........KKK..",
    "..........KDDLK.",
    "......KK..KDKKDK",
    ".....KLLK.KDK.KK",
    "KKK.KLLDK.KDK...",
    "DDDKKKDDKKDDK...",
    "DDDDDDKKDDDK....",
    "KKKKKKKKKKK.....",
    "................",
    "................",
    "................",
    "................",
    "................",
]
COLORS = {".": T, "K": K, "D": D, "L": L, "R": R, "P": P, "W": W, "M": M}


def from_ascii(rows):
    im = new()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            put(im, x, y, COLORS[ch])
    return im


def save(im, name):
    im.save(OUT / f"{name}.png")
    print(f"sprites/{name}.png")


save(stem(), "vine_stem_spr_0")
save(corner(), "vine_corner_spr_0")
save(root(), "vine_root_spr_0")
for i, deg in enumerate([0, 40, 80, 40]):
    save(head(deg), f"vine_head_spr_{i}")
sprig = from_ascii(SPRIG)
save(sprig, "vine_sprig_spr_0")
# Segundo frame: la punta enrulada un pixel más arriba (vaivén)
sway = new()
sway.paste(sprig.crop((0, 0, 9, S)), (0, 0))
sway.paste(sprig.crop((9, 1, S, S)), (9, 0))
save(sway, "vine_sprig_spr_1")
