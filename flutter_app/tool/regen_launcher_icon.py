"""Regenerate Android launcher icon raster mipmaps from the Gochano master artwork.

The master artwork is `assets/branding/gochano1.png` (1254x1254 RGB). We want
the same artwork to be visible on pre-Android-8 devices that read the
`mipmap-*/ic_launcher.png` fallback.

Composition rules (Android adaptive icon spec):

  * Square canvas, output side N.
  * Brand-purple background fills 100% of the canvas.
  * The foreground artwork sits inside the 66dp safe zone, which is the
    inscribed circle of a 108dp adaptive-icon viewport. For a square canvas
    that means the artwork occupies the central 66/108 = 61.1% of each side.
  * We resize the master artwork to N * 0.611 and centre it.
  * The master PNG is mostly white-on-light, so it composites cleanly against
    a purple background without any further tinting.

Run with:
    cd flutter_app
    python tool/regen_launcher_icon.py

Output:
    android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png

This file is checked in but the PNG output is ignored — we commit the result.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


BRAND_PURPLE = (0x5B, 0x3D, 0xF5, 0xFF)  # EkColors.purple
SAFE_ZONE_RATIO = 66.0 / 108.0  # 0.6111...
MASTER = Path("assets/branding/gochano1.png")

# Android density bucket -> output square px.
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

OUT_DIR = Path("android/app/src/main/res")


def compose_one(master: Image.Image, side: int) -> Image.Image:
    """Return a brand-purple square with the master artwork centred inside the safe zone."""
    canvas = Image.new("RGBA", (side, side), BRAND_PURPLE)

    # The safe zone is the inscribed circle of a 108dp viewport; the artwork
    # should fill that circle, so it occupies SAFE_ZONE_RATIO of the side.
    inner_side = int(round(side * SAFE_ZONE_RATIO))
    if inner_side < 1:
        inner_side = 1

    # Master is RGB; paste over the purple canvas. PIL pastes RGBA only.
    artwork = master.convert("RGBA").resize(
        (inner_side, inner_side), Image.LANCZOS
    )

    offset = ((side - inner_side) // 2, (side - inner_side) // 2)
    canvas.alpha_composite(artwork, offset)
    return canvas


def main() -> int:
    if not MASTER.exists():
        print(f"error: master artwork not found: {MASTER}", file=sys.stderr)
        return 1

    master = Image.open(MASTER)
    print(f"master artwork: {master.size} {master.mode}")

    for bucket, side in DENSITIES.items():
        out_path = OUT_DIR / f"mipmap-{bucket}" / "ic_launcher.png"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        composed = compose_one(master, side)
        composed.save(out_path, format="PNG", optimize=True)
        print(f"  wrote {out_path}  ({side}x{side})")

    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
