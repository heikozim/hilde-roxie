#!/usr/bin/env python3
# Part of ROXIE, a log collector on Wolly.
# SPDX-FileCopyrightText: 2026 Heiko Zimmermann
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Draws ROXIE's icon, a red panda's face, from a few shapes in the colours of
# share/roxie.css, and writes share/icons/: roxie.svg, the PNGs and
# favicon.ico.  The SVG and the PNGs come from the same list of shapes; the
# PNGs are rendered here with 4 by 4 samples a pixel, so nothing outside
# Python's standard library is needed and a second run writes the same bytes.
#
#     python3 scripts/make-icons.py [out directory, default share/icons]
import math
import os
import struct
import sys
import zlib

# The colours of share/roxie.css, by their names there.
BG = "#24300f"         # --bg
HIGH = "#e8b26a"       # --high: the fur
SECONDARY = "#f5f3e8"  # --secondary: the white of the face
DARK = "#1b2409"       # --on-accent: eyes, nose, inside of the ears
ACCENT = "#e3ee8a"     # --accent: the ring of the round icons

# The face on a canvas of 512 by 512, drawn in this order.  Each shape:
# ("ellipse", cx, cy, rx, ry, degrees, colour) or ("polygon", points, colour).
FACE = [
    ("polygon", [(70, 236), (104, 54), (236, 150)], SECONDARY),
    ("polygon", [(442, 236), (408, 54), (276, 150)], SECONDARY),
    ("polygon", [(108, 206), (124, 104), (204, 160)], DARK),
    ("polygon", [(404, 206), (388, 104), (308, 160)], DARK),
    ("ellipse", 256, 292, 186, 160, 0, HIGH),
    ("ellipse", 186, 336, 74, 60, 0, SECONDARY),
    ("ellipse", 326, 336, 74, 60, 0, SECONDARY),
    ("ellipse", 256, 366, 68, 58, 0, SECONDARY),
    ("ellipse", 186, 216, 30, 20, -12, SECONDARY),
    ("ellipse", 326, 216, 30, 20, 12, SECONDARY),
    ("ellipse", 202, 318, 15, 40, 18, HIGH),
    ("ellipse", 310, 318, 15, 40, -18, HIGH),
    ("ellipse", 200, 270, 21, 23, 0, DARK),
    ("ellipse", 312, 270, 21, 23, 0, DARK),
    ("ellipse", 193, 262, 7, 7, 0, SECONDARY),
    ("ellipse", 305, 262, 7, 7, 0, SECONDARY),
    ("ellipse", 256, 338, 28, 19, 0, DARK),
    ("polygon", [(250, 352), (262, 352), (262, 382), (250, 382)], DARK),
]

SIZE = 512


def rgb(colour):
    return tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5))


def background(kind):
    """The ground under the face: a square with round corners, a full
    square (apple-touch-icon, which iOS rounds itself) or a circle with a
    ring."""
    if kind == "square":
        return [("rect", 0, 0, SIZE, SIZE, 96, BG)]
    if kind == "full":
        return [("rect", 0, 0, SIZE, SIZE, 0, BG)]
    return [("ellipse", 256, 256, 256, 256, 0, ACCENT), ("ellipse", 256, 256, 240, 240, 0, BG)]


def inside(shape, x, y):
    kind = shape[0]
    if kind == "ellipse":
        _, cx, cy, rx, ry, deg, _ = shape
        a = math.radians(deg)
        dx, dy = x - cx, y - cy
        u = dx * math.cos(a) + dy * math.sin(a)
        v = -dx * math.sin(a) + dy * math.cos(a)
        return (u / rx) ** 2 + (v / ry) ** 2 <= 1.0
    if kind == "rect":
        _, x0, y0, w, h, r, _ = shape
        if not (x0 <= x <= x0 + w and y0 <= y <= y0 + h):
            return False
        cx = min(max(x, x0 + r), x0 + w - r)
        cy = min(max(y, y0 + r), y0 + h - r)
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    points = shape[1]
    hit = False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]
        xj, yj = points[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def box(shape):
    kind = shape[0]
    if kind == "ellipse":
        _, cx, cy, rx, ry, _, _ = shape
        r = max(rx, ry)
        return cx - r, cy - r, cx + r, cy + r
    if kind == "rect":
        _, x0, y0, w, h, _, _ = shape
        return x0, y0, x0 + w, y0 + h
    xs = [p[0] for p in shape[1]]
    ys = [p[1] for p in shape[1]]
    return min(xs), min(ys), max(xs), max(ys)


def render(shapes, n, samples=4):
    """RGBA rows of n by n pixels: each sample takes the colour of the last
    shape over it, a pixel the mean of its samples, transparent where no
    shape is."""
    m = n * samples
    scale = SIZE / m
    grid = [None] * (m * m)
    for shape in shapes:
        colour = rgb(shape[-1])
        x0, y0, x1, y1 = box(shape)
        for sy in range(max(0, int(y0 / scale)), min(m, int(y1 / scale) + 1)):
            y = (sy + 0.5) * scale
            row = sy * m
            for sx in range(max(0, int(x0 / scale)), min(m, int(x1 / scale) + 1)):
                if inside(shape, (sx + 0.5) * scale, y):
                    grid[row + sx] = colour
    rows = []
    k = samples * samples
    for py in range(n):
        row = bytearray()
        for px in range(n):
            r = g = b = a = 0
            for sy in range(py * samples, (py + 1) * samples):
                for sx in range(px * samples, (px + 1) * samples):
                    c = grid[sy * m + sx]
                    if c is not None:
                        r += c[0]
                        g += c[1]
                        b += c[2]
                        a += 1
            if a == 0:
                row += b"\0\0\0\0"
            else:
                row += bytes((round(r / a), round(g / a), round(b / a), round(255 * a / k)))
        rows.append(bytes(row))
    return rows


def png(rows, n):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\0" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def ico(entries):
    """An ICO of PNG entries (Windows Vista on reads them), each (n, png)."""
    head = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    table = b""
    for n, data in entries:
        table += struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    return head + table + b"".join(d for _, d in entries)


def svg(shapes):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">',
           "<title>ROXIE</title>"]
    for s in shapes:
        if s[0] == "ellipse":
            _, cx, cy, rx, ry, deg, c = s
            turn = f' transform="rotate({deg} {cx} {cy})"' if deg else ""
            out.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{c}"{turn}/>')
        elif s[0] == "rect":
            _, x, y, w, h, r, c = s
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{c}"/>')
        else:
            pts = " ".join(f"{x},{y}" for x, y in s[1])
            out.append(f'<polygon points="{pts}" fill="{s[2]}"/>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "share", "icons")
    square = background("square") + FACE
    made = {}

    def write(name, data):
        with open(os.path.join(out, name), "wb") as f:
            f.write(data)
        made[name] = len(data)

    write("roxie.svg", svg(square).encode())
    for n in (16, 32, 48, 64, 128, 180, 192, 256, 512):
        write(f"roxie-{n}.png", png(render(square, n), n))
    for n in (96, 128, 256, 512):
        write(f"roxie-round-{n}.png", png(render(background("round") + FACE, n), n))
    write("apple-touch-icon.png", png(render(background("full") + FACE, 180), 180))
    with open(os.path.join(out, "roxie-16.png"), "rb") as f16, open(os.path.join(out, "roxie-32.png"), "rb") as f32, \
            open(os.path.join(out, "roxie-48.png"), "rb") as f48:
        write("favicon.ico", ico([(16, f16.read()), (32, f32.read()), (48, f48.read())]))
    for name in sorted(made):
        print(f"{made[name]:8d} {name}")


main()
