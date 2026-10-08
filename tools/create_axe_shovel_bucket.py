"""
Blender 5.2 Automation Script — Axe, Shovel, Bucket
Стиль: stylized semi-realistic, weathered, post-storm rural industrial.
Палитра/материалы совпадают с pickaxe (tools/create_miner_and_pickaxe.py):
  M_Hardwood, M_LeatherGrip, M_ForgedIron, M_PolishedSteel, M_BrassRivet
  + M_GalvanizedSteel, M_Rust, M_CanvasWater (для ведра)
Требования Design Document §41 (Master Prompt):
  clean hierarchy, real-world proportions, clean topology, PBR Principled,
  origin/pivot, applied transforms, Godot-ready, consistent scale.
Выходы:
  assets/models/tools/{axe,shovel,bucket}.glb + .blend
  assets/tools/{axe,shovel,bucket}_icon.png (512x512, transparent, ortho)
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Euler

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODELS_TOOL_DIR = os.path.join(BASE_DIR, "assets", "models", "tools")
TOOLS_SPRITES_DIR = os.path.join(BASE_DIR, "assets", "tools")
for d in [MODELS_TOOL_DIR, TOOLS_SPRITES_DIR]:
    os.makedirs(d, exist_ok=True)

OUTPUTS = {
    "axe": {
        "glb": os.path.join(MODELS_TOOL_DIR, "axe.glb"),
        "blend": os.path.join(MODELS_TOOL_DIR, "axe.blend"),
        "icon": os.path.join(TOOLS_SPRITES_DIR, "axe_icon.png"),
    },
    "shovel": {
        "glb": os.path.join(MODELS_TOOL_DIR, "shovel.glb"),
        "blend": os.path.join(MODELS_TOOL_DIR, "shovel.blend"),
        "icon": os.path.join(TOOLS_SPRITES_DIR, "shovel_icon.png"),
    },
    "bucket": {
        "glb": os.path.join(MODELS_TOOL_DIR, "bucket.glb"),
        "blend": os.path.join(MODELS_TOOL_DIR, "bucket.blend"),
        "icon": os.path.join(TOOLS_SPRITES_DIR, "bucket_icon.png"),
    },
}


def reset_scene():
    if bpy.context.active_object and bpy.context.active_object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in [bpy.data.meshes, bpy.data.materials, bpy.data.armatures,
                       bpy.data.actions, bpy.data.cameras, bpy.data.lights, bpy.data.images]:
        for block in list(collection):
            try:
                collection.remove(block, do_unlink=True)
            except Exception:
                pass


def create_pbr_material(name, base_color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name=name)
    nodes = mat.node_tree.nodes
    nodes.clear()
    out_node = nodes.new(type='ShaderNodeOutputMaterial')
    bsdf = nodes.new(type='ShaderNodeBsdfPrincipled')
    # Principled BSDF: Base Color / Metallic / Roughness — единственные входы,
    # гарантированно экспортируемые в glTF (см. skill blender-materials).
    bsdf.inputs['Base Color'].default_value = base_color
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    mat.node_tree.links.new(bsdf.outputs['BSDF'], out_node.inputs['Surface'])
    return mat


def get_shared_materials():
    return {
        "wood": create_pbr_material("M_Hardwood", (0.34, 0.20, 0.10, 1.0), metallic=0.0, roughness=0.65),
        "leather": create_pbr_material("M_LeatherGrip", (0.22, 0.14, 0.08, 1.0), metallic=0.0, roughness=0.85),
        "iron": create_pbr_material("M_ForgedIron", (0.22, 0.24, 0.26, 1.0), metallic=0.92, roughness=0.34),
        "steel": create_pbr_material("M_PolishedSteel", (0.65, 0.68, 0.72, 1.0), metallic=0.96, roughness=0.20),
        "brass": create_pbr_material("M_BrassRivet", (0.82, 0.66, 0.24, 1.0), metallic=0.90, roughness=0.30),
        "galv": create_pbr_material("M_GalvanizedSteel", (0.55, 0.57, 0.58, 1.0), metallic=1.0, roughness=0.45),
        "rust": create_pbr_material("M_RustyHoop", (0.35, 0.18, 0.08, 1.0), metallic=0.9, roughness=0.60),
        "water": create_pbr_material("M_BucketWater", (0.15, 0.35, 0.55, 1.0), metallic=0.0, roughness=0.15),
    }


def finish_single_object(obj, root_name, grip_at_origin=None, grip_rotate=None):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    # Apply transforms (skill blender-export, Recipe 7)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if grip_at_origin is not None:
        # In-hand вариант: точка хвата (grip) переносится в origin (0,0,0) —
        # та же конвенция, что у кирки centered=False (grip z=0.35 -> origin).
        # Рукоять остаётся вдоль +Z, рабочая часть сверху: identity-парентинг
        # к кости ToolSocket.R даёт правильную позу в руке без подгонки.
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for v in bm.verts:
            v.co.z -= grip_at_origin
        bm.to_mesh(obj.data)
        bm.free()
        if grip_rotate is not None:
            # Доворот вокруг точки хвата (origin): хват остаётся в кулаке.
            # Значения подобраны по превью на риге фермера (preview_dig_scoop.py):
            #   лопата (0, pi, 0) — клинок вниз, а не вверх;
            #   ведро (1.39, -0.58, -0.49) — висит сбоку от ноги, а не в теле.
            obj.rotation_mode = 'XYZ'
            obj.rotation_euler = Euler(grip_rotate, 'XYZ')
            bpy.ops.object.transform_apply(rotation=True)
        bpy.context.scene.cursor.location = Vector((0, 0, 0))
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    else:
        # Центр origin в границы — стандарт standalone-ассета (как pickaxe centered=True)
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    obj.location = Vector((0, 0, 0))
    obj.rotation_euler = Euler((0, 0, 0), 'XYZ')
    obj.name = root_name
    return obj


# ==============================================================================
# AXE — Старый топор Lv.1 (длина ~0.78 м, лезвие + обух)
# ==============================================================================

def build_axe(m, grip_at_origin=None):
    parts = []
    # Рукоять 0.75 м, овальное сечение, раструбы как у кирки
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.022, depth=0.75, location=(0, 0, 0.375))
    handle = bpy.context.active_object
    handle.name = "Axe_Handle"
    handle.data.materials.append(m["wood"])
    bm = bmesh.new()
    bm.from_mesh(handle.data)
    for v in bm.verts:
        t = v.co.z / 0.75
        v.co.x *= 0.85
        if t < 0.15:
            f = 1.0 + (0.15 - t) * 2.0
            v.co.x *= f
            v.co.y *= f
        elif t > 0.78:
            f = 1.0 + (t - 0.78) * 1.0
            v.co.x *= f
            v.co.y *= f
    bm.to_mesh(handle.data)
    bm.free()
    parts.append(handle)

    # Кожаная обмотка хвата
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.026, depth=0.16, location=(0, 0, 0.60))
    grip = bpy.context.active_object
    grip.name = "Axe_Grip"
    grip.data.materials.append(m["leather"])
    parts.append(grip)

    # Проушина (eye) — кованый блок
    bpy.ops.mesh.primitive_cube_add(size=0.07, location=(0, 0, 0.76))
    eye = bpy.context.active_object
    eye.name = "Axe_Eye"
    eye.scale = (1.0, 1.3, 1.15)
    bpy.ops.object.transform_apply(scale=True)
    eye.data.materials.append(m["iron"])
    parts.append(eye)

    # Лезвие — клин вперёд (-Y), построено bmesh-кольцами (сужение к кромке)
    mesh_blade = bpy.data.meshes.new("Axe_Blade_Mesh")
    blade = bpy.data.objects.new("Axe_Blade", mesh_blade)
    bpy.context.collection.objects.link(blade)
    blade.data.materials.append(m["iron"])
    blade.data.materials.append(m["steel"])  # кромка — полированная сталь
    bm = bmesh.new()
    steps = 5
    rings = []
    for i in range(steps + 1):
        t = i / steps
        y = -0.045 - t * 0.20
        z = 0.76 + (0.02 * math.sin(t * math.pi))
        rx = 0.030 * (1.0 - t * 0.5)
        rz = 0.055 * (1.0 - t * 0.2) + 0.008
        ring = []
        for a in range(4):
            ang = a * (math.pi / 2.0) + math.pi / 4.0
            ring.append(bm.verts.new((math.cos(ang) * rx, y, z + math.sin(ang) * rz)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        r1, r2 = rings[i], rings[i + 1]
        for j in range(4):
            jn = (j + 1) % 4
            f = bm.faces.new([r1[j], r1[jn], r2[jn], r2[j]])
            if i == len(rings) - 2:
                f.material_index = 1  # режущая кромка
    f_end = bm.faces.new(rings[-1])
    f_end.material_index = 1
    bm.to_mesh(mesh_blade)
    bm.free()
    parts.append(blade)

    # Обух (poll) — тупой боёк сзади (+Y)
    bpy.ops.mesh.primitive_cube_add(size=0.06, location=(0, 0.075, 0.76))
    poll = bpy.context.active_object
    poll.name = "Axe_Poll"
    poll.scale = (1.0, 0.8, 1.1)
    bpy.ops.object.transform_apply(scale=True)
    poll.data.materials.append(m["iron"])
    parts.append(poll)

    # Стальной клин сверху рукояти
    bpy.ops.mesh.primitive_cube_add(size=0.02, location=(0, 0, 0.815))
    wedge = bpy.context.active_object
    wedge.name = "Axe_Wedge"
    wedge.scale = (1.4, 0.5, 0.4)
    bpy.ops.object.transform_apply(scale=True)
    wedge.data.materials.append(m["steel"])
    parts.append(wedge)

    # Латунная заклёпка-обойма под проушиной
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.030, depth=0.03, location=(0, 0, 0.70))
    collar = bpy.context.active_object
    collar.name = "Axe_Collar"
    collar.data.materials.append(m["iron"])
    parts.append(collar)

    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = handle
    bpy.ops.object.join()
    return finish_single_object(bpy.context.active_object, "Axe", grip_at_origin)


# ==============================================================================
# SHOVEL — Лопата Lv.1 (длина ~1.10 м, T-ручка, штыковое полотно)
# ==============================================================================

def build_shovel(m, grip_at_origin=None, grip_rotate=None):
    parts = []
    # Черенок 1.0 м
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.020, depth=1.0, location=(0, 0, 0.55))
    shaft = bpy.context.active_object
    shaft.name = "Shovel_Shaft"
    shaft.data.materials.append(m["wood"])
    parts.append(shaft)

    # T-ручка (перекладина 0.22 м)
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.018, depth=0.22, location=(0, 0, 1.06))
    grip_bar = bpy.context.active_object
    grip_bar.name = "Shovel_TGrip"
    grip_bar.rotation_euler = Euler((0, math.radians(90), 0), 'XYZ')
    bpy.ops.object.transform_apply(rotation=True)
    grip_bar.data.materials.append(m["wood"])
    parts.append(grip_bar)

    # Обойма-стакан между черенком и полотном
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.026, depth=0.12, location=(0, 0, 0.10))
    socket = bpy.context.active_object
    socket.name = "Shovel_Socket"
    socket.data.materials.append(m["iron"])
    parts.append(socket)

    # Заклёпки обоймы
    for y_sign in [-1, 1]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.007,
                                             location=(0, y_sign * 0.026, 0.10))
        rivet = bpy.context.active_object
        rivet.name = f"Shovel_Rivet_{y_sign}"
        rivet.data.materials.append(m["brass"])
        parts.append(rivet)

    # Полотно — штыковая лопата: широкое сверху, сужается к острию, лёгкий изгиб
    mesh_blade = bpy.data.meshes.new("Shovel_Blade_Mesh")
    blade = bpy.data.objects.new("Shovel_Blade", mesh_blade)
    bpy.context.collection.objects.link(blade)
    blade.data.materials.append(m["iron"])
    blade.data.materials.append(m["steel"])
    bm = bmesh.new()
    rows = 5
    rings = []
    for i in range(rows + 1):
        t = i / rows  # 0 верх (у обоймы) -> 1 остриё
        z = 0.04 - t * 0.30
        half_w = 0.13 * (1.0 - t * 0.72)
        scoop = 0.018 * math.sin(t * math.pi)  # лёгкий совок вперёд
        ring = [
            bm.verts.new((-half_w, scoop, z)),
            bm.verts.new((half_w, scoop, z)),
            bm.verts.new((half_w * 0.96, scoop + 0.012, z)),
            bm.verts.new((-half_w * 0.96, scoop + 0.012, z)),
        ]
        rings.append(ring)
    for i in range(len(rings) - 1):
        r1, r2 = rings[i], rings[i + 1]
        bm.faces.new([r1[0], r1[1], r2[1], r2[0]])
        bm.faces.new([r1[3], r1[2], r2[2], r2[3]])
    # Остриё — сходится в тупой клин, материал сталь
    tip = bm.verts.new((0.0, 0.004, 0.04 - 0.30 - 0.035))
    last = rings[-1]
    for j in range(4):
        f = bm.faces.new([last[j], last[(j + 1) % 4], tip])
        f.material_index = 1
    bm.to_mesh(mesh_blade)
    bm.free()
    parts.append(blade)

    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = shaft
    bpy.ops.object.join()
    return finish_single_object(bpy.context.active_object, "Shovel", grip_at_origin, grip_rotate)


# ==============================================================================
# BUCKET — Ведро Lv.1 (усечённый конус, обручи, дужка)
# ==============================================================================

def build_bucket(m, grip_at_origin=None, grip_rotate=None, filled=False):
    parts = []
    # Корпус — усечённый конус: верх r=0.16, низ r=0.12, высота 0.28
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.16, depth=0.28, location=(0, 0, 0.14))
    body = bpy.context.active_object
    body.name = "Bucket_Body"
    # Сужаем нижние вершины к r=0.12
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:
        if v.co.z < 0:
            f = 0.12 / 0.16
            v.co.x *= f
            v.co.y *= f
    bm.to_mesh(body.data)
    bm.free()
    body.data.materials.append(m["galv"])
    parts.append(body)

    # Дно
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.12, depth=0.012, location=(0, 0, 0.006))
    bottom = bpy.context.active_object
    bottom.name = "Bucket_Bottom"
    bottom.data.materials.append(m["galv"])
    parts.append(bottom)

    # Тёмное нутро (внутренний диск чуть ниже кромки — читаемость глубины)
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.148, depth=0.005, location=(0, 0, 0.245))
    inner = bpy.context.active_object
    inner.name = "Bucket_Inner"
    inner.data.materials.append(m["rust"])
    parts.append(inner)

    # Два обруча (тор, ржавый металл)
    for z, r in [(0.055, 0.128), (0.225, 0.152)]:
        bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.008, location=(0, 0, z))
        hoop = bpy.context.active_object
        hoop.name = f"Bucket_Hoop_{int(z * 1000)}"
        hoop.data.materials.append(m["rust"])
        parts.append(hoop)

    # Дужка-ручка: полутор (дуга над ведром), стержень r=0.008
    bpy.ops.mesh.primitive_torus_add(major_radius=0.155, minor_radius=0.008, location=(0, 0, 0.28))
    bail = bpy.context.active_object
    bail.name = "Bucket_Bail"
    bail.rotation_euler = Euler((0, 0, 0), 'XYZ')
    # Оставляем полный тор как дужку в поднятом положении — читаемо в изометрии
    bpy.ops.object.transform_apply(rotation=True)
    bail.data.materials.append(m["iron"])
    parts.append(bail)

    # Ушки крепления дужки
    for x_sign in [-1, 1]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.012,
                                             location=(x_sign * 0.155, 0, 0.26))
        lug = bpy.context.active_object
        lug.name = f"Bucket_Lug_{x_sign}"
        lug.data.materials.append(m["brass"])
        parts.append(lug)

    if filled:
        # Зеркало воды чуть ниже кромки — вариант «наполненное ведро».
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.15, depth=0.012,
                                            location=(0, 0, 0.255))
        water = bpy.context.active_object
        water.name = "Bucket_Water"
        water.data.materials.append(m["water"])
        parts.append(water)

    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    return finish_single_object(bpy.context.active_object,
                                "BucketFull" if filled else "Bucket",
                                grip_at_origin, grip_rotate)


# ==============================================================================
# РЕНДЕР ИКОНОК — как у кирки: ortho, 3-point sun, 512x512 transparent
# ==============================================================================

def render_tool_icon(target_path, hero_rotation):
    cam_data = bpy.data.cameras.new("IconCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 1.15
    cam_obj = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = Vector((1.0, -1.0, 0.9))
    cam_obj.rotation_euler = Euler((math.radians(55.0), 0.0, math.radians(45.0)), 'XYZ')
    bpy.context.scene.camera = cam_obj

    key_data = bpy.data.lights.new("IconKey", type='SUN')
    key_data.energy = 4.5
    key_data.color = (1.0, 0.96, 0.90)
    key_obj = bpy.data.objects.new("IconKey", key_data)
    bpy.context.collection.objects.link(key_obj)
    key_obj.rotation_euler = Euler((math.radians(45), math.radians(25), math.radians(-30)), 'XYZ')

    fill_data = bpy.data.lights.new("IconFill", type='SUN')
    fill_data.energy = 2.2
    fill_data.color = (0.75, 0.85, 1.0)
    fill_obj = bpy.data.objects.new("IconFill", fill_data)
    bpy.context.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = Euler((math.radians(-30), math.radians(-45), math.radians(120)), 'XYZ')

    rim_data = bpy.data.lights.new("IconRim", type='SUN')
    rim_data.energy = 3.0
    rim_obj = bpy.data.objects.new("IconRim", rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.rotation_euler = Euler((math.radians(-60), math.radians(20), math.radians(200)), 'XYZ')

    scene = bpy.context.scene
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = target_path

    tool = None
    for name in ("Axe", "Shovel", "Bucket"):
        if name in bpy.data.objects:
            tool = bpy.data.objects[name]
            break
    if tool:
        tool.location = Vector((0, 0, 0))
        tool.rotation_euler = Euler(hero_rotation, 'XYZ')

    bpy.ops.render.render(write_still=True)
    print(f"Rendered icon to: {target_path}")


def export_current_tool(glb_path, blend_path):
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format='GLB',
        use_selection=False,
        export_materials='EXPORT',
        export_apply=True,
    )
    print(f"Exported GLB: {glb_path}")


def verify(path):
    import os as _os
    if not _os.path.exists(path):
        raise RuntimeError(f"NOT FOUND: {path}")
    size = _os.path.getsize(path)
    print(f"verified:{path} {size} bytes")
    return size


def main():
    import os as _os
    if _os.environ.get("TOOL_VARIANTS") == "inhand":
        main_inhand()
        return
    print("==================================================================")
    print("BLENDER: AXE + SHOVEL + BUCKET (stylized semi-realistic, PBR, GLB)")
    print("==================================================================")

    jobs = [
        ("axe", build_axe, (math.radians(25), math.radians(-35), math.radians(15))),
        ("shovel", build_shovel, (math.radians(18), math.radians(-30), math.radians(10))),
        ("bucket", build_bucket, (math.radians(20), math.radians(-25), math.radians(0))),
    ]
    for tool_id, builder, hero_rot in jobs:
        reset_scene()
        print(f"-- building {tool_id} ...")
        get_mats = get_shared_materials()
        builder(get_mats)
        # Проверка модели: вершины, материалы, масштаб
        obj = bpy.context.active_object
        mesh = obj.data
        print(f"check:{obj.name} verts:{len(mesh.vertices)} faces:{len(mesh.polygons)} mats:{len(mesh.materials)}")
        for slot in mesh.materials:
            print(f"  mat:{slot.name if slot else '<none>'}")
        render_tool_icon(OUTPUTS[tool_id]["icon"], hero_rot)
        export_current_tool(OUTPUTS[tool_id]["glb"], OUTPUTS[tool_id]["blend"])

    print("------------------------------------------------------------------")
    for tool_id in OUTPUTS:
        for kind in ("glb", "blend", "icon"):
            verify(OUTPUTS[tool_id][kind])
    print("ALL 3 TOOLS + ICONS GENERATED SUCCESSFULLY!")


def main_inhand():
    """In-hand варианты для сокета ToolSocket.R: grip в origin, рукоять +Z.

    Точки хвата (до центрирования, в локальных координатах построения):
      axe:    z=0.31  (хват на рукояти 0.75 м, как у кирки 0.35/0.85)
      shovel: z=0.45  (нижне-средняя часть черенка — вторая рука)
      bucket: z=0.443 (вершина дужки — несут за дужку, корпус висит вниз)
    """
    print("==================================================================")
    print("BLENDER: IN-HAND VARIANTS (grip at origin, for ToolSocket.R)")
    print("==================================================================")
    # (grip_z, rot_xyz_or_None, filled)
    jobs = [
        ("axe", build_axe, 0.31, None, False),
        ("shovel", build_shovel, 0.45, (0, math.pi, 0), False),
        ("bucket", build_bucket, 0.443, (1.39, -0.58, -0.49), False),
        ("bucket_full", build_bucket, 0.443, (1.39, -0.58, -0.49), True),
    ]
    for tool_id, builder, grip, rot, filled in jobs:
        reset_scene()
        print(f"-- building in-hand {tool_id} (grip z={grip}, rot={rot}, filled={filled}) ...")
        if filled:
            builder(get_shared_materials(), grip_at_origin=grip, grip_rotate=rot, filled=True)
        elif rot is None:
            builder(get_shared_materials(), grip_at_origin=grip)
        else:
            builder(get_shared_materials(), grip_at_origin=grip, grip_rotate=rot)
        obj = bpy.context.active_object
        mesh = obj.data
        print(f"check:{obj.name} verts:{len(mesh.vertices)} faces:{len(mesh.polygons)} origin:grip")
        glb_path = os.path.join(MODELS_TOOL_DIR, f"{tool_id}_inhand.glb" if tool_id != "bucket_full" else "bucket_full_inhand.glb")
        blend_path = os.path.join(MODELS_TOOL_DIR, f"{tool_id}_inhand.blend" if tool_id != "bucket_full" else "bucket_full_inhand.blend")
        export_current_tool(glb_path, blend_path)
    print("------------------------------------------------------------------")
    for tool_id, _b, _g, _r, _f in jobs:
        fname = f"{tool_id}_inhand.glb" if tool_id != "bucket_full" else "bucket_full_inhand.glb"
        verify(os.path.join(MODELS_TOOL_DIR, fname))
    print("ALL 4 IN-HAND VARIANTS GENERATED SUCCESSFULLY!")


if __name__ == "__main__":
    main()
