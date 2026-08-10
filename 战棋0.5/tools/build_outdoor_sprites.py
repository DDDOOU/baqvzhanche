from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "assets" / "outdoor_buildings_32"
GROUPS = {
    "outdoor_buildings": "outdoor_buildings_source_transparent.png",
    "fortifications": "fortifications_source_transparent.png",
    "infrastructure": "infrastructure_source_transparent.png",
}


def trim_and_fit(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A")
    bbox = alpha.getbbox()
    result = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    if bbox is None:
        return result
    subject = cell.crop(bbox)
    max_w, max_h = 30, 30
    scale = min(max_w / subject.width, max_h / subject.height)
    size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
    subject = subject.resize(size, Image.Resampling.NEAREST)
    x = (32 - subject.width) // 2
    y = 31 - subject.height
    result.alpha_composite(subject, (x, y))
    return result


def build_group(name: str, source_name: str) -> None:
    source = Image.open(ROOT / source_name).convert("RGBA")
    cell_w, cell_h = source.width // 4, source.height // 4
    sheet = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    sprites_dir = ROOT / name
    sprites_dir.mkdir(exist_ok=True)
    for row in range(4):
        for col in range(4):
            index = row * 4 + col + 1
            crop = source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
            sprite = trim_and_fit(crop)
            sprite.save(sprites_dir / f"{name}_{index:02d}.png")
            sheet.alpha_composite(sprite, (col * 32, row * 32))
    sheet.save(ROOT / f"{name}_32.png")


for group_name, filename in GROUPS.items():
    build_group(group_name, filename)
