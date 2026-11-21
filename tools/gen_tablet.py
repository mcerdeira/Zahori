"""Genera los sprites de la tableta de piedra coleccionable (paleta gameboy-color-type1).

- tablet_front_spr_0 (60x80): cara con el relieve de un pozo de agua rodeado por dos
  enredaderas que suben desde las raíces y se cruzan arriba en espirales.
- tablet_back_spr_0 (60x80): reverso con filas de glifos tallados (ilegibles a propósito).
- tablet_side_spr_0 (16x16): el canto de la piedra (vetas horizontales), se repite.
- tablet_piece_spr_0..1 (16x16): el fragmento suelto como aparece en el mundo; el
  frame 1 tiene un destello.

Las caras se cortan en 4 pedazos en el juego (scenes/tablet_mesh.gd); acá se dibujan
enteras. El reverso se ve espejado al girar la tableta, por eso los glifos no importan.

Uso: python3 tools/gen_tablet.py
"""
import math
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "sprites"
W, H = 60, 80


def C(*a):
    return a + (255,)


T = (0, 0, 0, 0)
K = C(0, 0, 0)
D = C(82, 82, 82)      # surco / sombra
M = C(148, 148, 148)   # piedra
L = C(165, 165, 165)   # piedra clara / labio del tallado
WH = C(255, 255, 255)
P = C(83, 82, 140)     # sombra fría
G1 = C(0, 131, 0)
G2 = C(123, 255, 48)
TEAL = C(0, 132, 134)
B1 = C(1, 99, 198)
B2 = C(100, 165, 255)


class Canvas:
    def __init__(self, w, h, fill=T):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), fill)
        self.px = self.im.load()

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return None

    def save(self, name):
        self.im.save(OUT / f"{name}.png")


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


def catmull(pts, samples=8):
    """Curva suave que pasa por los puntos de control; devuelve puntos enteros conectados."""
    pts = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((round(x), round(y)))
    out.append(tuple(pts[-2]))
    joined = []
    for a, b in zip(out, out[1:]):
        seg = line(a, b)
        joined += seg if not joined else seg[1:]
    return joined


def stone(cv, rng, speck=0.07):
    """Piedra base con motas claras y oscuras en grupitos."""
    for y in range(cv.h):
        for x in range(cv.w):
            cv.put(x, y, M)
    for _ in range(int(cv.w * cv.h * speck)):
        x, y = rng.randrange(cv.w), rng.randrange(cv.h)
        c = L if rng.random() < 0.6 else D
        cv.put(x, y, c)
        if rng.random() < 0.3:
            cv.put(x + 1, y, c)


def carve(cv, pts):
    """Tallado: surco oscuro con labio claro abajo a la derecha (luz de arriba a la izquierda)."""
    s = set(pts)
    for x, y in pts:
        cv.put(x, y, D)
    for x, y in pts:
        for dx, dy in ((1, 1), (0, 1)):
            q = (x + dx, y + dy)
            if q not in s and cv.get(*q) in (M, L, D) and cv.get(*q) != D:
                cv.put(*q, L)


def frame(cv):
    """Marco tallado alrededor de la cara, a 3 px del borde."""
    pts = []
    x0, y0, x1, y1 = 3, 3, cv.w - 4, cv.h - 4
    for x in range(x0, x1 + 1):
        pts += [(x, y0), (x, y1)]
    for y in range(y0, y1 + 1):
        pts += [(x0, y), (x1, y)]
    carve(cv, pts)


def relief(cv, pts, core, light):
    """Trazo en relieve de 2 px: núcleo, brillo arriba-izquierda y sombra abajo-derecha."""
    s = set()
    for x, y in pts:
        s.add((x, y))
        s.add((x + 1, y))
    for x, y in s:
        cv.put(x, y, core)
    for x, y in s:
        if (x - 1, y) not in s:
            cv.put(x, y, light)
    for x, y in s:
        for q in ((x + 1, y + 1), (x, y + 1), (x + 1, y)):
            if q not in s and cv.get(*q) in (M, L):
                cv.put(*q, D)


def leaf(cv, x, y, side):
    """Hoja chiquita en forma de lágrima hacia `side` (-1 izquierda, 1 derecha)."""
    for dx, dy, c in ((1, 0, G1), (2, -1, G2), (2, 0, G1), (3, -1, G2), (3, -2, G2), (4, -2, G1)):
        cv.put(x + dx * side, y + dy, c)
    cv.put(x + 2 * side, y + 1, D)
    cv.put(x + 3 * side, y, D)


def spiral(cx, cy, r0, turns, direction):
    pts = []
    n = int(turns * 40)
    for i in range(n + 1):
        t = i / n
        a = direction * t * turns * 2 * math.pi
        r = r0 * (1 - t * 0.85)
        pts.append((round(cx + math.cos(a) * r), round(cy + math.sin(a) * r)))
    out = []
    for a, b in zip(pts, pts[1:]):
        seg = line(a, b)
        out += seg if not out else seg[1:]
    return out


def front():
    rng = random.Random(41)
    cv = Canvas(W, H)
    stone(cv, rng)
    frame(cv)

    # El pozo: anillo tallado con agua adentro, ondas concéntricas y un brillo.
    cx, cy, r = 30, 37, 10
    for y in range(cy - r - 2, cy + r + 3):
        for x in range(cx - r - 2, cx + r + 3):
            d = math.hypot(x - cx, y - cy)
            if d <= r - 0.5:
                cv.put(x, y, B1)
            elif d <= r + 0.7:
                cv.put(x, y, D)
            elif d <= r + 1.6 and (x - cx) + (y - cy) > 0:
                cv.put(x, y, L)
            elif d <= r + 1.6:
                cv.put(x, y, P)
    for rr, arc in ((3, (0.2, 2.6)), (6, (3.4, 5.9)), (8, (0.6, 2.2))):
        for i in range(60):
            a = arc[0] + (arc[1] - arc[0]) * i / 59
            cv.put(round(cx + math.cos(a) * rr), round(cy + math.sin(a) * rr * 0.8), B2)
    cv.put(cx - 4, cy - 5, WH)
    cv.put(cx - 3, cy - 5, B2)

    # Raíces que se hunden en el marco de abajo
    for pts in ([(22, 76), (19, 79)], [(26, 76), (27, 79)], [(36, 76), (35, 79)], [(40, 76), (43, 79)]):
        for p in line(*pts):
            cv.put(*p, TEAL)

    # Dos enredaderas que rodean el pozo y se cruzan arriba
    stem_a = catmull([(24, 76), (21, 68), (16, 58), (15, 47), (16, 36), (17, 26), (22, 18), (30, 13), (37, 10)])
    stem_b = catmull([(37, 76), (39, 68), (43, 58), (44, 47), (43, 36), (41, 26), (36, 18), (28, 13), (21, 10)])
    relief(cv, stem_a, G1, G2)
    relief(cv, stem_b, G1, G2)
    relief(cv, spiral(39, 7, 4, 1.2, -1), G1, G2)
    relief(cv, spiral(19, 7, 4, 1.2, 1), G1, G2)

    # Hojas alternadas a lo largo de cada tallo
    for stem, first in ((stem_a, -1), (stem_b, 1)):
        side = first
        for i in range(6, len(stem) - 8, 9):
            x, y = stem[i]
            leaf(cv, x + (2 if side > 0 else -1), y, side)
            side = -side

    # Zarcillos finos hacia el pozo
    for pts in (spiral(21, 50, 3, 1.0, 1), spiral(39, 50, 3, 1.0, -1)):
        for p in pts:
            if cv.get(*p) in (M, L, D):
                cv.put(*p, G1)
    cv.save("tablet_front_spr_0")


def glyph(cv, ox, oy, rng):
    """Un glifo inventado: 2 a 4 trazos sobre una grilla de 3x4 nodos (5x7 px)."""
    nodes = [(x, y) for x in (0, 2, 4) for y in (0, 2, 4, 6)]
    edges = []
    for a in nodes:
        for b in nodes:
            if a < b and abs(a[0] - b[0]) <= 2 and abs(a[1] - b[1]) <= 2:
                edges.append((a, b))
    start = rng.choice(nodes)
    used = []
    cur = start
    for _ in range(rng.randint(2, 4)):
        options = [e for e in edges if cur in e and e not in used]
        if not options:
            break
        e = rng.choice(options)
        used.append(e)
        cur = e[1] if e[0] == cur else e[0]
    pts = []
    for a, b in used:
        pts += line((ox + a[0], oy + a[1]), (ox + b[0], oy + b[1]))
    if rng.random() < 0.3:
        pts.append((ox + rng.choice((0, 2, 4)), oy + 8))  # punto debajo, como diacrítico
    carve(cv, pts)


def back():
    rng = random.Random(1717)
    cv = Canvas(W, H)
    stone(cv, rng, 0.035)  # menos motas: que los glifos se lean como escritura
    frame(cv)
    # Encabezado: un círculo tallado (el pozo) flanqueado por dos rayas
    cx, cy = 30, 11
    ring = [(round(cx + math.cos(a / 30 * math.pi) * 3), round(cy + math.sin(a / 30 * math.pi) * 3)) for a in range(60)]
    carve(cv, ring + [(cx, cy)])
    carve(cv, line((9, 11), (23, 11)) + line((37, 11), (50, 11)))
    # Seis filas de seis glifos
    for row in range(6):
        for col in range(6):
            glyph(cv, 9 + col * 7, 19 + row * 9, rng)
    cv.save("tablet_back_spr_0")


def side():
    rng = random.Random(5)
    cv = Canvas(16, 16)
    stone(cv, rng, 0.05)
    for y in (3, 9, 13):
        for x in range(16):
            if rng.random() < 0.8:
                cv.put(x, y, D if y != 9 else L)
    cv.save("tablet_side_spr_0")


def piece():
    """Fragmento suelto: esquirla de piedra con un trozo de enredadera; frame 1 con destello."""
    shape = [
        "......KK........",
        ".....KLLK.......",
        "....KLLMMKK.....",
        "...KLLMMMMLK....",
        "...KLMMGGMMMK...",
        "..KLMMMGLGMMMK..",
        "..KLMMMMGGMMDK..",
        ".KLMMMMMMGMMDK..",
        ".KLMMMMMMGGMDDK.",
        ".KMMMMMMMMGMDDK.",
        "..KMMMMMMMMDDK..",
        "..KDMMMMMDDDK...",
        "...KDDMMDDDK....",
        "....KKDDDKK.....",
        "......KKK.......",
        "................",
    ]
    cmap = {".": T, "K": K, "L": L, "M": M, "D": D, "G": G1}
    for f in range(2):
        cv = Canvas(16, 16)
        for y, row in enumerate(shape):
            for x, ch in enumerate(row):
                c = cmap[ch]
                if ch == "L" and f == 0 and (x + y) % 3 == 0:
                    c = M
                cv.put(x, y, c)
        cv.put(9, 5, G2)
        if f == 1:
            for x, y in ((4, 2), (3, 2), (5, 2), (4, 1), (4, 3)):
                cv.put(x, y, WH)
            cv.put(6, 4, WH)
        cv.save(f"tablet_piece_spr_{f}")


if __name__ == "__main__":
    front()
    back()
    side()
    piece()
    print("ok")
