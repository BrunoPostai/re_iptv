"""Generates the neutral placeholder artwork used by the player.

These assets are intentionally generic (an abstract play mark plus a stylised
dotted world map) so that the repository does not ship anybody else's artwork.
Replace the files in `app/assets/branding/` with your own — or point
`app_config.json` at absolute file paths — to personalise the build.

Usage:
    python tools/make_branding.py
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "app", "assets", "branding")

# Wordmark drawn under the play mark. Placeholder art only — change it, or
# replace the images entirely, to brand a build.
WORDMARK = "IPTV"

GOLD = (224, 168, 60)
BLUE = (44, 111, 187)
DEEP = (7, 16, 28)

# Rough landmass ellipses (cx, cy, rx, ry) in normalised 2:1 map space.
LAND = [
    (0.20, 0.28, 0.085, 0.10),
    (0.155, 0.19, 0.06, 0.05),
    (0.255, 0.45, 0.028, 0.05),
    (0.315, 0.63, 0.048, 0.115),
    (0.50, 0.27, 0.05, 0.055),
    (0.53, 0.56, 0.068, 0.135),
    (0.585, 0.30, 0.075, 0.10),
    (0.72, 0.30, 0.115, 0.105),
    (0.675, 0.50, 0.038, 0.062),
    (0.79, 0.47, 0.045, 0.05),
    (0.845, 0.72, 0.055, 0.055),
]


def _font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ("seguisb.ttf" if bold else "segoeui.ttf", "arialbd.ttf", "arial.ttf"):
        path = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", name)
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _radial_gradient(size, inner, outer, center=(0.5, 0.5), radius=1.0):
    width, height = size
    image = Image.new("RGB", size, outer)
    draw = ImageDraw.Draw(image)
    steps = 220
    cx, cy = center[0] * width, center[1] * height
    max_dist = math.hypot(width, height) * radius
    for step in range(steps, 0, -1):
        t = step / steps
        colour = _lerp(inner, outer, t)
        rx = max_dist * t
        ry = max_dist * t * 0.62
        draw.ellipse(
            [cx - rx, cy - ry, cx + rx, cy + ry],
            fill=colour,
        )
    return image.filter(ImageFilter.GaussianBlur(6))


def _inside_land(x: float, y: float) -> bool:
    for cx, cy, rx, ry in LAND:
        if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
            return True
    return False


def _world_map(size, dot_colour, spacing=15, radius=1.9, alpha=110):
    width, height = size
    # Fit the 2:1 map across the middle 92% of the canvas.
    map_w = width * 0.98
    map_h = map_w / 2.0
    origin_x = (width - map_w) / 2.0
    origin_y = (height - map_h) / 2.0
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    rows = int(map_h // spacing) + 1
    cols = int(map_w // spacing) + 1
    for row in range(rows):
        for col in range(cols):
            nx = col / cols
            ny = row / rows
            if not _inside_land(nx, ny):
                continue
            # Fade the dots towards the edges of the map.
            edge = min(nx, 1 - nx, ny, 1 - ny)
            fade = max(0.0, min(1.0, edge * 6.0))
            if fade <= 0:
                continue
            x = origin_x + col * spacing + (spacing / 2 if row % 2 else 0)
            y = origin_y + row * spacing
            a = int(alpha * fade)
            draw.ellipse(
                [x - radius, y - radius, x + radius, y + radius],
                fill=(*dot_colour, a),
            )
    return layer


def make_background(path, inner, outer, dots, spacing=15, alpha=110, dot_colour=None):
    size = (1920, 1080)
    base = _radial_gradient(size, inner, outer, center=(0.42, 0.28), radius=0.95)
    base = base.convert("RGBA")
    if dots:
        base = Image.alpha_composite(base, _world_map(size, dot_colour or dots, spacing=spacing, alpha=alpha))
    # Vignette
    vignette = Image.new("L", size, 0)
    vdraw = ImageDraw.Draw(vignette)
    vdraw.ellipse([-size[0] * 0.25, -size[1] * 0.35, size[0] * 1.25, size[1] * 1.35], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(180))
    dark = Image.new("RGBA", size, (0, 0, 0, 255))
    base = Image.composite(base, Image.alpha_composite(base, dark), vignette)
    base.convert("RGB").save(path, "JPEG", quality=88, optimize=True)
    print("wrote", path)


def make_logo(path, size):
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    pad = int(size * 0.06)
    radius = int(size * 0.22)

    # Rounded plate with a diagonal gradient.
    plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(plate)
    pdraw.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=radius,
        fill=BLUE + (255,),
        outline=GOLD + (255,),
        width=max(2, int(size * 0.014)),
    )
    grad = Image.new("L", (size, size), 0)
    gdraw = ImageDraw.Draw(grad)
    for i in range(size):
        gdraw.line([(i, 0), (i, size)], fill=int(150 * (1 - i / size)))
    plate = Image.composite(Image.new("RGBA", (size, size), (0, 0, 0, 150)), plate, grad)
    image = Image.alpha_composite(image, plate)
    draw = ImageDraw.Draw(image)

    # Play triangle.
    cx, cy = size / 2.0, size * 0.47
    tri = size * 0.20
    draw.polygon(
        [(cx - tri * 0.75, cy - tri), (cx - tri * 0.75, cy + tri), (cx + tri * 0.95, cy)],
        fill=(255, 255, 255, 255),
    )

    # Word mark.
    text = WORDMARK
    font = _font(int(size * 0.15))
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(
        ((size - tw) / 2.0, size * 0.74),
        text,
        font=font,
        fill=GOLD + (255,),
    )
    image.save(path, "PNG")
    print("wrote", path)


def main():
    os.makedirs(OUT, exist_ok=True)

    make_background(
        os.path.join(OUT, "bg_main.jpg"),
        inner=(18, 54, 96),
        outer=(4, 10, 20),
        dots=(120, 170, 220),
        spacing=15,
        alpha=125,
    )
    make_background(
        os.path.join(OUT, "bg_honor.jpg"),
        inner=(64, 46, 16),
        outer=(10, 8, 4),
        dots=(224, 168, 60),
        spacing=16,
        alpha=105,
    )
    make_background(
        os.path.join(OUT, "bg_black.jpg"),
        inner=(14, 16, 22),
        outer=(2, 3, 5),
        dots=(120, 170, 220),
        spacing=22,
        alpha=60,
    )

    make_logo(os.path.join(OUT, "logo.png"), 512)
    make_logo(os.path.join(OUT, "logo_small.png"), 128)


if __name__ == "__main__":
    main()
