"""Genera el ícono del juego (icon.png e icon.ico) a partir del sprite idle del player."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPRITE = ROOT / "sprites" / "player_idle_spr_0.png"
SIZES = [16, 32, 48, 64, 128, 256]


def centered(sprite: Image.Image) -> Image.Image:
    """Centra el contenido del sprite en una celda cuadrada del mismo tamaño."""
    box = sprite.getbbox()
    content = sprite.crop(box)
    side = max(sprite.size)
    cell = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    cell.paste(content, ((side - content.width) // 2, (side - content.height) // 2))
    return cell


def main() -> None:
    cell = centered(Image.open(SPRITE).convert("RGBA"))
    frames = [cell.resize((s, s), Image.NEAREST) for s in SIZES]
    frames[-1].save(ROOT / "icon.png")
    frames[-1].save(ROOT / "icon.ico", sizes=[(s, s) for s in SIZES], append_images=frames[:-1])
    print(f"icon.png e icon.ico generados desde {SPRITE.name}")


if __name__ == "__main__":
    main()
