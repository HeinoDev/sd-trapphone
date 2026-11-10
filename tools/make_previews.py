"""
make_previews.py -- composes the pictures in the README (docs/previews/*.webp).

    python tools/make_previews.py <shots folder> <renders folder> [in-game screenshot]

shots    608 x 1432 captures of the handset page, one per screen:
         http://localhost:4317/#shot=<colour>:<screen>[:<number>], saved as
         <colour>_<screen>[_<number>].png
renders  props_faces.png and props_backs.png from tools/render_props.py

Fonts are read from web/node_modules (run `npm install` in web/ first).
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_textures import silhouette  # noqa: E402  the handset's outline, shared with the icons

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT = os.path.join(ROOT, "docs", "previews")
FONTS = os.path.join(ROOT, "web", "node_modules", "@fontsource")

W, H = 1920, 1080
INK = (236, 240, 246)
DIM = (150, 160, 176)
ACCENT = (255, 168, 40)


def font(family, weight, size):
    path = os.path.join(FONTS, family, "files", "%s-latin-%s-normal.woff" % (family, weight))
    return ImageFont.truetype(path, size)


def backdrop(w=W, h=H, glow=(40, 120, 220)):
    """Near-black with one soft pool of light, the way a product shot is lit."""
    bg = Image.new("RGB", (w, h), (13, 15, 20))
    pool = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(pool)
    d.ellipse([w * 0.30, h * 0.10, w * 1.05, h * 1.25], fill=glow)
    pool = pool.filter(ImageFilter.GaussianBlur(220))
    bg = Image.blend(bg, Image.eval(pool, lambda v: v), 0.0)
    return Image.composite(pool, bg, pool.convert("L").point(lambda v: int(v * 0.42)))


def phone(shots, name, height):
    """One capture cut to the handset's outline, at a given height."""
    src = Image.open(os.path.join(shots, name + ".png")).convert("RGB")
    scale = height / 716.0
    w = int(304 * scale)
    img = src.resize((w, height), Image.LANCZOS).convert("RGBA")
    img.putalpha(silhouette(0, scale).resize((w, height), Image.LANCZOS))
    return img


def place(bg, img, x, y):
    """Paste with a soft shadow under it."""
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    blob = Image.new("RGBA", img.size, (0, 0, 0, 170))
    blob.putalpha(img.getchannel("A").point(lambda v: int(v * 0.66)))
    shadow.alpha_composite(blob, (x + 10, y + 26))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    out = bg.convert("RGBA")
    out.alpha_composite(shadow)
    out.alpha_composite(img, (x, y))
    return out.convert("RGB")


def heading(bg, x, y, kicker, title, body, width=520):
    d = ImageDraw.Draw(bg)
    d.text((x, y), kicker, font=font("michroma", "400", 20), fill=ACCENT)
    f_title = font("michroma", "400", 46)
    ty = y + 46
    for line in title.split("\n"):
        d.text((x, ty), line, font=f_title, fill=INK)
        ty += 62
    f_body = font("pixelify-sans", "400", 30)
    ty += 18
    for para in body:
        words, line = para.split(), ""
        for word in words:
            trial = (line + " " + word).strip()
            if d.textlength(trial, font=f_body) > width and line:
                d.text((x, ty), line, font=f_body, fill=DIM)
                ty += 38
                line = word
            else:
                line = trial
        if line:
            d.text((x, ty), line, font=f_body, fill=DIM)
            ty += 38
        ty += 16
    return bg


def row(bg, shots, names, height, left, right, y):
    """Spread handsets evenly between two x positions."""
    w = int(304 * height / 716.0)
    gap = (right - left - w * len(names)) / max(1, len(names) - 1)
    for i, name in enumerate(names):
        bg = place(bg, phone(shots, name, height), int(left + i * (w + gap)), y + (26 if i % 2 else 0))
    return bg


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name + ".webp"), "WEBP", quality=90, method=6)


def render_strip(renders, name, width):
    """A prop render trimmed to what it shows and scaled to a width."""
    img = Image.open(os.path.join(renders, name + ".png")).convert("RGBA")
    img = img.crop(img.getbbox())
    return img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)


def main(shots, renders, ingame=None):
    # Banner: the ten props in a row under the name.
    bg = backdrop(W, 960)
    d = ImageDraw.Draw(bg)
    title = "sd-trapphone"
    f = font("michroma", "400", 96)
    d.text(((W - d.textlength(title, font=f)) / 2, 96), title, font=f, fill=INK)
    sub = "A keypad burner that runs a street business"
    f2 = font("pixelify-sans", "400", 40)
    d.text(((W - d.textlength(sub, font=f2)) / 2, 232), sub, font=f2, fill=DIM)
    strip = render_strip(renders, "props_faces", 1640)
    canvas = bg.convert("RGBA")
    canvas.alpha_composite(strip, ((W - strip.width) // 2, 356))
    save(canvas.convert("RGB"), "sd-trapphone-banner")

    # 1. Selling.
    bg = backdrop(glow=(210, 120, 30))
    bg = heading(bg, 96, 250, "CORNER SALES", "Customers text.\nYou name the price.", [
        "Start serving from the phone and offers arrive as texts while the customer walks over.",
        "Accept, haggle or turn them down. Mark a pull-up spot and some arrive by car.",
    ])
    bg = row(bg, shots, ["bling_messages", "bubblegum_thread_555-7731", "lime_hustle"], 860, 720, 1840, 96)
    save(bg, "01-selling")

    # 2. People and turf.
    bg = backdrop(glow=(140, 70, 220))
    bg = heading(bg, 96, 250, "PEOPLE AND TURF", "A name brings\nnew numbers.", [
        "Plugs, a supplier, an informant and each crew's shot caller reach out as you level.",
        "Order weight, buy tips, pay for protection, and check whose block you are standing on.",
    ], width=470)
    bg = row(bg, shots, ["grape_contacts", "graphite_contact_555-0151", "tangerine_order_555-0142", "cherry_turf"], 700, 640, 1860, 180)
    save(bg, "02-people-turf")

    # 3. The handset.
    bg = backdrop(glow=(30, 150, 200))
    bg = heading(bg, 96, 250, "THE HANDSET", "Keys, soft keys\nand a d-pad.", [
        "Every screen works by mouse, by keyboard or by clicking the keypad, and you can still walk and drive.",
        "Ringtones are played by the page itself. There is a game, of course.",
    ], width=470)
    bg = row(bg, shots, ["ice_menu", "pearl_status", "chrome_games", "ice_tones"], 700, 640, 1860, 180)
    save(bg, "03-handset")

    # 4. The props.
    bg = backdrop(glow=(60, 90, 140))
    d = ImageDraw.Draw(bg)
    d.text((96, 70), "TEN COLOURS", font=font("michroma", "400", 20), fill=ACCENT)
    d.text((96, 112), "Each colour is its own item and its own model.", font=font("michroma", "400", 40), fill=INK)
    canvas = bg.convert("RGBA")
    faces = render_strip(renders, "props_faces", 1560)
    backs = render_strip(renders, "props_backs", 1560)
    canvas.alpha_composite(faces, ((W - faces.width) // 2, 210))
    canvas.alpha_composite(backs, ((W - backs.width) // 2, 640))
    save(canvas.convert("RGB"), "04-props")

    # 5. In game, as captured.
    if ingame and os.path.isfile(ingame):
        shot = Image.open(ingame).convert("RGB").resize((W, H), Image.LANCZOS)
        save(shot, "05-in-game")

    print("previews written to", OUT)


if __name__ == "__main__":
    main(*sys.argv[1:4])
