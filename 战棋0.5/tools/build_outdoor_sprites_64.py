from pathlib import Path
from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT / "assets" / "outdoor_buildings_32"
OUTPUT_ROOT = PROJECT / "assets" / "outdoor_buildings_64"
GROUPS = ("fortifications", "infrastructure")


def fit_sprite(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A")
    bbox = alpha.getbbox()
    result = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    if bbox is None:
        return result
    subject = cell.crop(bbox)
    scale = min(62 / subject.width, 62 / subject.height)
    size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(size, Image.Resampling.NEAREST)
    x = (64 - subject.width) // 2
    y = 63 - subject.height
    result.alpha_composite(subject, (x, y))
    return result


for group in GROUPS:
    source_path = SOURCE_ROOT / f"{group}_source_transparent.png"
    source = Image.open(source_path).convert("RGBA")
    output_dir = OUTPUT_ROOT / group
    output_dir.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    for row in range(4):
        for col in range(4):
            left = round(col * source.width / 4)
            top = round(row * source.height / 4)
            right = round((col + 1) * source.width / 4)
            bottom = round((row + 1) * source.height / 4)
            sprite = fit_sprite(source.crop((left, top, right, bottom)))
            index = row * 4 + col + 1
            sprite.save(output_dir / f"{group}_{index:02d}.png")
            sheet.alpha_composite(sprite, (col * 64, row * 64))
    sheet.save(OUTPUT_ROOT / f"{group}_64.png")

