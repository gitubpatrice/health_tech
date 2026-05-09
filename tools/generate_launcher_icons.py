"""
Generate launcher icons for Health Tech, matching the Files Tech family
checkerboard (blue / red quadrants) with two-line white text "Health / Tech".

Outputs into:
  android/app/src/main/res/mipmap-{m,h,x,xx,xxx}hdpi/ic_launcher.png
  android/app/src/main/res/drawable-{m,h,x,xx,xxx}hdpi/ic_launcher_foreground.png
  android/app/src/main/res/values/colors.xml (background color)

Run from the project root:
  python tools/generate_launcher_icons.py
"""
from __future__ import annotations

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Sampled from notes_tech mipmap-xxxhdpi/ic_launcher.png so the family stays
# visually coherent.
BLUE = (45, 80, 200)  # top-left, bottom-right
RED = (190, 50, 60)   # top-right, bottom-left
TEXT = (255, 255, 255)
SHADOW = (0, 0, 0, 110)

# Adaptive-icon background (single colour visible when the launcher applies
# its own mask). Notes Tech uses #262660 — we re-use it for cohesion.
ADAPTIVE_BG_HEX = "#262660"

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def find_font(size: int) -> ImageFont.FreeTypeFont:
    """Locate a bold sans-serif font available on Windows / Linux."""
    candidates = [
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    # Pillow built-in fallback (smaller, less polished but always available).
    return ImageFont.load_default(size=size)


def draw_icon(side: int) -> Image.Image:
    """Render a single launcher icon at `side` x `side` pixels."""
    img = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    half = side // 2
    quadrants = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    qd = ImageDraw.Draw(quadrants)
    qd.rectangle((0, 0, half, half), fill=BLUE)
    qd.rectangle((half, 0, side, half), fill=RED)
    qd.rectangle((0, half, half, side), fill=RED)
    qd.rectangle((half, half, side, side), fill=BLUE)

    # Round the outer corners so the icon reads as a tile, not a pure square.
    mask = Image.new("L", (side, side), 0)
    md = ImageDraw.Draw(mask)
    radius = int(side * 0.18)
    md.rounded_rectangle((0, 0, side - 1, side - 1), radius=radius, fill=255)
    img.paste(quadrants, (0, 0), mask)

    # --- Text -------------------------------------------------------------
    # Pick a font size so each line spans ~62% of the icon width. The two
    # words have similar widths so a single sizing heuristic is enough.
    target_width = int(side * 0.62)
    fsize = int(side * 0.30)
    while fsize > 4:
        font = find_font(fsize)
        if font.getlength("Health") <= target_width:
            break
        fsize -= 2

    line1 = "Health"
    line2 = "Tech"
    bbox1 = font.getbbox(line1)
    bbox2 = font.getbbox(line2)
    line_height = bbox1[3] - bbox1[1]
    gap = int(line_height * 0.05)
    total_h = (bbox1[3] - bbox1[1]) + gap + (bbox2[3] - bbox2[1])
    top = (side - total_h) // 2 - bbox1[1]

    def draw_centered(text: str, y: int, font: ImageFont.FreeTypeFont) -> None:
        bbox = font.getbbox(text)
        x = (side - (bbox[2] - bbox[0])) // 2 - bbox[0]
        # soft shadow
        shadow_layer = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow_layer)
        sd.text((x, y + max(2, side // 80)), text, font=font, fill=SHADOW)
        shadow_layer = shadow_layer.filter(
            ImageFilter.GaussianBlur(radius=max(1, side // 150))
        )
        img.alpha_composite(shadow_layer)
        d = ImageDraw.Draw(img)
        d.text((x, y), text, font=font, fill=TEXT)

    draw_centered(line1, top, font)
    draw_centered(line2, top + (bbox1[3] - bbox1[1]) + gap, font)
    return img


def write_color_xml(android_res: str) -> None:
    target = os.path.join(android_res, "values", "colors.xml")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            f'    <color name="ic_launcher_background">{ADAPTIVE_BG_HEX}</color>\n'
            "</resources>\n"
        )


def write_adaptive_icon(android_res: str) -> None:
    target_dir = os.path.join(android_res, "mipmap-anydpi-v26")
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, "ic_launcher.xml")
    with open(target, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '  <background android:drawable="@color/ic_launcher_background"/>\n'
            "  <foreground>\n"
            "      <inset\n"
            '          android:drawable="@drawable/ic_launcher_foreground"\n'
            '          android:inset="16%" />\n'
            "  </foreground>\n"
            "</adaptive-icon>\n"
        )


def main() -> int:
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    android_res = os.path.join(project_root, "android", "app", "src", "main", "res")
    if not os.path.isdir(android_res):
        print(f"Android res dir not found: {android_res}", file=sys.stderr)
        return 1

    for density, size in DENSITIES.items():
        # Adaptive-icon foreground convention: 108dp visible area at the
        # given density; we render a 2.25x oversample (= legacy size * 2.25)
        # so the launcher mask never reveals jagged edges.
        legacy = draw_icon(size)
        mipmap_dir = os.path.join(android_res, f"mipmap-{density}")
        os.makedirs(mipmap_dir, exist_ok=True)
        legacy.save(os.path.join(mipmap_dir, "ic_launcher.png"), "PNG")

        foreground_size = round(size * 2.25)
        foreground = draw_icon(foreground_size)
        drawable_dir = os.path.join(android_res, f"drawable-{density}")
        os.makedirs(drawable_dir, exist_ok=True)
        foreground.save(
            os.path.join(drawable_dir, "ic_launcher_foreground.png"), "PNG"
        )
        print(f"  {density}: legacy {size}px, foreground {foreground_size}px")

    write_color_xml(android_res)
    write_adaptive_icon(android_res)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
