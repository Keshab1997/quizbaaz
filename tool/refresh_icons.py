#!/usr/bin/env python3
"""Refresh the launcher icons.

1. Removes the tiny baked-in "QuizBaaz 3D" wordmark from the adaptive icon
   foreground (it is illegible at launcher size and against icon guidelines).
2. Regenerates every legacy ``ic_launcher.png`` density from the cleaned
   badge, so older launchers show the same rounded icon as modern ones.

Idempotent: running it again is a no-op once the wordmark is gone.

Run from the repository root:
    python3 tool/refresh_icons.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

FG = "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"
MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
# Wordmark area inside the 432px foreground canvas (badge sits at 82..350).
# y0, y1, x0, x1 -- covers the text plus its anti-aliased glow.
TEXT_REGION = (106, 144, 148, 318)


def remove_wordmark(im):
    a = np.array(im).astype(float)
    y0, y1, x0, x1 = TEXT_REGION
    region = np.zeros(a.shape[:2], bool)
    region[y0:y1, x0:x1] = True
    bright = (a[..., :3].min(axis=2) > 100) & (a[..., 3] > 200)
    mask = region & bright
    if mask.sum() < 200:
        print("no wordmark found; nothing to remove")
        return im

    for _ in range(5):  # dilate to cover the glow / anti-aliasing
        m = mask.copy()
        m[1:, :] |= mask[:-1, :]
        m[:-1, :] |= mask[1:, :]
        m[:, 1:] |= mask[:, :-1]
        m[:, :-1] |= mask[:, 1:]
        mask = m

    img = a.copy()
    for x in range(mask.shape[1]):
        ys = np.where(mask[:, x])[0]
        if not len(ys):
            continue
        ya, yb = ys.min(), ys.max()
        top, bot = img[ya - 1, x], img[yb + 1, x]
        span = (yb + 1) - (ya - 1)
        for y in ys:
            t = (y - (ya - 1)) / span
            img[y, x] = (1 - t) * top + t * bot

    out = Image.fromarray(img.astype(np.uint8))
    smooth = np.array(out.filter(ImageFilter.GaussianBlur(1.2))).astype(float)
    img2 = img.copy()
    img2[mask] = 0.5 * img[mask] + 0.5 * smooth[mask]
    out = Image.fromarray(img2.astype(np.uint8))
    print(f"removed wordmark ({int(mask.sum())} px)")
    return out


def main():
    fg = Image.open(FG).convert("RGBA")
    fg = remove_wordmark(fg)
    fg.save(FG, optimize=True)
    print(f"wrote {FG}")

    # Legacy launcher icons: the rounded badge fills the whole square.
    a = np.array(fg)
    ys, xs = np.where(a[..., 3] > 10)
    badge = fg.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    for folder, size in MIPMAPS.items():
        path = f"android/app/src/main/res/{folder}/ic_launcher.png"
        if not os.path.isfile(path):
            print(f"skip {path} (missing)")
            continue
        badge.resize((size, size), Image.LANCZOS).save(path, optimize=True)
        print(f"wrote {path} ({size}px)")


if __name__ == "__main__":
    main()
