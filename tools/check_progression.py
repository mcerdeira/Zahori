#!/usr/bin/env python3
"""Chequeo estático de progresión: ¿se puede terminar el juego? ¿hay soft-locks?

Modela cada room como una grilla de 16 px y explora (BFS) todos los estados a los que
puede llegar el player desde el arranque (level0), con las habilidades que va
consiguiendo. Después mira, hacia atrás, desde qué estados se puede llegar al objetivo.

  - Si el objetivo no es alcanzable: el juego no se puede terminar.
  - Soft-lock: un estado alcanzable desde el que ya no se puede llegar al objetivo (sin
    salir al título). Se reportan las "jugadas fatales": el paso que lleva de un estado
    ganable a uno perdido, con el camino de rooms para reproducirlo.

Modelo (aproximado, ver README al final del archivo):
  - Caminar, caer (con algo de control en el aire), puertas (UP) e instantáneas.
  - blocks: torre de hasta Global.max_blocks celdas (sin límite con reach) y bajarse
    por un costado a cualquier altura.
  - eat: la piedra cuenta como aire (se come al pisarla, empujarla o al construir).
  - hydro: el agua no mata y el bote no flota (cae hasta un tile o se pierde).
  - teleport: intercambio con plantas y fantasmas en la misma fila.
  - Bote: se lanza a izquierda/derecha y avanza hasta chocar.
  - Morir: recarga la room y reaparece en la puerta de entrada (bote, plantas, etc. como al entrar),
    o en el último altar usado en esa room (usar cualquier altar mueve ahí el respawn hasta
    salir por una puerta).
    Si esa puerta está bajo el agua y no tiene hydro, se ahoga al aparecer y sale por esa
    misma puerta (a la room de la que venía), como en el juego (player.gd: _drowned_door).
  - Altares: resolver da la habilidad; volver a uno resuelto la prende/apaga. Los altares
    de pista también la prenden/apagan si el puzzle al que apuntan (campo `puzzle` de
    puzzles/hint_XX.tres) ya está resuelto.
  - Hermana: da zahori. Laberinto: con zahori se acierta la puerta; sin zahori no (salvo
    --maze-luck).
  - Los enemigos (fantasmas, enredaderas) no bloquean: se asume que se los esquiva.
  - Objetivo: el final del laberinto (o --goal). Las rooms a las que se llega desde el
    objetivo pero desde las que no se vuelve (la parte final) cuentan como llegada.
  - Cuenta lo que haya fuera de la pantalla (tiles, killers, agua, puertas instant): una
    caída que termina en un killerobj de afuera es una muerte, no una caída al vacío.

Uso: python3 tools/check_progression.py [--goal ROOM] [--maze-luck] [--assume ab1,ab2]
                                        [--verbose]
Sale con código 1 si el objetivo no es alcanzable o si hay soft-locks.
"""

import argparse
import math
import re
import sys
from collections import deque
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rooms_model import COLS, ROWS, ROOT, TILE, load_rooms, resolve_target  # noqa: E402

# --- Parámetros del juego (se leen del código cuando se puede) ----------------------------

def _read_max_blocks():
    m = re.search(r"var max_blocks: int = (\d+)", (ROOT / "scripts" / "Global.gd").read_text())
    return int(m.group(1)) if m else 4


def _read_abilities():
    text = (ROOT / "scripts" / "Global.gd").read_text()
    block = re.search(r"var abilities: Dictionary = \{(.*?)\}", text, re.S).group(1)
    return re.findall(r'&"(\w+)"', block)


def _read_maze():
    text = (ROOT / "scripts" / "DoorMaze.gd").read_text()
    rooms = re.findall(r'"(res://scenes/rooms/[^"]+)"', re.search(r"const ROOMS[^=]*=\s*\[(.*?)\]", text, re.S).group(1))
    final = re.search(r'const FINAL_SCENE := "([^"]*)"', text).group(1)
    return rooms, final


def _read_puzzles():
    """{altar_number: ability_id} de puzzles/altar_XX.tres."""
    out = {}
    for p in sorted((ROOT / "puzzles").glob("altar_*.tres")):
        m = re.search(r'ability_id = &"(\w+)"', p.read_text())
        if m:
            out[int(re.search(r"(\d+)", p.stem).group(1))] = m.group(1)
    return out


def _read_hints():
    """{número de pista: número del altar de puzzle al que apunta} de puzzles/hint_XX.tres
    (sólo las que apuntan a alguno)."""
    out = {}
    for p in sorted((ROOT / "puzzles").glob("hint_*.tres")):
        m = re.search(r"^puzzle = (\d+)", p.read_text(), re.M)
        if m and int(m.group(1)) > 0:
            out[int(re.search(r"(\d+)", p.stem).group(1))] = int(m.group(1))
    return out


MAX_BLOCKS = _read_max_blocks()
ABILITIES = _read_abilities()
BIT = {a: 1 << i for i, a in enumerate(ABILITIES)}
MAZE_ROOMS, MAZE_FINAL = _read_maze()
PUZZLES = _read_puzzles()
HINTS = _read_hints()
START_ROOM = "res://scenes/rooms/level0.tscn"


def _monologue_seconds(lines):
    """Duración de un monólogo con los tiempos de scripts/monologue.gd."""
    t = 0.0
    for ln in lines:
        t += len(ln) * 0.075 + ln.count(",") * 0.35 + ln.count(".") * 0.3 + 2.5 + 0.6
    return t


def _read_lines(path, const=None):
    text = (ROOT / path).read_text()
    m = re.search((rf"{const}[^=]*=\s*\[" if const else r"lines = \[") + r"(.*?)\]", text, re.S)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)) if m else []


INTRO_READ_TIME = 20.0  # Intro.tscn: leer el texto y apretar una tecla
INTRO2_TIME = _monologue_seconds(_read_lines("scenes/intro2.gd"))
SISTER_TIME = _monologue_seconds(_read_lines("scenes/sister.gd", "const LINES"))
BUILD_INTERVAL = 0.2  # player.gd
DOOR_TIME = 1.1 + 0.6  # transition_time + caminar al centro / carga
TOGGLE_TIME = 6.0  # abrir la terminal, YES, cerrar

# Física del player (player.gd / project.godot)
GRAVITY = 980.0
MAX_FALL = 240.0
SPEED = 120.0
ACCEL = 900.0

# Márgenes mínimos de la simulación alrededor de la pantalla; cada room los agranda si
# tiene paredes, killers, agua o puertas instant más afuera (RoomSim.row_max, etc.).
ROW_MIN = -4  # se puede subir un poco por encima de la pantalla
ROW_MAX = ROWS + 2  # más abajo: cayó al vacío
COL_MIN, COL_MAX = -14, COLS + 13  # más afuera: se fue de la pantalla y no vuelve


def names(mask):
    return [a for a in ABILITIES if mask & BIT[a]] or ["-"]


# --- Caída ----------------------------------------------------------------------------------

def _fall_time(rows):
    d = rows * TILE
    d_term = MAX_FALL ** 2 / (2 * GRAVITY)
    if d <= d_term:
        return math.sqrt(2 * d / GRAVITY)
    return MAX_FALL / GRAVITY + (d - d_term) / MAX_FALL


@lru_cache(None)
def max_drift(rows, moving):
    """Columnas que se puede desplazar en el aire tras caer `rows` filas.
    moving: venía caminando (sale con velocidad plena); si no, arranca quieto."""
    t = _fall_time(rows)
    if moving:
        reach = SPEED * t
        first = 8.5  # px desde que empieza a caer hasta tocar la columna siguiente
    else:
        t_acc = SPEED / ACCEL
        reach = 0.5 * ACCEL * t * t if t < t_acc else 0.5 * ACCEL * t_acc ** 2 + SPEED * (t - t_acc)
        first = 4.5
    if reach < first:
        return 0
    return 1 + int((reach - first) // TILE)


# --- Simulación de una room -----------------------------------------------------------------

class RoomSim:
    def __init__(self, room, by_uid):
        self.room = room
        self.by_uid = by_uid
        self.water = self._cells("water")
        self.killer = self._cells("killerobj")
        self.instant = {}  # celda -> puerta
        self.doors = {}  # celda de parado -> [puertas]
        self.altars = {}  # celda -> [(kind, number)]
        self.sister = set()
        for e in room.entities:
            if e.kind == "door" and e.props.get("instant"):
                for c in self._overlap_cells(e.rect()):
                    self.instant.setdefault(c, e)
            elif e.kind == "door":
                for c in self._stand_cells(e.rect()):
                    self.doors.setdefault(c, []).append(e)
            elif e.kind == "altar":
                kind = e.props.get("kind", 0)
                num = e.props.get("altar_number", 1)
                for c in self._stand_cells(e.rect()):
                    self.altars.setdefault(c, []).append((kind, num, e.name))
            elif e.kind == "sister":
                self.sister |= self._stand_cells(e.rect())
        # Límites de la simulación: la pantalla más un margen, agrandado para abarcar lo que
        # haya afuera (paredes, killers, agua o puertas instant fuera de la pantalla). Caer
        # más allá cuenta como "se fue de la pantalla y no vuelve".
        extra = set(room.outside) | self.killer | self.water | set(self.instant)
        xs = [c[0] for c in extra] or [0]
        ys = [c[1] for c in extra] or [0]
        self.col_min, self.col_max = min(COL_MIN, min(xs) - 1), max(COL_MAX, max(xs) + 1)
        self.row_min = min(ROW_MIN, min(ys))
        self.row_max = max(ROW_MAX, max(ys) + 1)
        self.plants0 = tuple(sorted((int(e.pos[0]), int(e.pos[1])) for e in room.of_kind("plant")))
        self.ghost_axes = [e.props.get("direction", 0) for e in room.of_kind("ghost")]
        self.ghosts0 = tuple(self._ghost_anchor(i, int(e.pos[0] // TILE), int(e.pos[1] // TILE))
                             for i, e in enumerate(room.of_kind("ghost")))
        boats = room.of_kind("boat")
        self.boat0 = (boats[0].pos[0], boats[0].pos[1]) if boats else None
        self.water_rects = [e.rect() for e in room.of_kind("water")]

    # -- geometría --
    @staticmethod
    def _overlap_cells(rect, margin=3.0):
        """Celdas donde el player (7x12, en cualquier lugar de la celda) puede tocar el rect."""
        x0, y0, x1, y1 = rect
        out = set()
        for cx in range(int(x0 // TILE) - 1, int(x1 // TILE) + 2):
            for cy in range(int(y0 // TILE) - 1, int(y1 // TILE) + 2):
                # el player ocupa como mucho la celda entera en x, y la franja y*16+4..+16
                if min(x1, cx * TILE + TILE) - max(x0, cx * TILE) > margin and \
                        min(y1, cy * TILE + TILE) - max(y0, cy * TILE + 4) > margin:
                    out.add((cx, cy))
        return out

    def _cells(self, kind):
        out = set()
        for e in self.room.of_kind(kind):
            x0, y0, x1, y1 = e.rect()
            for cx in range(int(x0 // TILE) - 1, int(x1 // TILE) + 2):
                for cy in range(int(y0 // TILE) - 1, int(y1 // TILE) + 2):
                    # Mata si toca al player aun centrado en la celda
                    px0, px1 = cx * TILE + 4.5, cx * TILE + 11.5
                    py0, py1 = cy * TILE + 4, cy * TILE + 16
                    if min(x1, px1) - max(x0, px0) > 0.5 and min(y1, py1) - max(y0, py0) > 0.5:
                        out.add((cx, cy))
        return out

    def _stand_cells(self, rect):
        """Celdas donde el player parado se superpone con el rect (área de interacción)."""
        x0, y0, x1, y1 = rect
        out = set()
        for cx in range(int(x0 // TILE) - 1, int(x1 // TILE) + 2):
            for cy in range(int(y0 // TILE) - 1, int(y1 // TILE) + 2):
                if min(x1, cx * TILE + TILE) - max(x0, cx * TILE) > 1 and \
                        min(y1, cy * TILE + 16) - max(y0, cy * TILE + 4) > 0:
                    out.add((cx, cy))
        return out

    def tile(self, x, y):
        return self.room.solid(x, y)

    # -- bote --
    def boat_settle(self, boat, hydro):
        """Posición final del bote (x, y del origen) tras flotar o caer. None si se pierde."""
        if boat is None:
            return None
        bx, by = boat
        if not hydro:
            best = None
            for (x0, y0, x1, y1) in self.water_rects:
                if x0 <= bx <= x1 and by <= y0 - 5 + 1:
                    best = y0 if best is None else min(best, y0)
            if best is not None:
                return (bx, best - 5)
        # Cae hasta apoyarse en un tile (base del collider = origen + 8)
        c0, c1 = int((bx - 14) // TILE), int((bx + 14 - 0.01) // TILE)
        for row in range(max(0, int((by + 8) // TILE)), ROWS):
            if any(self.tile(c, row) != " " for c in range(c0, c1 + 1)):
                return (bx, row * TILE - 8)
        return None

    @staticmethod
    def boat_cols(boat):
        bx = boat[0]
        return range(int((bx - 14) // TILE), int((bx + 14 - 0.01) // TILE) + 1)

    @staticmethod
    def boat_rider_row(boat):
        return int((boat[1] + 2 - 6) // TILE)  # top = origen + 2; centro del player 6 px arriba

    # -- pasabilidad --
    def blocked(self, x, y, act, boat):
        t = self.tile(x, y)
        if t == "#" or (t == "S" and not act & BIT.get("eat", 0)):
            return True
        if boat and y == self.boat_rider_row(boat) + 1 and x in self.boat_cols(boat):
            return True
        return False

    def floor(self, x, y, act, boat):
        if boat and y == self.boat_rider_row(boat) and x in self.boat_cols(boat):
            return True
        return self.blocked(x, y + 1, act, boat)

    def deadly(self, x, y, act, boat, ghosts):
        if boat and y == self.boat_rider_row(boat) and x in self.boat_cols(boat):
            return False  # parado en el bote, por encima del agua
        if (x, y) in self.killer:
            return True
        if (x, y) in self.water and not act & BIT.get("hydro", 0):
            return True
        return False

    def ghost_cells(self, ghosts):
        out = set()
        for i, g in enumerate(ghosts):
            out |= set(self._ghost_segment(i, g))
        return out

    # -- fantasmas --
    def _ghost_segment(self, i, anchor):
        x, y = anchor
        horiz = self.ghost_axes[i] == 0
        dx, dy = (1, 0) if horiz else (0, 1)
        cells = [(x, y)]
        for s in (1, -1):
            cx, cy = x + dx * s, y + dy * s
            while self.tile(cx, cy) == " " and self.col_min <= cx <= self.col_max and self.row_min <= cy <= self.row_max:
                cells.append((cx, cy))
                cx, cy = cx + dx * s, cy + dy * s
        return sorted(cells)

    def _ghost_anchor(self, i, x, y):
        return self._ghost_segment(i, (x, y))[0]

    # -- movimientos --
    def fall(self, x, y, act, dyn, moving_dir):
        """Resuelve una caída desde la celda (x, y) en el aire. Devuelve eventos."""
        plants, ghosts, boat = dyn
        out = set()
        cur = {x}
        n = 0
        r = y
        while cur:
            if r > self.row_max:
                out.add(("void",))
                break
            drift = max_drift(n + 1, moving_dir != 0)
            lo = x - (drift if moving_dir <= 0 else 0)
            hi = x + (drift if moving_dir >= 0 else 0)
            seen = set()
            stack = list(cur)
            while stack:
                c = stack.pop()
                if c in seen:
                    continue
                seen.add(c)
                if c < self.col_min or c > self.col_max:
                    out.add(("void",))
                    continue
                if (c, r) in self.instant:
                    out.add(("instant", self.instant[(c, r)].name))
                    continue
                if self.deadly(c, r, act, boat, ghosts):
                    out.add(("death",))
                    continue
                if self.floor(c, r, act, boat):
                    out.add(("stand", c, r))
                    continue
                for nc in (c - 1, c + 1):
                    if lo <= nc <= hi and nc not in seen and not self.blocked(nc, r, act, boat):
                        stack.append(nc)
            nxt = {c for c in seen
                   if self.col_min <= c <= self.col_max and (c, r) not in self.instant
                   and not self.deadly(c, r, act, boat, ghosts) and not self.floor(c, r, act, boat)
                   and not self.blocked(c, r + 1, act, boat)}
            cur = nxt
            r += 1
            n += 1
        return out

    def land(self, x, y, act, dyn, moving_dir=0):
        """El player aparece en (x, y): parado si hay piso, si no cae."""
        plants, ghosts, boat = dyn
        if (x, y) in self.instant and moving_dir != 0:
            return {("instant", self.instant[(x, y)].name)}
        if self.deadly(x, y, act, boat, ghosts):
            return {("death",)}
        if self.blocked(x, y, act, boat):
            return set()  # adentro de una pared: movimiento inválido
        if self.floor(x, y, act, boat):
            return {("stand", x, y)}
        return self.fall(x, y, act, dyn, moving_dir)

    def moves(self, x, y, act, dyn):
        """Eventos alcanzables con una acción desde parado en (x, y).
        Devuelve lista de (evento, dyn_nuevo, etiqueta)."""
        plants, ghosts, boat = dyn
        res = []
        # Caminar
        for d in (-1, 1):
            if not self.blocked(x + d, y, act, boat):
                for ev in self.land(x + d, y, act, dyn, d):
                    res.append((ev, dyn, "walk"))
        # Construir y bajarse por un costado
        if act & BIT.get("blocks", 0):
            limit = ROW_MAX if act & BIT.get("reach", 0) else MAX_BLOCKS
            for k in range(1, limit + 1):
                h = y - k
                if h < self.row_min or self.blocked(x, h, act, boat):
                    break
                if self.deadly(x, h, act, boat, ghosts):
                    res.append((("death",), dyn, f"build{k}"))
                    break
                if (x, h) in self.instant:
                    res.append((("instant", self.instant[(x, h)].name), dyn, f"build{k}"))
                    break
                for d in (-1, 1):
                    if not self.blocked(x + d, h, act, boat):
                        for ev in self.land(x + d, h, act, dyn, d):
                            res.append((ev, dyn, f"build{k}"))
        # Teleport
        if act & BIT.get("teleport", 0):
            res += self._teleport(x, y, act, dyn)
        # Bote
        if boat and y == self.boat_rider_row(boat) and x in self.boat_cols(boat):
            res += self._launch(x, y, act, dyn)
        # Morir a propósito contra un fantasma (si su recorrido pasa al lado)
        gc = self.ghost_cells(ghosts)
        if any((x + d, y + e) in gc for d in (-1, 0, 1) for e in (-1, 0, 1)):
            res.append((("death",), dyn, "ghost"))
        return res

    def _teleport(self, x, y, act, dyn):
        plants, ghosts, boat = dyn
        res = []
        ray_y = y * TILE + 9
        for d in (-1, 1):
            c = x + d
            while self.col_min <= c <= self.col_max:
                hit = None
                for i, (ppx, ppy) in enumerate(plants):
                    if int(ppx // TILE) == c and ppy + 1 - 7 <= ray_y <= ppy + 1 + 7:
                        hit = ("plant", i)
                        break
                if hit is None:
                    for i, g in enumerate(ghosts):
                        if (c, y) in self._ghost_segment(i, g):
                            hit = ("ghost", i)
                            break
                if hit:
                    if hit[0] == "plant":
                        ppx, ppy = plants[hit[1]]
                        nx, ny = c, int((ppy + 2) // TILE)
                        new_plants = list(plants)
                        new_plants[hit[1]] = (x * TILE + 8, y * TILE + 8)
                        ndyn = (tuple(sorted(new_plants)), ghosts, boat)
                    else:
                        # El fantasma queda donde estaba el player; no se sigue su nueva
                        # posición (explota la cantidad de estados): se lo deja en su recorrido.
                        nx, ny = c, y
                        ndyn = dyn
                    for ev in self.land(nx, ny, act, ndyn, 0):
                        res.append((ev, ndyn, f"teleport-{hit[0]}"))
                    break
                if self.tile(c, y) != " " or (boat and self.blocked(c, y, act, boat)):
                    break
                c += d
        return res

    def _launch(self, x, y, act, dyn):
        plants, ghosts, boat = dyn
        res = []
        bx, by = boat
        top = by + 2
        rows = range(int(top // TILE), int((top + 6 - 0.01) // TILE) + 1)
        cols = list(self.boat_cols(boat))
        for d in (-1, 1):
            edge = cols[0] if d < 0 else cols[-1]
            c = edge + d
            if any(self.tile(c, r) != " " for r in rows):
                continue  # no hay lugar: camina normal
            path = []
            while self.col_min <= c <= self.col_max and not any(self.tile(c, r) != " " for r in rows):
                path.append(c)
                c += d
            if not (self.col_min <= c <= self.col_max):
                # Avanza sin chocar: se va de la pantalla con el player (salvo puerta instantánea)
                off = x - edge
                ev = next((("instant", self.instant[(pc + off, y)].name)
                           for pc in range(edge + d, edge + d * 80, d)
                           if (pc + off, y) in self.instant), ("void",))
                res.append((ev, dyn, "boat"))
                continue
            # Frena pegado al tile en la columna c
            nbx = (c + 1) * TILE + 14 if d < 0 else c * TILE - 14
            nboat = (nbx, by)
            shift = int(round((nbx - bx) / TILE))
            px = x + shift
            ev = None
            for pc in range(x + d, px + d, d):
                if (pc, y) in self.instant:
                    ev = ("instant", self.instant[(pc, y)].name)
                    break
            ndyn = (plants, ghosts, nboat)
            res.append((ev or ("stand", px, y), ndyn, "boat"))
        return res


# --- Exploración global ---------------------------------------------------------------------

class Game:
    def __init__(self, args):
        self.rooms, self.by_uid = load_rooms()
        self.sims = {p: RoomSim(r, self.by_uid) for p, r in self.rooms.items()}
        self.args = args
        self.warnings = []
        self._move_cache = {}
        # Rooms donde el spawn depende de por qué puerta se salió la última vez
        # (alguna puerta llega desde una room a la que ninguna puerta de ésta vuelve).
        self.ambiguous = set()
        for src, r in self.rooms.items():
            for d in r.of_kind("door"):
                tp = resolve_target(d.props.get("target_scene", ""), self.by_uid)
                if tp in self.rooms and not self._candidates(tp, src):
                    self.ambiguous.add(tp)
                    self.warnings.append(
                        f"{self.short(tp)}: ninguna puerta vuelve a {self.short(src)}; viniendo de "
                        f"ahí aparece en la última puerta por la que salió de {self.short(tp)}")
        self.post_goal = self._post_goal_rooms()
        if self.post_goal:
            # La parte final es de un solo sentido a propósito: no avisar que no se vuelve
            names = {self.short(r) for r in self.post_goal}
            self.warnings = [w for w in self.warnings if w.split(":", 1)[0] not in names]

    def _door_graph(self):
        """{room: {rooms a las que lleva alguna puerta}} sin mirar habilidades (con el laberinto)."""
        g = {r: set() for r in self.rooms}
        for src, r in self.rooms.items():
            for d in r.of_kind("door"):
                t = d.props.get("target_scene", "")
                if t == "-1" and src in MAZE_ROOMS:
                    step = MAZE_ROOMS.index(src)
                    g[src].add(MAZE_ROOMS[0])
                    nxt = MAZE_FINAL if step == len(MAZE_ROOMS) - 1 else MAZE_ROOMS[step + 1]
                    if nxt in self.rooms:
                        g[src].add(nxt)
                    continue
                tp = resolve_target(t, self.by_uid)
                if tp is None and t in self.args.fix:
                    tp = self.args.fix[t]
                if tp in self.rooms:
                    g[src].add(tp)
        return g

    def _post_goal_rooms(self):
        """Rooms "después del objetivo": se llega desde el objetivo pero desde ellas ya no se
        puede volver a él (p. ej. la parte final tras salir del laberinto). Estar ahí cuenta
        como haber llegado, no como estar encerrado."""
        goal = self.args.goal
        if goal not in self.rooms:
            return set()
        g = self._door_graph()
        def reach(start, graph):
            seen, stack = {start}, [start]
            while stack:
                for m in graph[stack.pop()]:
                    if m not in seen:
                        seen.add(m)
                        stack.append(m)
            return seen
        rev = {r: set() for r in g}
        for a, bs in g.items():
            for b in bs:
                rev[b].add(a)
        return reach(goal, g) - reach(goal, rev)

    def short(self, path):
        return path.rsplit("/", 1)[-1].removesuffix(".tscn")

    def spawn_entry(self, room_path, door):
        """(respawn_px, dyn) al entrar a una room por `door` (None: posición inicial)."""
        sim = self.sims[room_path]
        boat = sim.boat0
        if door is None:
            pos = self.rooms[room_path].player_start
        elif door.props.get("use_spawn_point"):
            pos = door.props["spawn_point"]
        else:
            pos = (door.pos[0], door.pos[1] + 10 - 8)
        if door is not None and door.props.get("with_boat") and boat:
            if door.props.get("use_boat_point"):
                boat = door.props["boat_point"]
            else:
                boat = (pos[0], pos[1] + 8 - 2)
        return pos, boat

    def _candidates(self, target, source):
        return [d for d in self.rooms[target].of_kind("door")
                if resolve_target(d.props.get("target_scene", ""), self.by_uid) == source]

    def entries_for(self, target, source, mem):
        """Puertas de `target` por las que aparece el player viniendo de `source`
        (Global.find_spawn_door). mem: {room: última puerta por la que salió}."""
        cands = self._candidates(target, source)
        saved = dict(mem).get(target)
        if cands:
            if len(cands) > 1:
                pick = [d for d in cands if d.name == saved]
                if pick:
                    return pick
                self.warnings.append(
                    f"{self.short(target)}: varias puertas vuelven a {self.short(source)} "
                    f"({', '.join(d.name for d in cands)}); se prueban todas")
            return cands
        # Sin candidata: la última puerta por la que salió de target (o la posición inicial)
        door = next((d for d in self.rooms[target].of_kind("door") if d.name == saved), None)
        return [door]

    def initial_node(self, room_path, door, act, solved, mem=()):
        sim = self.sims[room_path]
        pos, raw_boat = self.spawn_entry(room_path, door)
        dyn = self.reset_dyn(room_path, raw_boat, act)
        # resp: dónde reaparece, cómo arranca el bote (morir recarga la room) y la
        # puerta por la que apareció (si está bajo el agua, sin hydro sale por ella)
        resp = (self._px_cell(pos), raw_boat, door.name if door is not None else None)
        return (room_path, resp, act, solved, dyn, None, mem)  # posición se resuelve al expandir

    def reset_dyn(self, room_path, raw_boat, act):
        """Estado dinámico de la room recién cargada (plantas, fantasmas y bote en su lugar)."""
        sim = self.sims[room_path]
        return (sim.plants0, sim.ghosts0, sim.boat_settle(raw_boat, act & BIT.get("hydro", 0)))

    @staticmethod
    def _px_cell(pos):
        # centro del player = origen + 2 (collider)
        return (int(pos[0] // TILE), int((pos[1] + 2) // TILE))

    def land_events(self, room, cell, act, dyn):
        return self.sims[room].land(cell[0], cell[1], act, dyn, 0)

    def cached_moves(self, room, x, y, act, dyn):
        key = (room, x, y, act & (BIT.get("blocks", 0) | BIT.get("reach", 0) | BIT.get("eat", 0)
                                  | BIT.get("hydro", 0) | BIT.get("teleport", 0)), dyn)
        r = self._move_cache.get(key)
        if r is None:
            r = self.sims[room].moves(x, y, key[3], dyn)
            self._move_cache[key] = r
        return r

    def run(self):
        start_solved = 0
        for a in self.args.assume:
            start_solved |= BIT[a]
        start_act = start_solved
        goal_room = self.args.goal

        # Nodo = (room, respawn_cell, act, solved, dyn, pos)  pos=(x,y) parado
        # Los nodos "de entrada" tienen pos=None y se resuelven a su caída.
        ids = {}
        nodes = []
        succ = []
        cost = []  # cost[i][k]: segundos estimados de la arista succ[i][k]
        parent = []
        labels = []

        def nid(node, par, label):
            i = ids.get(node)
            if i is None:
                i = len(nodes)
                ids[node] = i
                nodes.append(node)
                succ.append([])
                cost.append([])
                parent.append(par)
                labels.append(label)
                queue.append(i)
            return i

        queue = deque()
        start = self.initial_node(START_ROOM, None, start_act, start_solved)
        nid(start, None, "start")
        void_nodes = set()  # nodos "colgados" (cayó al vacío / se fue de pantalla)
        self.broken = set()
        self.maze_seen = {}
        visited_altars = set()

        while queue:
            i = queue.popleft()
            if nodes[i][0] == "VOID":
                continue
            if self.args.verbose and i and i % 20000 == 0:
                from collections import Counter
                cnt = Counter(self.short(nd[0]) for nd in nodes if nd[0] != "VOID")
                print(f"  ... {i} nodos, por room: {cnt.most_common(6)}", file=sys.stderr)
            room, resp, act, solved, dyn, pos, mem = nodes[i]
            sim = self.sims[room]
            if pos is None:
                if resp[2] and resp[0] in sim.water and not act & BIT.get("hydro", 0):
                    # Aparece en una puerta bajo el agua sin hydro: se ahoga y sale por ella
                    evs = [(("door", resp[2]), dyn, "ahogado al aparecer")]
                else:
                    # Aparecer en resp
                    evs = [(ev, dyn, "spawn") for ev in sim.land(resp[0][0], resp[0][1], act, dyn, 0)]
            else:
                evs = list(self.cached_moves(room, pos[0], pos[1], act, dyn))
                # Interacciones parado
                if pos in sim.altars and resp[0] != pos:
                    # Usar un altar (aunque no cambie nada) lo vuelve el respawn de la room
                    evs.append((("set", act, solved), dyn, "usar altar"))
                for kind, num, aname in sim.altars.get(pos, []):
                    if kind != 0:
                        # Altar de pista: si su puzzle ya está resuelto, prende/apaga esa habilidad
                        ab = PUZZLES.get(HINTS.get(num))
                        if ab in BIT and solved & BIT[ab] and ab not in self.args.no_toggle:
                            evs.append((("set", act ^ BIT[ab], solved), dyn, f"toggle {ab} (pista {num})"))
                        continue
                    ab = PUZZLES.get(num)
                    if ab is None or ab not in BIT:
                        self.warnings.append(f"{self.short(room)}: altar {num} sin puzzle/habilidad válida")
                        continue
                    visited_altars.add(num)
                    b = BIT[ab]
                    if solved & b:
                        if ab not in self.args.no_toggle:
                            evs.append((("set", act ^ b, solved), dyn, f"toggle {ab}"))
                    else:
                        evs.append((("set", act | b, solved | b), dyn, f"altar {num} ({ab})"))
                if pos in sim.sister and "zahori" in BIT and not solved & BIT["zahori"]:
                    b = BIT["zahori"]
                    evs.append((("set", act | b, solved | b), dyn, "hermana (zahori)"))
                for door in sim.doors.get(pos, []):
                    evs.append((("door", door.name), dyn, f"puerta {door.name}"))

            for ev, ndyn, label in evs:
                kind = ev[0]
                if kind == "stand":
                    j = nid((room, resp, act, solved, ndyn, (ev[1], ev[2]), mem), i, label)
                elif kind == "death":
                    # Morir recarga la room: todo vuelve a como estaba al entrar
                    j = nid((room, resp, act, solved, self.reset_dyn(room, resp[1], act), None, mem),
                            i, label + " → muere")
                elif kind == "set":
                    nact, nsolved = ev[1], ev[2]
                    # Cambiar hydro cambia el agua de la room al instante (y el bote)
                    ndyn2 = ndyn
                    if (nact ^ act) & BIT.get("hydro", 0) and ndyn[2]:
                        ndyn2 = (ndyn[0], ndyn[1], sim.boat_settle(ndyn[2], nact & BIT["hydro"]))
                    # Usar un altar mueve el respawn de la room a ese altar
                    nresp = (pos, resp[1], None) if label.startswith(("altar", "toggle", "usar altar")) else resp
                    j = nid((room, nresp, nact, nsolved, ndyn2, pos, mem), i, label)
                elif kind == "void":
                    j = nid(("VOID", room), i, label + " → cae al vacío / sale de pantalla")
                    void_nodes.add(j)
                elif kind in ("door", "instant"):
                    door = next(d for d in self.rooms[room].of_kind("door") if d.name == ev[1])
                    targets = self.door_targets(room, door, act, mem)
                    if not targets:
                        continue
                    nmem = mem
                    if room in self.ambiguous and door.props.get("target_scene") != "-1":
                        nmem = tuple(sorted({**dict(mem), room: door.name}.items()))
                    for troom, tdoor, note in targets:
                        n2 = self.initial_node(troom, tdoor, act, solved, nmem)
                        j = nid(n2, i, f"{label}{note} → {self.short(troom)}")
                        succ[i].append(j)
                        cost[i].append(self.edge_cost(label, kind))
                    continue
                else:
                    continue
                succ[i].append(j)
                cost[i].append(self.edge_cost(label, kind))

        self.cost = cost
        self.nodes, self.succ, self.parent, self.labels = nodes, succ, parent, labels
        self.void_nodes = void_nodes
        self.visited_altars = visited_altars
        return self.analyze(goal_room)

    def edge_cost(self, label, kind):
        """Segundos que tarda un player que sabe qué hacer en dar ese paso."""
        if kind == "door":
            return DOOR_TIME
        if kind == "instant":
            return 0.3
        if kind == "death":
            return 1.5
        if kind == "set":
            if label.startswith("altar"):
                return self.args.puzzle_time
            if label.startswith("hermana"):
                return SISTER_TIME
            return TOGGLE_TIME
        if label == "walk":
            return TILE / SPEED
        if label.startswith("build"):
            return int(label[5:]) * BUILD_INTERVAL + 0.3
        if label.startswith("teleport"):
            return 0.8
        if label == "boat":
            return 3.0
        return 0.0

    def door_targets(self, room, door, act, mem):
        target = door.props.get("target_scene", "")
        if target == "-1":
            if room not in MAZE_ROOMS:
                self.broken.add((room, door.name, target))
                return []
            step = MAZE_ROOMS.index(room)
            out = [(MAZE_ROOMS[0], None, " (laberinto: errada)")]
            nxt = MAZE_FINAL if step == len(MAZE_ROOMS) - 1 else MAZE_ROOMS[step + 1]
            if nxt and (act & BIT.get("zahori", 0) or self.args.maze_luck):
                self.maze_seen.setdefault(room, set()).add(door.name)
                out.append((nxt, None, " (laberinto: correcta)"))
            return out
        tp = resolve_target(target, self.by_uid)
        if tp is None and target in self.args.fix:
            tp = self.args.fix[target]
        if tp is None or tp not in self.rooms:
            self.broken.add((room, door.name, target))
            return []
        return [(tp, d, "") for d in self.entries_for(tp, room, mem)]

    # --- Análisis ---
    def is_goal(self, node):
        return node[0] == self.args.goal or node[0] in self.post_goal

    def path_to(self, i):
        steps = []
        while i is not None:
            steps.append(i)
            i = self.parent[i]
        steps.reverse()
        return steps

    def describe_path(self, i):
        """Camino compacto: rooms recorridas y habilidades conseguidas."""
        out = []
        last_room = None
        for s in self.path_to(i):
            node = self.nodes[s]
            lab = self.labels[s]
            room = node[0]
            if room == "VOID":
                out.append(lab)
                continue
            if room != last_room:
                out.append(self.short(room))
                last_room = room
            if lab.startswith(("altar", "toggle", "hermana", "usar altar")):
                out.append(f"[{lab}]")
        return " → ".join(out)

    def print_time_estimate(self, goal_ids):
        """Dijkstra con los costos de cada paso: el recorrido más rápido sabiendo todo."""
        import heapq
        n = len(self.nodes)
        dist = [math.inf] * n
        via = [None] * n
        dist[0] = 0.0
        heap = [(0.0, 0)]
        goals = set(goal_ids)
        end = None
        while heap:
            d, i = heapq.heappop(heap)
            if d > dist[i]:
                continue
            if i in goals:
                end = i
                break
            for j, c in zip(self.succ[i], self.cost[i]):
                if d + c < dist[j]:
                    dist[j] = d + c
                    via[j] = i
                    heapq.heappush(heap, (d + c, j))
        if end is None:
            return
        # Desglose
        parts = {"moverse": 0.0, "puertas": 0.0, "puzzles": 0.0, "hermana": 0.0, "otros": 0.0}
        doors = rooms = 0
        j = end
        while via[j] is not None:
            i = via[j]
            c = self.cost[i][self.succ[i].index(j)]
            lab = self.labels[j]
            if self.nodes[j][0] != self.nodes[i][0]:
                parts["puertas"] += c
                doors += 1
            elif lab.startswith("altar"):
                parts["puzzles"] += c
            elif lab.startswith("hermana"):
                parts["hermana"] += c
            elif lab.startswith(("walk", "build", "teleport", "boat")):
                parts["moverse"] += c
            else:
                parts["otros"] += c
            j = i
        intro = INTRO_READ_TIME + INTRO2_TIME
        total = dist[end] + intro
        fmt = lambda t: f"{int(t // 60)}:{int(t % 60):02d}"
        print(f"\nDuración del recorrido más rápido (sabiendo todo, {doors} cruces de puerta):")
        print(f"  {fmt(total)}  = moverse {fmt(parts['moverse'])} + puertas {fmt(parts['puertas'])}"
              f" + puzzles {fmt(parts['puzzles'])} ({self.args.puzzle_time:.0f} s c/u)"
              f" + hermana {fmt(parts['hermana'])} + intro {fmt(intro)} + otros {fmt(parts['otros'])}")
        # Primera partida: se explora (rooms de más, idas y vueltas, muertes) y se
        # piensan los puzzles. Factores a ojo, para dar un rango.
        n_puzzles = len(PUZZLES)
        n_hints = len(list((ROOT / "puzzles").glob("hint_*.tres")))
        base = intro + SISTER_TIME + n_hints * 20
        move = parts["moverse"] + parts["puertas"]
        lo = base + move * 5 + n_puzzles * 120
        hi = base + move * 10 + n_puzzles * 300
        print(f"  Primera partida estimada: {fmt(lo)} a {fmt(hi)} (exploración/muertes x5-x10, los"
              f" {n_puzzles} puzzles a 2-5 min c/u, leer {n_hints} pistas)")

    def _depths(self):
        depth = [0] * len(self.nodes)
        for i, p in enumerate(self.parent):
            if p is not None:
                depth[i] = depth[p] + 1  # los padres siempre tienen índice menor (BFS)
        return depth

    def _rooms_from(self, j):
        seen = {j}
        dq = deque([j])
        rooms = set()
        while dq:
            k = dq.popleft()
            if self.nodes[k][0] != "VOID":
                rooms.add(self.nodes[k][0])
            for m in self.succ[k]:
                if m not in seen:
                    seen.add(m)
                    dq.append(m)
        return rooms

    def analyze(self, goal_room):
        n = len(self.nodes)
        pred = [[] for _ in range(n)]
        for i, ss in enumerate(self.succ):
            for j in ss:
                pred[j].append(i)
        good = [False] * n
        self.good = good
        dq = deque(i for i in range(n) if self.is_goal(self.nodes[i]))
        for i in dq:
            good[i] = True
        while dq:
            j = dq.popleft()
            for i in pred[j]:
                if not good[i]:
                    good[i] = True
                    dq.append(i)

        a = self.args
        ok = True
        print(f"Nodos explorados: {n}  (rooms: {len(self.rooms)}, max_blocks={MAX_BLOCKS})")
        visited_rooms = {nd[0] for nd in self.nodes if nd[0] != "VOID"}
        unvisited = sorted(self.short(p) for p in self.rooms if p not in visited_rooms)
        print(f"Rooms alcanzables: {len(visited_rooms)}/{len(self.rooms)}"
              + (f"   NO alcanzables: {', '.join(unvisited)}" if unvisited else ""))
        all_solved = 0
        for nd in self.nodes:
            if nd[0] != "VOID":
                all_solved |= nd[3]
        missing = [x for x in ABILITIES if not all_solved & BIT[x]]
        print(f"Habilidades obtenibles: {', '.join(names(all_solved))}"
              + (f"   NUNCA: {', '.join(missing)}" if missing else ""))
        for room, r in self.rooms.items():
            for d in r.of_kind("door"):
                t = d.props.get("target_scene", "")
                if t == "-1" and room in MAZE_ROOMS:
                    continue
                if resolve_target(t, self.by_uid) not in self.rooms and t not in a.fix:
                    self.broken.add((room, d.name, t))
        if self.broken:
            print("Puertas a escenas inexistentes:")
            for room, dn, t in sorted(self.broken):
                print(f"  {self.short(room)}.{dn} → '{t}'")
        for room in MAZE_ROOMS:
            if room in self.rooms and room in visited_rooms:
                total = {d.name for d in self.rooms[room].of_kind("door") if d.props.get("target_scene") == "-1"}
                seen = self.maze_seen.get(room, set())
                if seen and seen != total and a.verbose:
                    print(f"  laberinto {self.short(room)}: puertas inalcanzables {sorted(total - seen)}")

        goal_ids = [i for i in range(n) if self.is_goal(self.nodes[i])]
        if not goal_ids:
            ok = False
            print(f"\n✗ El objetivo ({self.short(goal_room)}) NO es alcanzable.")
        else:
            best = min(goal_ids, key=lambda i: len(self.path_to(i)))
            if self.post_goal:
                print(f"\n  Después del objetivo, sin vuelta (cuentan como llegada): "
                      f"{', '.join(sorted(self.short(r) for r in self.post_goal))}")
            print(f"\n✓ Objetivo ({self.short(goal_room)}) alcanzable. Un camino:")
            print("  " + self.describe_path(best))
            self.print_time_estimate(goal_ids)

            # Jugadas fatales: de un nodo ganable a uno perdido. Se agrupan por "trampa":
            # las rooms a las que todavía se puede llegar desde el estado perdido + habilidades.
            depth = self._depths()
            traps = {}
            sig_cache = {}
            for i in range(n):
                if not good[i]:
                    continue
                for j in self.succ[i]:
                    if good[j]:
                        continue
                    tgt = self.nodes[j]
                    src = self.nodes[i][0]
                    if tgt[0] == "VOID":
                        sig = ("VOID", src)
                    else:
                        k = (tgt[0], tgt[2], tgt[3], tgt[6])
                        if k not in sig_cache:
                            sig_cache[k] = frozenset(self._rooms_from(j))
                        sig = (sig_cache[k], src)
                    cur = traps.get(sig)
                    if cur is None:
                        traps[sig] = [i, j, set()]
                    elif depth[i] < depth[cur[0]]:
                        cur[0], cur[1] = i, j
                    traps[sig][2].add(self.nodes[i][2])
            if traps:
                ok = False
                print(f"\n✗ Soft-locks: {len(traps)} trampas distintas (estados alcanzables desde los que "
                      f"ya no se llega a {self.short(goal_room)}):")
                items = sorted(traps.items(), key=lambda kv: depth[kv[1][0]])
                for sig, (i, j, acts) in items:
                    if sig[0] == "VOID":
                        continue
                    node = self.nodes[i]
                    where = f"en ({node[5][0]},{node[5][1]})" if node[5] else "al entrar"
                    rooms = ", ".join(sorted(self.short(r) for r in sig[0]))
                    print(f"\n  * {self.short(node[0])} {where}, hab=[{','.join(names(node[2]))}]: "
                          f"{self.labels[j]}")
                    print(f"    → queda encerrado en [{rooms}]")
                    if len(acts) > 1:
                        print(f"    (también con otras {len(acts) - 1} combinaciones de habilidades)")
                    print(f"    camino: {self.describe_path(i)}")
                voids = [(sig, v) for sig, v in items if sig[0] == "VOID"]
                if voids:
                    print("\n  * Caídas fuera de la pantalla (sin killer debajo: cae para siempre):")
                    for sig, (i, j, acts) in voids:
                        node = self.nodes[i]
                        where = f"({node[5][0]},{node[5][1]})" if node[5] else "al entrar"
                        print(f"    - {self.short(node[0])} {where} hab=[{','.join(names(node[2]))}]: "
                              f"{self.labels[j].split(' →')[0]}")
                        if a.verbose:
                            print(f"      camino: {self.describe_path(i)}")
            else:
                print("\n✓ Sin soft-locks: desde todo estado alcanzable se puede llegar al objetivo.")
        if self.void_nodes and a.verbose:
            print(f"\nCaídas al vacío alcanzables: {len(self.void_nodes)}")
        ws = sorted(set(self.warnings))
        if ws:
            print("\nAvisos:")
            for w in ws:
                print("  - " + w)
        return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default_goal = MAZE_ROOMS[-1] if MAZE_ROOMS else None
    ap.add_argument("--goal", default=default_goal,
                    help="room objetivo (nombre o res://). Por defecto la última del laberinto")
    ap.add_argument("--maze-luck", action="store_true",
                    help="permitir acertar el laberinto sin zahori")
    ap.add_argument("--assume", default="", help="habilidades con las que se arranca (coma)")
    ap.add_argument("--fix", action="append", default=[], metavar="TARGET=ROOM",
                    help="tratar target_scene=TARGET como la room ROOM (p. ej. 17=level17), "
                         "para analizar el resto mientras una puerta está rota")
    ap.add_argument("--puzzle-time", type=float, default=60.0,
                    help="segundos por puzzle de altar para el recorrido rápido (default 60)")
    ap.add_argument("--no-toggle", default="",
                    help="habilidades que no se pueden apagar en el altar (coma), para probar diseños")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.goal and not args.goal.startswith("res://"):
        args.goal = f"res://scenes/rooms/{args.goal.removesuffix('.tscn')}.tscn"
    args.assume = [a for a in args.assume.split(",") if a]
    args.no_toggle = [a for a in args.no_toggle.split(",") if a]
    args.fix = {k: f"res://scenes/rooms/{v.removesuffix('.tscn')}.tscn"
                for k, v in (f.split("=", 1) for f in args.fix)}
    ok = Game(args).run()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
