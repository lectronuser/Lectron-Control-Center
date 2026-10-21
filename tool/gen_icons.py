#!/usr/bin/env python3
"""Generates the app icons of every platform from the Lectron logo.

The icon is the "L" mark of the logo on a white rounded square. Run from the project root:
    python3 tool/gen_icons.py /path/to/lectron.png
The source is the wide LECTRON wordmark (transparent PNG); its first letter is cut out.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")
MASTER = 1024
MARK_COLUMNS = (0, 536)  # the "L" of the 3934 px wide wordmark


def mark(source):
    logo = Image.open(source).convert("RGBA")
    scale = logo.width / 3934
    letter = logo.crop((round(MARK_COLUMNS[0] * scale), 0, round(MARK_COLUMNS[1] * scale), logo.height))
    return letter.crop(letter.getbbox())


def master(letter, margin=0.0):
    """White rounded square with the mark in the middle; `margin` leaves a transparent border (macOS)."""
    big = MASTER * 4  # drawn large and scaled down for smooth corners
    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    inset = round(big * margin)
    side = big - 2 * inset
    ImageDraw.Draw(icon).rounded_rectangle((inset, inset, big - inset - 1, big - inset - 1),
                                           radius=round(side * 0.22), fill="white")
    height = round(side * 0.62)
    width = round(letter.width * height / letter.height)
    scaled = letter.resize((width, height), Image.LANCZOS)
    icon.alpha_composite(scaled, ((big - width) // 2, (big - height) // 2))
    return icon.resize((MASTER, MASTER), Image.LANCZOS)


def save(icon, path, size):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    icon.resize((size, size), Image.LANCZOS).save(path)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    letter = mark(sys.argv[1])
    icon = master(letter)

    # shown in the app's top bar and used as the Linux window icon
    save(icon, "assets/icon/app_icon.png", 256)
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(icon, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", size)
    mac = master(letter, margin=0.1)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save(mac, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", size)
    icon.save(os.path.join(ROOT, "windows/runner/resources/app_icon.ico"),
              sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print("icons written")


if __name__ == "__main__":
    main()
