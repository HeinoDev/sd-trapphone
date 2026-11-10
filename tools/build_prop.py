"""
build_prop.py -- builds the trap phone's in-hand prop in every colour and exports it for FiveM.

    sd_trapphone_<colour>.ydr   x10, texture EMBEDDED in each drawable, so no .ytd
    sd_trapphone.ytyp           one archetype per model

all written into ../stream. Run tools/make_textures.py first: it composes the textures this
reads (tools/art/tex_<colour>.png) from art captured off the handset page, which is why the
prop looks like the phone on screen.

Needs Blender 5.x with the Sollumz extension enabled, and a Blender WINDOW (Sollumz's ytyp
operators read context.space_data, which a background -b session does not have):

    blender --python tools/build_prop.py -- <report.json> [preview folder]

builds, writes the report, renders two preview pictures of the first colour when a folder is
given, and closes Blender again. Everything it makes lives in a scene of its own.

The model is laid out from the same numbers as the page's CSS (a 304 x 716 px handset), so
every key, the d-pad and the lens are real raised geometry sitting exactly under their art.
Local axes follow GTA's own hand props: X across the screen, Y through it, Z up it, origin at
the centre, screen facing -Y. That is what lets it sit in the texting grip with no offset.

If a model is changed and re-exported for a server with players on it, a connected client
keeps drawing its own copy of a same-named streamed file until it reconnects.
"""

import bpy
import bmesh
import json
import math
import os
import struct
import sys
import tempfile
import traceback

import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCE = os.path.normpath(os.path.join(HERE, ".."))
STREAM = os.path.join(RESOURCE, "stream")
ART = os.path.join(HERE, "art")

PREFIX = "sd_trapphone_"
YTYP = "sd_trapphone"
COLOURS = ["graphite", "chrome", "pearl", "bling", "ice", "bubblegum", "lime", "cherry", "grape", "tangerine"]
LOD_DIST = 60.0
SCENE = "sd_trapphone_build"
SZ = "bl_ext.user_default.sollumz"

# -- size -------------------------------------------------------------------------------------------
PAGE_W, PAGE_H = 304.0, 716.0   # the handset on the page, in CSS px
WIDTH = 0.046                   # metres across; the height follows from the page's proportions
DEPTH = 0.019
K = WIDTH / PAGE_W              # metres per page px

# -- texture layout (shared with make_textures.py) ----------------------------------------------------
TEX = 1024
FACE_W = 434
BACK_X = 440
SCREEN = (38.0, 76.0, 266.0, 364.0)   # left, top, right, bottom on the page

# -- the body: (depth from the face in metres, inset from the outline in page px) ---------------------
# A flat face, a rounded front edge, straight sides, a rounded back edge, a flat back.
BODY = [
    (0.00000, 14.0), (0.00025, 9.0), (0.00080, 5.0), (0.00180, 2.0), (0.00320, 0.5), (0.00500, 0.0),
    (0.00950, 0.0),
    (0.01400, 0.0), (0.01580, 0.5), (0.01720, 2.0), (0.01820, 5.0), (0.01875, 9.0), (0.01900, 14.0),
]
MID = 0.0095   # everything nearer the face than this wears the face's art, the rest the back's


# -- texture ----------------------------------------------------------------------------------------
def bc1(rgb):
    """DXT1-compress uint8 (h, w, 3). Lifted from sd-minis build_textures.py."""
    h, w, _ = rgb.shape
    b = rgb.reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3).astype(np.float32)
    mean = b.mean(axis=1, keepdims=True)
    d = b - mean
    cov = np.einsum('nij,nik->njk', d, d)
    axis = np.tile(np.array([0.299, 0.587, 0.114], np.float32), (b.shape[0], 1))
    for _ in range(5):
        axis = np.einsum('njk,nk->nj', cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    t = np.einsum('nij,nj->ni', d, axis)
    lo = mean[:, 0, :] + axis * t.min(axis=1, keepdims=True)
    hi = mean[:, 0, :] + axis * t.max(axis=1, keepdims=True)

    def to565(c):
        c = np.clip(c, 0, 255)
        return ((np.round(c[:, 0] * 31 / 255).astype(np.uint16) << 11)
                | (np.round(c[:, 1] * 63 / 255).astype(np.uint16) << 5)
                | np.round(c[:, 2] * 31 / 255).astype(np.uint16))

    def from565(c):
        return np.stack([((c >> 11) & 31) * (255.0 / 31), ((c >> 5) & 63) * (255.0 / 63),
                         (c & 31) * (255.0 / 31)], axis=1).astype(np.float32)

    a, z = to565(hi), to565(lo)
    c0, c1 = np.maximum(a, z), np.minimum(a, z)
    p0, p1 = from565(c0), from565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], axis=1)
    idx = ((b[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=3).argmin(axis=2).astype(np.uint32)
    idx[c0 == c1] = 0
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(axis=1).astype(np.uint32)
    out = np.zeros(b.shape[0], dtype=[('c0', '<u2'), ('c1', '<u2'), ('i', '<u4')])
    out['c0'], out['c1'], out['i'] = c0, c1, bits
    return out.tobytes()


def mip_chain(a):
    chain = [a]
    while chain[-1].shape[0] > 1 or chain[-1].shape[1] > 1:
        m = chain[-1]
        m = (m[0::2, 0::2] + m[1::2, 0::2] + m[0::2, 1::2] + m[1::2, 1::2]) * 0.25
        chain.append(m)
    return chain


def read_png(path):
    """A PNG as float32 (h, w, 3) in 0..255, top row first. A byte image's pixels are its
    stored values in its own colourspace, so nothing is converted."""
    img = bpy.data.images.load(path)
    w, h = img.size
    buf = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[::-1, :, :3] * 255.0


def texture_image(colour):
    """The colour's sheet as a packed DXT1 .dds with a full mip chain. Sollumz only embeds a
    texture whose data is DDS: an embedded PNG is skipped at export with a warning and the model
    ships untextured."""
    name = PREFIX + colour + "_d"
    rgb = read_png(os.path.join(ART, "tex_%s.png" % colour))
    if rgb.shape[0] != TEX or rgb.shape[1] != TEX:
        raise RuntimeError("tex_%s.png is %s, expected %d square" % (colour, rgb.shape, TEX))

    body = b""
    for m in mip_chain(rgb):
        u8 = np.clip(m + 0.5, 0, 255).astype(np.uint8)
        if u8.shape[0] < 4:
            u8 = np.tile(u8, (4 // u8.shape[0], 4 // u8.shape[1], 1))
        body += bc1(u8)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    mips = int(math.log2(TEX)) + 1
    hdr = b"DDS " + struct.pack("<7I", 124, flags, TEX, TEX, (TEX // 4) ** 2 * 8, 0, mips) + b"\x00" * 44
    hdr += struct.pack("<2I4s5I", 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    hdr += struct.pack("<5I", 0x1000 | 0x8 | 0x400000, 0, 0, 0, 0)

    path = os.path.join(tempfile.gettempdir(), "sd_trapphone_build", name + ".dds")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(hdr + body)

    old = bpy.data.images.get(name + ".dds")
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.load(path)
    img.name = name + ".dds"       # Sollumz names the embedded texture after the image FILE
    img.colorspace_settings.name = 'sRGB'
    img.pack()
    return img


# How far inside the outline the walls sample the art: past the thin highlight drawn right on
# the edge, short of the chrome band.
EDGE = 4.5


# -- page px -> model, and -> texture ---------------------------------------------------------------
def pos(px, py, y):
    return ((px - PAGE_W / 2) * K, y, (PAGE_H / 2 - py) * K)


def uv_face(px, py):
    """Straight-on projection of the face's art. Sampled a little inside the outline, so the
    walls take the colour of the edge they hang from."""
    px = min(max(px, EDGE), PAGE_W - EDGE)
    py = min(max(py, EDGE), PAGE_H - EDGE)
    return (px / PAGE_W * FACE_W / TEX, 1.0 - py / PAGE_H)


def uv_back(px, py):
    """The back's art, seen from behind: left and right swap."""
    px = min(max(PAGE_W - px, EDGE), PAGE_W - EDGE)
    py = min(max(py, EDGE), PAGE_H - EDGE)
    return ((BACK_X + px / PAGE_W * FACE_W) / TEX, 1.0 - py / PAGE_H)


# -- outlines, in page px -----------------------------------------------------------------------------
def rrect(l, t, r, b, top, bottom, n):
    """A rectangle with elliptical corners: `top` and `bottom` are (rx, ry). Every call with the
    same n gives the same number of points in the same order, so two outlines loft cleanly."""
    pts = []
    corners = [((l + top[0], t + top[1]), top, math.pi),
               ((r - top[0], t + top[1]), top, 1.5 * math.pi),
               ((r - bottom[0], b - bottom[1]), bottom, 0.0),
               ((l + bottom[0], b - bottom[1]), bottom, 0.5 * math.pi)]
    for (cx, cy), (rx, ry), a0 in corners:
        for i in range(n + 1):
            a = a0 + 0.5 * math.pi * i / n
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


def box(l, t, r, b, top, bottom, n):
    """An outline you can ask for at any inset."""
    def at(d):
        shrink = lambda rad: (max(rad[0] - d, 0.6), max(rad[1] - d, 0.6))
        return rrect(l + d, t + d, r - d, b - d, shrink(top), shrink(bottom), n)
    return at


def disc(cx, cy, radius, n):
    def at(d):
        rr = max(radius - d, 0.6)
        return [(cx + rr * math.cos(2 * math.pi * i / n), cy + rr * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return at


BODY_OUTLINE = box(0.0, 0.0, PAGE_W, PAGE_H, (74.0, 60.0), (96.0, 88.0), 12)


# -- geometry ---------------------------------------------------------------------------------------
def ring(bm, pts, y):
    return [(bm.verts.new(pos(px, py, y)), px, py) for px, py in pts]


def face(bm, uv, corners, paint, mat):
    f = bm.faces.new([v for v, _, _ in corners])
    f.material_index = mat
    for loop, (_, px, py) in zip(f.loops, corners):
        loop[uv].uv = paint(px, py)
    return f


def loft(bm, uv, a, b, paint, mat=0):
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        face(bm, uv, [a[i], a[j], b[j], b[i]], paint, mat)


def body(bm, uv):
    """The shell: one closed surface from the face round to the back."""
    y0 = -DEPTH / 2
    rings = [ring(bm, BODY_OUTLINE(inset), y0 + depth) for depth, inset in BODY]
    for i in range(len(rings) - 1):
        nearer_face = (BODY[i][0] + BODY[i + 1][0]) / 2 < MID
        loft(bm, uv, rings[i], rings[i + 1], uv_face if nearer_face else uv_back)
    face(bm, uv, rings[0], uv_face, 0)
    face(bm, uv, rings[-1], uv_back, 0)


def raised(bm, uv, outline, height, bevel_px, bevel_h, back=False, mat=0):
    """A part standing proud of the face (or the back): a foot sunk just inside the shell, a
    wall, a rounded shoulder and a flat top. Closed underneath so its normals resolve."""
    sign, paint = (1.0, uv_back) if back else (-1.0, uv_face)
    surface = sign * DEPTH / 2
    foot = ring(bm, outline(0.0), surface - sign * 0.0006)
    shoulder = ring(bm, outline(0.0), surface + sign * (height - bevel_h))
    top = ring(bm, outline(bevel_px), surface + sign * height)
    loft(bm, uv, foot, shoulder, paint, mat)
    loft(bm, uv, shoulder, top, paint, mat)
    face(bm, uv, top, paint, mat)
    face(bm, uv, foot, paint, mat)


LENS_H = 0.0008


def build(bm, uv):
    body(bm, uv)

    # The lens: the glossy plate that holds the brand and the display.
    raised(bm, uv, box(24, 44, 280, 392, (34, 30), (46, 60), 10), LENS_H, 3.0, 0.0004)

    # The display: its own material so it can be lit from within. A hair above the lens.
    l, t, r, b = SCREEN
    y = -DEPTH / 2 - LENS_H - 0.00006
    quad = [(bm.verts.new(pos(px, py, y)), px, py) for px, py in ((l, t), (r, t), (r, b), (l, b))]
    f = face(bm, uv, quad, uv_face, 1)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()

    # Soft keys, call and end, either side of the d-pad.
    for kl, kr in ((30, 97), (207, 274)):
        for kt, kb in ((404, 447), (453, 496)):
            raised(bm, uv, box(kl, kt, kr, kb, (11, 10), (11, 10), 5), 0.0011, 2.5, 0.0005)

    # The d-pad ring and its centre key.
    raised(bm, uv, disc(152, 450, 47, 36), 0.0013, 3.0, 0.0006)
    raised(bm, uv, disc(152, 450, 21, 24), 0.0019, 2.5, 0.0005)

    # The twelve keys. The middle column sits a touch lower, following the chin.
    col_w = (236.0 - 18.0) / 3.0
    for row in range(4):
        for col in range(3):
            kl = 34.0 + col * (col_w + 9.0)
            kt = 508.0 + row * 40.0 + (5.0 if col == 1 else 0.0)
            raised(bm, uv, box(kl, kt, kl + col_w, kt + 32.0, (15, 14), (15, 14), 6), 0.0011, 2.5, 0.0005)

    # On the back: the camera's chrome ring.
    raised(bm, uv, disc(152, 91, 31, 32), 0.0012, 3.0, 0.0005, back=True)

    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index == 0])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])


# -- Sollumz ----------------------------------------------------------------------------------------
def sz(path):
    import importlib
    return importlib.import_module(SZ + "." + path)


def principled(name, image):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = image
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


def make_mesh(name, coll, image):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap 0")    # Sollumz binds the shader's UV node by this NAME
    build(bm, uv)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # default.sps multiplies by a vertex colour; without these a surface can render black.
    for attr in ("Color 0", "Color 1"):
        layer = me.color_attributes.new(name=attr, type='BYTE_COLOR', domain='CORNER')
        for d in layer.data:
            d.color = (1.0, 1.0, 1.0, 1.0)

    me.materials.append(principled(name + "_body", image))
    me.materials.append(principled(name + "_screen", image))

    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    for mod in list(ob.modifiers):          # 4.1+ may do this with a modifier; bake it in
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def glow(ob, image, report):
    """Swap the display's material for emissive.sps so the screen is lit at night. If Sollumz
    will not have it, the display stays on default.sps: darker at night, otherwise the same."""
    me = ob.data
    try:
        mats = sz("ydr.shader_materials").shadermats
        index = next(i for i, s in enumerate(mats) if getattr(s, "value", None) == "emissive.sps")
        before = set(bpy.data.materials)
        slots = len(me.materials)
        bpy.ops.sollumz.createshadermaterial(shader_index=index)
        new = [m for m in bpy.data.materials if m not in before]
        if not new:
            raise RuntimeError("no material was created")
        while len(me.materials) > slots:
            me.materials.pop(index=len(me.materials) - 1)
        me.materials[1] = new[0]        # assigned in place: clearing slots resets every face to 0
        new[0].name = ob.name + "_screen"
        for node in new[0].node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.image = image
        report["screen_shader"] = "emissive.sps"
    except Exception as err:
        report["screen_shader"] = "default.sps (emissive failed: %s)" % err


def as_sollumz(ob, image, report):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.sollumz.autoconvertmaterials()
    glow(ob, image, report)
    for mat in ob.data.materials:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.image = image                  # the packed DDS
    bpy.ops.sollumz.setallembedded()
    me = ob.data
    names = [a.name for a in me.color_attributes]
    uvs = [u.name for u in me.uv_layers]
    if "Color 1" not in names or "UVMap 0" not in uvs:
        raise RuntimeError("%s: attributes renamed by Sollumz: %s %s" % (ob.name, names, uvs))

    bpy.context.scene.auto_create_embedded_col = False
    name = ob.name
    bpy.ops.sollumz.converttodrawable()
    return bpy.data.objects[name]


def export_drawable(drawable, name, stream, report):
    drawable.name = name                     # becomes the .ydr name AND the model name
    model = next(c for c in drawable.children if c.sollum_type == "sollumz_drawable_model")
    model.name = name + ".model"
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [drawable] + list(drawable.children_recursive):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = drawable
    # Omitting target_versions writes gen8/ and gen9/ subfolders instead of a .ydr.
    bpy.ops.sollumz.export_assets(
        directory=stream, target_formats={'NATIVE'}, target_versions={'GEN8'},
        limit_to_selected=True, apply_transforms=True, direct_export=True,
        use_custom_settings=True)
    # The archetype. Without it the .ydr streams but CreateObject cannot resolve the name.
    bpy.ops.object.select_all(action='DESELECT')
    drawable.select_set(True)
    bpy.context.view_layer.objects.active = drawable
    bpy.ops.sollumz.createarchetypefromselected()
    report["files"][name + ".ydr"] = file_facts(os.path.join(stream, name + ".ydr"))


def file_facts(path):
    ok = os.path.isfile(path)
    return {"exists": ok, "size": os.path.getsize(path) if ok else 0,
            "magic": open(path, "rb").read(4).decode("latin1") if ok else None}


def mesh_facts(ob):
    me = ob.data
    xs = [v.co for v in me.vertices]
    lo = [round(min(c[i] for c in xs), 4) for i in range(3)]
    hi = [round(max(c[i] for c in xs), 4) for i in range(3)]
    return {"triangles": len(me.polygons), "min": lo, "max": hi}


# -- preview ----------------------------------------------------------------------------------------
def preview(ob, folder, report):
    """Two pictures of the freshly built mesh, before Sollumz touches its materials."""
    sc = bpy.context.scene
    os.makedirs(folder, exist_ok=True)
    for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT', 'BLENDER_WORKBENCH'):
        try:
            sc.render.engine = engine
            break
        except TypeError:
            continue
    world = bpy.data.worlds.new("sd_trapphone_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.18, 0.21, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    sc.world = world
    sc.view_settings.view_transform = 'Standard'
    sc.render.resolution_x, sc.render.resolution_y = 760, 900
    sc.render.image_settings.file_format = 'PNG'

    cam = bpy.data.objects.new("sd_trapphone_cam", bpy.data.cameras.new("sd_trapphone_cam"))
    cam.data.lens = 90
    cam.data.clip_start = 0.01
    sc.collection.objects.link(cam)
    sc.camera = cam
    lamps = []
    for loc, power in (((-0.25, -0.35, 0.3), 14.0), ((0.3, 0.35, 0.25), 14.0), ((0.0, -0.2, -0.3), 5.0)):
        lamp = bpy.data.objects.new("sd_trapphone_lamp", bpy.data.lights.new("sd_trapphone_lamp", 'AREA'))
        lamp.data.energy = power
        lamp.data.size = 0.3
        lamp.location = loc
        lamp.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(lamp)
        lamps.append(lamp)

    shots = []
    for tag, loc in (("face", (-0.115, -0.30, 0.075)), ("back", (0.115, 0.30, 0.075)), ("side", (-0.30, -0.10, 0.02))):
        cam.location = loc
        cam.rotation_euler = (-Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(folder, "prop_%s_%s.png" % (ob.name, tag))
        bpy.ops.render.render(write_still=True)
        shots.append(sc.render.filepath)
    report["preview"] = shots

    for extra in [cam] + lamps:
        bpy.data.objects.remove(extra, do_unlink=True)


# -- driver -----------------------------------------------------------------------------------------
def export(report, stream, preview_dir):
    os.makedirs(stream, exist_ok=True)
    sc = bpy.context.scene
    coll = sc.collection
    report["files"] = {}

    while len(sc.ytyps):
        bpy.ops.sollumz.deleteytyp()
    bpy.ops.sollumz.createytyp()
    ytyp = sc.ytyps[sc.ytyp_index]
    ytyp.name = YTYP

    for i, colour in enumerate(COLOURS):
        name = PREFIX + colour
        image = texture_image(colour)
        ob = make_mesh(name, coll, image)
        if i == 0:
            report["mesh"] = mesh_facts(ob)
            if preview_dir:
                preview(ob, preview_dir, report)
        drawable = as_sollumz(ob, image, report)
        export_drawable(drawable, name, stream, report)

    report["archetypes"] = {}
    for a in ytyp.archetypes:
        a.lod_dist = LOD_DIST
        report["archetypes"][a.name] = {"txd": a.texture_dictionary, "physics": a.physics_dictionary,
                                        "lod": a.lod_dist, "type": a.asset_type}
    bpy.ops.sollumz.export_ytyp_io(directory=stream, target_formats={'NATIVE'},
                                   target_versions={'GEN8'}, use_custom_settings=True)
    report["files"][YTYP + ".ytyp"] = file_facts(os.path.join(stream, YTYP + ".ytyp"))


_state = {}


def tidy():
    """Removes the build scene and everything made for it, and puts the old scene back."""
    window = bpy.context.window_manager.windows[0]
    prev = _state.pop("scene", None)
    if prev and prev in bpy.data.scenes:
        window.scene = bpy.data.scenes[prev]
    sc = bpy.data.scenes.get(SCENE)
    if sc is not None:
        obs = list(sc.collection.all_objects)
        if window.scene == sc:
            window.scene = next(s for s in bpy.data.scenes if s != sc)
        bpy.data.scenes.remove(sc)
        for ob in obs:
            if ob.name in bpy.data.objects:
                bpy.data.objects.remove(ob, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.worlds):
        for item in [i for i in block if i.users == 0 and i.name.startswith("sd_trapphone")]:
            block.remove(item)


def main(stream=None, keep=False, log_path=None, preview_dir=None):
    """Build and export every colour. Returns a report (dimensions, triangles, files)."""
    report = {"ok": False}
    try:
        tidy()
        window = bpy.context.window_manager.windows[0]
        _state["scene"] = window.scene.name
        window.scene = bpy.data.scenes.new(SCENE)
        area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
        region = next(r for r in area.regions if r.type == 'WINDOW')
        with bpy.context.temp_override(window=window, screen=window.screen, area=area,
                                       region=region, space_data=area.spaces.active):
            export(report, stream or STREAM, preview_dir)
        report["ok"] = all(f["exists"] and (n.endswith(".ytyp") or f["magic"] == "RSC7")
                           for n, f in report["files"].items())
    except Exception:
        report["error"] = traceback.format_exc()
    finally:
        if not keep:
            tidy()
    if log_path:
        with open(log_path, "w") as f:
            json.dump(report, f, indent=1, default=str)
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(log_path=argv[0] if argv else None, preview_dir=argv[1] if len(argv) > 1 else None)
    bpy.ops.wm.quit_blender()
