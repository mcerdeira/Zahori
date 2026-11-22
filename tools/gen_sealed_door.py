"""Genera el sprite de la puerta sellada (12x20, como las puertas normales; paleta
gameboy-color-type1) en sprites/door_sealed_spr_0.png.

Es la puerta por la que se llega a level182 desde el laberinto, cerrada para siempre:
una losa de piedra oscura con grietas, atravesada por enredaderas.

Uso: python3 tools/gen_sealed_door.py
"""
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "sprites"
W, H = 12, 20


def C(*a):
    return a + (255,)


K = C(0, 0, 0)
D = C(82, 82, 82)       # piedra
M = C(148, 148, 148)    # piedra clara (borde iluminado)
P = C(83, 82, 140)      # sombra fría
G1 = C(0, 131, 0)
G2 = C(123, 255, 48)

# . transparente  K contorno  D piedra  M borde claro  P sombra  g/G enredadera
ROWS = [
    "KKKKKKKKKKKK",
    "KMMMMMMMMMMK",
    "KMDDDDDDDDPK",
    "KMDDDDDgDDPK",
    "KMDDDDgGDDPK",
    "KMDKDDgDDDPK",
    "KMDDKgDDDDPK",
    "KMDDgKDDDDPK",
    "KMDgGDKDDDPK",
    "KMgDDDDKDDPK",
    "KMDgDDDDKDPK",
    "KMDDgDDDDKPK",
    "KMDDDgDDDDPK",
    "KMDDDDgDDDPK",
    "KMDDDDDgGDPK",
    "KMDDDDDDgDPK",
    "KMDDDDDgDDPK",
    "KMDDDDDDgGPK",
    "KMPPPPPPPgPK",
    "KKKKKKKKKKKK",
]
CMAP = {"K": K, "D": D, "M": M, "P": P, "g": G1, "G": G2}


def main():
    im = Image.new("RGBA", (W, H))
    px = im.load()
    for y, row in enumerate(ROWS):
        assert len(row) == W, (y, row)
        for x, ch in enumerate(row):
            px[x, y] = CMAP[ch]
    im.save(OUT / "door_sealed_spr_0.png")
    print("ok")


if __name__ == "__main__":
    main()
