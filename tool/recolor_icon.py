#!/usr/bin/env python3
"""Recolour the generated launcher icon from blue to shades of purple.

Keeps the existing shape and shading - only the hue changes. Run after
`flutter create` (needs Pillow: pip install pillow).
"""
import colorsys
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
PURPLE_HUE = 0.75  # ~270 degrees


def recolor(path: pathlib.Path) -> None:
    img = Image.open(path).convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if ss < 0.15:  # leave whites/greys alone
                continue
            # Map every blue shade to a purple shade, preserving light/dark variation.
            nr, ng, nb = colorsys.hsv_to_rgb(PURPLE_HUE, min(1.0, ss * 1.05), vv)
            px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    img.save(path)


def main() -> None:
    icons = list(RES.glob("mipmap-*/ic_launcher*.png"))
    if not icons:
        raise SystemExit("no launcher icons found - run flutter create first")
    for icon in icons:
        recolor(icon)
    print(f"recoloured {len(icons)} launcher icons to purple")


if __name__ == "__main__":
    main()
