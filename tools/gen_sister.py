"""Genera el sprite de la hermana muerta (32x32, paleta gameboy-color-type1) en sprites/.

Mismo estilo y colores que el player (cabeza blanca, túnica roja), pero colgando de la
pared con los brazos en alto, la cabeza caída sobre el pecho y los ojos cerrados,
atada por enredaderas en las muñecas, el pecho y los tobillos.
- sister_spr_0: con la vara zahorí (horquilla en Y) enganchada en la enredadera.
- sister_norod_spr_0: igual pero sin la vara (después de que el player la agarra).

Uso: python3 tools/gen_sister.py
"""
from pathlib import Path

from PIL import Image

S = 32
OUT = Path(__file__).resolve().parent.parent / "sprites"


def C(*a):
    return a + (255,)


T = (0, 0, 0, 0)
A = C(227, 230, 255)  # piel/cabeza (igual que el player)
B = C(0, 0, 0)
R = C(230, 0, 0)  # túnica
G = C(0, 131, 0)
L = C(123, 255, 48)
W1 = C(131, 49, 0)  # vara: madera oscura
W2 = C(165, 107, 49)
W3 = C(255, 173, 99)
SPARK = C(255, 255, 255)


def line(p0, p1):
    """Puntos enteros de una recta (Bresenham)."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    pts = []
    while True:
        pts.append((x0, y0))
        if (x0, y0) == (x1, y1):
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def polyline(*pts):
    out = []
    for a, b in zip(pts, pts[1:]):
        out += line(a, b)
    return out


def draw_figure(px):
    # Túnica, con los hombros un poco más anchos
    for y in range(13, 18):
        for x in range(13, 18):
            px[(x, y)] = R
    for x in (12, 18):
        px[(x, 13)] = R
    # Brazos en alto a 45°, de 1 px, hasta las manos atadas arriba
    for p in [(11, 12), (10, 11), (9, 10), (8, 9), (7, 8), (6, 7), (6, 6)]:
        px[p] = A
    for p in [(19, 12), (20, 11), (21, 10), (22, 9), (23, 8), (24, 7), (24, 6)]:
        px[p] = A
    # Piernas colgando, con las puntas de los pies caídas
    for y in range(18, 22):
        for x in (13, 14, 16, 17):
            px[(x, y)] = A
    px[(13, 22)] = A
    px[(17, 22)] = A
    # Cabeza caída e inclinada hacia la derecha
    for y, x0, x1 in [(8, 12, 16), (9, 12, 18), (10, 12, 18), (11, 12, 18), (12, 14, 18)]:
        for x in range(x0, x1 + 1):
            px[(x, y)] = A
    # Ojos cerrados, bajos (mirando al piso)
    px[(15, 11)] = B
    px[(17, 11)] = B


def vine(px, pts):
    """Tallo de 1 px con brillos salteados; el contorno negro se agrega al final."""
    for x, y in pts:
        px[(x, y)] = L if (x * 3 + y) % 7 < 2 else G


def leaf(px, x, y, flip=False):
    d = -1 if flip else 1
    px[(x, y)] = G
    px[(x + d, y - 1)] = L
    px[(x + 2 * d, y - 1)] = G


def draw_vines(px):
    # Muñecas: rama que cruza arriba de la cabeza y da una vuelta en cada mano
    vine(px, polyline((0, 4), (6, 6), (11, 3), (19, 3), (24, 6), (31, 4)))
    vine(px, [(5, 7), (7, 6), (23, 6), (25, 7)])
    # Pecho: cruza la túnica en diagonal
    vine(px, polyline((0, 20), (8, 17), (13, 16), (17, 15), (23, 13), (31, 11)))
    # Tobillos
    vine(px, polyline((2, 31), (8, 26), (13, 22), (17, 22), (23, 26), (29, 31)))
    leaf(px, 3, 4)
    leaf(px, 28, 4, True)
    leaf(px, 4, 18)
    leaf(px, 27, 11, True)
    leaf(px, 8, 25)
    leaf(px, 22, 25, True)


def draw_rod(px):
    """Vara zahorí: horquilla en Y colgada de la enredadera, al lado de la mano derecha."""
    for p in [(25, 8), (26, 9), (28, 8), (27, 9), (26, 10), (26, 11), (26, 12), (26, 13), (26, 14)]:
        px[p] = W2
    px[(26, 14)] = W1
    px[(26, 13)] = W1
    px[(25, 8)] = W3
    px[(28, 8)] = W3
    px[(29, 7)] = SPARK


def outline(px, keep):
    """Contorno negro alrededor de las enredaderas y la vara (sin pisar a la hermana)."""
    out = dict(px)
    for (x, y), c in px.items():
        if c not in keep:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if 0 <= q[0] < S and 0 <= q[1] < S and q not in px:  # sólo hacia afuera
                out[q] = B
    return out


def render(with_rod):
    px = {}
    draw_figure(px)
    draw_vines(px)
    if with_rod:
        draw_rod(px)
    px = outline(px, {G, L, W1, W2, W3, SPARK, A, R})
    im = Image.new("RGBA", (S, S), T)
    for (x, y), c in px.items():
        if 0 <= x < S and 0 <= y < S:
            im.putpixel((x, y), c)
    return im


for name, rod in (("sister_spr_0", True), ("sister_norod_spr_0", False)):
    render(rod).save(OUT / f"{name}.png")
    print(f"sprites/{name}.png")
