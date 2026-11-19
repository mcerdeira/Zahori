#!/usr/bin/env python3
"""Genera un mapa (PNG) de las rooms y a dónde lleva cada puerta. Uso personal, no va en el juego.

Lee los `scenes/rooms/levelN.tscn`, resuelve el `target_scene` de cada puerta (uid o ruta) y dibuja
cada room como un cuadradito con su número. Si una puerta apunta a un número en vez de a una escena,
la room destino se dibuja igual pero en amarillo (todavía no existe la escena).
Marca en la esquina cada altar con su número: H2 = altar de pista 2, P1 = altar de puzzle 1.
Antes de dibujar corre Godot con tools/capture_rooms.tscn, que saca una captura de cada room a
tools/room_shots/levelN.png (abre una ventana un par de segundos). Cada room se dibuja con su captura
en miniatura; si no hay (Godot falló o se pasó --no-capture), como un cuadro azul.

A la izquierda dibuja un machete con la palabra de cada altar de puzzle (puzzles/altar_XX.tres) y,
para cada pista (puzzles/hint_XX.tres), la palabra del puzzle al que apunta (su campo `puzzle`) o,
si no tiene, la primera línea del texto. Un * rojo al lado de la etiqueta marca los altares que no
están ubicados en ninguna room o que están en más de una (contando también las del laberinto).

Uso: python3 tools/gen_map.py [--no-capture] [salida.png]   (por defecto tools/map.png)
     GODOT=/ruta/al/binario si `godot` no está en el PATH.
"""

import os
import re
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ROOMS_DIR = ROOT / "scenes" / "rooms"
FONT_PATH = ROOT / "fonts" / "prstartk.ttf"
SHOTS_DIR = ROOT / "tools" / "room_shots"
PUZZLES_DIR = ROOT / "puzzles"

BOX_W = 192  # px, ancho de cada room (576 / 3)
BOX_H = 108  # px, alto de cada room (324 / 3)
GAP_X = 56  # px, separación horizontal entre columnas
GAP_Y = 40  # px, separación vertical entre filas
MARGIN = 40  # px
SIDE_W = 230  # px, ancho del machete de la izquierda
SIDE_LINE = 16  # px entre renglones del machete

COL_BG = (34, 32, 42)
COL_ROOM = (90, 160, 210)
COL_MISSING = (240, 200, 40)
COL_BORDER = (240, 240, 240)
COL_TEXT = (20, 20, 28)
COL_EDGE = (200, 200, 210)
COL_START = (120, 220, 120)
COL_LABEL_BG = (240, 240, 240)
COL_SIDE_BG = (26, 24, 33)
COL_HEADER = (255, 200, 107)
COL_NO_PUZZLE = (150, 150, 160)  # pistas que no apuntan a ningún puzzle
COL_WARN = (255, 70, 70)  # el * de altares sin ubicar o repetidos
# Un color por altar de puzzle (P1, P2, ...); las pistas toman el del puzzle al que apuntan.
# Sin amarillo, que es el de las rooms sin escena.
PUZZLE_COLORS = [
    (110, 215, 110),  # verde
    (80, 170, 255),   # azul
    (255, 140, 50),   # naranja
    (240, 90, 200),   # rosa
    (170, 120, 255),  # violeta
    (60, 215, 200),   # turquesa
    (240, 75, 75),    # rojo
    (190, 160, 110),  # marrón claro
]

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
            x = MARGIN + d * (BOX_W + GAP_X)
            y = MARGIN + (i + offset) * (BOX_H + GAP_Y)
            pos[n] = (x, y)
    w = MARGIN * 2 + len(cols) * BOX_W + (len(cols) - 1) * GAP_X
    h = MARGIN * 2 + rows * BOX_H + (rows - 1) * GAP_Y + 24  # + leyenda
    return pos, int(w), int(h)


def center(p):
    return (p[0] + BOX_W / 2, p[1] + BOX_H / 2)


def bezier(a, ctrl, b, steps=24):
    return [
        ((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * ctrl[0] + t * t * b[0],
         (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * ctrl[1] + t * t * b[1])
        for t in (i / steps for i in range(steps + 1))
    ]


def hits_box(points, boxes):
    for bx, by in boxes:
        for x, y in points:
            if bx - 4 < x < bx + BOX_W + 4 and by - 4 < y < by + BOX_H + 4:
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
        off = k * (BOX_H * 0.6)
        pts = bezier(pa, (mid[0] + nx * off, mid[1] + ny * off), pb)
        if not hits_box(pts, others):
            return pts
    return bezier(pa, mid, pb)


def clip_to_box(pts, box_pos, from_end):
    """Corta la polilínea donde entra al cuadrado (para que la flecha quede en el borde)."""
    bx, by = box_pos
    seq = list(reversed(pts)) if from_end else pts
    for i, (x, y) in enumerate(seq):
        if not (bx <= x <= bx + BOX_W and by <= y <= by + BOX_H):
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


def capture_shots():
    """Corre Godot para regenerar las capturas de las rooms. Si falla, avisa y sigue con las que haya."""
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        print("aviso: no encontré godot en el PATH (o en $GODOT); uso las capturas que ya hay")
        return
    print("capturando rooms con Godot...")
    try:
        res = subprocess.run([godot, "--path", str(ROOT), "res://tools/capture_rooms.tscn"],
                             capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        print("aviso: Godot tardó demasiado capturando; uso las capturas que ya hay")
        return
    if res.returncode != 0:
        print(f"aviso: Godot terminó con código {res.returncode}; uso las capturas que ya hay")
        print(res.stderr.strip()[-2000:])


def tres_prop(text, name):
    """Valor de una propiedad `name = ...` de un .tres (string sin comillas, o el literal tal cual)."""
    m = re.search(rf'^{name} = (?:&?"((?:[^"\\]|\\.)*)"|(.+))$', text, re.M | re.S)
    if not m:
        return None
    return m.group(1) if m.group(1) is not None else m.group(2).strip()


def load_altar_data():
    """Lee los puzzles y las pistas. Devuelve (puzzles {n: palabra}, hints {n: (puzzle o None, primera línea)})."""
    num_of = lambda f: int(re.search(r"(\d+)", f.stem).group(1))
    puzzles = {}
    for f in sorted(PUZZLES_DIR.glob("altar_*.tres"), key=num_of):
        puzzles[num_of(f)] = tres_prop(f.read_text(encoding="utf-8"), "word") or "?"
    hints = {}
    for f in sorted(PUZZLES_DIR.glob("hint_*.tres"), key=num_of):
        text = f.read_text(encoding="utf-8")
        target = tres_prop(text, "puzzle")
        target = int(target) if target and int(target) in puzzles else None
        first = (tres_prop(text, "text") or "").split("\n")[0].strip()
        hints[num_of(f)] = (target, first)
    return puzzles, hints


def count_placed_altars():
    """Cuántas veces aparece cada altar (kind, número) en todas las rooms, incluidas las del laberinto."""
    counts = {}
    for f in ROOMS_DIR.glob("level*.tscn"):
        for altar in parse_scene(f)[2]:
            counts[altar] = counts.get(altar, 0) + 1
    return counts


def puzzle_color(n):
    return PUZZLE_COLORS[(n - 1) % len(PUZZLE_COLORS)]


def altar_color(kind, n, hints):
    """Color de un altar: el de su puzzle; las pistas, el del puzzle al que apuntan (gris si ninguno)."""
    if kind == 0:
        return puzzle_color(n)
    target = hints.get(n, (None, ""))[0]
    return puzzle_color(target) if target else COL_NO_PUZZLE


def draw_chip(d, xy, kind, n, hints, font, anchor="lt"):
    """Etiqueta de un altar: puzzle = relleno de color; pista = borde de color sobre oscuro.
    Devuelve el bbox de la etiqueta."""
    text = ("H" if kind == 1 else "P") + str(n)
    col = altar_color(kind, n, hints)
    tb = d.textbbox(xy, text, font=font, anchor=anchor)
    box = [tb[0] - 3, tb[1] - 3, tb[2] + 3, tb[3] + 3]
    if kind == 0:
        d.rectangle(box, fill=col)
        d.text(xy, text, font=font, fill=COL_TEXT, anchor=anchor)
    else:
        d.rectangle(box, fill=COL_SIDE_BG, outline=col, width=2)
        d.text(xy, text, font=font, fill=col, anchor=anchor)
    return box


def main():
    args = [a for a in sys.argv[1:] if a != "--no-capture"]
    if "--no-capture" not in sys.argv[1:]:
        capture_shots()
    out = Path(args[0]) if args else ROOT / "tools" / "map.png"
    rooms, edges = collect()
    if not rooms:
        sys.exit("no encontré rooms en scenes/rooms/")
    pos, w, h = layout(rooms, edges)
    puzzles, hints = load_altar_data()
    placed = count_placed_altars()

    legend = "HN: hint N (color del puzzle al que apunta)  PN: puzzle N  amarillo: sin escena  azul: sin captura  borde verde: inicio  flecha: puerta de ida"
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
        shot = SHOTS_DIR / f"level{n}.png"
        border = COL_START if n == start else COL_BORDER
        has_shot = not r["missing"] and shot.exists()
        if has_shot:
            thumb = Image.open(shot).convert("RGB").resize((BOX_W, BOX_H), Image.LANCZOS)
            img.paste(thumb, (int(x), int(y)))
            d.rectangle([x, y, x + BOX_W, y + BOX_H], outline=border, width=3)
        else:
            fill = COL_MISSING if r["missing"] else COL_ROOM
            d.rectangle([x, y, x + BOX_W, y + BOX_H], fill=fill, outline=border, width=3)

        # Número: centrado en los cuadros de color; en una etiqueta arriba a la izquierda sobre la captura.
        if has_shot:
            label_box = d.textbbox((x + 6, y + 6), str(n), font=font_big)
            d.rectangle([label_box[0] - 3, label_box[1] - 3, label_box[2] + 3, label_box[3] + 3], fill=COL_LABEL_BG)
            d.text((x + 6, y + 6), str(n), font=font_big, fill=COL_TEXT)
        else:
            d.text((x + BOX_W / 2, y + BOX_H / 2), str(n), font=font_big, fill=COL_TEXT, anchor="mm")

        # Un tag por altar (H2, P1...), primero las pistas, arriba a la derecha.
        # Se dibujan de derecha a izquierda, así que se recorren al revés.
        tx = x + BOX_W - 6
        for k, num in reversed(sorted(r["altars"], key=lambda a: (-a[0], a[1]))):
            box = draw_chip(d, (tx, y + 7), k, num, hints, font_small, anchor="rt")
            tx = box[0] - 7

    d.text((MARGIN, h - MARGIN / 2 - 8), legend.upper(), font=font_small, fill=COL_EDGE)

    # Machete a la izquierda: se arma una imagen más ancha y se pega el mapa a la derecha.
    # Renglones: (título, None) o (texto, (kind, número)) con su etiqueta de color adelante.
    sheet = [("PUZZLES", None)]
    sheet += [(word, (0, n)) for n, word in puzzles.items()]
    sheet += [("", None), ("HINTS", None)]
    for n, (target, first) in hints.items():
        if target:
            text = f"> {puzzles[target]}"
        else:
            max_chars = (SIDE_W - 72) // 8
            text = first if len(first) <= max_chars else first[: max_chars - 2] + ".."
        sheet.append((text, (1, n)))
    full = Image.new("RGB", (w + SIDE_W, max(h, MARGIN * 2 + (len(sheet) + 2) * SIDE_LINE)), COL_BG)
    full.paste(img, (SIDE_W, 0))
    ds = ImageDraw.Draw(full)
    ds.rectangle([0, 0, SIDE_W - 16, full.height], fill=COL_SIDE_BG)
    for i, (text, chip) in enumerate(sheet):
        ty = MARGIN + i * SIDE_LINE
        if chip is None:
            ds.text((16, ty), text, font=font_small, fill=COL_HEADER)
            continue
        draw_chip(ds, (19, ty), chip[0], chip[1], hints, font_small)
        if placed.get(chip, 0) != 1:  # sin ubicar o repetido
            ds.text((52, ty), "*", font=font_small, fill=COL_WARN)
        col = altar_color(chip[0], chip[1], hints)
        ds.text((64, ty), text.upper(), font=font_small, fill=col)
    ds.text((16, MARGIN + (len(sheet) + 1) * SIDE_LINE), "* SIN UBICAR/REPETIDO", font=font_small, fill=COL_WARN)
    img = full

    img.save(out)
    print(f"mapa guardado en {out} ({len(rooms)} rooms, {len(drawn)} conexiones)")


if __name__ == "__main__":
    main()
