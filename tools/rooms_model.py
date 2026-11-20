#!/usr/bin/env python3
"""Lee las rooms (`scenes/rooms/*.tscn`) y arma un modelo en grilla de cada una.

Lo usa `tools/check_progression.py`. No depende de Godot: parsea el texto de las escenas.

Cada room queda como una grilla de COLS x ROWS celdas de 16 px con:
  '#'  sólido (tech / floor_*)       'S'  piedra (comestible con eat)
y una lista de entidades (puertas, altares, agua, killers, bote, fantasmas, plantas,
enredaderas, la hermana) con su rect en px y sus propiedades.
"""

import base64
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROOMS_DIR = ROOT / "scenes" / "rooms"
TILE = 16
COLS = 36  # 576 / 16
ROWS = 21  # 324 / 16 = 20.25 (la fila 20 se ve a medias)
EDIBLE_TEXTURE = "res://sprites/block_stone_spr_0.png"

# Rects de colisión de cada escena instanciada: (offset_x, offset_y, ancho, alto) en px
# relativos al origen del nodo, antes de escalar. Sacados de los .tscn de cada entidad.
SHAPES = {
    "door": (0, 0, 10, 20),
    "altar": (0, -1, 14, 18),
    "water": (0, 0, 16, 16),
    "killerobj": (0, 0, 16, 16),
    "boat": (0, 5, 28, 6),
    "ghost": (0, 0.5, 12, 13),
    "plant": (0, 1, 10, 14),
    "sister": (0, 2, 12, 24),
    "vine": (0, 0, 16, 16),
    "player": (-0.5, 2, 7, 12),
}


@dataclass
class Entity:
    kind: str  # door, altar, water, killerobj, boat, ghost, plant, sister, vine, player
    name: str
    pos: tuple  # px (x, y) del origen del nodo
    scale: tuple
    props: dict = field(default_factory=dict)

    def rect(self):
        """(x0, y0, x1, y1) en px del collider, escalado."""
        ox, oy, w, h = SHAPES[self.kind]
        sx, sy = self.scale
        cx, cy = self.pos[0] + ox * sx, self.pos[1] + oy * sy
        hw, hh = w * abs(sx) / 2, h * abs(sy) / 2
        return (cx - hw, cy - hh, cx + hw, cy + hh)

    def cells(self):
        """Celdas de la grilla que toca el rect (puede salirse de la room)."""
        x0, y0, x1, y1 = self.rect()
        eps = 0.01
        return {(cx, cy)
                for cx in range(int((x0 + eps) // TILE), int((x1 - eps) // TILE) + 1)
                for cy in range(int((y0 + eps) // TILE), int((y1 - eps) // TILE) + 1)}


@dataclass
class Room:
    path: str  # res://scenes/rooms/levelN.tscn
    name: str  # levelN
    uid: str
    grid: list  # grid[y][x] in ' ', '#', 'S'
    water_tiles: set
    entities: list
    player_start: tuple  # px

    def solid(self, x, y):
        if 0 <= y < ROWS and 0 <= x < COLS:
            return self.grid[y][x]
        return " "

    def of_kind(self, kind):
        return [e for e in self.entities if e.kind == kind]


def _vec(s):
    m = re.match(r"Vector2\(([-\d.e]+),\s*([-\d.e]+)\)", s)
    return (float(m.group(1)), float(m.group(2)))


def _value(s):
    s = s.strip()
    if s.startswith("Vector2("):
        return _vec(s)
    if s.startswith('"') or s.startswith('&"'):
        return s.split('"')[1]
    if s in ("true", "false"):
        return s == "true"
    try:
        return float(s) if "." in s else int(s)
    except ValueError:
        return s


def _decode_tiles(data_b64):
    raw = base64.b64decode(data_b64)
    cells = []
    for i in range(2, len(raw) - 11, 12):  # 2 bytes de versión, 12 por celda
        x, y, src, ax, ay, alt = struct.unpack("<hhHHHH", raw[i:i + 12])
        cells.append((x, y, src))
    return cells


def parse_room(path: Path) -> Room:
    text = path.read_text()
    uid = re.search(r'\[gd_scene[^\]]*uid="([^"]+)"', text).group(1)
    ext = {m.group(2): m.group(1) for m in
           re.finditer(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', text)}
    # Secciones: [header] + líneas de propiedades
    sections = []
    for block in re.split(r"\n(?=\[)", text):
        lines = block.strip().split("\n")
        head = lines[0]
        props = {}
        for ln in lines[1:]:
            if " = " in ln:
                k, v = ln.split(" = ", 1)
                props[k.strip()] = v
        sections.append((head, props))

    # Texturas de cada atlas y fuentes del tileset
    atlas_tex = {}
    tileset_sources = {}
    for head, props in sections:
        m = re.match(r'\[sub_resource type="TileSetAtlasSource" id="([^"]+)"', head)
        if m:
            tm = re.search(r'ExtResource\("([^"]+)"\)', props.get("texture", ""))
            atlas_tex[m.group(1)] = ext.get(tm.group(1), "") if tm else ""
            # ¿tiene colisión?
            atlas_tex[m.group(1) + ":solid"] = any("physics_layer" in k for k in props)
        m = re.match(r'\[sub_resource type="TileSet"', head)
        if m:
            for k, v in props.items():
                sm = re.match(r"sources/(\d+)", k)
                if sm:
                    tileset_sources[int(sm.group(1))] = re.search(r'SubResource\("([^"]+)"\)', v).group(1)

    grid = [[" "] * COLS for _ in range(ROWS)]
    water_tiles = set()
    entities = []
    player_start = (0.0, 0.0)
    for head, props in sections:
        m = re.match(r'\[node name="([^"]+)"', head)
        if not m:
            continue
        name = m.group(1)
        if 'type="TileMapLayer"' in head and "tile_map_data" in props:
            data = re.search(r'PackedByteArray\("([^"]*)"\)', props["tile_map_data"]).group(1)
            for x, y, src in _decode_tiles(data):
                sub = tileset_sources.get(src)
                tex = atlas_tex.get(sub, "")
                solid = atlas_tex.get(f"{sub}:solid", False)
                if not (0 <= x < COLS and 0 <= y < ROWS):
                    continue
                if Path(tex).name.startswith("water"):
                    water_tiles.add((x, y))
                elif solid:
                    grid[y][x] = "S" if tex == EDIBLE_TEXTURE else "#"
            continue
        im = re.search(r'instance=ExtResource\("([^"]+)"\)', head)
        if not im:
            continue
        kind = Path(ext.get(im.group(1), "")).stem
        if kind not in SHAPES:
            continue
        p = {k: _value(v) for k, v in props.items()}
        pos = p.pop("position", (0.0, 0.0))
        scale = p.pop("scale", (1.0, 1.0))
        if kind == "player":
            player_start = pos
            continue
        entities.append(Entity(kind, name, pos, scale, p))
    return Room(f"res://scenes/rooms/{path.name}", path.stem, uid, grid, water_tiles,
                entities, player_start)


def load_rooms():
    rooms = {}
    for p in sorted(ROOMS_DIR.glob("level*.tscn")):
        r = parse_room(p)
        rooms[r.path] = r
    by_uid = {r.uid: r.path for r in rooms.values()}
    return rooms, by_uid


def resolve_target(target, by_uid):
    """Ruta res:// de un target_scene (uid o ruta). None si no existe la escena."""
    if not target:
        return None
    if target.startswith("uid://"):
        return by_uid.get(target)
    if target.startswith("res://"):
        return target
    return None


if __name__ == "__main__":
    import sys
    rooms, _ = load_rooms()
    for r in rooms.values():
        if len(sys.argv) > 1 and r.name not in sys.argv[1:]:
            continue
        print(f"== {r.name}  start={r.player_start}")
        marks = {}
        for e in r.entities:
            ch = {"door": "D", "altar": "A", "water": "~", "killerobj": "x", "boat": "B",
                  "ghost": "G", "plant": "P", "sister": "H", "vine": "V"}[e.kind]
            if e.kind == "door" and e.props.get("instant"):
                ch = "I"
            for c in e.cells():
                marks.setdefault(c, ch)
        for y in range(ROWS):
            print("".join(marks.get((x, y), r.grid[y][x]) for x in range(COLS)))
        for e in r.entities:
            print("  ", e.kind, e.name, e.pos, e.props)
