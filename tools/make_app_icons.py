"""Renders the platform icon sets from the branding mark.

Two things stop the mark from being used as-is. It is a rounded plate drawn for
use *inside* the app, on top of the app's own background: an app icon is masked
by the OS, so a rounded plate ends up with the canvas showing at the corners and
drawn twice. And its word mark is only legible down to about 32 px, below which
it is three gold smudges in the taskbar.

So the plate is drawn full bleed - square corners, no rim - and the OS does the
rounding, while the Windows icon drops the word mark at its small sizes. iOS
goes down only to 40 px across the catalogue and keeps it everywhere.

Icons are flattened to RGB for iOS because the App Store rejects an alpha
channel.

Usage:
    python tools/make_app_icons.py
"""

from __future__ import annotations

import io
import json
import os
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from make_branding import make_logo  # noqa: E402  (path set up above)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON = os.path.join(
    ROOT, "app", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)
CATALOGUE = os.path.join(APPICON, "Contents.json")
WINDOWS_ICO = os.path.join(ROOT, "app", "windows", "runner", "resources", "app_icon.ico")

MASTER = 1024

# Windows asks for these from the shell, the taskbar and Explorer's own zoom
# levels; 256 is the largest an .ico can describe.
WINDOWS_SIZES = (256, 128, 64, 48, 40, 32, 24, 20, 16)
WINDOWS_WORDMARK_FROM = 48


def render(size, wordmark=True):
    """One square icon, drawn rather than resampled, so edges stay crisp."""
    master_path = os.path.join(APPICON, f".{size}-{int(wordmark)}.png")
    make_logo(master_path, size, full_bleed=True, wordmark=wordmark)
    with Image.open(master_path) as image:
        image.load()
        rendered = image.convert("RGB")
    os.remove(master_path)
    return rendered


def catalogue_images():
    with open(CATALOGUE, encoding="utf-8") as handle:
        catalogue = json.load(handle)
    for image in catalogue["images"]:
        points = float(image["size"].split("x")[0])
        scale = int(image["scale"].rstrip("x"))
        yield image["filename"], int(round(points * scale))


def write_ios_icons():
    master = render(MASTER)
    written = 0
    for filename, pixels in catalogue_images():
        icon = master if pixels == MASTER else master.resize((pixels, pixels), Image.LANCZOS)
        icon.save(os.path.join(APPICON, filename), "PNG")
        written += 1
    return written


def _single_size_ico(image, size):
    buffer = io.BytesIO()
    image.save(buffer, format="ICO", sizes=[(size, size)])
    return buffer.getvalue()


def write_windows_ico():
    """A real multi-size icon: each size is drawn, not one image shrunk.

    Pillow writes one image to an .ico, so each size is written as its own
    one-entry icon and the entries are stitched back together - which keeps
    Pillow's BMP encoding for the small sizes, as Explorer expects.
    """
    blobs = [
        _single_size_ico(render(size, wordmark=size >= WINDOWS_WORDMARK_FROM), size)
        for size in WINDOWS_SIZES
    ]

    header = struct.pack("<HHH", 0, 1, len(blobs))
    entries = b""
    payload = b""
    offset = 6 + 16 * len(blobs)
    for blob in blobs:
        width, height, colours, reserved, planes, bits, length, start = struct.unpack_from(
            "<BBBBHHII", blob, 6
        )
        entries += struct.pack(
            "<BBBBHHII", width, height, colours, reserved, planes, bits, length, offset + len(payload)
        )
        payload += blob[start : start + length]

    with open(WINDOWS_ICO, "wb") as handle:
        handle.write(header + entries + payload)


def main():
    if not os.path.isdir(APPICON):
        raise SystemExit(
            f"no asset catalogue at {APPICON} - is this the app's repository root?"
        )

    print(f"wrote {write_ios_icons()} icons into {APPICON}")
    write_windows_ico()
    print("wrote", WINDOWS_ICO)


if __name__ == "__main__":
    main()
