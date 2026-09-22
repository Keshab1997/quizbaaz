#!/usr/bin/env python3
"""Regenerate the adaptive launcher icon foreground with rounded corners.

Takes the original full-bleed square artwork and produces a spec-compliant
adaptive icon foreground:
  - logo scaled to 62% of the 108dp canvas (inside the safe zone),
  - smooth anti-aliased rounded corners (24% corner radius),
  - centered on a transparent 432x432 canvas.

Run once from the original square artwork:
    python3 tool/make_rounded_foreground.py

The script refuses to run twice (it detects the already-badged asset by its
transparent corners) so the icon cannot be shrunk repeatedly.
"""
from PIL import Image, ImageDraw

SRC = "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
CANVAS = 432          # 108dp @ xxxhdpi
BADGE_RATIO = 0.62    # logo occupies 62% of the canvas (adaptive safe zone)
CORNER_RATIO = 0.24   # corner radius as a share of the badge side
SS = 4                # supersampling factor for smooth corners


def main() -> None:
    src = Image.open(SRC).convert("RGBA")

    # Guard: already processed (transparent corners) -> do not shrink again.
    w, h = src.size
    corners = [src.getpixel(p)[3] for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    if all(a == 0 for a in corners):
        raise SystemExit("ic_launcher_foreground.png already has transparent corners; nothing to do.")

    badge = int(round(CANVAS * BADGE_RATIO))
    big = badge * SS
    radius = int(round(big * CORNER_RATIO))

    small = src.resize((big, big), Image.LANCZOS)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=radius, fill=255
    )
    small.putalpha(mask)
    small = small.resize((badge, badge), Image.LANCZOS)

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off = (CANVAS - badge) // 2
    out.paste(small, (off, off), small)
    out.save(SRC, optimize=True)
    print(f"wrote {SRC} (badge {badge}px, corner radius {CORNER_RATIO:.0%})")


if __name__ == "__main__":
    main()
