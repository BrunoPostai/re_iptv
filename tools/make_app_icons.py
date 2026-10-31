"""Renders the iOS app icon set from the branding mark.

The mark in `app/assets/branding/` is a rounded plate drawn for use *inside* the
app, on top of the app's own background. An app icon is different: the OS masks
it to its own shape, so anything round inside it ends up with the canvas showing
behind the corners and drawn twice. This renders the same plate full bleed -
square corners, no rim - and lets iOS do the rounding.

Every size in the asset catalogue's `Contents.json` is written from one 1024 px
master, so the small variants are properly resampled rather than separately
drawn. Icons are flattened to RGB because the App Store rejects an alpha
channel.

Usage:
    python tools/make_app_icons.py
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from make_branding import make_logo  # noqa: E402  (path set up above)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON = os.path.join(
    ROOT, "app", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)
CATALOGUE = os.path.join(APPICON, "Contents.json")

MASTER = 1024


def render_master(path):
    make_logo(path, MASTER, full_bleed=True)


def catalogue_images():
    with open(CATALOGUE, encoding="utf-8") as handle:
        catalogue = json.load(handle)
    for image in catalogue["images"]:
        points = float(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        yield image["filename"], int(round(points * scale))


def main():
    if not os.path.isdir(APPICON):
        raise SystemExit(
            f"no asset catalogue at {APPICON} - is this the app's repository root?"
        )

    master_path = os.path.join(APPICON, ".master.png")
    render_master(master_path)
    master = Image.open(master_path).convert("RGB")

    written = 0
    for filename, pixels in catalogue_images():
        icon = master if pixels == MASTER else master.resize((pixels, pixels), Image.LANCZOS)
        icon.save(os.path.join(APPICON, filename), "PNG")
        written += 1

    os.remove(master_path)
    print(f"wrote {written} icons into {APPICON}")


if __name__ == "__main__":
    main()
