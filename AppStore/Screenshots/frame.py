#!/usr/bin/env python3
"""Turns raw simulator captures into App Store screenshots: a headline on the
icon's gradient with the real screen beneath it. Needs Pillow.

    python3 AppStore/Screenshots/frame.py

Reads raw/<device>/<shot>.png, writes <device>/<n>-<shot>.jpg at the exact
size App Store Connect asks for. See ../Screenshots.md for how to recapture.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

here = pathlib.Path(__file__).parent
TOP, BOTTOM = (238, 138, 80), (201, 82, 45)  # the app icon's gradient
INK = (255, 250, 242)

DEVICES = {
    # folder: (canvas size, screen width, corner radius, headline pt, subline pt, top margin)
    "iphone-6.5": ("iphone", (1284, 2778), 1060, 84, 104, 46, 150),
    "ipad-13": ("ipad", (2064, 2752), 1760, 56, 120, 54, 130),
}

SHOTS = {
    "iphone": [
        ("1-feed", "Every Sunday dinner,\nkept.", "Snap it, name it, give it your stars."),
        ("3-detail", "Your stars\nstay yours.", "Private ratings. Not even the cook sees them."),
        ("2-feed-scrolled", "Years of dinners,\none album.", "The whole family adds to the same timeline."),
        ("7-ideas", "What's for\ndinner?", "Ideas from your own table, not the internet."),
        ("9-live", "Everyone at\nthe table.", "Go live and the family checks in with photos."),
        ("8-family", "Just your family.\nNo accounts.", "Everything stays in your iCloud."),
    ],
    "ipad": [
        ("1-feed", "Every Sunday dinner, kept.", "Snap it, name it, give it your stars."),
        ("2-feed-scrolled", "Years of dinners, one album.", "The whole family adds to the same timeline."),
        ("3-detail", "Your stars stay yours.", "Private ratings. Not even the cook sees them."),
        ("9-live", "Everyone at the table.", "Go live and the family checks in with photos."),
        ("8-family", "Just your family. No accounts.", "Everything stays in your iCloud."),
    ],
}


def font(size, weight):
    face = ImageFont.truetype(str(here / "fonts" / "Newsreader.ttf"), size)
    face.set_variation_by_axes([weight, 72])  # weight, optical size
    return face


def gradient(size):
    width, height = size
    column = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / (height - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return column.resize(size)


def frame(raw, size, screen_width, radius, head_pt, sub_pt, top, headline, subline):
    canvas = gradient(size)
    draw = ImageDraw.Draw(canvas)
    center = size[0] // 2

    head = font(head_pt, 660)
    draw.multiline_text((center, top), headline, font=head, fill=INK, anchor="ma", align="center", spacing=head_pt * 0.3)
    bottom = draw.multiline_textbbox((center, top), headline, font=head, anchor="ma", align="center", spacing=head_pt * 0.3)[3]
    sub = font(sub_pt, 480)
    draw.text((center, bottom + sub_pt * 0.9), subline, font=sub, fill=INK, anchor="ma")
    y = round(bottom + sub_pt * 0.9 + sub_pt * 2.6)

    screen = Image.open(raw).convert("RGB")
    screen = screen.resize((screen_width, round(screen.height * screen_width / screen.width)), Image.LANCZOS)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *screen.size), radius, fill=255)
    x = (size[0] - screen_width) // 2

    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 24, x + screen.width, y + 24 + screen.height), radius, fill=(70, 20, 0, 120))
    canvas.paste(shadow.filter(ImageFilter.GaussianBlur(40)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.paste(screen, (x, y), mask)
    return canvas


for folder, (kind, size, screen_width, radius, head_pt, sub_pt, top) in DEVICES.items():
    out = here / folder
    out.mkdir(exist_ok=True)
    for index, (shot, headline, subline) in enumerate(SHOTS[kind], start=1):
        image = frame(here / "raw" / kind / f"{shot}.png", size, screen_width, radius, head_pt, sub_pt, top, headline, subline)
        path = out / f"{index}-{shot.split('-', 1)[1]}.jpg"
        image.save(path, quality=93, subsampling=0)
        print(path.relative_to(here), image.size)
