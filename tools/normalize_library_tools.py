"""Normalize library tools (Quaternius + Kenney) to game socket convention.
- handle along +Z, grip at origin, PBR materials kept, real-world scale
- standalone (centered) + inhand (grip) GLB + 512px icons
Run headless: Blender --background --python normalize_library_tools.py
Env PREVIEW=1: also parent inhand variants to farmer socket + render check shots.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler

TMP = "C:/Users/inval/AppData/Local/Temp/opencode"
FAN = TMP + "/fantasy/Exports/glTF"
ROOT = "K:/After Wind"
MODELS = ROOT + "/assets/models/tools"
ICONS = ROOT + "/assets/tools"
PREVIEW = os.environ.get("PREVIEW") == "1"
OUT = ROOT + "/outputs/library_preview"
os.makedirs(OUT, exist_ok=True)

# file, target_height_m, rotZ_deg, grip_mode, tilt_xyz_or_None(inhand only)
JOBS = {
    "axe":     {"file": FAN + "/Axe_Bronze.gltf", "h": 0.80, "rotz": 90, "grip": "shaft40", "tilt": (0, math.pi, 0), "filled": False},
    "pickaxe": {"file": FAN + "/Pickaxe_Bronze.gltf", "h": 0.90, "rotz": 90, "grip": "shaft40", "tilt": None, "filled": False},
    "bucket":  {"file": FAN + "/Bucket_Metal.gltf", "h": 0.40, "rotz": 0, "grip": "top", "tilt": (1.39, -0.58, -0.49), "filled": False},
    "bucket_full": {"file": FAN + "/Bucket_Metal.gltf", "h": 0.40, "rotz": 0, "grip": "top", "tilt": (1.39, -0.58, -0.49), "filled": True},
    "shovel":  {"file": TMP + "/kenney/Models/GLB format/shovel.glb", "h": 1.10, "rotz": 0, "grip": "shaft40", "tilt": (0, math.pi, 0), "filled": False},
}


def reset():
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for col in [bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images]:
        for b in list(col):
            try:
                col.remove(b, do_unlink=True)
            except Exception:
                pass


def import_all(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    # Текстуры 2048² избыточны для ручных инструментов: жмём до 512.
    for img in bpy.data.images:
        w, h = img.size
        if max(w, h) > 512:
            nw = 512 if w >= h else max(1, int(512 * w / h))
            nh = 512 if h > w else max(1, int(512 * h / w))
            img.scale(nw, nh)
            print(f"downscaled image {img.name} to {nw}x{nh}")
    return [o for o in bpy.data.objects if o not in before]


def make_water_material():
    mat = bpy.data.materials.get("M_BucketWater")
    if mat:
        return mat
    mat = bpy.data.materials.new(name="M_BucketWater")
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (0.15, 0.35, 0.55, 1.0)
    bsdf.inputs['Metallic'].default_value = 0.0
    bsdf.inputs['Roughness'].default_value = 0.15
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    return mat


def join_meshes(objs, name):
    # Кривые (дужка ведра) -> меш, всё в один меш.
    for o in objs:
        if o.type == 'CURVE':
            bpy.ops.object.select_all(action='DESELECT')
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def normalize(tid, cfg):
    objs = import_all(cfg["file"])
    obj = join_meshes(objs, "LIB_" + tid)
    filled = cfg.get("filled", False)
    # 1. apply transforms, measure
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    ws = obj.matrix_world
    vs = [ws @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    size = mx - mn
    # 2. scale to target height (Z is length for all four)
    s = cfg["h"] / size.z
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    # 3. rotZ about origin
    if cfg["rotz"]:
        obj.rotation_euler = Euler((0, 0, math.radians(cfg["rotz"])), 'XYZ')
        bpy.ops.object.transform_apply(rotation=True)
    if filled:
        # Зеркало воды: радиус по факту корпуса на этой высоте, чуть ниже кромки.
        vs0 = [Vector(v.co) for v in obj.data.vertices]
        top_z = max(v.z for v in vs0)
        disc_z = top_z - 0.10 * s
        rr = [Vector((v.x, v.y, 0)).length for v in vs0 if abs(v.z - disc_z) < 0.03]
        disc_r = (max(rr) if rr else 0.15) * 0.88
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=disc_r, depth=0.012,
                                            location=(0, 0, disc_z))
        water = bpy.context.active_object
        water.name = "LIB_WaterDisc"
        water.data.materials.clear()
        water.data.materials.append(make_water_material())
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        water.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.join()
        obj = bpy.context.active_object
        print(f"water disc r={disc_r:.3f} z={disc_z:.3f}")
    # 4. measure again, grip translate (shaft centering in XY for shaft tools)
    vs = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    h = mx.z - mn.z
    gz = mn.z + 0.40 * h if cfg["grip"] == "shaft40" else mx.z
    # центр хвата по полосе черенка (середина высоты) -> ось x=y=0
    mesh = obj.data
    xs, ys = [], []
    for v in mesh.vertices:
        wz = v.co.z
        if mn.z + 0.35 * h <= wz <= mn.z + 0.65 * h:
            xs.append(v.co.x)
            ys.append(v.co.y)
    gx = sum(xs) / len(xs) if xs else (mn.x + mx.x) / 2
    gy = sum(ys) / len(ys) if ys else (mn.y + mx.y) / 2
    if cfg["grip"] == "top":
        gx, gy = 0.0, 0.0
    bm = bmesh.new()
    bm.from_mesh(mesh)
    for v in bm.verts:
        v.co.x -= gx
        v.co.y -= gy
        v.co.z -= gz
    bm.to_mesh(mesh)
    bm.free()
    obj.location = Vector((0, 0, 0))
    print(f"NORM {tid}: h={h:.3f} grip_z={gz:.3f} shaft_xy=({gx:.3f},{gy:.3f}) verts={len(mesh.vertices)}")
    return obj


def set_origin(obj, mode):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if mode == 'grip':
        bpy.context.scene.cursor.location = Vector((0, 0, 0))
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    else:
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        # вернуть геометрию так, чтобы origin остался в центре баундов:
        obj.location = Vector((0, 0, 0))


def export_glb(obj, path):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_materials='EXPORT', export_apply=True)
    print(f"exported {path} ({os.path.getsize(path)} bytes)")


def render_icon(obj, path):
    for o in list(bpy.data.objects):
        if o.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(o, do_unlink=True)
    cam_data = bpy.data.cameras.new("IconCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 1.15
    cam_obj = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = Vector((1.0, -1.0, 0.9))
    cam_obj.rotation_euler = Euler((math.radians(55.0), 0.0, math.radians(45.0)), 'XYZ')
    bpy.context.scene.camera = cam_obj
    for name, energy, color, rot in [
            ("K", 4.5, (1.0, 0.96, 0.90), (45, 25, -30)),
            ("F", 2.2, (0.75, 0.85, 1.0), (-30, -45, 120)),
            ("R", 3.0, (1.0, 1.0, 1.0), (-60, 20, 200))]:
        ld = bpy.data.lights.new("Icon" + name, type='SUN')
        ld.energy = energy
        ld.color = color
        lo = bpy.data.objects.new("Icon" + name, ld)
        bpy.context.collection.objects.link(lo)
        lo.rotation_euler = Euler((math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2])), 'XYZ')
    obj.location = Vector((0, 0, 0))
    obj.rotation_euler = Euler((math.radians(25), math.radians(-35), math.radians(15)), 'XYZ')
    scene = bpy.context.scene
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"icon {path}")
    obj.rotation_euler = Euler((0, 0, 0), 'XYZ')


def build_variant(tid, cfg, inhand):
    reset()
    obj = normalize(tid, cfg)
    bpy.ops.object.shade_smooth()
    if inhand and cfg["tilt"]:
        obj.rotation_mode = 'XYZ'
        obj.rotation_euler = Euler(cfg["tilt"], 'XYZ')
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(rotation=True)
    set_origin(obj, 'grip' if inhand else 'center')
    suffix = "_inhand" if inhand else ""
    export_glb(obj, os.path.join(MODELS, tid + suffix + ".glb"))
    return obj


def main():
    for tid, cfg in JOBS.items():
        # standalone (origin в центре) + иконка; у bucket_full только inhand
        if tid != "bucket_full":
            obj = build_variant(tid, cfg, False)
            render_icon(obj, os.path.join(ICONS, tid + "_icon.png"))
        build_variant(tid, cfg, True)
    print("NORMALIZE_DONE")


if __name__ == '__main__':
    main()
