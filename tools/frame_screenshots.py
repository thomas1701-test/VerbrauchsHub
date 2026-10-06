#!/usr/bin/env python3
"""Wraps raw simulator screenshots into App Store marketing images.

Usage: frame_screenshots.py <raw_dir> <out_dir>
Raw files are named like "01-dashboard.png" (see VerbrauchsHubUITests/ScreenshotTests.swift).
The output keeps the input pixel size, so App Store Connect accepts it for the same display class.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/System/Library/Fonts/SFNS.ttf"

CAPTIONS = {
    "01-dashboard": ("Alle Zähler.\nEin Blick.", "Strom, Gas, Wasser & PV – mit Kosten und Trend"),
    "02-detail": ("Verbrauch &\nPrognose", "Monat, Jahr und Hochrechnung – automatisch"),
    "03-reading": ("In Sekunden\nabgelesen", "Zählerstand eintippen, optional mit Foto"),
    "04-statistics": ("Vergleiche,\ndie zählen", "Tag bis Jahr – auch mit dem Vorjahr"),
    "05-pv": ("Deine\nPV-Bilanz", "Einspeisung, Eigenverbrauch und Autarkiegrad"),
    "06-meters": ("Mehrere\nGebäude", "Haus, Wohnung, Ferienhaus – sauber getrennt"),
}

# Top → bottom gradient per screenshot, derived from the meter colours used in the app.
GRADIENTS = {
    "01-dashboard": ("#1E88E5", "#0D47A1"),
    "02-detail": ("#E53935", "#8E1B1B"),
    "03-reading": ("#00ACC1", "#00606B"),
    "04-statistics": ("#5E35B1", "#2A1470"),
    "05-pv": ("#43A047", "#1B5E20"),
    "06-meters": ("#FB8C00", "#A84E00"),
}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def gradient(size, top, bottom):
    w, h = size
    a, b = hex_rgb(top), hex_rgb(bottom)
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        col.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return col.resize((w, h))


def frame(src: Path, dst: Path):
    key = src.stem
    title, subtitle = CAPTIONS[key]
    shot = Image.open(src).convert("RGB")
    W, H = shot.size
    canvas = gradient((W, H), *GRADIENTS[key]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    u = W / 1320  # scale unit relative to the 6.9" iPhone
    is_tablet = W / H > 0.6
    title_font = font(round((110 if not is_tablet else 120) * u), "Bold")
    sub_font = font(round((48 if not is_tablet else 50) * u), "Medium")

    y = round(150 * u)
    draw.multiline_text((W / 2, y), title, font=title_font, fill="white", anchor="ma",
                        align="center", spacing=round(10 * u))
    tb = draw.multiline_textbbox((W / 2, y), title, font=title_font, anchor="ma", spacing=round(10 * u))
    y = tb[3] + round(36 * u)
    draw.text((W / 2, y), subtitle, font=sub_font, fill=(255, 255, 255, 220), anchor="ma")
    y += round(110 * u)

    # Screenshot below the caption, bleeding off the bottom edge.
    scale = (0.80 if not is_tablet else 0.74)
    sw, sh = round(W * scale), round(H * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    radius = round(70 * u)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), radius, fill=255)

    x = (W - sw) // 2
    border = round(14 * u)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x - border, y - border + round(20 * u), x + sw + border, y + sh + border + round(20 * u)),
        radius + border, fill=(0, 0, 0, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(40 * u))))
    bezel = ImageDraw.Draw(canvas)
    bezel.rounded_rectangle((x - border, y - border, x + sw + border, y + sh + border),
                            radius + border, fill=(18, 18, 22, 255))
    canvas.paste(shot, (x, y), mask)
    canvas.convert("RGB").save(dst, "PNG", optimize=True)


def main():
    raw, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for src in sorted(raw.glob("0*.png")):
        if src.stem in CAPTIONS:
            frame(src, out / src.name)
            print(out / src.name)


if __name__ == "__main__":
    main()
