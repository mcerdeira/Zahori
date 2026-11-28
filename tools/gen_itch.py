"""Genera el banner y el fondo de la página de itch.io a partir de los sprites del juego.

Compone todo a la resolución del juego (pixel de 16 px por tile) y lo escala sin suavizado,
así respeta el tamaño de pixel. El título va en Pirata One, como en la pantalla de título.

Salida en marketing/itch/: banner.png (960x384) y background.png (1920x1080).
"""
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SPR = ROOT / "sprites"
OUT = ROOT / "marketing" / "itch"
FONT = ROOT / "fonts" / "PirataOne-Regular.ttf"

SCALE = 3
BASE = (10, 6, 14)
TITLE = (232, 232, 244)
EMBERS = [(255, 170, 60), (255, 110, 40), (230, 60, 30)]
FIREFLIES = [(170, 255, 140), (120, 230, 120)]


def spr(name: str) -> Image.Image:
    path = SPR / (name if name.endswith(".png") else name + ".png")
    return Image.open(path).convert("RGBA")


def tint(img: Image.Image, factor: float) -> Image.Image:
    """Oscurece un sprite (para las capas del fondo) sin tocar el alfa."""
    r, g, b, a = img.split()
    r, g, b = (c.point(lambda v: int(v * factor)) for c in (r, g, b))
    return Image.merge("RGBA", (r, g, b, a))


def put(canvas: Image.Image, img: Image.Image, x: int, y: int, flip: bool = False) -> None:
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(img, (x, y))


def pattern(size: tuple[int, int], factor: float) -> Image.Image:
    """El patrón back_itch repetido y atenuado."""
    tile = tint(spr("back_itch"), factor)
    out = Image.new("RGBA", size, BASE + (255,))
    for y in range(0, size[1], tile.height):
        for x in range(0, size[0], tile.width):
            out.alpha_composite(tile, (x, y))
    black = Image.new("RGBA", size, BASE + (255,))
    mask = Image.eval(tile.convert("L"), lambda v: 255 if v > 8 else 0)
    full_mask = Image.new("L", size, 0)
    for y in range(0, size[1], tile.height):
        for x in range(0, size[0], tile.width):
            full_mask.paste(mask, (x, y))
    return Image.composite(out, black, full_mask)


def hanging_vine(canvas: Image.Image, x: int, length: int, factor: float = 1.0, y: int = 0) -> None:
    body = tint(spr("deco_vine_hang_spr_0"), factor)
    end = tint(spr("deco_vine_hang_end_spr_0"), factor)
    for i in range(length - 1):
        put(canvas, body, x, y + i * 16)
    put(canvas, end, x, y + (length - 1) * 16)


def particles(canvas: Image.Image, rng: random.Random, count: int, colors, area, glow: bool = True) -> None:
    """Brasas y luciérnagas de 1 pixel con un halo tenue."""
    x0, y0, x1, y1 = area
    halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dots = ImageDraw.Draw(canvas)
    hd = ImageDraw.Draw(halo)
    for _ in range(count):
        x, y = rng.randrange(x0, x1), rng.randrange(y0, y1)
        c = rng.choice(colors)
        if glow:
            hd.point([(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=c + (45,))
        dots.point((x, y), fill=c + (255,))
    canvas.alpha_composite(halo)


def vignette(size: tuple[int, int], strength: float, inner: float = 0.45) -> Image.Image:
    """Máscara radial: 0 en el centro, `strength` en las esquinas."""
    w, h = size
    small = Image.new("L", (64, 36), 0)
    px = small.load()
    for y in range(36):
        for x in range(64):
            dx, dy = (x + 0.5) / 32 - 1, (y + 0.5) / 18 - 1
            d = max(0.0, (dx * dx + dy * dy) ** 0.5 - inner) / (1.42 - inner)
            px[x, y] = int(255 * min(1.0, d) * strength)
    return small.resize((w, h), Image.BICUBIC)


def darken(img: Image.Image, mask: Image.Image) -> Image.Image:
    black = Image.new("RGBA", img.size, BASE + (255,))
    return Image.composite(black, img, mask)


def title(size: tuple[int, int], text: str, font_size: int, center: tuple[int, int]) -> Image.Image:
    """Título plano con un contorno oscuro, a resolución final."""
    font = ImageFont.truetype(str(FONT), font_size)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = d.textbbox((0, 0), text, font=font)
    x = center[0] - (box[0] + box[2]) // 2
    y = center[1] - (box[1] + box[3]) // 2

    d.text((x, y), text, font=font, fill=TITLE + (255,), stroke_width=4, stroke_fill=(16, 10, 22, 255))
    return layer


LEVEL = [
    "####################",
    "#..................#",
    "#..................#",
    "#..................#",
    "#..................#",
    "#..................#",
    "########~~~~~#######",
    "####################",
]


def banner() -> Image.Image:
    """Una room armada en la grilla: paredes y piso de floor_vine_alt, nada superpuesto."""
    w, h = len(LEVEL[0]) * 16, len(LEVEL) * 16
    rng = random.Random(7)
    c = pattern((w, h), 0.45)
    c = darken(c, vignette((w, h), 0.9, 0.2))

    tile = spr("floor_vine_alt_spr_0")
    water = spr("water_sheet_spr")
    for row, line in enumerate(LEVEL):
        for col, ch in enumerate(line):
            if ch == "#":
                put(c, tile, col * 16, row * 16)
            elif ch == "~":
                put(c, water.crop((0, 0, 16, 16)) if col % 2 == 0 else water.crop((16, 0, 32, 16)), col * 16, row * 16)

    def cell(col: int, row: int) -> tuple[int, int]:
        return col * 16, row * 16

    put(c, spr("boat_spr_0"), *cell(9, 5))
    for row in (5, 4, 3):
        put(c, spr("block_green_spr_0"), *cell(4, row))
    put(c, spr("player_build_spr_0"), *cell(4, 2))
    put(c, spr("plant_spr_0"), *cell(2, 5))
    put(c, spr("altar1"), *cell(6, 5))
    put(c, spr("block_stone_spr_0"), *cell(14, 5))
    put(c, spr("block_stone_spr_0"), *cell(15, 5))
    put(c, spr("block_stone_spr_0"), *cell(15, 4))
    put(c, spr("ghost_spr_0"), 11 * 16, 4 * 16 + 6)

    for col, n in [(1, 3), (2, 2), (5, 1), (14, 1), (17, 2), (18, 3)]:
        hanging_vine(c, col * 16, n, y=16)

    particles(c, rng, 12, EMBERS, (20, 18, w - 20, 92))
    particles(c, rng, 6, FIREFLIES, (20, 30, w - 20, 92))

    big = c.resize((w * SCALE, h * SCALE), Image.NEAREST)
    big.alpha_composite(title(big.size, "Zahori", 170, (big.width // 2, 140)))
    return big.convert("RGB")


def background() -> Image.Image:
    w, h = 640, 360
    rng = random.Random(3)
    c = pattern((w, h), 0.3)

    column = Image.new("L", (w, h), 0)
    ImageDraw.Draw(column).rectangle((w // 2 - 175, 0, w // 2 + 175, h), fill=200)
    column = column.filter(ImageFilter.GaussianBlur(30))
    c = darken(c, ImageChops.lighter(column, vignette((w, h), 0.6, 0.55)))

    left = range(-4, w // 2 - 172, 9)
    right = range(w // 2 + 164, w, 9)
    for x in list(left) + list(right):
        if rng.random() < 0.7:
            hanging_vine(c, x + rng.randrange(-2, 3), rng.randint(3, 14), rng.uniform(0.2, 0.4), -rng.randrange(16))
    for x in list(left)[::2] + list(right)[::2]:
        if rng.random() < 0.6:
            hanging_vine(c, x + rng.randrange(-2, 3), rng.randint(1, 6), rng.uniform(0.65, 0.95), -rng.randrange(16))

    particles(c, rng, 60, EMBERS, (0, 0, w, h))
    particles(c, rng, 20, FIREFLIES, (0, 0, w, h))

    fade = Image.new("L", (w, h), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(h // 2, h):
        fd.line((0, y, w, y), fill=int(255 * ((y - h // 2) / (h // 2)) ** 1.5))
    c = darken(c, fade)
    return c.resize((w * SCALE, h * SCALE), Image.NEAREST).convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    banner().save(OUT / "banner.png")
    background().save(OUT / "background.png")
    print(f"generados en {OUT.relative_to(ROOT)}: banner.png, background.png (color de fondo #%02x%02x%02x)" % BASE)


if __name__ == "__main__":
    main()
