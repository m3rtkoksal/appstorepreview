"""
App Store screenshot generator.

Builds one continuous panoramic scene (background, glows, floating chips)
and slices it into 4 frames of 1284x2778 so the set reads like consecutive
crops of a single photo. Phones are tilted at varying angles and bleed
slightly into neighbouring frames; chips straddle the frame boundaries.

Run:  python3 generate.py
"""

from __future__ import annotations

import math
import os
from dataclasses import dataclass, field

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #

W, H = 1284, 2778          # App Store 6.7" portrait
N = 3                      # number of frames
PW = W * N                 # panorama width

ASSETS = "assets"
FONTS = "fonts"
OUT = "output"

NAVY = (11, 18, 32)
NAVY_2 = (19, 30, 54)
CARD = (255, 255, 255)
INK = (15, 23, 42)
MUTED = (163, 177, 201)
ORANGE = (242, 101, 34)
ORANGE_2 = (255, 145, 66)
GREEN = (22, 163, 74)
GREEN_BG = (220, 252, 231)
VIOLET = (124, 58, 237)


@dataclass
class Frame:
    shot: str
    label: str
    headline: str                 # words wrapped in *asterisks* render orange
    sub: str
    angle: float                  # phone tilt in degrees
    dx: int = 0                   # phone offset from frame centre
    dy: int = 0


FRAMES = [
    Frame(
        shot="b8546236-1488-4ae4-a80a-cd83e41b9c10.png",
        label="Keşfet",
        headline="Evinize usta bulmak\nartık *çok kolay*",
        sub="Dakikalar içinde en iyi ustalardan teklif alın.",
        angle=-7, dx=-60, dy=10,
    ),
    Frame(
        shot="5fb32d3a-29ea-4b51-bf5b-e0870220d22b.png",
        label="Talep oluştur",
        headline="Talebini yaz,\n*kategorini* seç",
        sub="20 kategori, birkaç dokunuşla hazır talep.",
        angle=5, dx=70, dy=-20,
    ),
    Frame(
        shot="97bedec4-906e-4761-b93e-c299516298d6.png",
        label="Teklifler",
        headline="En fazla *10 teklif*,\ntek ekranda",
        sub="Gelen teklifleri karşılaştır, en iyisini seç.",
        angle=-4, dx=-40, dy=0,
    ),
]

# Floating chips that sit on the seams between frames (panorama coordinates).
@dataclass
class Chip:
    kind: str
    x: int
    y: int
    angle: float
    extra: dict = field(default_factory=dict)


CHIPS = [
    Chip("status", x=W * 1, y=1460, angle=-6),
    Chip("progress", x=W * 2, y=1180, angle=4, extra={"done": 7, "total": 10}),
    Chip("check", x=W * 3 - 240, y=1720, angle=-3),
]


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def vertical_gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    mask = Image.linear_gradient("L").resize(size)
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), mask)


def add_glow(base: Image.Image, center: tuple[int, int], radii: tuple[int, int],
             color: tuple, alpha: int, blur: int) -> None:
    """Soft elliptical glow, rendered at 1/4 scale for speed."""
    s = 4
    layer = Image.new("RGBA", (base.width // s, base.height // s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center[0] // s, center[1] // s
    rx, ry = radii[0] // s, radii[1] // s
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur // s))
    layer = layer.resize(base.size, Image.BICUBIC)
    base.alpha_composite(layer)


def shadowed(layer_size: tuple[int, int], draw_fn, shadow_alpha=150,
             shadow_blur=48, shadow_offset=(0, 40), pad=220) -> Image.Image:
    """Return an RGBA layer containing a blurred shadow plus the drawn object."""
    w, h = layer_size
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    obj = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw_fn(obj)
    alpha = obj.getchannel("A").point(lambda a: a * shadow_alpha // 255)
    shadow.paste((0, 0, 0, 255), (pad + shadow_offset[0], pad + shadow_offset[1]), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(obj, (pad, pad))
    return canvas


def paste_rotated(base: Image.Image, layer: Image.Image, center: tuple[int, int], angle: float) -> None:
    rotated = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    base.alpha_composite(rotated, (center[0] - rotated.width // 2, center[1] - rotated.height // 2))


# --------------------------------------------------------------------------- #
# Phone mockup
# --------------------------------------------------------------------------- #

SCREEN_W = 860
BEZEL = 22


def build_phone(shot_path: str) -> Image.Image:
    shot = Image.open(shot_path).convert("RGB")
    screen_h = round(SCREEN_W * shot.height / shot.width)
    screen = shot.resize((SCREEN_W, screen_h), Image.LANCZOS)
    screen = screen.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))

    phone_w, phone_h = SCREEN_W + BEZEL * 2, screen_h + BEZEL * 2
    outer_r = 128

    def draw(obj: Image.Image) -> None:
        d = ImageDraw.Draw(obj)
        # body: subtle metallic edge then matte black frame
        d.rounded_rectangle((0, 0, phone_w - 1, phone_h - 1), outer_r, fill=(38, 40, 46))
        d.rounded_rectangle((3, 3, phone_w - 4, phone_h - 4), outer_r - 3, fill=(12, 12, 14))
        # screen
        mask = rounded_mask((SCREEN_W, screen_h), outer_r - BEZEL)
        obj.paste(screen, (BEZEL, BEZEL), mask)
        # dynamic island
        iw, ih = 250, 72
        ix = (phone_w - iw) // 2
        iy = BEZEL + 24
        d.rounded_rectangle((ix, iy, ix + iw, iy + ih), ih // 2, fill=(8, 8, 10))
        # side buttons
        d.rounded_rectangle((-4, 420, 2, 520), 3, fill=(60, 62, 68))
        d.rounded_rectangle((-4, 580, 2, 760), 3, fill=(60, 62, 68))
        d.rounded_rectangle((-4, 800, 2, 980), 3, fill=(60, 62, 68))
        d.rounded_rectangle((phone_w - 3, 620, phone_w + 3, 900), 3, fill=(60, 62, 68))

    return shadowed((phone_w, phone_h), draw, shadow_alpha=190, shadow_blur=70, shadow_offset=(0, 70))


# --------------------------------------------------------------------------- #
# Chips
# --------------------------------------------------------------------------- #

def build_chip(chip: Chip) -> Image.Image:
    f_title = font("Inter-SemiBold.ttf", 40)
    f_small = font("Inter-Medium.ttf", 32)
    pad_x, pad_y = 40, 34

    if chip.kind == "status":
        text = "Teklif toplanıyor"
        tw = f_title.getlength(text)
        w, h = int(pad_x * 2 + 28 + 20 + tw), int(pad_y * 2 + 48)

        def draw(obj):
            d = ImageDraw.Draw(obj)
            d.rounded_rectangle((0, 0, w - 1, h - 1), 40, fill=CARD)
            cy = h // 2
            d.ellipse((pad_x, cy - 14, pad_x + 28, cy + 14), fill=GREEN)
            d.text((pad_x + 48, cy), text, font=f_title, fill=INK, anchor="lm")

    elif chip.kind == "progress":
        done, total = chip.extra["done"], chip.extra["total"]
        label, count = "Gelen teklifler", f"{done}/{total}"
        w, h = 520, 168

        def draw(obj):
            d = ImageDraw.Draw(obj)
            d.rounded_rectangle((0, 0, w - 1, h - 1), 40, fill=CARD)
            d.text((pad_x, 56), label, font=f_title, fill=INK, anchor="lm")
            d.text((w - pad_x, 56), count, font=f_small, fill=(100, 112, 138), anchor="rm")
            gap, y0, y1 = 10, 104, 124
            seg_w = (w - pad_x * 2 - gap * (total - 1)) / total
            for i in range(total):
                x0 = pad_x + i * (seg_w + gap)
                col = ORANGE if i < done else (226, 232, 240)
                d.rounded_rectangle((x0, y0, x0 + seg_w, y1), 8, fill=col)

    else:  # check
        text = "Güvenle seç"
        tw = f_title.getlength(text)
        w, h = int(pad_x * 2 + 56 + 20 + tw), int(pad_y * 2 + 56)

        def draw(obj):
            d = ImageDraw.Draw(obj)
            d.rounded_rectangle((0, 0, w - 1, h - 1), 40, fill=CARD)
            cy = h // 2
            d.ellipse((pad_x, cy - 28, pad_x + 56, cy + 28), fill=ORANGE)
            cx = pad_x + 28
            d.line([(cx - 13, cy + 1), (cx - 3, cy + 11), (cx + 15, cy - 9)], fill=CARD, width=6, joint="curve")
            d.text((pad_x + 76, cy), text, font=f_title, fill=INK, anchor="lm")

    return shadowed((w, h), draw, shadow_alpha=120, shadow_blur=40, shadow_offset=(0, 30), pad=120)


# --------------------------------------------------------------------------- #
# Typography
# --------------------------------------------------------------------------- #

def parse_markup(line: str) -> list[tuple[str, tuple]]:
    parts, col, buf = [], WHITE_, ""
    for ch in line:
        if ch == "*":
            if buf:
                parts.append((buf, col))
                buf = ""
            col = ORANGE_2 if col == WHITE_ else WHITE_
        else:
            buf += ch
    if buf:
        parts.append((buf, col))
    return parts


WHITE_ = (255, 255, 255)


def draw_headline(d: ImageDraw.ImageDraw, x: int, y: int, text: str, max_w: int) -> int:
    size = 108
    lines = text.split("\n")
    while size > 60:
        f = font("InterDisplay-Bold.ttf", size)
        if all(f.getlength(l.replace("*", "")) <= max_w for l in lines):
            break
        size -= 2
    f = font("InterDisplay-Bold.ttf", size)
    line_h = int(size * 1.08)
    for i, line in enumerate(lines):
        cx = x
        for seg, col in parse_markup(line):
            d.text((cx, y + i * line_h), seg, font=f, fill=col)
            cx += f.getlength(seg)
    return y + len(lines) * line_h


# --------------------------------------------------------------------------- #
# Scene
# --------------------------------------------------------------------------- #

def build_background() -> Image.Image:
    bg = vertical_gradient((PW, H), NAVY_2, NAVY).convert("RGBA")

    # faint blueprint grid, fading out towards the bottom (echoes the app header)
    grid = Image.new("RGBA", (PW, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    step = 96
    for x in range(0, PW, step):
        g.line([(x, 0), (x, H)], fill=(255, 255, 255, 255), width=2)
    for y in range(0, H, step):
        g.line([(0, y), (PW, y)], fill=(255, 255, 255, 255), width=2)
    fade = Image.linear_gradient("L").resize((PW, H)).point(lambda v: int(max(0, 22 - v * 22 / 150)))
    grid.putalpha(fade)
    bg.alpha_composite(grid)

    # one big "sunrise" glow that drifts across the whole panorama
    add_glow(bg, (int(PW * 0.30), -300), (2600, 1500), ORANGE, 110, 520)
    add_glow(bg, (int(PW * 0.72), -200), (1800, 1100), ORANGE_2, 70, 520)
    # cool counterweights low in the scene
    add_glow(bg, (int(PW * 0.12), 2650), (1500, 900), VIOLET, 70, 480)
    add_glow(bg, (int(PW * 0.88), 2500), (1700, 1000), (37, 99, 235), 60, 480)
    add_glow(bg, (int(PW * 0.5), 2900), (2200, 700), ORANGE, 55, 520)
    return bg


def build_scene() -> Image.Image:
    scene = build_background()
    d = ImageDraw.Draw(scene)

    margin = 96
    f_label = font("Inter-SemiBold.ttf", 34)
    f_num = font("InterDisplay-Bold.ttf", 34)
    f_sub = font("Inter-Medium.ttf", 44)

    # connector line running behind every step badge, across the whole panorama
    badge_y = 236
    d.line([(0, badge_y), (PW, badge_y)], fill=(255, 255, 255, 34), width=2)

    for i, fr in enumerate(FRAMES):
        ox = i * W
        # step badge + label
        r = 34
        bx = ox + margin + r
        d.ellipse((bx - r, badge_y - r, bx + r, badge_y + r), fill=ORANGE)
        d.text((bx, badge_y + 1), str(i + 1), font=f_num, fill=WHITE_, anchor="mm")
        label = fr.label.upper()
        lw = f_label.getlength(label) + 40
        d.rounded_rectangle((bx + r + 20, badge_y - 30, bx + r + 20 + lw, badge_y + 30), 30, fill=NAVY_2 + (255,))
        d.text((bx + r + 40, badge_y + 1), label, font=f_label, fill=MUTED, anchor="lm")

        # headline + sub
        y_end = draw_headline(d, ox + margin, 330, fr.headline, W - margin * 2)
        d.text((ox + margin, y_end + 28), fr.sub, font=f_sub, fill=MUTED)

    # phones (drawn after text so tilted corners can overlap the copy area)
    for i, fr in enumerate(FRAMES):
        phone = build_phone(os.path.join(ASSETS, fr.shot))
        cx = i * W + W // 2 + fr.dx
        cy = 720 + (phone.height - 440) // 2 + fr.dy
        paste_rotated(scene, phone, (cx, cy), fr.angle)

    # chips on the seams
    for chip in CHIPS:
        paste_rotated(scene, build_chip(chip), (chip.x, chip.y), chip.angle)

    return scene


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    scene = build_scene().convert("RGB")
    scene.save(os.path.join(OUT, "panorama.png"))

    for i in range(N):
        frame = scene.crop((i * W, 0, (i + 1) * W, H))
        frame.save(os.path.join(OUT, f"appstore_{i + 1}_1284x2778.png"))
        frame.resize((1242, 2688), Image.LANCZOS).save(os.path.join(OUT, f"appstore_{i + 1}_1242x2688.png"))

    # small contact sheet with App Store-style gaps for a quick look
    gap = 40
    sheet = Image.new("RGB", ((W + gap) * N - gap, H), (24, 24, 28))
    for i in range(N):
        sheet.paste(scene.crop((i * W, 0, (i + 1) * W, H)), (i * (W + gap), 0))
    sheet.resize((sheet.width // 4, sheet.height // 4), Image.LANCZOS).save(os.path.join(OUT, "preview_sheet.png"))
    print("done ->", OUT)


if __name__ == "__main__":
    main()
