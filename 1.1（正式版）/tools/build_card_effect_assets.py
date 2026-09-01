"""Build crisp, transparent four-frame card-effect sheets from the AI master.

The master keeps the approved visual direction. This script removes the magenta
key, slices the 10 x 4 layout, normalizes every ground anchor, then performs a
two-pixel nearest-neighbour treatment so the effects remain readable beside the
project's 32 px terrain and building art.
"""

from __future__ import annotations

import colorsys
import json
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT_ROOT / "assets/effects/card_effects/_source/card_fx_master_magenta.png"
OUTPUT_DIR = PROJECT_ROOT / "assets/effects/card_effects"
SOURCE_DIR = OUTPUT_DIR / "_source"

# These effects previously inherited accidental vehicle silhouettes from the
# generated master. Keep their vehicle-free source strips separate so rebuilding
# the atlas cannot reintroduce trucks, tanks, or holographic vehicle outlines.
SOURCE_OVERRIDES = {
    "sapper_mines": SOURCE_DIR / "sapper_mines_no_vehicle.png",
    "reserve_deployment": SOURCE_DIR / "reserve_deployment_no_vehicle.png",
    "false_report": SOURCE_DIR / "false_report_no_vehicle.png",
}

# Persistent effects hold their final frame until the underlying gameplay state
# disappears. Other card animations remain short one-shot feedback.
PERSISTENCE = {
    "smoke_screen": "smoke",
    "sapper_mines": "mines",
}

# Order must match the ten rows in the generated master.
EFFECTS = (
    ("call_artillery", 128, 128, 2, 2, 0.88),
    ("blind_fire_barrage", 192, 112, 3, 3, 0.91),
    ("smoke_screen", 256, 128, 4, 4, 0.92),
    ("sapper_mines", 128, 80, 2, 1, 0.91),
    ("coordinate_prediction", 80, 72, 1, 1, 0.90),
    ("fortify_position", 96, 88, 1, 1, 0.92),
    ("sacrifice_charge", 80, 88, 1, 1, 0.92),
    ("power_cut", 96, 88, 1, 1, 0.91),
    ("reserve_deployment", 96, 88, 1, 1, 0.92),
    ("false_report", 96, 80, 1, 1, 0.91),
)

# The image model keeps the requested row order but allows tall effects to use
# slightly different vertical spacing. These measured boundaries avoid slicing
# smoke or sparks from a neighbouring row into another effect.
ROW_BOUNDS = (0, 174, 335, 500, 630, 785, 943, 1100, 1218, 1370, 1536)


def remove_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = list(rgba.getdata())
    cleaned: list[tuple[int, int, int, int]] = []
    for red, green, blue, _alpha in pixels:
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        degrees = hue * 360.0
        is_key = (
            286.0 <= degrees <= 345.0
            and saturation >= 0.24
            and value >= 0.45
            and red > 105
            and blue > 105
            and green < max(red, blue) * 0.86
        )
        cleaned.append((red, green, blue, 0 if is_key else 255))
    rgba.putdata(cleaned)
    return rgba


def remove_generated_background(image: Image.Image) -> Image.Image:
    """Remove transparent, black, magenta, or baked checkerboard backgrounds."""
    rgba = image.convert("RGBA")
    had_transparency = rgba.getchannel("A").getextrema()[0] < 255
    cleaned: list[tuple[int, int, int, int]] = []
    for red, green, blue, alpha_value in rgba.getdata():
        if had_transparency:
            cleaned.append((red, green, blue, alpha_value))
            continue

        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        degrees = hue * 360.0
        is_magenta = (
            286.0 <= degrees <= 345.0
            and saturation >= 0.24
            and value >= 0.45
            and red > 105
            and blue > 105
        )
        is_black = value <= 0.075
        is_light_checker = saturation <= 0.10 and value >= 0.74
        cleaned.append((red, green, blue, 0 if is_magenta or is_black or is_light_checker else 255))
    rgba.putdata(cleaned)
    return rgba


def load_override_frames(path: Path) -> list[Image.Image]:
    strip = remove_generated_background(Image.open(path))
    strip_width, strip_height = strip.size
    return [
        strip.crop(
            (
                round(frame_index * strip_width / 4),
                0,
                round((frame_index + 1) * strip_width / 4),
                strip_height,
            )
        )
        for frame_index in range(4)
    ]


def normalize_frame(source: Image.Image, width: int, height: int, ground: float) -> Image.Image:
    alpha = source.getchannel("A")
    bounds = alpha.getbbox()
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    if bounds is None:
        return canvas

    cropped = source.crop(bounds)
    # Work at half resolution, then upscale by nearest neighbour. At the game's
    # common 0.5 camera zoom each authored 2 x 2 pixel becomes one sharp pixel.
    low_width = max(1, width // 2)
    low_height = max(1, height // 2)
    margin = 3
    available_width = max(1, low_width - margin * 2)
    available_height = max(1, int(low_height * ground) - margin)
    scale = min(available_width / cropped.width, available_height / cropped.height)
    size = (
        max(1, int(round(cropped.width * scale))),
        max(1, int(round(cropped.height * scale))),
    )
    reduced = cropped.resize(size, Image.Resampling.LANCZOS)
    reduced = reduced.quantize(colors=40, method=Image.Quantize.FASTOCTREE).convert("RGBA")
    reduced_pixels = []
    for red, green, blue, alpha_value in reduced.getdata():
        reduced_pixels.append((red, green, blue, 255 if alpha_value >= 92 else 0))
    reduced.putdata(reduced_pixels)

    low_canvas = Image.new("RGBA", (low_width, low_height), (0, 0, 0, 0))
    paste_x = (low_width - reduced.width) // 2
    ground_y = int(round(low_height * ground))
    paste_y = min(low_height - reduced.height, ground_y - reduced.height)
    paste_y = max(0, paste_y)
    low_canvas.alpha_composite(reduced, (paste_x, paste_y))
    return low_canvas.resize((width, height), Image.Resampling.NEAREST)


def recolor_sheet(source: Image.Image, hue: float, saturation_scale: float) -> Image.Image:
    recolored = source.convert("RGBA")
    output: list[tuple[int, int, int, int]] = []
    for red, green, blue, alpha_value in recolored.getdata():
        if alpha_value == 0:
            output.append((0, 0, 0, 0))
            continue
        old_hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if saturation > 0.22 and value > 0.22:
            new_rgb = colorsys.hsv_to_rgb(hue, min(1.0, saturation * saturation_scale), value)
            red, green, blue = (int(round(channel * 255)) for channel in new_rgb)
        output.append((red, green, blue, alpha_value))
    recolored.putdata(output)
    return recolored


def main() -> None:
    master = remove_magenta(Image.open(SOURCE))
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    master_width, master_height = master.size
    metadata: dict[str, dict[str, object]] = {}

    for row, (effect_id, frame_width, frame_height, area_width, area_height, ground) in enumerate(EFFECTS):
        row_top = ROW_BOUNDS[row]
        row_bottom = ROW_BOUNDS[row + 1]
        override_frames = (
            load_override_frames(SOURCE_OVERRIDES[effect_id])
            if effect_id in SOURCE_OVERRIDES
            else None
        )
        sheet = Image.new("RGBA", (frame_width * 4, frame_height), (0, 0, 0, 0))
        for frame_index in range(4):
            if override_frames is not None:
                source_frame = override_frames[frame_index]
            else:
                left = round(frame_index * master_width / 4)
                right = round((frame_index + 1) * master_width / 4)
                source_frame = master.crop((left, row_top, right, row_bottom))
            if effect_id == "smoke_screen" and frame_index == 3:
                # The generated third smoke cloud slightly crosses the next
                # column. Remove that isolated left-edge fragment.
                source_frame.paste((0, 0, 0, 0), (0, 0, 34, source_frame.height))
            normalized = normalize_frame(source_frame, frame_width, frame_height, ground)
            sheet.alpha_composite(normalized, (frame_index * frame_width, 0))

        filename = f"{effect_id}_4f.png"
        sheet.save(OUTPUT_DIR / filename, optimize=True)
        metadata[effect_id] = {
            "texture": f"res://assets/effects/card_effects/{filename}",
            "frame_width": frame_width,
            "frame_height": frame_height,
            "frames": 4,
            "fps": 7.0,
            "area_width": area_width,
            "area_height": area_height,
            "ground_ratio": ground,
        }
        if effect_id in PERSISTENCE:
            metadata[effect_id]["persistence"] = PERSISTENCE[effect_id]

    # 两张全局状态牌没有独立地块范围，但仍需要明确的启动反馈。
    # 复用同风格几何轮廓并重新配色，避免为了全局状态引入另一套像素语言。
    derived_effects = (
        ("emi_countermeasure", "power_cut", 0.82, 1.08),
        ("radio_silence", "coordinate_prediction", 0.34, 0.86),
    )
    for effect_id, source_id, hue, saturation_scale in derived_effects:
        source_path = OUTPUT_DIR / f"{source_id}_4f.png"
        derived = recolor_sheet(Image.open(source_path), hue, saturation_scale)
        filename = f"{effect_id}_4f.png"
        derived.save(OUTPUT_DIR / filename, optimize=True)
        source_config = metadata[source_id]
        metadata[effect_id] = {
            **source_config,
            "texture": f"res://assets/effects/card_effects/{filename}",
            "area_width": 1,
            "area_height": 1,
        }

    (OUTPUT_DIR / "card_effects.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Built {len(metadata)} card-effect sheets in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
