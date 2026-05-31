#!/usr/bin/env python3
"""Generate the VerbrauchsHub app icon at 1024x1024 PNG."""
from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

SIZE = 1024
OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def make_background(size):
    """Diagonal gradient from deep blue (top-left) to vibrant green (bottom-right)."""
    img = Image.new("RGB", (size, size), (0, 0, 0))
    top = hex_to_rgb("#1565C0")     # rich blue
    bottom = hex_to_rgb("#2E7D32")  # deep green
    px = img.load()
    for y in range(size):
        for x in range(size):
            # diagonal blend (top-left → bottom-right)
            t = (x + y) / (2 * (size - 1))
            px[x, y] = lerp(top, bottom, t)
    return img


def draw_gauge(img):
    """Draw a clean white gauge with a colored arc and a needle on top of the gradient."""
    draw = ImageDraw.Draw(img, "RGBA")
    cx, cy = SIZE // 2, SIZE // 2 + 40
    outer_r = 360
    inner_r = 300

    # Soft drop-shadow circle behind the dial
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse(
        (cx - outer_r - 20, cy - outer_r - 10, cx + outer_r + 20, cy + outer_r + 30),
        fill=(0, 0, 0, 80),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    img.alpha_composite(shadow)

    draw = ImageDraw.Draw(img, "RGBA")

    # White dial disc
    draw.ellipse(
        (cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r),
        fill=(255, 255, 255, 255),
    )

    # Colored arc (energy gradient: green → amber → red across the gauge)
    # Sweep from 135° to 405° (i.e. -45° from the bottom going clockwise across the top)
    arc_thickness = 56
    arc_bbox = (cx - outer_r + 30, cy - outer_r + 30, cx + outer_r - 30, cy + outer_r - 30)
    arc_start = 135
    arc_end = 405  # = 45 wrapping past 360

    # Draw the arc as many small wedges to achieve a smooth color transition
    segments = 240
    stops = [
        (0.00, hex_to_rgb("#43A047")),  # green
        (0.50, hex_to_rgb("#FFB300")),  # amber
        (1.00, hex_to_rgb("#E53935")),  # red
    ]

    def color_at(t):
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0)
                return lerp(c0, c1, k)
        return stops[-1][1]

    for i in range(segments):
        t0 = i / segments
        t1 = (i + 1) / segments
        a0 = arc_start + (arc_end - arc_start) * t0
        a1 = arc_start + (arc_end - arc_start) * t1
        c = color_at(t0) + (255,)
        draw.arc(arc_bbox, a0, a1 + 0.5, fill=c, width=arc_thickness)

    # Tick marks
    tick_outer = outer_r - 90
    tick_inner = outer_r - 130
    for i in range(11):
        t = i / 10
        angle_deg = arc_start + (arc_end - arc_start) * t
        rad = math.radians(angle_deg)
        x1 = cx + math.cos(rad) * tick_inner
        y1 = cy + math.sin(rad) * tick_inner
        x2 = cx + math.cos(rad) * tick_outer
        y2 = cy + math.sin(rad) * tick_outer
        width = 8 if i % 5 == 0 else 4
        draw.line((x1, y1, x2, y2), fill=(60, 60, 70, 255), width=width)

    # Needle pointing to ~70% (energy in use)
    needle_t = 0.70
    needle_angle = math.radians(arc_start + (arc_end - arc_start) * needle_t)
    nlen = outer_r - 80
    nx = cx + math.cos(needle_angle) * nlen
    ny = cy + math.sin(needle_angle) * nlen
    # Needle base perpendicular
    perp = needle_angle + math.pi / 2
    base_w = 22
    bx1 = cx + math.cos(perp) * base_w
    by1 = cy + math.sin(perp) * base_w
    bx2 = cx - math.cos(perp) * base_w
    by2 = cy - math.sin(perp) * base_w
    draw.polygon(
        [(bx1, by1), (bx2, by2), (nx, ny)],
        fill=(33, 33, 33, 255),
    )

    # Center hub
    hub_r = 40
    draw.ellipse((cx - hub_r, cy - hub_r, cx + hub_r, cy + hub_r), fill=(33, 33, 33, 255))
    draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(255, 255, 255, 255))

    # Mini bar chart at the bottom of the dial face
    bar_base_y = cy + 200
    bar_widths = 38
    bar_gap = 22
    bar_heights = [40, 70, 100, 60, 110]
    total_w = len(bar_heights) * bar_widths + (len(bar_heights) - 1) * bar_gap
    start_x = cx - total_w // 2
    bar_colors = [
        hex_to_rgb("#039BE5"),
        hex_to_rgb("#43A047"),
        hex_to_rgb("#FFB300"),
        hex_to_rgb("#E53935"),
        hex_to_rgb("#8E24AA"),
    ]
    for i, h in enumerate(bar_heights):
        x0 = start_x + i * (bar_widths + bar_gap)
        x1 = x0 + bar_widths
        y1 = bar_base_y
        y0 = bar_base_y - h
        draw.rounded_rectangle((x0, y0, x1, y1), radius=6, fill=bar_colors[i] + (255,))


def add_inner_glow(img):
    """Subtle inner highlight at top to give a glossy feel."""
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((-SIZE // 3, -SIZE, SIZE + SIZE // 3, SIZE // 2), fill=(255, 255, 255, 30))
    overlay = overlay.filter(ImageFilter.GaussianBlur(40))
    img.alpha_composite(overlay)


def main():
    bg = make_background(SIZE).convert("RGBA")
    draw_gauge(bg)
    add_inner_glow(bg)
    # iOS app icons are full-bleed squares — the system applies the rounded corners.
    out = bg.convert("RGB")
    out.save(OUTPUT, format="PNG", optimize=True)
    print(f"Wrote {OUTPUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
