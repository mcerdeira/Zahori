"""Suma los tiles de enredadera (tools/gen_vine_tiles.py) al TileSet de una o más rooms.

Cada room tiene su TileSet embebido. También le agrega la capa BackTiles, detrás del player: ahí
van bg_vine y deco_vine_* (LevelTiles se dibuja por encima del player y lo taparía).
Se puede volver a correr: lo que ya está no se duplica.
Conviene cerrar la room en el editor antes de correrlo.

Uso: python3 tools/add_vine_tiles.py level186 level187
"""
import re
import sys
from pathlib import Path

ROOMS = Path(__file__).resolve().parent.parent / "scenes" / "rooms"
FIRST_SOURCE = 20  # ids altos para no chocar con las fuentes existentes (0..7)
SOLID = ["floor_vine", "floor_vine_alt", "floor_vine_vein", "floor_vine_top", "floor_vine_bottom",
         "floor_vine_left", "floor_vine_right", "floor_vine_tl", "floor_vine_tr", "floor_vine_bl",
         "floor_vine_br"]
DECO = ["bg_vine", "deco_vine_hang", "deco_vine_hang_end"]
BOX = "PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)"


def add_back_layer(text):
    if 'node name="BackTiles"' in text:
        return text
    tileset = re.search(r'\[node name="LevelTiles".*?tile_set = (SubResource\("[^"]+"\))', text, re.S)
    node = f'[node name="BackTiles" type="TileMapLayer" parent="."]\ntile_set = {tileset.group(1)}\n\n'
    player = text.index('[node name="Player"')
    return text[:player] + node + text[player:]


def patch(text):
    if 'id="vt_floor_vine"' in text:
        return add_back_layer(text)
    ext, sub, sources = "", "", ""
    for i, name in enumerate(SOLID + DECO):
        ext += (f'[ext_resource type="Texture2D" path="res://sprites/{name}_spr_0.png" '
                f'id="vt_{name}"]\n')
        sub += (f'[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_{name}"]\n'
                f'texture = ExtResource("vt_{name}")\n0:0/0 = 0\n')
        if name in SOLID:
            sub += f"0:0/0/physics_layer_0/polygon_0/points = {BOX}\n"
        sub += "\n"
        sources += f'sources/{FIRST_SOURCE + i} = SubResource("TileSetAtlasSource_{name}")\n'
    first_sub = text.index("[sub_resource")
    text = text[:first_sub].rstrip("\n") + "\n" + ext + "\n" + text[first_sub:]
    tileset = text.index('[sub_resource type="TileSet"')
    text = text[:tileset] + sub + text[tileset:]
    last = list(re.finditer(r"^sources/\d+ = .*\n", text, re.M))[-1]
    return add_back_layer(text[:last.end()] + sources + text[last.end():])


if __name__ == "__main__":
    for room in sys.argv[1:]:
        path = ROOMS / f"{room.removesuffix('.tscn')}.tscn"
        path.write_text(patch(path.read_text()))
        print(f"{path.name}: listo")
