#!/usr/bin/env python3
"""Shrink bundled topic photos before packaging (run in CI, needs Pillow).

Resizes assets/topics/*.jpg to 640 px wide and re-encodes them as optimized
progressive JPEGs. Cards decode at screen width anyway, and these are only
shown until the real news photo loads, so this saves ~3 MB of APK size with
no visible difference.
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAX_W = 640


def main() -> None:
    before = after = 0
    for f in sorted((ROOT / "assets/topics").glob("*.jpg")):
        before += f.stat().st_size
        img = Image.open(f).convert("RGB")
        if img.width > MAX_W:
            img = img.resize((MAX_W, round(img.height * MAX_W / img.width)), Image.LANCZOS)
        img.save(f, "JPEG", quality=74, optimize=True, progressive=True)
        after += f.stat().st_size
    print(f"topic photos: {before // 1024} KB -> {after // 1024} KB")


if __name__ == "__main__":
    main()
