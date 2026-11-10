"""
render_props.py -- renders the pictures of the props used in the README.

    blender --python tools/render_props.py -- <output folder>

Builds every colour with build_prop.py's own geometry and textures (nothing is exported), stands
them in a row and renders two pictures: the faces, and a few backs. Run make_textures.py first.
"""

import bpy
import math
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
B = runpy.run_path(os.path.join(HERE, "build_prop.py"))

COLOURS = B["COLOURS"]
SCENE = "sd_trapphone_render"


def lit_screen(mat, image):
    """Give the display its own light, as the emissive shader does in game."""
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = next(n for n in nt.nodes if n.type == 'TEX_IMAGE')
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = 0.9


def plastic(mat):
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.5   # soft plastic: a sheen, not a mirror of the lamps


def look_at(ob, target):
    from mathutils import Vector
    ob.rotation_euler = (Vector(target) - ob.location).to_track_quat('-Z', 'Y').to_euler()


def main(out):
    os.makedirs(out, exist_ok=True)
    window = bpy.context.window_manager.windows[0]
    sc = bpy.data.scenes.new(SCENE)
    window.scene = sc
    area = next(a for a in window.screen.areas if a.type == 'VIEW_3D')
    region = next(r for r in area.regions if r.type == 'WINDOW')

    with bpy.context.temp_override(window=window, screen=window.screen, area=area, region=region,
                                   space_data=area.spaces.active):
        for engine in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
            try:
                sc.render.engine = engine
                break
            except TypeError:
                continue
        world = bpy.data.worlds.new(SCENE)
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.035, 0.04, 0.05, 1.0)
        world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        sc.world = world
        sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
        sc.render.image_settings.file_format = 'PNG'
        sc.render.film_transparent = True
        sc.view_settings.view_transform = 'Standard'   # the art's own colours, not a filmic curve

        phones = []
        for i, colour in enumerate(COLOURS):
            image = bpy.data.images.load(os.path.join(B["ART"], "tex_%s.png" % colour))
            ob = B["make_mesh"]("render_" + colour, sc.collection, image)
            plastic(ob.data.materials[0])
            lit_screen(ob.data.materials[1], image)
            phones.append(ob)

        cam = bpy.data.objects.new("render_cam", bpy.data.cameras.new("render_cam"))
        cam.data.lens = 70
        cam.data.clip_start = 0.01
        sc.collection.objects.link(cam)
        sc.camera = cam

        for loc, power, size in (((-0.45, -0.9, 0.18), 9.0, 1.2), ((0.6, -0.7, 0.05), 5.0, 1.0), ((0.0, 0.9, 0.2), 8.0, 1.2)):
            lamp = bpy.data.objects.new("render_lamp", bpy.data.lights.new("render_lamp", 'AREA'))
            lamp.data.energy = power
            lamp.data.size = size
            lamp.location = loc
            sc.collection.objects.link(lamp)
            look_at(lamp, (0.0, 0.0, 0.0))

        # The faces: ten in a gentle arc, each turned a little and leaning back.
        n = len(phones)
        for i, ob in enumerate(phones):
            t = i - (n - 1) / 2
            ob.location = (t * 0.058, abs(t) * 0.006, (0.012 if i % 2 else -0.012))
            ob.rotation_euler = (math.radians(-10), 0.0, math.radians(-16 + t * 2.0))
        cam.location = (0.0, -1.42, 0.14)
        look_at(cam, (0.0, 0.0, 0.0))
        sc.render.filepath = os.path.join(out, "props_faces.png")
        bpy.ops.render.render(write_still=True)

        # The backs: the same row, turned round.
        for i, ob in enumerate(phones):
            t = i - (n - 1) / 2
            ob.rotation_euler = (math.radians(10), 0.0, math.radians(180 - 16 + t * 2.0))
        sc.render.filepath = os.path.join(out, "props_backs.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    try:
        main(argv[0] if argv else os.path.join(HERE, "art"))
    finally:
        bpy.ops.wm.quit_blender()
