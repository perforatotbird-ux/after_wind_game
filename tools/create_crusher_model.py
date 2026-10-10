"""Процедурная модель автоматической стимпанк-дробилки камня для Blender 5.x.
Создаёт полноценную 3D-модель со всеми статическими и кинематическими узлами,
настроенными локальными пивотами, PBR-материалами и запечённой циклической анимацией Crusher_Work.

Запуск из корня проекта:
  & 'C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe' --background --python tools/create_crusher_model.py
  (с флагом --render: рендерит превью с 3 камер)
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix, Euler

# ---------- Конфигурация путей ----------
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_BUILD = os.path.join(ROOT_DIR, "crusher_build")
OUT_ASSETS = os.path.join(ROOT_DIR, "assets", "models", "crusher")

os.makedirs(OUT_BUILD, exist_ok=True)
os.makedirs(OUT_ASSETS, exist_ok=True)

# .gdignore чтобы Godot не индексировал промежуточные файлы сборки
open(os.path.join(OUT_BUILD, ".gdignore"), "w").close()

# ---------- Очистка сцены ----------
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
sc.frame_start = 1
sc.frame_end = 60  # 2 секунды зацикленной анимации при 30 fps

col_crusher = bpy.data.collections.new("StoneCrusher")
sc.collection.children.link(col_crusher)

# ---------- Вспомогательные функции для материалов ----------
def srgb_to_linear(hex_str):
    hex_str = hex_str.lstrip('#')
    c = [int(hex_str[i:i+2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def create_pbr_mat(name, color_hex, roughness=0.6, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    col_lin = srgb_to_linear(color_hex)
    b.inputs["Base Color"].default_value = (*col_lin, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

MATS = {
    "iron": create_pbr_mat("M_CastIron", "#2b2e34", roughness=0.55, metallic=0.88),
    "iron_dark": create_pbr_mat("M_CastIronDark", "#1d2024", roughness=0.65, metallic=0.92),
    "brass": create_pbr_mat("M_AgedBrass", "#b89038", roughness=0.40, metallic=0.92),
    "copper": create_pbr_mat("M_AgedCopper", "#9e4a30", roughness=0.45, metallic=0.85),
    "granite": create_pbr_mat("M_GraniteStone", "#6c7075", roughness=0.90, metallic=0.0),
    "granite_rough": create_pbr_mat("M_GraniteRough", "#52555a", roughness=0.95, metallic=0.0),
    "wood": create_pbr_mat("M_WeatheredWood", "#4d341f", roughness=0.82, metallic=0.0),
    "wood_dark": create_pbr_mat("M_WoodDark", "#352212", roughness=0.85, metallic=0.0),
    "gravel": create_pbr_mat("M_CrushedRock", "#7a7e85", roughness=0.92, metallic=0.0),
    "gauge_face": create_pbr_mat("M_GaugeFace", "#e8e4dc", roughness=0.30, metallic=0.0),
}

# ---------- Примитивы геометрии ----------
def add_mesh_obj(name, mesh_data, loc=(0,0,0), rot=(0,0,0), parent=None):
    obj = bpy.data.objects.new(name, mesh_data)
    obj.location = loc
    obj.rotation_euler = rot
    if parent:
        obj.parent = parent
    col_crusher.objects.link(obj)
    return obj

def make_box(name, size, loc=(0,0,0), mat_name="iron", bevel=0.0, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=2, profile=0.5)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    obj = add_mesh_obj(name, me, loc, parent=parent)
    obj.data.materials.append(MATS[mat_name])
    return obj

def make_cylinder(name, radius, depth, loc=(0,0,0), rot=(0,0,0), segs=32, mat_name="iron", parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False,
                          radius1=radius, radius2=radius, depth=depth, segments=segs)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    obj = add_mesh_obj(name, me, loc, rot, parent=parent)
    obj.data.materials.append(MATS[mat_name])
    return obj

def make_bevel_gear(name, r_outer, r_inner, height, teeth_count=18, mat_name="brass", loc=(0,0,0), rot=(0,0,0), parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, radius1=r_outer, radius2=r_inner, depth=height, segments=teeth_count*2)
    bm.faces.ensure_lookup_table()
    side_faces = [f for f in bm.faces if abs(f.normal.z) < 0.7]
    teeth_faces = side_faces[0::2]
    if teeth_faces:
        verts = list({v for f in teeth_faces for v in f.verts})
        bmesh.ops.scale(bm, vec=Vector((1.12, 1.12, 1.0)), verts=verts)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    obj = add_mesh_obj(name, me, loc, rot, parent=parent)
    obj.data.materials.append(MATS[mat_name])
    return obj

def make_millstone(name, radius, height, grooves=16, mat_name="granite", loc=(0,0,0), rot=(0,0,0), rim=True, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, radius1=radius, radius2=radius*0.96, depth=height, segments=48)
    bm.faces.ensure_lookup_table()
    top_faces = [f for f in bm.faces if f.normal.z > 0.8]
    if top_faces:
        bmesh.ops.inset_individual(bm, faces=top_faces, thickness=0.015, depth=-0.02)
    me = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(me)
    bm.free()
    obj = add_mesh_obj(name, me, loc, rot, parent=parent)
    obj.data.materials.append(MATS[mat_name])

    if rim:
        rim_obj = make_cylinder(name + "_Rim", radius*1.015, height*0.35,
                                loc=(0, 0, height*0.2), mat_name="iron", parent=obj)
    return obj

def make_flywheel(name, r_outer, width, spoke_count=6, loc=(0,0,0), rot=(0,0,0), parent=None):
    # Корневой пустой объект для маховика
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = 'CIRCLE'
    root.location = loc
    root.rotation_euler = rot
    if parent:
        root.parent = parent
    col_crusher.objects.link(root)

    # Обод маховика
    rim = make_cylinder(name + "_Rim", r_outer, width, loc=(0, 0, 0), rot=(0, math.pi/2, 0), segs=36, mat_name="iron", parent=root)
    # Внутренняя ступица
    hub = make_cylinder(name + "_Hub", r_outer * 0.22, width * 1.3, loc=(0, 0, 0), rot=(0, math.pi/2, 0), segs=20, mat_name="brass", parent=root)

    # Спицы
    for i in range(spoke_count):
        ang = i * (2 * math.pi / spoke_count)
        sy = math.cos(ang) * (r_outer * 0.5)
        sz = math.sin(ang) * (r_outer * 0.5)
        sp = make_cylinder(f"{name}_Spoke_{i}", r_outer * 0.045, r_outer * 0.8,
                           loc=(0, sy, sz), rot=(ang, 0, 0), segs=10, mat_name="iron", parent=root)

    # Противовес на ободе
    c_weight = make_box(name + "_Counterweight", (width * 1.15, r_outer * 0.28, r_outer * 0.16),
                        loc=(0, 0, -r_outer * 0.72), mat_name="iron_dark", bevel=0.01, parent=root)
    return root

# ==============================================================================
# СБОРКА КОМПОНЕНТОВ ДРОБИЛКИ
# ==============================================================================

# Общий корневой контейнер
root_crusher = bpy.data.objects.new("StoneCrusherRoot", None)
col_crusher.objects.link(root_crusher)

# ----------------- 1. СТАТИЧЕСКАЯ ЧАСТЬ -----------------

# А. Каменный фундамент (Foundation_Stone)
foundation = make_box("Foundation_Stone", (2.2, 2.2, 0.35), loc=(0, 0, 0.175), mat_name="granite_rough", bevel=0.04, parent=root_crusher)

# Б. Деревянный силовой каркас (Frame_Base)
# 4 массивные угловые стойки
posts = []
post_size = 0.18
post_h = 1.95
for sx in (-0.75, 0.75):
    for sy in (-0.75, 0.75):
        p = make_box(f"Frame_Post_{sx}_{sy}", (post_size, post_size, post_h),
                     loc=(sx, sy, 0.35 + post_h / 2), mat_name="wood", bevel=0.015, parent=root_crusher)
        posts.append(p)
        # Стальные косынки внизу
        make_box(f"Frame_Gusset_{sx}_{sy}", (post_size*1.3, post_size*1.3, 0.08),
                 loc=(sx, sy, 0.39), mat_name="iron", parent=root_crusher)

# Горизонтальные балки обвязки
beam_h = 0.16
for y_pos in (-0.75, 0.75):
    make_box(f"Frame_Beam_X_{y_pos}", (1.5, post_size, beam_h),
             loc=(0, y_pos, 0.35 + post_h - beam_h/2), mat_name="wood", bevel=0.01, parent=root_crusher)
for x_pos in (-0.75, 0.75):
    make_box(f"Frame_Beam_Y_{x_pos}", (post_size, 1.5, beam_h),
             loc=(x_pos, 0, 0.35 + post_h - beam_h/2), mat_name="wood", bevel=0.01, parent=root_crusher)

# Центральная поперечная балка для верхнего подшипника
make_box("Frame_Beam_Center", (1.5, post_size*1.2, beam_h),
         loc=(0, 0, 0.35 + post_h - beam_h/2), mat_name="wood", bevel=0.01, parent=root_crusher)

# В. Нижний неподвижный жернов (Millstone_Lower)
stone_r = 0.62
stone_h = 0.32
stone_z0 = 0.35 + stone_h / 2
millstone_lower = make_millstone("Millstone_Lower", stone_r, stone_h, grooves=0, mat_name="granite",
                                 loc=(0, 0, stone_z0), parent=root_crusher)

# Кожух дробильной камеры (Crusher_Housing)
housing_r = stone_r * 1.08
housing_h = 0.55
crusher_housing = make_cylinder("Crusher_Housing", housing_r, housing_h,
                                loc=(0, 0, 0.35 + housing_h/2), mat_name="iron", segs=40, parent=root_crusher)

# Разгрузочный наклонный лоток (Chute_Discharge) - направлен вперед (-Y)
chute_w = 0.42
chute_l = 0.70
chute_h = 0.14
chute = make_box("Chute_Discharge", (chute_w, chute_l, chute_h),
                 loc=(0, -0.85, 0.42), mat_name="iron_dark", bevel=0.01, parent=root_crusher)
chute.rotation_euler = (math.radians(-24), 0, 0)

# Маленькая горка дробленого камня под лотком
gravel_pile = make_cone = make_cylinder("Crushed_Gravel_Pile", 0.35, 0.18, loc=(0, -1.22, 0.26),
                                        segs=16, mat_name="gravel", parent=root_crusher)

# Загрузочный бункер (Hopper_Feed) - сверху
hopper_z = 0.35 + post_h + 0.18
hopper_w_top = 0.85
hopper_w_bot = 0.38
hopper_depth = 0.45
hopper = make_box("Hopper_Feed", (hopper_w_top, hopper_w_top, hopper_depth),
                  loc=(0, 0, hopper_z), mat_name="iron", bevel=0.02, parent=root_crusher)

# Г. Паровой двигатель и котел (Steam_Boiler)
# Расположен сбоку справа (+X)
boiler_x = 0.82
boiler_y = 0.05
boiler_r = 0.28
boiler_h = 1.15
boiler_z = 0.35 + boiler_h / 2
boiler = make_cylinder("Steam_Boiler", boiler_r, boiler_h, loc=(boiler_x, boiler_y, boiler_z),
                       segs=32, mat_name="iron_dark", parent=root_crusher)

# Купольная крышка котла
boiler_dome = make_cylinder("Steam_Boiler_Dome", boiler_r * 0.98, 0.12,
                            loc=(boiler_x, boiler_y, boiler_z + boiler_h/2 + 0.06), mat_name="iron_dark", parent=root_crusher)

# Латунные обручи на котле
for dz in (-0.35, 0.0, 0.35):
    make_cylinder(f"Boiler_Band_{dz}", boiler_r * 1.02, 0.045,
                  loc=(boiler_x, boiler_y, boiler_z + dz), mat_name="brass", parent=root_crusher)

# Манометр (Pressure Gauge)
gauge_loc = (boiler_x + boiler_r * 0.85, boiler_y - boiler_r * 0.45, boiler_z + 0.25)
gauge_body = make_cylinder("Pressure_Gauge_Body", 0.08, 0.04, loc=gauge_loc,
                           rot=(0, math.pi/2, math.radians(-30)), mat_name="brass", parent=root_crusher)
gauge_face = make_cylinder("Pressure_Gauge_Face", 0.065, 0.042, loc=gauge_loc,
                           rot=(0, math.pi/2, math.radians(-30)), mat_name="gauge_face", parent=root_crusher)

# Медные трубы обвязки (Static_Pipes)
pipe1 = make_cylinder("Pipe_Steam_Supply", 0.035, 0.65, loc=(boiler_x - 0.25, boiler_y, boiler_z + 0.45),
                      rot=(0, math.pi/2, 0), mat_name="copper", parent=root_crusher)

# Выхлопная труба (Exhaust_Pipe)
exhaust_h = 0.85
exhaust_r = 0.09
exhaust_z = boiler_z + boiler_h/2 + exhaust_h/2 + 0.10
exhaust = make_cylinder("Exhaust_Pipe", exhaust_r, exhaust_h,
                        loc=(boiler_x, boiler_y, exhaust_z), mat_name="iron", parent=root_crusher)
exhaust_cap = make_cylinder("Exhaust_Rain_Cap", exhaust_r * 1.45, 0.04,
                            loc=(boiler_x, boiler_y, exhaust_z + exhaust_h/2 + 0.03), mat_name="iron", parent=root_crusher)

# Паровой цилиндр (Engine Cylinder)
cyl_x = boiler_x - 0.22
cyl_y = -0.42
cyl_z = 0.72
engine_cyl = make_cylinder("Engine_Cylinder", 0.12, 0.38, loc=(cyl_x, cyl_y, cyl_z),
                           rot=(math.pi/2, 0, 0), segs=24, mat_name="iron", parent=root_crusher)


# ----------------- 2. КИНЕМАТИЧЕСКАЯ ЧАСТЬ (АНИМИРОВАННЫЕ УЗЛЫ) -----------------

# А. Верхний жернов (Millstone_Upper)
# Зазор 0.07м над нижним камнем: Z = 0.35 + 0.32 + 0.07 + stone_h/2 = 0.90
gap = 0.07
upper_stone_z = 0.35 + stone_h + gap + stone_h / 2
millstone_upper = make_millstone("Millstone_Upper", stone_r * 0.96, stone_h, grooves=16,
                                 mat_name="granite", loc=(0, 0, upper_stone_z), parent=root_crusher)

# Б. Центральный вертикальный вал (Shaft_Central)
shaft_h = 1.35
shaft_z = upper_stone_z + shaft_h / 2 - 0.15
shaft_central = make_cylinder("Shaft_Central", 0.055, shaft_h, loc=(0, 0, shaft_z),
                              mat_name="iron", parent=root_crusher)

# В. Вертикальная коническая шестерня (Gear_Bevel_Vertical) на центральном валу
gear_bevel_v = make_bevel_gear("Gear_Bevel_Vertical", 0.24, 0.18, 0.08, teeth_count=18,
                               mat_name="brass", loc=(0, 0, upper_stone_z + 0.88), parent=root_crusher)

# Г. Горизонтальный приводной вал двигателя
horiz_shaft_z = upper_stone_z + 0.88
horiz_shaft_x = 0.42
horiz_shaft = make_cylinder("Shaft_Horizontal_Drive", 0.045, 0.95, loc=(horiz_shaft_x, 0, horiz_shaft_z),
                            rot=(0, math.pi/2, 0), mat_name="iron", parent=root_crusher)

# Д. Горизонтальная коническая шестерня (Gear_Bevel_Horizontal)
gear_bevel_h = make_bevel_gear("Gear_Bevel_Horizontal", 0.24, 0.18, 0.08, teeth_count=18,
                               mat_name="brass", loc=(0.18, 0, horiz_shaft_z),
                               rot=(0, -math.pi/2, 0), parent=root_crusher)

# Е. Маховик привода (Drive_Flywheel)
flywheel_x = 0.88
flywheel_y = -0.42
flywheel_z = 0.72
flywheel = make_flywheel("Drive_Flywheel", r_outer=0.48, width=0.10, spoke_count=6,
                         loc=(flywheel_x, flywheel_y, flywheel_z), rot=(0, math.pi/2, 0), parent=root_crusher)

# Ж. Кривошипный диск и кривошипный палец (Crank)
crank_r = 0.14
crank_disc = make_cylinder("Crank_Disc", 0.18, 0.05, loc=(flywheel_x - 0.06, flywheel_y, flywheel_z),
                           rot=(0, math.pi/2, 0), mat_name="iron", parent=root_crusher)

# З. Шток и поршень (Engine_Piston)
piston = make_cylinder("Engine_Piston", 0.04, 0.35, loc=(cyl_x, cyl_y, cyl_z),
                       rot=(math.pi/2, 0, 0), mat_name="iron_dark", parent=root_crusher)

# И. Шатун (Connecting_Rod)
con_rod = make_box("Connecting_Rod", (0.045, 0.42, 0.055), loc=(cyl_x + 0.05, cyl_y - 0.22, cyl_z),
                   mat_name="brass", bevel=0.008, parent=root_crusher)


# ----------------- 3. ЭФФЕКТНЫЕ ТОЧКИ / МАРКЕРЫ (EFFECT NODES) -----------------
def add_marker(name, loc):
    m = bpy.data.objects.new(name, None)
    m.empty_display_type = 'PLAIN_AXES'
    m.empty_display_size = 0.2
    m.location = loc
    m.parent = root_crusher
    col_crusher.objects.link(m)
    return m

marker_smoke = add_marker("Smoke_Emitter", (boiler_x, boiler_y, exhaust_z + exhaust_h/2 + 0.05))
marker_steam = add_marker("Steam_Emitter", (boiler_x + boiler_r, boiler_y, boiler_z + 0.45))
marker_dust = add_marker("Grinding_Dust", (0, 0, upper_stone_z - stone_h/2))
marker_chute = add_marker("Crushed_Stone_Output", (0, -1.15, 0.35))


# ==============================================================================
# 4. СОЗДАНИЕ КИНЕМАТИЧЕСКОЙ АНИМАЦИИ (ACTION: Crusher_Work)
# ==============================================================================
# Полный бесшовный цикл на 60 кадров (2.0 секунды):
# - Маховик делает 2 полных оборота (720 градусов)
# - Поршень совершает 2 гармонических хода вперед-назад
# - Верхний жернов и центральный вал совершают непрерывный поворот на 240 градусов

def set_linear_interpolation(obj):
    if not obj.animation_data or not obj.animation_data.action:
        return
    act = obj.animation_data.action
    fcurves = []
    if hasattr(act, 'fcurves'):
        fcurves = act.fcurves
    elif hasattr(act, 'layers'):
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    fcurves.extend(cb.fcurves)
    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'

def setup_rotation_anim(obj, axis_index, start_deg, end_deg):
    obj.rotation_euler[axis_index] = math.radians(start_deg)
    obj.keyframe_insert(data_path="rotation_euler", index=axis_index, frame=1)
    obj.rotation_euler[axis_index] = math.radians(end_deg)
    obj.keyframe_insert(data_path="rotation_euler", index=axis_index, frame=61)
    set_linear_interpolation(obj)

# Анимация маховика (вращение вокруг локальной оси X)
setup_rotation_anim(flywheel, 0, 0.0, 720.0)

# Анимация кривошипного диска
setup_rotation_anim(crank_disc, 0, 0.0, 720.0)

# Анимация верхнего жернова (вращение вокруг вертикальной оси Z)
setup_rotation_anim(millstone_upper, 2, 0.0, 240.0)

# Анимация центрального вала и вертикальной шестерни
setup_rotation_anim(shaft_central, 2, 0.0, 240.0)
setup_rotation_anim(gear_bevel_v, 2, 0.0, 240.0)

# Анимация горизонтального вала и горизонтальной шестерни
setup_rotation_anim(horiz_shaft, 0, 0.0, 480.0)
setup_rotation_anim(gear_bevel_h, 0, 0.0, 480.0)

# Анимация хода поршня (возвратно-поступательное движение по оси Y)
for f in range(1, 62):
    t = (f - 1) / 30.0 * math.pi * 2  # 2 полных оборота
    y_val = cyl_y + math.cos(t) * crank_r
    piston.location[1] = y_val
    piston.keyframe_insert(data_path="location", index=1, frame=f)

# Анимация шатуна (качание угла и смещение)
for f in range(1, 62):
    t = (f - 1) / 30.0 * math.pi * 2
    y_val = cyl_y - 0.22 + math.cos(t) * (crank_r * 0.5)
    rot_val = math.sin(t) * math.radians(14)
    con_rod.location[1] = y_val
    con_rod.rotation_euler[0] = rot_val
    con_rod.keyframe_insert(data_path="location", index=1, frame=f)
    con_rod.keyframe_insert(data_path="rotation_euler", index=0, frame=f)

# ==============================================================================
# 5. СОХРАНЕНИЕ И ЭКСПОРТ
# ==============================================================================

# Сохранение .blend файла
blend_filepath = os.path.join(OUT_BUILD, "crusher.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_filepath)
print(f"Blender project saved: {blend_filepath}")

# Экспорт в glTF / GLB (rock_grinder.glb)
glb_target_build = os.path.join(OUT_BUILD, "rock_grinder.glb")
glb_target_assets = os.path.join(OUT_ASSETS, "rock_grinder.glb")

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=glb_target_build,
    export_format='GLB',
    use_selection=False,
    export_apply=False,
    export_animations=True,
    export_current_frame=False,
    export_materials='EXPORT',
    export_cameras=False,
    export_lights=False
)

# Копируем также в assets/models/crusher/
import shutil
shutil.copyfile(glb_target_build, glb_target_assets)
print(f"GLB asset exported: {glb_target_assets} ({os.path.getsize(glb_target_assets)} bytes)")

# ==============================================================================
# 6. ОПЦИОНАЛЬНЫЙ РЕНДЕР С 3 РАКУРСОВ (если передан флаг --render)
# ==============================================================================
if "--render" in sys.argv:
    print("Rendering studio previews...")
    render_dir = os.path.join(OUT_BUILD, "renders")
    os.makedirs(render_dir, exist_ok=True)

    # Настройка студийного света
    light_data = bpy.data.lights.new(name="KeyLight", type='SUN')
    light_data.energy = 4.5
    light_obj = bpy.data.objects.new("KeyLight", light_data)
    light_obj.rotation_euler = (math.radians(50), math.radians(20), math.radians(-35))
    sc.collection.objects.link(light_obj)

    fill_light = bpy.data.lights.new(name="FillLight", type='SUN')
    fill_light.energy = 2.0
    fill_obj = bpy.data.objects.new("FillLight", fill_light)
    fill_obj.rotation_euler = (math.radians(30), math.radians(-40), math.radians(140))
    sc.collection.objects.link(fill_obj)

    # Камера
    cam_data = bpy.data.cameras.new("RenderCam")
    cam_data.lens = 55
    cam_obj = bpy.data.objects.new("RenderCam", cam_data)
    sc.collection.objects.link(cam_obj)
    sc.camera = cam_obj

    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if hasattr(bpy.types, 'RenderSettings') and 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'

    views = [
        ("front_iso", (3.2, -3.4, 2.8), (math.radians(60), 0, math.radians(45))),
        ("rear_iso", (-3.2, 3.4, 2.8), (math.radians(60), 0, math.radians(-135))),
        ("top_hopper", (0.0, -0.2, 4.2), (0, 0, 0)),
    ]

    for v_name, loc, rot in views:
        cam_obj.location = loc
        cam_obj.rotation_euler = rot
        sc.render.filepath = os.path.join(render_dir, f"preview_{v_name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered: {sc.render.filepath}")

print("CRUSHER BLENDER GENERATION COMPLETED SUCCESSFULLY.")
