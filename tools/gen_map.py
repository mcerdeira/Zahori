#!/usr/bin/env python3
"""Genera un mapa (PNG) de las rooms y a dónde lleva cada puerta. Uso personal, no va en el juego.

Lee los `scenes/rooms/levelN.tscn`, resuelve el `target_scene` de cada puerta (uid o ruta) y dibuja
cada room como un cuadradito con su número. Si una puerta apunta a un número en vez de a una escena,
la room destino se dibuja igual pero en amarillo (todavía no existe la escena).
Marca en la esquina cada altar con su número: H2 = altar de pista 2, P1 = altar de puzzle 1.

Uso: python3 tools/gen_map.py [salida.png]   (por defecto tools/map.png)
"""

import re
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ROOMS_DIR = ROOT / "scenes" / "rooms"
FONT_PATH = ROOT / "fonts" / "prstartk.ttf"

BOX = 64  # px, lado de cada room
GAP_X = 56  # px, separación horizontal entre columnas
GAP_Y = 40  # px, separación vertical entre filas
MARGIN = 40  # px

COL_BG = (34, 32, 42)
COL_ROOM = (90, 160, 210)
COL_MISSING = (240, 200, 40)
COL_BORDER = (240, 240, 240)
COL_TEXT = (20, 20, 28)
COL_EDGE = (200, 200, 210)
COL_START = (120, 220, 120)

LEVEL_RE = re.compile(r"level(\d+)\.tscn$")


def parse_scene(path: Path):
    """Devuelve (uid, puertas, altares) de un .tscn. Puertas: lista de target_scene. Altares: lista de kinds."""
    text = path.read_text(encoding="utf-8")
    header = re.match(r'\[gd_scene[^\]]*uid="([^"]+)"', text)
    uid = header.group(1) if header else None

    ext = {}  # id -> ruta
    for m in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text):
        ext[m.group(2)] = m.group(1)

    doors, altars = [], []
    # Separar en secciones [ ... ] con sus propiedades.
    sections = re.split(r"\n(?=\[)", text)
    for sec in sections:
        if not sec.startswith("[node"):
            continue
        inst = re.search(r'instance=ExtResource\("([^"]+)"\)', sec.split("\n", 1)[0])
        inst_path = ext.get(inst.group(1), "") if inst else ""
        target = re.search(r'^target_scene = "([^"]*)"', sec, re.M)
        if inst_path.endswith("door.tscn") or target:
            doors.append(target.group(1) if target else "")
        elif inst_path.endswith("altar.tscn"):
            kind = re.search(r"^kind = (\d+)", sec, re.M)
            number = re.search(r"^altar_number = (\d+)", sec, re.M)
            # (kind, número): kind 0 = PUZZLE, 1 = HINT; altar_number por defecto es 1.
            altars.append((int(kind.group(1)) if kind else 0, int(number.group(1)) if number else 1))
    return uid, doors, altars


def collect():
    """Arma el grafo: rooms {num: {...}} y aristas dirigidas (origen, destino)."""
    uid_to_path = {}
    for f in ROOT.rglob("*.tscn"):
        if ".godot" in f.parts:
            continue
        m = re.match(r'\[gd_scene[^\]]*uid="([^"]+)"', f.read_text(encoding="utf-8").split("\n", 1)[0])
        if m:
            uid_to_path[m.group(1)] = f

    rooms, edges = {}, []
    for f in sorted(ROOMS_DIR.glob("level*.tscn")):
        m = LEVEL_RE.search(f.name)
        if not m:
            continue  # rooms internas del laberinto de puertas (level181a, ...)
        num = int(m.group(1))
        _, doors, altars = parse_scene(f)
        rooms[num] = {"missing": False, "altars": altars, "doors": doors}

    for num, room in list(rooms.items()):
        for target in room["doors"]:
            if not target:
                print(f"aviso: level{num} tiene una puerta sin target_scene")
                continue
            if target == "-1":
                continue  # puerta del laberinto (la resuelve DoorMaze en el juego)
            if target.isdigit():
                dest = int(target)
            else:
                if target.startswith("uid://"):
                    dest_path = uid_to_path.get(target)
                else:
                    dest_path = ROOT / target.removeprefix("res://")
                m = LEVEL_RE.search(dest_path.name) if dest_path else None
                if not m:
                    print(f"aviso: level{num} tiene una puerta a algo que no es una room: {target}")
                    continue
                dest = int(m.group(1))
            if dest not in rooms:
                rooms[dest] = {"missing": True, "altars": [], "doors": []}
            edges.append((num, dest))
    return rooms, edges


def layout(rooms, edges):
    """Columnas por distancia (BFS) desde la room más baja; las que no se alcanzan van al final."""
    adj = {n: [] for n in rooms}
    for a, b in edges:
        adj[a].append(b)
        adj[b].append(a)
    depth = {}
    for start in sorted(rooms):
        if start in depth:
            continue
        base = max(depth.values(), default=-1) + 1
        depth[start] = base
        q = deque([start])
        while q:
            n = q.popleft()
            for m in sorted(adj[n]):
                if m not in depth:
                    depth[m] = depth[n] + 1
                    q.append(m)
    cols = {}
    for n in sorted(rooms, key=lambda n: (depth[n], n)):
        cols.setdefault(depth[n], []).append(n)
    # Ordenar cada columna según el promedio de fila de sus vecinos en la columna anterior
    # (baricentro), para que se crucen menos las líneas.
    for d in sorted(cols)[1:]:
        prev = cols.get(d - 1, [])
        def bary(n):
            ys = [prev.index(m) for m in adj[n] if m in prev]
            return (sum(ys) / len(ys) if ys else len(prev), n)
        cols[d].sort(key=bary)
    rows = max(len(c) for c in cols.values())
    pos = {}
    for d, col in cols.items():
        offset = (rows - len(col)) / 2  # centrar la columna verticalmente
        for i, n in enumerate(col):
            x = MARGIN + d * (BOX + GAP_X)
            y = MARGIN + (i + offset) * (BOX + GAP_Y)
            pos[n] = (x, y)
    w = MARGIN * 2 + len(cols) * BOX + (len(cols) - 1) * GAP_X
    h = MARGIN * 2 + rows * BOX + (rows - 1) * GAP_Y + 24  # + leyenda
    return pos, int(w), int(h)


def center(p):
    return (p[0] + BOX / 2, p[1] + BOX / 2)


def bezier(a, ctrl, b, steps=24):
    return [
        ((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * ctrl[0] + t * t * b[0],
         (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * ctrl[1] + t * t * b[1])
        for t in (i / steps for i in range(steps + 1))
    ]


def hits_box(points, boxes):
    for bx, by in boxes:
        for x, y in points:
            if bx - 4 < x < bx + BOX + 4 and by - 4 < y < by + BOX + 4:
                return True
    return False


def edge_path(a, b, pos):
    """Recta si no pisa otras rooms; si no, una curva que se va abriendo hasta esquivarlas."""
    pa, pb = center(pos[a]), center(pos[b])
    others = [p for n, p in pos.items() if n not in (a, b)]
    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    nx, ny = -dy / length, dx / length
    mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
    for k in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
        off = k * (BOX * 0.6)
        pts = bezier(pa, (mid[0] + nx * off, mid[1] + ny * off), pb)
        if not hits_box(pts, others):
            return pts
    return bezier(pa, mid, pb)


def clip_to_box(pts, box_pos, from_end):
    """Corta la polilínea donde entra al cuadrado (para que la flecha quede en el borde)."""
    bx, by = box_pos
    seq = list(reversed(pts)) if from_end else pts
    for i, (x, y) in enumerate(seq):
        if not (bx <= x <= bx + BOX and by <= y <= by + BOX):
            seq = seq[i:]
            break
    return list(reversed(seq)) if from_end else seq


def draw_arrow(d, pts):
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    size = 9
    left = (x1 - ux * size - uy * size * 0.6, y1 - uy * size + ux * size * 0.6)
    right = (x1 - ux * size + uy * size * 0.6, y1 - uy * size - ux * size * 0.6)
    d.polygon([(x1, y1), left, right], fill=COL_EDGE)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools" / "map.png"
    rooms, edges = collect()
    if not rooms:
        sys.exit("no encontré rooms en scenes/rooms/")
    pos, w, h = layout(rooms, edges)

    legend = "HN: hint N  PN: puzzle N  amarillo: sin escena  borde verde: inicio  flecha: puerta de ida"
    w = max(w, MARGIN * 2 + len(legend) * 8)  # que entre la leyenda (8 px por caracter)
    img = Image.new("RGB", (w, h), COL_BG)
    d = ImageDraw.Draw(img)
    font_big = ImageFont.truetype(str(FONT_PATH), 16)
    font_small = ImageFont.truetype(str(FONT_PATH), 8)

    # Aristas: una sola línea por par; flecha sólo si la puerta es de ida.
    pairs = set(edges)
    drawn = set()
    for a, b in edges:
        key = tuple(sorted((a, b)))
        if key in drawn or a == b:
            continue
        drawn.add(key)
        both = (b, a) in pairs
        pts = edge_path(a, b, pos)
        pts = clip_to_box(clip_to_box(pts, pos[a], False), pos[b], True)
        d.line(pts, fill=COL_EDGE, width=2, joint="curve")
        if not both:
            draw_arrow(d, pts)

    start = min(n for n, r in rooms.items() if not r["missing"])
    for n, (x, y) in pos.items():
        r = rooms[n]
        fill = COL_MISSING if r["missing"] else COL_ROOM
        border = COL_START if n == start else COL_BORDER
        d.rectangle([x, y, x + BOX, y + BOX], fill=fill, outline=border, width=3)
        d.text((x + BOX / 2, y + BOX / 2), str(n), font=font_big, fill=COL_TEXT, anchor="mm")
        # Un tag por altar (H2, P1...), primero las pistas; uno por línea si no entran.
        tags = [("H" if k == 1 else "P") + str(num) for k, num in sorted(r["altars"], key=lambda a: (-a[0], a[1]))]
        lines, line = [], ""
        for t in tags:
            cand = f"{line} {t}" if line else t
            if len(cand) * 8 > BOX - 8 and line:
                lines.append(line)
                cand = t
            line = cand
        if line:
            lines.append(line)
        for i, text in enumerate(lines):
            d.text((x + BOX - 5, y + 6 + i * 10), text, font=font_small, fill=COL_TEXT, anchor="rt")

    d.text((MARGIN, h - MARGIN / 2 - 8), legend.upper(), font=font_small, fill=COL_EDGE)

    img.save(out)
    print(f"mapa guardado en {out} ({len(rooms)} rooms, {len(drawn)} conexiones)")


if __name__ == "__main__":
    main()
