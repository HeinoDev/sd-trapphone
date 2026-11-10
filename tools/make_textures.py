"""
make_textures.py -- composes the handset prop's textures and the inventory icons from the art
captured off the handset page.

    python tools/make_textures.py

Reads   tools/art/prop_<colour>.png, tools/art/propback_<colour>.png   (608 x 1432 each)
Writes  tools/art/tex_<colour>.png      1024 x 1024: the face on the left, the back beside it
        images/trap_phone_<colour>.png  128 x 128 inventory icon on a clear background

The art comes from the page itself, so the prop always matches what is on screen. To redo it
after a design change: `npm run build` and `npx vite preview --port 4317` in web/, then capture
http://localhost:4317/#prop=<colour> and #propback=<colour> at a 608 x 1432 window (headless
Chrome's --screenshot does it), and run this again, then tools/build_prop.py in Blender.

Layout numbers here are shared with build_prop.py: change them in both.
"""

import os
from PIL import Image, ImageDraw, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "art")
IMAGES = os.path.normpath(os.path.join(HERE, "..", "images"))

COLOURS = ["graphite", "chrome", "pearl", "bling", "ice", "bubblegum", "lime", "cherry", "grape", "tangerine"]

TEX = 1024
FACE_W = 434            # 608 x 1432 scaled to the texture's height
BACK_X = 440            # the back sits beside the face with a small gutter
SCREEN = (38, 76, 266, 364)   # the display on the 304 x 716 page, left, top, right, bottom

# Game lighting lifts a bright albedo a long way. The plastic is pulled down so a white phone
# is not a glowing one; the display is left alone, it is drawn with an emissive shader.
BODY_GAIN = 0.76


def compose(colour):
    face = Image.open(os.path.join(ART, "prop_%s.png" % colour)).convert("RGB")
    back = Image.open(os.path.join(ART, "propback_%s.png" % colour)).convert("RGB")

    face_s = face.resize((FACE_W, TEX), Image.LANCZOS)
    back_s = back.resize((FACE_W, TEX), Image.LANCZOS)

    k = TEX / 716.0
    box = tuple(int(round(v * k)) for v in SCREEN)
    display = face_s.crop(box)

    face_s = ImageEnhance.Brightness(face_s).enhance(BODY_GAIN)
    back_s = ImageEnhance.Brightness(back_s).enhance(BODY_GAIN)
    face_s.paste(display, box[:2])

    # Fill the whole sheet with the body colour first, so the gutters and the unused strip
    # never bleed a foreign colour into the mips.
    body = back_s.getpixel((FACE_W // 2, TEX // 2))
    sheet = Image.new("RGB", (TEX, TEX), body)
    sheet.paste(face_s, (0, 0))
    sheet.paste(back_s, (BACK_X, 0))
    sheet.save(os.path.join(ART, "tex_%s.png" % colour))

    return face


def silhouette(size, scale):
    """The handset's outline as a mask: a rectangle with the page's elliptical corners."""
    w, h = int(304 * scale), int(716 * scale)
    big = 4
    mask = Image.new("L", (w * big, h * big), 0)
    d = ImageDraw.Draw(mask)
    s = scale * big
    rxt, ryt, rxb, ryb = 74 * s, 60 * s, 96 * s, 88 * s
    W, H = w * big, h * big
    d.rectangle([rxt, 0, W - rxt, ryt], fill=255)
    d.rectangle([0, ryt, W, H - ryb], fill=255)
    d.rectangle([rxb, H - ryb, W - rxb, H], fill=255)
    d.ellipse([0, 0, 2 * rxt, 2 * ryt], fill=255)
    d.ellipse([W - 2 * rxt, 0, W, 2 * ryt], fill=255)
    d.ellipse([0, H - 2 * ryb, 2 * rxb, H], fill=255)
    d.ellipse([W - 2 * rxb, H - 2 * ryb, W, H], fill=255)
    return mask.resize((w, h), Image.LANCZOS)


def icon(colour, face):
    size = 128
    scale = (size - 8) / 716.0
    w, h = int(304 * scale), int(716 * scale)
    small = face.resize((w, h), Image.LANCZOS).convert("RGBA")
    small.putalpha(silhouette(size, scale))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(small, ((size - w) // 2, (size - h) // 2), small)
    os.makedirs(IMAGES, exist_ok=True)
    out.save(os.path.join(IMAGES, "trap_phone_%s.png" % colour))


if __name__ == "__main__":
    for c in COLOURS:
        icon(c, compose(c))
    print("textures and icons written for", len(COLOURS), "colours")
