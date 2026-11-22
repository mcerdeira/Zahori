#!/usr/bin/env python3
"""Genera un mapa (PNG) de las rooms y a dónde lleva cada puerta. Uso personal, no va en el juego.

Lee los `scenes/rooms/levelN.tscn` y `secretN.tscn`, resuelve el `target_scene` de cada puerta (uid o
ruta) y dibuja cada room como un cuadradito con su número (las secretas como S0, S1... con borde
violeta). Si una puerta apunta a un número en vez de a una escena, la room destino (levelN) se dibuja
igual pero en amarillo (todavía no existe la escena).

Las rooms se ubican imitando el espacio: la posición de cada puerta dentro de su room dice para
dónde queda la otra (puerta a la derecha -> la otra room a la derecha; las `instant` de los bordes
pesan más). Se arma una grilla y se ajusta con recocido simulado (semilla fija, sale igual siempre)
para que las conexiones queden entre vecinas, sin cruzarse ni pasar por encima de otras rooms.
Cada puerta se marca en su lugar dentro de la captura (círculo; cuadrado si es instant; rojo si está
rota; gris si es del laberinto) y la línea va de puerta a puerta: gris si es de ida y vuelta,
naranja con flecha si la otra room no tiene puerta de vuelta, amarilla si va a una room sin escena.
Marca en la esquina cada altar con su número: H2 = altar de pista 2, P1 = altar de puzzle 1.
Abajo a la izquierda marca los fragmentos de la tableta coleccionable con su `piece_index` (T0..T3).
Antes de dibujar corre Godot con tools/capture_rooms.tscn, que saca una captura de cada room a
tools/room_shots/<room>.png (abre una ventana un par de segundos). Cada room se dibuja con su captura
en miniatura; si no hay (Godot falló o se pasó --no-capture), como un cuadro azul.

A la izquierda dibuja un machete con la palabra de cada altar de puzzle (puzzles/altar_XX.tres) y,
para cada pista (puzzles/hint_XX.tres), la palabra del puzzle al que apunta (su campo `puzzle`) o,
si no tiene, la primera línea del texto. Debajo, cada fragmento de la tableta con la room donde está.
Un * rojo al lado de la etiqueta marca los altares y fragmentos que no están ubicados en ninguna room
o que están en más de una (contando también las del laberinto).

Uso: python3 tools/gen_map.py [--no-capture] [salida.png]   (por defecto tools/map.png)
     GODOT=/ruta/al/binario si `godot` no está en el PATH.
"""

import math
import os
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rooms_model import room_files  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ROOMS_DIR = ROOT / "scenes" / "rooms"
FONT_PATH = ROOT / "fonts" / "prstartk.ttf"
SHOTS_DIR = ROOT / "tools" / "room_shots"
PUZZLES_DIR = ROOT / "puzzles"

BOX_W = 192  # px, ancho de cada room (576 / 3)
BOX_H = 108  # px, alto de cada room (324 / 3)
GAP_X = 72  # px, separación horizontal entre columnas
GAP_Y = 56  # px, separación vertical entre filas
MARGIN = 40  # px
SIDE_W = 230  # px, ancho del machete de la izquierda
SIDE_LINE = 16  # px entre renglones del machete

COL_BG = (34, 32, 42)
COL_ROOM = (90, 160, 210)
COL_MISSING = (240, 200, 40)
COL_BORDER = (240, 240, 240)
COL_TEXT = (20, 20, 28)
COL_EDGE = (200, 200, 210)
COL_ONE_WAY = (255, 160, 60)  # conexión de ida (sin puerta de vuelta)
COL_DOOR = (255, 255, 255)
COL_MAZE = (150, 150, 160)  # puertas del laberinto (las resuelve DoorMaze)
COL_START = (120, 220, 120)
COL_SECRET = (190, 110, 255)  # borde de las rooms secretas
COL_LABEL_BG = (240, 240, 240)
COL_SIDE_BG = (26, 24, 33)
COL_HEADER = (255, 200, 107)
COL_NO_PUZZLE = (150, 150, 160)  # pistas que no apuntan a ningún puzzle
COL_WARN = (255, 70, 70)  # el * de altares y fragmentos sin ubicar o repetidos
COL_TABLET = (225, 215, 185)  # etiqueta de los fragmentos de la tableta (T0..T3)
TABLET = 2  # "kind" de las etiquetas de fragmentos (0 = puzzle, 1 = pista)
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

# Rooms que van al mapa: levelN y secretN. Las internas del laberinto (level181a, ...) no.
ROOM_RE = re.compile(r"^(level|secret)(\d+)\.tscn$")
ROOM_KINDS = ("level", "secret")


def room_key(name):
    """Orden de las rooms: primero las levelN, después las secretN, cada una por número."""
    m = re.match(r"([a-z]+)(\d+)$", name)
    return (ROOM_KINDS.index(m.group(1)), int(m.group(2)))


def room_label(name):
    """Lo que se escribe en el cuadro: el número para levelN, S + número para secretN."""
    kind, num = ROOM_KINDS[room_key(name)[0]], room_key(name)[1]
    return str(num) if kind == "level" else f"S{num}"


def is_secret(name):
    return name.startswith("secret")


def parse_scene(path: Path):
    """Devuelve (uid, puertas, altares, fragmentos) de un .tscn.
    Puertas: lista de {"target": target_scene, "pos": (x, y) px, "instant": bool}.
    Altares: lista de (kind, número). Fragmentos: lista de piece_index de la tableta."""
    text = path.read_text(encoding="utf-8")
    header = re.match(r'\[gd_scene[^\]]*uid="([^"]+)"', text)
    uid = header.group(1) if header else None

    ext = {}  # id -> ruta
    for m in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text):
        ext[m.group(2)] = m.group(1)

    doors, altars, tablets = [], [], []
    # Separar en secciones [ ... ] con sus propiedades.
    sections = re.split(r"\n(?=\[)", text)
    for sec in sections:
        if not sec.startswith("[node"):
            continue
        inst = re.search(r'instance=ExtResource\("([^"]+)"\)', sec.split("\n", 1)[0])
        inst_path = ext.get(inst.group(1), "") if inst else ""
        target = re.search(r'^target_scene = "([^"]*)"', sec, re.M)
        if inst_path.endswith("door.tscn") or target:
            p = re.search(r"^position = Vector2\(([-\d.e]+), ([-\d.e]+)\)", sec, re.M)
            doors.append({
                "target": target.group(1) if target else "",
                "pos": (float(p.group(1)), float(p.group(2))) if p else (0.0, 0.0),
                "instant": bool(re.search(r"^instant = true", sec, re.M)),
            })
        elif inst_path.endswith("altar.tscn"):
            kind = re.search(r"^kind = (\d+)", sec, re.M)
            number = re.search(r"^altar_number = (\d+)", sec, re.M)
            # (kind, número): kind 0 = PUZZLE, 1 = HINT; altar_number por defecto es 1.
            altars.append((int(kind.group(1)) if kind else 0, int(number.group(1)) if number else 1))
        elif inst_path.endswith("tablet_piece.tscn"):
            index = re.search(r"^piece_index = (\d+)", sec, re.M)
            tablets.append(int(index.group(1)) if index else 0)  # piece_index por defecto es 0
    return uid, doors, altars, tablets


def collect():
    """Arma el grafo: rooms {nombre: {...}} y links, una por puerta que lleva a otra room:
    {"a": origen, "b": destino, "pos": posición de la puerta en a, "instant": bool}."""
    uid_to_path = {}
    for f in ROOT.rglob("*.tscn"):
        if ".godot" in f.parts:
            continue
        m = re.match(r'\[gd_scene[^\]]*uid="([^"]+)"', f.read_text(encoding="utf-8").split("\n", 1)[0])
        if m:
            uid_to_path[m.group(1)] = f

    rooms, edges = {}, []
    for f in room_files():
        if not ROOM_RE.match(f.name):
            continue  # rooms internas del laberinto de puertas (level181a, ...)
        _, doors, altars, tablets = parse_scene(f)
        rooms[f.stem] = {"missing": False, "altars": altars, "door_list": doors, "tablets": tablets}

    for name, room in list(rooms.items()):
        for door in room["door_list"]:
            target = door["target"]
            door["dest"] = None
            if not target:
                print(f"aviso: {name} tiene una puerta sin target_scene")
                continue
            if target == "-1":
                continue  # puerta del laberinto (la resuelve DoorMaze en el juego)
            if target.isdigit():
                dest = f"level{int(target)}"
            else:
                if target.startswith("uid://"):
                    dest_path = uid_to_path.get(target)
                else:
                    dest_path = ROOT / target.removeprefix("res://")
                if not dest_path or not ROOM_RE.match(dest_path.name):
                    print(f"aviso: {name} tiene una puerta a algo que no es una room: {target}")
                    continue
                dest = dest_path.stem
            if dest not in rooms:
                rooms[dest] = {"missing": True, "altars": [], "door_list": [], "tablets": []}
            door["dest"] = dest
            edges.append({"a": name, "b": dest, "pos": door["pos"], "instant": door["instant"]})
    return rooms, edges


ROOM_W, ROOM_H = 576.0, 324.0  # px, tamaño de una room en el juego
SCALE = BOX_W / ROOM_W  # de coordenadas de la room a coordenadas del cuadro en el mapa


def door_dir(door):
    """Hacia dónde "apunta" una puerta según dónde está en su room: un vector con x, y en -1..1
    (borde izquierdo/arriba = -1) y un peso. Las puertas `instant` están en un borde y salir por
    ahí es literal, así que pesan más y se redondean a la dirección de ese borde."""
    x, y = door["pos"]
    vx = max(-1.0, min(1.0, (x - ROOM_W / 2) / (ROOM_W / 2)))
    vy = max(-1.0, min(1.0, (y - ROOM_H / 2) / (ROOM_H / 2)))
    if door["instant"]:
        return ((1.0 if vx > 0 else -1.0, 0.0) if abs(vx) >= abs(vy)
                else (0.0, 1.0 if vy > 0 else -1.0)), 3.0
    return (vx, vy), 1.0


def snap(d):
    """Vector -> paso en la grilla (dx, dy en -1..1). Diagonal sólo si las dos componentes pesan parecido."""
    dx, dy = d
    ax, ay = abs(dx), abs(dy)
    if max(ax, ay) < 0.15:
        return (1, 0)
    sx, sy = (1 if dx > 0 else -1), (1 if dy > 0 else -1)
    if min(ax, ay) > 0.6 * max(ax, ay):
        return (sx, sy)
    return (sx, 0) if ax >= ay else (0, sy)


def layout(rooms, links):
    """Ubica las rooms en una grilla imitando el espacio: si la puerta de A a B está a la derecha
    de A (y la de vuelta, a la izquierda de B), B va a la derecha de A. Arranca en la room inicial
    y va agregando primero las conexiones más claras; si la celda deseada está ocupada usa la libre
    más cercana. Devuelve ({room: (x, y) px}, ancho, alto)."""
    # Dirección deseada de A a B, sumando las puertas de ida y (en contra) las de vuelta.
    want = {}
    for l in links:
        a, b = l["a"], l["b"]
        if a == b:
            continue
        (vx, vy), w = door_dir(l)
        for key, sign in (((a, b), 1.0), ((b, a), -1.0)):
            cur = want.get(key, (0.0, 0.0, 0.0))
            want[key] = (cur[0] + vx * w * sign, cur[1] + vy * w * sign, cur[2] + w)
    adj = {n: set() for n in rooms}
    for a, b in want:
        adj[a].add(b)

    cell, taken = {}, {}

    def place(n, c):
        cell[n] = c
        taken[c] = n

    def best_cell(n):
        placed = [m for m in adj[n] if m in cell]
        targets = []
        for m in placed:
            dx, dy, w = want[(m, n)]
            sx, sy = snap((dx, dy))
            targets.append(((cell[m][0] + sx, cell[m][1] + sy), w))
        total = sum(w for _, w in targets)
        tx = sum(c[0] * w for c, w in targets) / total
        ty = sum(c[1] * w for c, w in targets) / total
        best, best_cost = None, None
        for r in range(0, 8):
            for cx in range(round(tx) - r, round(tx) + r + 1):
                for cy in range(round(ty) - r, round(ty) + r + 1):
                    if (cx, cy) in taken:
                        continue
                    # Cerca del objetivo, y sin alejarse de ninguna room vecina ya ubicada.
                    cost = ((cx - tx) ** 2 + (cy - ty) ** 2) ** 0.5
                    cost += 0.3 * sum(((cx - cell[m][0]) ** 2 + (cy - cell[m][1]) ** 2) ** 0.5 for m in placed)
                    if best_cost is None or cost < best_cost:
                        best, best_cost = (cx, cy), cost
            if best is not None and r >= 2:
                break
        return best

    order = sorted(rooms, key=room_key)
    while len(cell) < len(rooms):
        # Componente nueva: su primera room a la derecha de todo lo ubicado.
        seed = next(n for n in order if n not in cell)
        place(seed, (max((c[0] for c in taken), default=-2) + 2, 0))
        while True:
            # La room sin ubicar más atada a las ya ubicadas (más puertas, más claras).
            cands = [(sum(want[(m, n)][2] for m in adj[n] if m in cell), n)
                     for n in order if n not in cell and any(m in cell for m in adj[n])]
            if not cands:
                break
            _, n = max(cands, key=lambda t: (t[0], [-k for k in room_key(t[1])]))
            place(n, best_cell(n))

    refine(cell, want)
    taken = {c: n for n, c in cell.items()}
    min_x = min(c[0] for c in taken)
    min_y = min(c[1] for c in taken)
    cols = max(c[0] for c in taken) - min_x + 1
    rows = max(c[1] for c in taken) - min_y + 1
    pos = {n: (MARGIN + (c[0] - min_x) * (BOX_W + GAP_X), MARGIN + (c[1] - min_y) * (BOX_H + GAP_Y))
           for n, c in cell.items()}
    w = MARGIN * 2 + cols * BOX_W + (cols - 1) * GAP_X
    h = MARGIN * 2 + rows * BOX_H + (rows - 1) * GAP_Y + 24  # + leyenda
    return pos, int(w), int(h)


def _segments_cross(p1, p2, q1, q2):
    """True si los segmentos p1-p2 y q1-q2 se cruzan (sin contar extremos compartidos)."""
    if p1 in (q1, q2) or p2 in (q1, q2):
        return False
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return (v > 0) - (v < 0)
    return (orient(p1, p2, q1) * orient(p1, p2, q2) < 0
            and orient(q1, q2, p1) * orient(q1, q2, p2) < 0)


def refine(cell, want):
    """Mejora la grilla moviendo rooms a celdas libres o intercambiando dos, mientras baje el costo:
    cuánto se aparta cada conexión del paso deseado (más si es larga), más cada cruce entre
    conexiones y cada conexión que pasa por encima de otra room."""
    pairs = {}
    for (a, b), (dx, dy, w) in want.items():
        key = (a, b) if room_key(a) <= room_key(b) else (b, a)
        if key not in pairs:
            sx, sy = snap(want[key][:2])
            pairs[key] = (sx, sy, want[key][2])
    links_of = {}
    for key in pairs:
        for n in key:
            links_of.setdefault(n, []).append(key)

    def link_cost(key, taken):
        (a, b), (sx, sy, w) = key, pairs[key]
        ca, cb = cell[a], cell[b]
        ox, oy = cb[0] - ca[0], cb[1] - ca[1]
        cost = w * (((ox - sx) ** 2 + (oy - sy) ** 2) ** 0.5) + 0.6 * (abs(ox) + abs(oy) - 1)
        # Pasa por encima de otra room (muestreo sobre la recta entre centros de celda)
        steps = 4 * max(abs(ox), abs(oy), 1)
        hit = set()
        for i in range(1, steps):
            c = (round(ca[0] + ox * i / steps), round(ca[1] + oy * i / steps))
            if c not in (ca, cb) and c in taken:
                hit.add(c)
        return cost + 2.0 * len(hit)

    def crossings(keys):
        n = 0
        for k in keys:
            for other in pairs:
                if other != k and _segments_cross(cell[k[0]], cell[k[1]], cell[other[0]], cell[other[1]]):
                    n += 1
        return n

    def local_cost(rooms_moved, taken):
        keys = {k for n in rooms_moved for k in links_of.get(n, [])}
        return sum(link_cost(k, taken) for k in keys) + 1.5 * crossings(keys)

    names = sorted(cell, key=room_key)

    def total_cost():
        taken = {c: n for n, c in cell.items()}
        return sum(link_cost(k, taken) for k in pairs) + 1.5 * crossings(pairs) / 2

    # 1) Recocido simulado: mueve o intercambia rooms al azar; al principio acepta empeorar
    #    (para salir de mínimos locales) y cada vez menos. Semilla fija: el mapa sale igual siempre.
    rng = random.Random(1)
    taken = {c: n for n, c in cell.items()}
    best_cost, best_cell = total_cost(), dict(cell)
    cur = best_cost
    steps = 30000
    for i in range(steps):
        temp = 3.0 * (0.02 / 3.0) ** (i / steps)
        n = rng.choice(names)
        xs = [c[0] for c in taken]
        ys = [c[1] for c in taken]
        c = (rng.randint(min(xs) - 1, max(xs) + 1), rng.randint(min(ys) - 1, max(ys) + 1))
        old, other = cell[n], taken.get(c)
        if other == n:
            continue
        moved = [n] if other is None else [n, other]
        before = local_cost(moved, taken)
        cell[n] = c
        if other:
            cell[other] = old
        t2 = dict(taken)
        t2.pop(old, None)
        t2[c] = n
        if other:
            t2[old] = other
        delta = local_cost(moved, t2) - before
        if delta <= 0 or rng.random() < math.exp(-delta / temp):
            taken = t2
            cur += delta
            if cur < best_cost - 1e-9:
                best_cost, best_cell = cur, dict(cell)
        else:
            cell[n] = old
            if other:
                cell[other] = c
    cell.clear()
    cell.update(best_cell)

    # 2) Ajuste fino: el mejor movimiento de cada room, mientras mejore.
    for _ in range(30):
        improved = False
        taken = {c: n for n, c in cell.items()}
        xs = [c[0] for c in taken]
        ys = [c[1] for c in taken]
        free = [(x, y) for x in range(min(xs) - 1, max(xs) + 2) for y in range(min(ys) - 1, max(ys) + 2)]
        for n in names:
            before = local_cost([n], taken)
            best, best_gain = None, 0.01
            for c in free:
                other = taken.get(c)
                if other == n:
                    continue
                moved = [n] if other is None else [n, other]
                base = before if other is None else local_cost(moved, taken)
                old = cell[n]
                # Probar: n a c (y el que estaba en c, a la celda de n)
                cell[n] = c
                if other:
                    cell[other] = old
                t2 = dict(taken)
                t2.pop(old, None)
                t2[c] = n
                if other:
                    t2[old] = other
                gain = base - local_cost(moved, t2)
                cell[n] = old
                if other:
                    cell[other] = c
                if gain > best_gain:
                    best, best_gain = c, gain
            if best is not None:
                old, other = cell[n], taken.get(best)
                cell[n] = best
                if other:
                    cell[other] = old
                taken = {c: m for m, c in cell.items()}
                improved = True
        if not improved:
            break


def door_point(box_pos, door):
    """Dónde se dibuja una puerta dentro del cuadro de su room (la posición real, escalada)."""
    x, y = door["pos"]
    x = max(4.0, min(ROOM_W - 4.0, x))
    y = max(4.0, min(ROOM_H - 4.0, y))
    return (box_pos[0] + x * SCALE, box_pos[1] + y * SCALE)


def border_point(box_pos, toward):
    """Punto del borde del cuadro en la dirección de `toward` desde su centro (para las de ida)."""
    cx, cy = center(box_pos)
    dx, dy = toward[0] - cx, toward[1] - cy
    if dx == 0 and dy == 0:
        return (cx, cy)
    t = min((BOX_W / 2) / abs(dx) if dx else 1e9, (BOX_H / 2) / abs(dy) if dy else 1e9)
    return (cx + dx * t, cy + dy * t)


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


def edge_path(pa, pb, others):
    """Recta de pa a pb si no pisa otras rooms; si no, una curva que se va abriendo hasta esquivarlas."""
    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    nx, ny = -dy / length, dx / length
    mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
    for k in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
        off = k * (BOX_H * 0.5)
        pts = bezier(pa, (mid[0] + nx * off, mid[1] + ny * off), pb)
        if not hits_box(pts, others):
            return pts
    return bezier(pa, mid, pb)


def draw_arrow(d, pts, color):
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    size = 11
    left = (x1 - ux * size - uy * size * 0.6, y1 - uy * size + ux * size * 0.6)
    right = (x1 - ux * size + uy * size * 0.6, y1 - uy * size - ux * size * 0.6)
    d.polygon([(x1, y1), left, right], fill=color, outline=COL_BG)


def pair_doors(links):
    """Junta cada puerta A->B con una de vuelta B->A. Devuelve (pares [(ida, vuelta)], sueltas [ida])."""
    by_pair = {}
    for l in links:
        by_pair.setdefault((l["a"], l["b"]), []).append(l)
    pairs, single, seen = [], [], set()
    for (a, b), fwd in by_pair.items():
        if (a, b) in seen:
            continue
        seen.add((a, b))
        seen.add((b, a))
        back = by_pair.get((b, a), []) if a != b else []
        for i, l in enumerate(fwd):
            if i < len(back):
                pairs.append((l, back[i]))
            else:
                single.append(l)
        single += back[len(fwd):]
    return pairs, single


def draw_links(d, links, pos, rooms):
    """Una línea por conexión, de la puerta en una room a la puerta de vuelta en la otra.
    Gris = ida y vuelta; naranja con flecha = puerta de ida (la otra room no tiene puerta de vuelta);
    amarillo = a una room que todavía no tiene escena."""
    pairs, single = pair_doors(links)
    lines = []
    for l, back in pairs:
        lines.append((door_point(pos[l["a"]], l), door_point(pos[l["b"]], back), l["a"], l["b"], False))
    for l in single:
        pa = door_point(pos[l["a"]], l)
        lines.append((pa, border_point(pos[l["b"]], pa), l["a"], l["b"], True))
    for pa, pb, a, b, one_way in lines:
        others = [p for n, p in pos.items() if n not in (a, b)]
        pts = edge_path(pa, pb, others)
        color = COL_MISSING if rooms[b]["missing"] else COL_ONE_WAY if one_way else COL_EDGE
        d.line(pts, fill=COL_BG, width=6, joint="curve")  # contorno para que se lea sobre las capturas
        d.line(pts, fill=color, width=2, joint="curve")
        if one_way:
            draw_arrow(d, pts, color)
    # Las puertas encima: círculo = común, cuadrado = instant (borde de la room).
    for n, r in rooms.items():
        if n not in pos:
            continue
        for door in r["door_list"]:
            x, y = door_point(pos[n], door)
            broken = door["dest"] is None and door["target"] != "-1"
            fill = COL_WARN if broken else COL_DOOR
            if door["target"] == "-1":
                fill = COL_MAZE
            box = [x - 3, y - 3, x + 3, y + 3]
            if door["instant"]:
                d.rectangle(box, fill=fill, outline=COL_BG)
            else:
                d.ellipse(box, fill=fill, outline=COL_BG)


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


def count_placed():
    """Recorre todas las rooms, incluidas las del laberinto. Devuelve (counts, tablet_rooms):
    counts {(kind, número): veces que aparece} para altares y fragmentos (kind TABLET), y
    tablet_rooms {piece_index: [rooms donde está]}."""
    counts, tablet_rooms = {}, {}
    for f in room_files():
        _, _, altars, tablets = parse_scene(f)
        for altar in altars:
            counts[altar] = counts.get(altar, 0) + 1
        for i in tablets:
            counts[(TABLET, i)] = counts.get((TABLET, i), 0) + 1
            tablet_rooms.setdefault(i, []).append(f.stem)
    return counts, tablet_rooms


def tablet_piece_count():
    """Cantidad de fragmentos de la tableta (Global.TABLET_PIECE_COUNT)."""
    m = re.search(r"const TABLET_PIECE_COUNT := (\d+)", (ROOT / "scripts" / "Global.gd").read_text(encoding="utf-8"))
    return int(m.group(1)) if m else 4


def puzzle_color(n):
    return PUZZLE_COLORS[(n - 1) % len(PUZZLE_COLORS)]


def altar_color(kind, n, hints):
    """Color de un altar: el de su puzzle; las pistas, el del puzzle al que apuntan (gris si ninguno)."""
    if kind == TABLET:
        return COL_TABLET
    if kind == 0:
        return puzzle_color(n)
    target = hints.get(n, (None, ""))[0]
    return puzzle_color(target) if target else COL_NO_PUZZLE


def draw_chip(d, xy, kind, n, hints, font, anchor="lt"):
    """Etiqueta de un altar: puzzle = relleno de color; pista = borde de color sobre oscuro.
    Fragmento de la tableta: T + índice, relleno color piedra. Devuelve el bbox de la etiqueta."""
    text = {0: "P", 1: "H", TABLET: "T"}[kind] + str(n)
    col = altar_color(kind, n, hints)
    tb = d.textbbox(xy, text, font=font, anchor=anchor)
    box = [tb[0] - 3, tb[1] - 3, tb[2] + 3, tb[3] + 3]
    if kind in (0, TABLET):
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
    placed, tablet_rooms = count_placed()
    n_tablets = tablet_piece_count()
    for i in sorted(tablet_rooms):
        if i >= n_tablets:
            print(f"aviso: fragmento T{i} fuera de rango (hay {n_tablets}) en {', '.join(tablet_rooms[i])}")

    legend = ("HN: hint N  PN: puzzle N  TN: fragmento de tableta N  SN: secreta N  borde verde: inicio  "
              "o: puerta  cuadrado: puerta instant  rojo: puerta rota  gris: ida y vuelta  "
              "naranja: solo ida  amarillo: room sin escena")
    w = max(w, MARGIN * 2 + len(legend) * 8)  # que entre la leyenda (8 px por caracter)
    img = Image.new("RGB", (w, h), COL_BG)
    d = ImageDraw.Draw(img)
    font_big = ImageFont.truetype(str(FONT_PATH), 16)
    font_small = ImageFont.truetype(str(FONT_PATH), 8)

    start = min((n for n, r in rooms.items() if not r["missing"]), key=room_key)
    for n, (x, y) in pos.items():
        r = rooms[n]
        shot = SHOTS_DIR / f"{n}.png"
        border = COL_START if n == start else COL_SECRET if is_secret(n) else COL_BORDER
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
            label = room_label(n)
            label_box = d.textbbox((x + 6, y + 6), label, font=font_big)
            d.rectangle([label_box[0] - 3, label_box[1] - 3, label_box[2] + 3, label_box[3] + 3],
                        fill=COL_SECRET if is_secret(n) else COL_LABEL_BG)
            d.text((x + 6, y + 6), label, font=font_big, fill=COL_TEXT)
        else:
            d.text((x + BOX_W / 2, y + BOX_H / 2), room_label(n), font=font_big, fill=COL_TEXT, anchor="mm")

        # Un tag por altar (H2, P1...), primero las pistas, arriba a la derecha.
        # Se dibujan de derecha a izquierda, así que se recorren al revés.
        tx = x + BOX_W - 6
        for k, num in reversed(sorted(r["altars"], key=lambda a: (-a[0], a[1]))):
            box = draw_chip(d, (tx, y + 7), k, num, hints, font_small, anchor="rt")
            tx = box[0] - 7

        # Fragmentos de la tableta (T0..T3), abajo a la izquierda.
        tx = x + 7
        for i in sorted(r["tablets"]):
            box = draw_chip(d, (tx, y + BOX_H - 7), TABLET, i, hints, font_small, anchor="lb")
            tx = box[2] + 7

    # Las conexiones van encima de las capturas, de puerta a puerta.
    draw_links(d, edges, pos, rooms)

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
    sheet += [("", None), ("TABLETS", None)]
    for i in range(n_tablets):
        where = tablet_rooms.get(i)
        sheet.append((", ".join(where) if where else "SIN UBICAR", (TABLET, i)))
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
    print(f"mapa guardado en {out} ({len(rooms)} rooms, {len(edges)} puertas entre rooms)")


if __name__ == "__main__":
    main()
