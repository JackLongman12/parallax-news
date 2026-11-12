#!/usr/bin/env python3
"""Put the (purple) app icon on the right side of the feature graphic.

Runs in CI after the screenshot test and tool/recolor_icon.py. Needs Pillow.
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
BANNER = ROOT / "screenshots/out/feature_graphic.png"
ICON = ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"


def main() -> None:
    banner = Image.open(BANNER).convert("RGBA")
    icon = Image.open(ICON).convert("RGBA")

    tile = 260  # launcher-style rounded tile
    x = banner.width - tile - 90
    y = (banner.height - tile) // 2

    mask = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tile - 1, tile - 1), radius=58, fill=255)
    bg = Image.new("RGBA", (tile, tile), (255, 255, 255, 255))
    banner.paste(bg, (x, y), mask)

    size = 200
    icon = icon.resize((size, size), Image.LANCZOS)
    banner.alpha_composite(icon, (x + (tile - size) // 2, y + (tile - size) // 2))
    banner.save(BANNER)
    print("feature graphic: app icon added")


if __name__ == "__main__":
    main()
