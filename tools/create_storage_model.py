"""Склад продукции «После бури» — процедурная модель в трёх состояниях для Blender 5.x (pip install bpy).
Референс: docs/art/storage_reference.svg, промт: docs/art/storage_reference_prompt.md.
Состояния (переменная STORAGE_STATE):
  ruins   — разрушенный склад (стадия 0): треснувшая плита, обломанные стойки, рухнувшая балка,
            ржавые листы кровли, разбитые ящики, рваный тент;
  barn    — восстановленный амбар (стадии 1–2): каркас с полом и припасами (frame), стены, ворота
            и кровля (shell), тент на стропилах (tarp). Стадия 1 = frame + tarp, стадия 2 = frame + shell;
  complex — логистический комплекс (стадия 3): кирпичный цоколь, обшивка, оцинкованная кровля,
            рулонные ворота, стеллажи, сортировочный навес и ручной подъёмник на шестернях
            (подвижные части: gear, crank, chain, hook);
  all     — все три рядом (только для рендера).
Запуск из корня проекта:
  STORAGE_STATE=barn python3 tools/create_storage_model.py --render 32
  STORAGE_STATE=barn python3 tools/create_storage_model.py --bake 2048
Папка результата — STORAGE_OUT (по умолчанию ./storage_build), запекание — в <STORAGE_OUT>/bake_<state>.
Затем: godot --headless --path . -s tools/import_storage_model.gd -- <STORAGE_OUT>

Оси Blender: Z — вверх, фасад смотрит в -Y (в Godot это +Z)."""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix
STATE = os.environ.get("STORAGE_STATE", "all")
OUT_ROOT = os.path.abspath(os.environ.get("STORAGE_OUT", "storage_build"))
os.makedirs(OUT_ROOT, exist_ok=True)
open(os.path.join(OUT_ROOT, ".gdignore"), "w").close()  # Godot не импортирует промежуточные файлы
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col_main = bpy.data.collections.new("Storage"); sc.collection.children.link(col_main)
col_env = bpy.data.collections.new("Stage"); sc.collection.children.link(col_env)
PART = "body"

# ---------- материалы ----------
def srgb(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def _mix_rgb(N, L, fac, a, b):
    m = N.new("ShaderNodeMix"); m.data_type = 'RGBA'; m.clamp_factor = True
    L.new(fac, m.inputs[0])
    if isinstance(a, tuple): m.inputs[6].default_value = (*a, 1)
    else: L.new(a, m.inputs[6])
    if isinstance(b, tuple): m.inputs[7].default_value = (*b, 1)
    else: L.new(b, m.inputs[7])
    return m.outputs[2]

def _mix_f(N, L, fac, a, b):
    m = N.new("ShaderNodeMix"); m.data_type = 'FLOAT'; m.clamp_factor = True
    L.new(fac, m.inputs[0])
    if isinstance(a, (int, float)): m.inputs[2].default_value = a
    else: L.new(a, m.inputs[2])
    if isinstance(b, (int, float)): m.inputs[3].default_value = b
    else: L.new(b, m.inputs[3])
    return m.outputs[0]

def _maprange(N, L, v, a, b, c=0.0, d=1.0):
    m = N.new("ShaderNodeMapRange"); m.clamp = True
    L.new(v, m.inputs["Value"])
    m.inputs["From Min"].default_value = a; m.inputs["From Max"].default_value = b
    m.inputs["To Min"].default_value = c; m.inputs["To Max"].default_value = d
    return m.outputs[0]

def _math(N, L, op, a, b=None):
    m = N.new("ShaderNodeMath"); m.operation = op
    for i, v in enumerate((a, b)):
        if v is None: continue
        if isinstance(v, (int, float)): m.inputs[i].default_value = v
        else: L.new(v, m.inputs[i])
    return m.outputs[0]

def pbr(name, c1, c2=None, rough=0.6, metal=0.0, scale=6.0, bump=0.2, wear=None, wear_metal=0.85,
        rust=0.0, stripes=None, bevel=0.012, grain=None, voronoi=None, emit=None, emit_strength=0.0):
    """Процедурный PBR-материал: шум цвета, сколы краски по рёбрам (Bevel-узел), ржавые потёки,
    диагональные полосы, волокна дерева, зерно щебня; скруглённые рёбра в нормалях."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale; nz.inputs["Detail"].default_value = 8
    nz.inputs["Roughness"].default_value = 0.6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    fac = nz.outputs["Fac"]
    if grain:
        mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = grain
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        wv = N.new("ShaderNodeTexWave"); wv.inputs["Scale"].default_value = 4.0; wv.bands_direction = 'Y'
        wv.inputs["Distortion"].default_value = 3.0; wv.inputs["Detail"].default_value = 3
        L.new(mp.outputs["Vector"], wv.inputs["Vector"])
        fac = _math(N, L, 'MULTIPLY', _math(N, L, 'ADD', fac, wv.outputs["Fac"]), 0.5)
    if voronoi:
        vo = N.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = voronoi
        L.new(tc.outputs["Object"], vo.inputs["Vector"])
        cell = _maprange(N, L, vo.outputs["Distance"], 0.0, 0.5)
        fac = _math(N, L, 'MULTIPLY', _math(N, L, 'ADD', _math(N, L, 'MULTIPLY', fac, 0.4), _math(N, L, 'MULTIPLY', vo.outputs["Color"], 0.6)), 1.0)
        height = _math(N, L, 'SUBTRACT', 1.0, cell)
    else:
        height = fac
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3; ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[0].color = (*srgb(c1), 1); ramp.color_ramp.elements[1].color = (*srgb(c2 or c1), 1)
    L.new(fac, ramp.inputs["Fac"])
    color = ramp.outputs["Color"]
    rgh = _maprange(N, L, nz.outputs["Fac"], 0.0, 1.0, max(0.05, rough - 0.12), min(1.0, rough + 0.12))
    met = metal
    if stripes:
        sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
        s = _math(N, L, 'ADD', _math(N, L, 'ADD', sep.outputs[0], sep.outputs[1]), sep.outputs[2])
        s = _math(N, L, 'FRACT', _math(N, L, 'MULTIPLY', s, stripes))
        smask = _math(N, L, 'GREATER_THAN', s, 0.5)
        color = _mix_rgb(N, L, smask, color, srgb('#1c1b1a'))
    if rust > 0:
        mp = N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (16.0, 16.0, 1.6)
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        rn = N.new("ShaderNodeTexNoise"); rn.inputs["Scale"].default_value = 2.0; rn.inputs["Detail"].default_value = 6
        L.new(mp.outputs["Vector"], rn.inputs["Vector"])
        rmask = _math(N, L, 'MULTIPLY', _maprange(N, L, rn.outputs["Fac"], 0.55, 0.72), rust)
        color = _mix_rgb(N, L, rmask, color, srgb('#5a3420'))
        rgh = _mix_f(N, L, rmask, rgh, 0.9)
    if wear:
        bv = N.new("ShaderNodeBevel"); bv.samples = 8; bv.inputs["Radius"].default_value = 0.025
        geo = N.new("ShaderNodeNewGeometry")
        dot = N.new("ShaderNodeVectorMath"); dot.operation = 'DOT_PRODUCT'
        L.new(bv.outputs["Normal"], dot.inputs[0]); L.new(geo.outputs["Normal"], dot.inputs[1])
        edge = _maprange(N, L, _math(N, L, 'SUBTRACT', 1.0, dot.outputs["Value"]), 0.003, 0.05)
        wn = N.new("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = 28; wn.inputs["Detail"].default_value = 6
        L.new(tc.outputs["Object"], wn.inputs["Vector"])
        chips_edge = _maprange(N, L, _math(N, L, 'MULTIPLY', edge, _math(N, L, 'MULTIPLY', wn.outputs["Fac"], 1.8)), 0.45, 0.6)
        cn = N.new("ShaderNodeTexNoise"); cn.inputs["Scale"].default_value = 7; cn.inputs["Detail"].default_value = 10
        cn.inputs["Roughness"].default_value = 0.7
        L.new(tc.outputs["Object"], cn.inputs["Vector"])
        chips_flat = _maprange(N, L, cn.outputs["Fac"], 0.66, 0.69)
        chip = _math(N, L, 'MAXIMUM', chips_edge, chips_flat)
        color = _mix_rgb(N, L, chip, color, srgb(wear))
        rgh = _mix_f(N, L, chip, rgh, 0.45)
        met = _mix_f(N, L, chip, metal, wear_metal)
    L.new(color, b.inputs["Base Color"])
    L.new(rgh, b.inputs["Roughness"])
    if isinstance(met, (int, float)): b.inputs["Metallic"].default_value = met
    else: L.new(met, b.inputs["Metallic"])
    if emit:
        b.inputs["Emission Color"].default_value = (*srgb(emit), 1)
        b.inputs["Emission Strength"].default_value = emit_strength
    bp = N.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump; bp.inputs["Distance"].default_value = 0.02
    L.new(height, bp.inputs["Height"])
    if bevel > 0:
        bv2 = N.new("ShaderNodeBevel"); bv2.samples = 8; bv2.inputs["Radius"].default_value = bevel
        L.new(bv2.outputs["Normal"], bp.inputs["Normal"])
    L.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m

def brick_mat(name, c1, c2, mortar, rough=0.85):
    """Кирпичная кладка: Brick-текстура по координатам (x + y, z) — годится для стен вдоль X и Y."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    b = N["Principled BSDF"]
    tc = N.new("ShaderNodeTexCoord")
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(tc.outputs["Object"], sep.inputs[0])
    cmb = N.new("ShaderNodeCombineXYZ")
    L.new(_math(N, L, 'ADD', sep.outputs[0], sep.outputs[1]), cmb.inputs[0]); L.new(sep.outputs[2], cmb.inputs[1])
    br = N.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 1.0; br.inputs["Mortar Size"].default_value = 0.011
    br.inputs["Brick Width"].default_value = 0.25; br.inputs["Row Height"].default_value = 0.075
    br.inputs["Mortar Smooth"].default_value = 0.2
    br.offset = 0.5; br.squash = 1.0
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 9; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*srgb(c1), 1); ramp.color_ramp.elements[1].color = (*srgb(c2), 1)
    L.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    L.new(cmb.outputs[0], br.inputs["Vector"])
    L.new(ramp.outputs["Color"], br.inputs["Color1"])
    br.inputs["Color2"].default_value = (*srgb(c2), 1)
    br.inputs["Mortar"].default_value = (*srgb(mortar), 1)
    L.new(br.outputs["Color"], b.inputs["Base Color"])
    L.new(_maprange(N, L, nz.outputs["Fac"], 0.0, 1.0, rough - 0.1, rough + 0.08), b.inputs["Roughness"])
    bp = N.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.6; bp.inputs["Distance"].default_value = 0.01
    L.new(_math(N, L, 'SUBTRACT', 1.0, br.outputs["Fac"]), bp.inputs["Height"])
    L.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m

M = {
    "wood_old": pbr("OldPlanks", '#5c544a', '#8a7d6c', rough=0.9, scale=3, bump=0.45, grain=(0.12, 1.0, 1.0), bevel=0.01),
    "wood_oldz": pbr("OldPlanksV", '#5a5248', '#867a6a', rough=0.9, scale=3, bump=0.45, grain=(1.0, 1.0, 0.12), bevel=0.01),
    "wood_dark": pbr("CharredWood", '#2c2621', '#4a3f35', rough=0.95, scale=4, bump=0.6, grain=(1.0, 1.0, 0.12), bevel=0.01),
    "wood_new": pbr("FreshPine", '#a67c4c', '#c79d66', rough=0.75, scale=3, bump=0.3, grain=(0.12, 1.0, 1.0), bevel=0.008),
    "wood_newz": pbr("FreshPineV", '#a27a4a', '#c49a62', rough=0.75, scale=3, bump=0.3, grain=(1.0, 1.0, 0.12), bevel=0.008),
    "siding": pbr("RedSiding", '#7a3524', '#93432c', rough=0.65, scale=5, bump=0.12, wear='#7c6d5a', wear_metal=0.0, grain=(0.12, 1.0, 1.0), bevel=0.006),
    "trim": pbr("WhiteTrim", '#c9c2b2', '#ddd6c6', rough=0.6, scale=6, bump=0.08, wear='#6f6455', wear_metal=0.0, bevel=0.006),
    "rust_sheet": pbr("RustySheet", '#5e4433', '#8a6448', rough=0.8, metal=0.45, scale=5, bump=0.3, rust=0.9),
    "old_sheet": pbr("OldGalvanized", '#6f7477', '#8f9597', rough=0.55, metal=0.7, scale=4, bump=0.1, voronoi=14, rust=0.6),
    "galv": pbr("Galvanized", '#8d959a', '#b1b9bd', rough=0.38, metal=0.85, scale=4, bump=0.06, voronoi=22, rust=0.1),
    "steel": pbr("Steel", '#5f646a', '#80868c', rough=0.38, metal=0.9, scale=10, bump=0.03, bevel=0.006),
    "iron": pbr("CastIron", '#26282b', '#36393d', rough=0.55, metal=0.85, scale=14, bump=0.12, wear='#7d8288', wear_metal=1.0),
    "rust": pbr("Rust", '#4a2c1b', '#7a4626', rough=0.85, metal=0.35, scale=9, bump=0.35, rust=0.6),
    "blue": pbr("BluePaint", '#2c5577', '#376690', rough=0.5, scale=6, bump=0.04, wear='#4a4d50', rust=0.15),
    "orange": pbr("OrangePaint", '#c0621f', '#d47428', rough=0.5, scale=6, bump=0.04, wear='#4a4d50', rust=0.15),
    "yellow": pbr("YellowPaint", '#c79620', '#d8a72a', rough=0.5, scale=6, bump=0.04, wear='#3b3936', rust=0.2),
    "red": pbr("RedPaint", '#8e1f17', '#a92b1d', rough=0.5, scale=6, bump=0.04, wear='#4a4a4a', rust=0.2),
    "green": pbr("GreenPaint", '#3f5a3b', '#4f6e49', rough=0.5, scale=6, bump=0.04, wear='#5e6266', rust=0.2),
    "concrete": pbr("Concrete", '#7f7c76', '#a19e97', rough=0.9, scale=5, bump=0.35, bevel=0.015),
    "stone": pbr("FieldStone", '#625e58', '#9a948a', rough=0.85, scale=6, bump=0.7, voronoi=5, bevel=0.0),
    "rubble": pbr("Rubble", '#6a665f', '#9d988f', rough=0.88, scale=7, bump=0.6, bevel=0.0),
    "brick": brick_mat("FiredBrick", '#8a3f26', '#a5552f', '#b8ae9c'),
    "tarp": pbr("GreenTarp", '#34512f', '#46663d', rough=0.75, scale=3, bump=0.25, bevel=0.0),
    "tarp_old": pbr("FadedTarp", '#4d5c3d', '#68754f', rough=0.85, scale=3, bump=0.35, rust=0.25, bevel=0.0),
    "rope": pbr("Rope", '#8b7a55', '#a8956a', rough=0.95, scale=60, bump=0.6, bevel=0.0),
    "burlap": pbr("Burlap", '#8c7a56', '#ab976c', rough=0.95, scale=45, bump=0.5, bevel=0.0),
    "white": pbr("SignPlate", '#d8d2c4', '#ece6d8', rough=0.6, scale=9, bump=0.1, wear='#5a5650', rust=0.25, bevel=0.003),
    "ink": pbr("SignInk", '#1d1b19', '#2a2724', rough=0.7, scale=9, bump=0.0, bevel=0.0),
    "glass": pbr("Glass", '#1c2a31', '#2c3d45', rough=0.12, scale=4, bump=0.0, bevel=0.0),
    "plaster": pbr("Plaster", '#8d877c', '#a49d90', rough=0.9, scale=4, bump=0.15, bevel=0.0),
    "dark": pbr("Shadowed", '#1c1a18', '#2a2724', rough=0.9, scale=5, bump=0.0, bevel=0.0),
    "lampglass": pbr("LampGlass", '#e9d9a0', '#f4e6b4', rough=0.25, scale=5, bump=0.0, bevel=0.0),
    "ground": pbr("Ground", '#3f5e22', '#62822f', rough=0.95, scale=1.5, bump=0.2, bevel=0.0),
    "dirt": pbr("Dirt", '#54402d', '#7a5c40', rough=0.95, scale=2, bump=0.3, bevel=0.0),
    "gravel": pbr("Gravel", '#57544f', '#8c877f', rough=0.9, scale=30, bump=0.9, voronoi=40, bevel=0.0),
    "logs": pbr("LogBark", '#4b3a2a', '#6b5440', rough=0.95, scale=8, bump=0.7, bevel=0.0),
}

# ---------- примитивы ----------
def link(o, c=None):
    for cc in o.users_collection: cc.objects.unlink(o)
    (c or col_main).objects.link(o)
    if c is None: o["part"] = PART
    return o

def finish(o, m, bevel=0.0, smooth=False, c=None, segs=1):
    link(o, c)
    o.data.materials.clear(); o.data.materials.append(M[m] if isinstance(m, str) else m)
    if bevel > 0:
        md = o.modifiers.new("Bevel", 'BEVEL'); md.width = bevel; md.segments = segs; md.limit_method = 'ANGLE'
        md.harden_normals = True
        o.data.shade_smooth()
    elif smooth:
        o.data.shade_smooth()
    return o

def from_bm(name, bm, m, bevel=0.0, smooth=False, segs=1):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); sc.collection.objects.link(o)
    return finish(o, m, bevel, smooth, segs=segs)

def box(name, size, loc, m, rot=(0, 0, 0), bevel=0.0, segs=1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, m, bevel, segs=segs)

def _auto_sharp(o, angle=40):
    """Плоские торцы + гладкие бока цилиндров: острые рёбра по углу."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle() > math.radians(angle):
            e.smooth = False
    bm.to_mesh(o.data); bm.free()

def cyl(name, r, h, loc, m, axis='Z', verts=24, r2=None, bevel=0.0, smooth=True):
    rot = {'Z': (0, 0, 0), 'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0)}[axis]
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object; o.name = name
    o = finish(o, m, bevel, smooth)
    if smooth and bevel == 0:
        o.modifiers.new("Normals", 'WEIGHTED_NORMAL').keep_sharp = True
        _auto_sharp(o)
    return o

def rock(name, r, loc, m, jitter=0.28, sub=2, scale=(1, 1, 1), rot=None):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=loc)
    o = bpy.context.object; o.name = name
    for v in o.data.vertices:
        n = v.co.normalized()
        v.co *= 1 + random.uniform(-jitter, jitter) * 0.6 + 0.25 * math.sin(n.x * 5 + n.y * 3) * jitter
    o.scale = scale
    o.rotation_euler = rot or (random.random() * 6, random.random() * 6, random.random() * 6)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(o, m, smooth=True)

def prism_yz(name, pts, x0, x1, m, bevel=0.0):
    """Многоугольник в плоскости YZ, выдавленный по X."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in pts]
    b = [bm.verts.new((x1, y, z)) for y, z in pts]
    n = len(pts)
    bm.faces.new(a[::-1]); bm.faces.new(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return from_bm(name, bm, m, bevel)

def prism_xz(name, pts, y0, y1, m, bevel=0.0):
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    n = len(pts)
    bm.faces.new(a); bm.faces.new(b[::-1])
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return from_bm(name, bm, m, bevel)

def ring_x(name, r_out, r_in, width, center, m, segs=48, bevel=0.006):
    """Обод: кольцо с осью X."""
    bm = bmesh.new()
    cx, cy, cz = center
    rings = []
    for x, r in ((cx - width / 2, r_out), (cx + width / 2, r_out), (cx + width / 2, r_in), (cx - width / 2, r_in)):
        rings.append([bm.verts.new((x, cy + r * math.cos(2 * math.pi * i / segs), cz + r * math.sin(2 * math.pi * i / segs))) for i in range(segs)])
    for k in range(4):
        A, B = rings[k], rings[(k + 1) % 4]
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((A[i], A[j], B[j], B[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = from_bm(name, bm, m, bevel)
    o.data.shade_smooth(); _auto_sharp(o)
    return o

def sweep_x(name, pts, x, w, t, m, closed=False, taper=None, bevel=0.0):
    """Протяжка прямоугольного сечения по кривой в плоскости YZ (x = const).
    w — ширина в плоскости, t — толщина по X; taper(u) — множитель ширины."""
    bm = bmesh.new()
    n = len(pts)
    loops = []
    for i, (y, z) in enumerate(pts):
        if closed:
            p0, p1 = pts[i - 1], pts[(i + 1) % n]
        else:
            p0, p1 = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
        ty, tz = p1[0] - p0[0], p1[1] - p0[1]; ln = math.hypot(ty, tz) or 1
        ny, nz = -tz / ln, ty / ln
        k = w * (taper(i / (n - 1)) if taper else 1.0) / 2
        loops.append([bm.verts.new((x + sx * t / 2, y + sn * k * ny, z + sn * k * nz)) for sx, sn in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    segs = n if closed else n - 1
    for i in range(segs):
        A, B = loops[i], loops[(i + 1) % n]
        for k in range(4):
            l = (k + 1) % 4
            bm.faces.new((A[k], A[l], B[l], B[k]))
    if not closed:
        bm.faces.new(loops[0][::-1]); bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return from_bm(name, bm, m, bevel)

def tube(name, pts, r, m, sides=8, closed=False):
    """Трубка по ломаной (кабель, пружина, сварной шов)."""
    bm = bmesh.new()
    pts = [Vector(p) for p in pts]
    n = len(pts)
    loops = []
    prev_n = None
    for i, p in enumerate(pts):
        a = pts[i - 1] if (closed or i > 0) else p
        b = pts[(i + 1) % n] if (closed or i < n - 1) else p
        t = (b - a).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        nrm = prev_n if prev_n is not None else t.cross(ref).normalized()
        nrm = (nrm - t * nrm.dot(t)).normalized(); prev_n = nrm
        bi = t.cross(nrm)
        loops.append([bm.verts.new(p + r * (math.cos(2 * math.pi * k / sides) * nrm + math.sin(2 * math.pi * k / sides) * bi)) for k in range(sides)])
    segs = n if closed else n - 1
    for i in range(segs):
        A, B = loops[i], loops[(i + 1) % n]
        for k in range(sides):
            l = (k + 1) % sides
            bm.faces.new((A[k], A[l], B[l], B[k]))
    if not closed:
        bm.faces.new(loops[0][::-1]); bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return from_bm(name, bm, m, smooth=True)

AXES = {'Z': Vector((0, 0, 1)), 'X': Vector((1, 0, 0)), '-X': Vector((-1, 0, 0)), 'Y': Vector((0, 1, 0)), '-Y': Vector((0, -1, 0))}

def bolt(loc, axis='Z', r=0.016, h=0.014, m="steel", washer=True):
    d = AXES[axis]; ax = axis.strip('-')
    o = cyl("Bolt", r, h, Vector(loc) + d * h / 2, m, axis=ax, verts=6, smooth=False)
    if washer:
        cyl("Washer", r * 1.45, 0.004, Vector(loc) + d * 0.002, "steel", axis=ax, verts=8, smooth=False)
    return o

def rivet(loc, axis='-Y', r=0.011):
    d = AXES[axis]
    return cyl("Rivet", r, 0.008, Vector(loc) + d * 0.004, "steel", axis=axis.strip('-'), verts=8, r2=r * 0.55)

# ---------- дополнительные примитивы ----------
def objs_since(before):
    return [o for o in col_main.objects if o.name not in before]

def snapshot():
    return {o.name for o in col_main.objects}

def xform(objs, loc=(0, 0, 0), rz=0.0, rx=0.0, ry=0.0):
    """Повернуть и сдвинуть группу объектов как единое целое (центр поворота — начало координат)."""
    Mx = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Rotation(ry, 4, 'Y') @ Matrix.Rotation(rx, 4, 'X')
    for o in objs:
        o.matrix_world = Mx @ o.matrix_world
    return objs

def frame_m(origin, ex, ey):
    ex = Vector(ex).normalized(); ey = Vector(ey).normalized(); ez = ex.cross(ey).normalized()
    m = Matrix.Identity(4)
    for r in range(3):
        m[r][0] = ex[r]; m[r][1] = ey[r]; m[r][2] = ez[r]; m[r][3] = origin[r]
    return m

def beam(name, p0, p1, w, h, m, bevel=0.008, up=(0, 0, 1)):
    """Брус от p0 до p1: w — ширина (поперёк, горизонтально), h — высота (вдоль up)."""
    p0 = Vector(p0); p1 = Vector(p1); d = p1 - p0
    o = box(name, (d.length, w, h), (0, 0, 0), m, bevel=bevel)
    upv = Vector(up)
    if abs(d.normalized().dot(upv)) > 0.95: upv = Vector((0, 1, 0)) if abs(d.normalized().y) < 0.95 else Vector((1, 0, 0))
    ey = upv.cross(d).normalized()
    o.matrix_world = frame_m((p0 + p1) / 2, d, ey)
    return o

def board(name, size, loc, m, rot=(0, 0, 0)):
    return box(name, size, loc, m, rot=rot, bevel=0.006)

def prism_xy(name, pts, z0, z1, m, bevel=0.0):
    bm = bmesh.new()
    a = [bm.verts.new((x, y, z0)) for x, y in pts]
    b = [bm.verts.new((x, y, z1)) for x, y in pts]
    n = len(pts)
    bm.faces.new(a[::-1]); bm.faces.new(b)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return from_bm(name, bm, m, bevel)

def corrugated(name, w, l, m, mat4, period=0.076, amp=0.014, rows=1, disp=None, thick=0.004, holes=None):
    """Профлист: волна поперёк (локальная X, ширина w), рёбра вдоль локальной Y (длина l).
    disp(u, v) -> смещение по нормали (вмятины, изгиб), holes(u, v) -> True — дыра."""
    bm = bmesh.new()
    nx = max(4, int(round(w / period * 4)))
    vs = []
    for j in range(rows + 1):
        v = j / rows
        row = []
        for i in range(nx + 1):
            u = i / nx
            x = -w / 2 + w * u
            z = amp * math.sin(2 * math.pi * x / period)
            if disp: z += disp(u, v)
            row.append(bm.verts.new((x, -l / 2 + l * v, z)))
        vs.append(row)
    for j in range(rows):
        for i in range(nx):
            if holes and holes((i + 0.5) / nx, (j + 0.5) / rows): continue
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    o = from_bm(name, bm, m)
    o.data.shade_smooth()
    sd = o.modifiers.new("Thick", 'SOLIDIFY'); sd.thickness = thick; sd.offset = 0.0
    o.matrix_world = mat4
    return o

def cloth(name, nx, ny, fn, m, thick=0.006, holes=None):
    """Ткань по параметрической поверхности fn(u, v) -> Vector; holes(u, v) — рваные дыры."""
    bm = bmesh.new()
    vs = [[bm.verts.new(fn(i / nx, j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            if holes and holes((i + 0.5) / nx, (j + 0.5) / ny): continue
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    o = from_bm(name, bm, m, smooth=True)
    sd = o.modifiers.new("Thick", 'SOLIDIFY'); sd.thickness = thick; sd.offset = 0.0
    return o

FONT = "/usr/share/fonts/liberation-sans/LiberationSans-Bold.ttf"
_font = None
def text(body, loc, size, rot=(math.pi / 2, 0, 0), m="ink", extrude=0.002):
    global _font
    if _font is None and os.path.exists(FONT): _font = bpy.data.fonts.load(FONT)
    bpy.ops.object.text_add(location=loc, rotation=rot)
    tx = bpy.context.object; tx.data.body = body
    if _font: tx.data.font = _font
    tx.data.size = size; tx.data.extrude = extrude; tx.data.align_x = 'CENTER'; tx.data.align_y = 'CENTER'
    bpy.ops.object.convert(target='MESH'); tx = bpy.context.object; tx.name = "Text"
    return finish(tx, m)

def crate(c, s=0.6, rz=0.0, m="wood_new", broken=0.0, lid=True, tip=None, seed=None):
    """Ящик из реек: угловые бруски, по три рейки на сторону, крышка; broken — доля выбитых реек."""
    rnd = random.Random(seed)
    before = snapshot()
    h = s / 2; t = 0.022; cw = 0.045
    for sx in (-1, 1):
        for sy in (-1, 1):
            if rnd.random() < broken * 0.4: continue
            board("CratePost", (cw, cw, s), (sx * (h - cw / 2), sy * (h - cw / 2), h), m)
    sl = (s - 0.03) / 3
    for k in range(3):
        z = 0.015 + sl * (k + 0.5)
        for sy in (-1, 1):
            if rnd.random() >= broken: board("Slat", (s, t, sl - 0.012), (0, sy * (h + t / 2 - 0.001), z), m)
        for sx in (-1, 1):
            if rnd.random() >= broken: board("Slat", (t, s - 0.004, sl - 0.012), (sx * (h + t / 2 - 0.001), 0, z), m)
    board("CrateBottom", (s - 0.01, s - 0.01, 0.02), (0, 0, 0.01), m)
    if lid:
        for k in range(4):
            if rnd.random() >= broken: board("Lid", ((s - 0.01) / 4 - 0.01, s + 0.04, t), (-h + (k + 0.5) * s / 4, 0, s + t / 2), m)
    else:
        box("CrateInside", (s - 0.02, s - 0.02, 0.01), (0, 0, s * 0.7), "dark")
    objs = objs_since(before)
    if tip: xform(objs, (0, 0, 0), rx=tip[0], ry=tip[1])
    return xform(objs, c, rz=rz)

def sack(loc, r=0.25, rz=0.0, flat=0.55, m="burlap"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=14, ring_count=9, location=(0, 0, 0))
    o = bpy.context.object; o.name = "Sack"
    for v in o.data.vertices:
        v.co.x *= 1.35; v.co.y *= 0.9
        v.co.z = max(v.co.z, -r * 0.65) * flat
        v.co += Vector((0, 0, 0)) + v.co.normalized() * 0.012 * math.sin(v.co.x * 40 + v.co.y * 30)
    o.location = (loc[0], loc[1], loc[2] + r * 0.65 * flat); o.rotation_euler = (0, 0, rz)
    finish(o, m, smooth=True)
    tie = cyl("SackTie", 0.035, 0.08, (0, 0, 0), "rope", verts=8)
    tie.location = (loc[0] + math.cos(rz) * r * 1.3, loc[1] + math.sin(rz) * r * 1.3, loc[2] + r * 0.55 * flat)
    tie.rotation_euler = (0, math.pi / 2, rz)
    return o

def barrel(loc, r=0.28, h=0.85, m="blue", axis='Z', rz=0.0):
    before = snapshot()
    cyl("Barrel", r, h, (0, 0, h / 2), m, verts=20)
    for z in (0.12, h / 2, h - 0.12):
        cyl("Hoop", r + 0.008, 0.035, (0, 0, z), "iron", verts=20)
    cyl("Lid", r * 0.92, 0.01, (0, 0, h + 0.004), "steel", verts=20)
    objs = objs_since(before)
    if axis == 'X':
        xform(objs, (0, 0, 0), ry=math.pi / 2); xform(objs, (-h / 2, 0, r))
    return xform(objs, loc, rz=rz)

def pallet(c, w=1.0, d=0.8, rz=0.0, m="wood_new"):
    before = snapshot()
    for k in range(5):
        board("PalletTop", (w, d / 5 - 0.03, 0.022), (0, -d / 2 + (k + 0.5) * d / 5, 0.133), m)
    for sx in (-1, 0, 1):
        board("PalletRunner", (0.09, d, 0.1), (sx * (w / 2 - 0.045), 0, 0.072), m)
    for sy in (-1, 1):
        board("PalletBase", (w, 0.1, 0.022), (0, sy * (d / 2 - 0.05), 0.011), m)
    return xform(objs_since(before), c, rz=rz)

def vboards(u0, u1, plane, c, z0, top, mats, w=0.19, gap=0.012, t=0.03, skip=None, rnd=None, lean=0.0):
    """Стена из вертикальных досок. plane 'XZ' — стена вдоль X на y=c, 'YZ' — вдоль Y на x=c.
    top(u) — верх доски, skip(u) — список вырезанных интервалов (za, zb)."""
    rnd = rnd or random
    n = max(1, int(round((u1 - u0) / (w + gap))))
    step = (u1 - u0) / n
    out = []
    for i in range(n):
        u = u0 + (i + 0.5) * step
        zt = top(u)
        pieces = [(z0, zt)]
        for za, zb in (skip(u) if skip else []):
            nxt = []
            for a, b in pieces:
                if zb <= a or za >= b: nxt.append((a, b)); continue
                if za > a: nxt.append((a, za))
                if zb < b: nxt.append((zb, b))
            pieces = nxt
        mats_i = mats(i, u) if callable(mats) else mats
        for a, b in pieces:
            if b - a < 0.05: continue
            mm = mats_i if isinstance(mats_i, str) else rnd.choice(mats_i)
            ww = step - gap * rnd.uniform(0.6, 1.4)
            if plane == 'XZ':
                out.append(board("Board", (ww, t, b - a), (u, c, (a + b) / 2), mm, rot=(0, rnd.uniform(-lean, lean), 0)))
            else:
                out.append(board("Board", (t, ww, b - a), (c, u, (a + b) / 2), mm, rot=(rnd.uniform(-lean, lean), 0, 0)))
    return out

def gable_top(eave, ridge, half):
    return lambda u: eave + (ridge - eave) * max(0.0, 1.0 - abs(u) / half)

# =====================================================================
#                 СОСТОЯНИЕ 1: РАЗРУШЕННЫЙ СКЛАД (стадия 0)
# =====================================================================
def sheet_between(name, p0, p1, w, m, side=(1, 0, 0), **kw):
    """Профлист от p0 до p1 (вдоль рёбер), ширина w; лицевая сторона — вверх/наружу."""
    p0 = Vector(p0); p1 = Vector(p1); ey = (p1 - p0).normalized()
    s = Vector(side); ex = (s - ey * s.dot(ey)).normalized()
    if ex.cross(ey).z < 0 and abs(ex.cross(ey).z) > 0.05: ex = -ex
    return corrugated(name, w, (p1 - p0).length, m, frame_m((p0 + p1) / 2, ex, ey), **kw)

def build_ruins():
    global PART; PART = "body"
    rnd = random.Random(11); random.seed(11)
    SL = 0.22
    # плита-фундамент, расколотая на три куска с зазорами и перекосом
    chunks = [
        ([(-2.4, -1.9), (0.3, -1.9), (-0.2, 0.1), (-2.4, 0.4)], (0.0, 0.012, 0.0), 0.0),
        ([(0.3, -1.9), (2.4, -1.9), (2.4, 0.6), (0.9, 0.2), (-0.2, 0.1)], (-0.025, -0.02, 0.0), 0.03),
        ([(-2.4, 0.4), (-0.2, 0.1), (0.9, 0.2), (2.4, 0.6), (2.4, 1.9), (-2.4, 1.9)], (0.01, 0.0, 0.0), 0.0),
    ]
    for pts, rot, lift in chunks:
        cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
        o = prism_xy("Slab", [((x - cx) * 0.985, (y - cy) * 0.985) for x, y in pts], 0.0, SL, "concrete", bevel=0.02)
        o.location = (cx, cy, lift); o.rotation_euler = rot
    cracks = [[(0.3, -1.9), (-0.2, 0.1), (0.9, 0.2), (2.4, 0.6)], [(-2.4, 0.4), (-0.2, 0.1)]]
    for line in cracks:
        for (ax, ay), (bx, by) in zip(line, line[1:]):
            for k in range(5):
                t = rnd.random()
                rock("Rubble", rnd.uniform(0.04, 0.09), (ax + (bx - ax) * t + rnd.uniform(-0.08, 0.08), ay + (by - ay) * t + rnd.uniform(-0.08, 0.08), SL + 0.03), "rubble", jitter=0.35, sub=1)
    for k in range(16):   # обломки вокруг плиты
        a = rnd.uniform(0, 2 * math.pi)
        x = max(-2.75, min(2.85, 2.55 * math.cos(a))); y = max(-2.15, min(2.1, 2.05 * math.sin(a)))
        rock("Rubble", rnd.uniform(0.05, 0.12), (x, y, 0.03), rnd.choice(["rubble", "concrete"]), jitter=0.35, sub=1, scale=(1, 1, 0.6))
    # остатки пола: лаги и обгоревшие доски в задней левой части
    for y in (0.75, 1.4):
        beam("Joist", (-2.3, y, SL + 0.05), (rnd.uniform(0.2, 0.7), y + rnd.uniform(-0.05, 0.05), SL + 0.05), 0.09, 0.1, "wood_dark")
    x = -2.2
    while x < 0.55:
        if rnd.random() > 0.3:
            ln = rnd.uniform(0.7, 1.35)
            board("FloorBoard", (0.18, ln, 0.03), (x, 1.8 - ln / 2, SL + 0.115), rnd.choice(["wood_dark", "wood_old"]),
                  rot=(rnd.uniform(-0.04, 0.12), 0, rnd.uniform(-0.05, 0.05)))
        x += 0.2
    # стойки: задняя левая уцелела, задняя правая сломана, передняя левая завалилась, передней правой — пенёк
    box("PostBL", (0.16, 0.16, 2.45), (-2.22, 1.72, SL + 1.225), "wood_dark", bevel=0.01)
    box("PostBR", (0.16, 0.16, 1.15), (2.22, 1.72, SL + 0.575), "wood_dark", bevel=0.01)
    for k in range(4):
        box("Splinter", (0.035, 0.05, rnd.uniform(0.12, 0.28)), (2.22 + rnd.uniform(-0.05, 0.05), 1.72 + rnd.uniform(-0.05, 0.05), SL + 1.2),
            "wood_dark", rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, 3)))
    beam("PostFL", (-2.22, -1.72, SL), (-1.7, -1.92, SL + 2.2), 0.16, 0.16, "wood_dark")
    box("PostFR", (0.16, 0.16, 0.42), (2.22, -1.72, SL + 0.21), "wood_dark", bevel=0.01)
    beam("PostFRTop", (2.55, -1.2, 0.08), (2.85, 0.6, 0.09), 0.16, 0.16, "wood_dark")
    # уцелевший кусок задней стены с рваным верхом и левой стены
    vboards(-2.3, 0.45, 'XZ', 1.84, SL, lambda u: SL + max(0.35, 2.3 - (u + 2.3) * 0.62 + rnd.uniform(-0.35, 0.25)),
            ["wood_dark", "wood_oldz", "wood_oldz"], rnd=rnd)
    beam("Girt", (-2.3, 1.9, 0.9), (-0.2, 1.9, 0.92), 0.06, 0.12, "wood_dark")
    beam("Girt", (-2.3, 1.9, 1.85), (-1.1, 1.9, 1.7), 0.06, 0.12, "wood_dark")
    vboards(0.55, 1.8, 'YZ', -2.32, SL, lambda u: SL + rnd.uniform(0.9, 2.1), ["wood_dark", "wood_oldz"], rnd=rnd)
    vboards(-1.8, -0.9, 'YZ', -2.32, SL, lambda u: SL + rnd.uniform(0.3, 0.8), ["wood_dark", "wood_oldz"], rnd=rnd)
    # рухнувшая балка конька и стропило
    beam("FallenRidge", (-2.2, 1.72, 2.6), (0.9, -0.6, 0.34), 0.16, 0.2, "wood_dark")
    beam("FallenRafter", (-0.4, 1.78, 1.15), (1.3, 0.85, 0.3), 0.07, 0.14, "wood_old")
    # обломок фермы на земле справа
    for p0, p1 in (((2.5, -0.7, 0.05), (2.62, 1.75, 0.05)), ((2.5, -0.7, 0.05), (2.95, 0.5, 0.05)), ((2.62, 1.75, 0.05), (2.95, 0.5, 0.05))):
        beam("TrussPiece", p0, p1, 0.08, 0.1, "wood_old")
    # листы кровли: на балке, смятый, прислонённый к стене
    sheet_between("RoofSheet", (-0.95, -0.95, SL + 0.03), (-0.8, 0.62, 1.53), 0.9, "rust_sheet",
                  holes=lambda u, v: (u - 0.7) ** 2 + (v - 0.8) ** 2 < 0.012)
    sheet_between("RoofSheet", (1.0, -1.65, SL + 0.06), (2.3, -0.95, SL + 0.06), 0.85, "old_sheet", rows=10,
                  disp=lambda u, v: 0.16 * math.sin(v * math.pi) ** 2 * (0.6 + 0.4 * math.sin(u * 7)) + 0.03 * math.sin(v * 23 + u * 9))
    sheet_between("RoofSheet", (-1.65, 1.25, SL + 0.03), (-1.5, 1.74, 1.95), 0.88, "rust_sheet", side=(1, 0, 0))
    # ящики: разбитый под рваным тентом, опрокинутый, рассыпанные мелкие
    crate((-1.5, -1.2, SL), 0.65, rz=0.3, m="wood_old", broken=0.25, seed=3)
    crate((0.15, -1.2, SL + 0.3), 0.6, rz=-0.4, m="wood_old", broken=0.5, tip=(0.0, math.pi / 2), seed=4)
    crate((1.2, -0.25, SL), 0.36, rz=0.7, m="wood_old", broken=0.2, seed=5)
    crate((2.0, 0.05, SL + 0.18), 0.36, rz=0.2, m="wood_old", tip=(math.pi / 2, 0.0), seed=6)
    # опрокинутый стеллаж
    before = snapshot()
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("ShelfPost", (0.05, 0.05, 1.7), (sx * 0.72, sy * 0.2, 0.85), "wood_old", bevel=0.005)
    for z in (0.3, 0.85, 1.4):
        board("Shelf", (1.45, 0.42, 0.025), (0, 0, z), rnd.choice(["wood_old", "wood_dark"]))
    xform(objs_since(before), (0, 0, 0), rx=math.pi / 2); xform(objs_since(before), (1.55, 1.78, SL + 0.225))
    barrel((0.2, 0.95, SL + 0.14), axis='X', rz=0.35, m="rust")
    # рваный тент на ящике
    cc = Vector((-1.5, -1.2)); ca, sa = math.cos(0.3), math.sin(0.3)
    def drape(u, v):
        lx = (u - 0.5) * 1.6; ly = (v - 0.5) * 1.4
        d = max(abs(lx), abs(ly)) - 0.34
        top = SL + 0.69
        z = top if d < 0 else max(SL + 0.02, top - 0.67 * min(1.0, (d / 0.32)) ** 0.8)
        z += 0.025 * math.sin(lx * 13 + ly * 5) + 0.015 * math.sin(ly * 17)
        return Vector((cc.x + lx * ca - ly * sa, cc.y + lx * sa + ly * ca, z))
    cloth("TornTarp", 22, 18, drape, "tarp_old",
          holes=lambda u, v: (u > 0.82 and v < 0.35) or (u - 0.25) ** 2 + (v - 0.8) ** 2 < 0.01 or (v > 0.93 and u < 0.4))
    # брошенные доски
    for k in range(7):
        board("LoosePlank", (rnd.uniform(0.9, 1.6), 0.16, 0.03), (rnd.uniform(-1.9, 1.6), rnd.uniform(-1.7, 0.2), SL + 0.02 + 0.03 * k % 0.09),
              rnd.choice(["wood_old", "wood_dark"]), rot=(0, rnd.uniform(-0.06, 0.06), rnd.uniform(0, math.pi)))
    # табличка «СКЛАД», упавшая у пенька
    th = -0.32; rz = 0.15
    R = Matrix.Rotation(rz, 3, 'Z') @ Matrix.Rotation(th, 3, 'X')
    c = Vector((1.75, -2.04, 0.17))
    box("Sign", (0.95, 0.03, 0.28), c, "white", rot=(th, 0, rz), bevel=0.004)
    text("СКЛАД", c + R @ Vector((0, -0.018, 0)), 0.19, rot=(math.pi / 2 + th, 0, rz))

# =====================================================================
#          СОСТОЯНИЕ 2: ВОССТАНОВЛЕННЫЙ АМБАР (стадии 1 и 2)
# =====================================================================
def roof_sheets(R, half_run, y0, y1, n, mats, rnd, lift=0.0, period=0.076, amp=0.014, skylight=None):
    """Двускатная кровля из профлиста: конёк вдоль Y на x = 0, R(x) — верх обрешётки."""
    tan = (R(0) - R(1.0))
    alpha = math.atan(tan)
    L = half_run / math.cos(alpha) + 0.04
    step = (y1 - y0 - 0.86) / (n - 1)
    out = []
    for s in (-1, 1):
        for k in range(n):
            yc = y0 + 0.43 + k * step
            xc = s * (half_run / 2 - 0.02)
            z = R(abs(xc)) + 0.03 + lift + (0.008 if k % 2 else 0.0)
            ey = Vector((s * math.cos(alpha), 0, -math.sin(alpha)))
            m = "glass" if skylight and (s, k) in skylight else (mats if isinstance(mats, str) else rnd.choice(mats))
            out.append(corrugated("RoofSheet", 0.86, L, m, frame_m(Vector((xc, yc, z)), (0, -s, 0), ey), period=period, amp=amp))
    return out

def gate_leaf(hinge, length, h, z0, rz, mats, rnd, sign=1):
    """Створка ворот из досок с Z-образной обвязкой; петля — в hinge, створка уходит по ±X (sign)."""
    before = snapshot()
    n = 5; w = length / n
    for i in range(n):
        board("GateBoard", (w - 0.012, 0.03, h), (sign * (i + 0.5) * w, 0, z0 + h / 2), rnd.choice(mats))
    for z in (z0 + 0.3, z0 + h - 0.3):
        board("GateRail", (length - 0.04, 0.03, 0.12), (sign * length / 2, -0.03, z), "wood_new")
        box("HingeStrap", (0.55, 0.008, 0.045), (sign * 0.3, -0.05, z), "iron", bevel=0.002)
        cyl("Pintle", 0.018, 0.12, (0, -0.02, z), "iron", verts=8)
    beam("GateBrace", (sign * 0.12, -0.03, z0 + 0.38), (sign * (length - 0.12), -0.03, z0 + h - 0.38), 0.03, 0.11, "wood_new")
    cyl("Handle", 0.03, 0.015, (sign * (length - 0.12), -0.055, z0 + h * 0.48), "iron", axis='Y', verts=10)
    return xform(objs_since(before), hinge, rz=rz)

def build_barn():
    global PART
    rnd = random.Random(22); random.seed(22)
    HX, HY, FL, EAVE, RID, OV = 2.15, 1.65, 0.4, 2.6, 3.5, 0.28
    tan = (RID - EAVE) / HX
    R = lambda x: EAVE + 0.16 + (HX - abs(x)) * tan          # верх стропил
    ys = [-1.8 + k * 0.6 for k in range(7)]
    # ---------------- каркас (стадии 1 и 2) ----------------
    PART = "frame"
    for x in (-HX, HX):
        for y in (-HY, 0.0, HY):
            box("Footing", (0.36, 0.36, 0.22), (x, y, 0.11), "stone", bevel=0.03)
        box("Sill", (0.18, 3.6, 0.16), (x, 0, 0.30), "wood_old", bevel=0.008)
    for y in (-1.75, 1.75):
        box("RimJoist", (4.3, 0.08, 0.16), (0, y, 0.30), "wood_old", bevel=0.006)
    for y in (-1.1, -0.4, 0.4, 1.1):
        box("Joist", (4.3, 0.08, 0.14), (0, y, 0.30), "wood_old")
    x = -2.25
    for i in range(22):
        board("FloorBoard", (0.192, 3.56, 0.035), (-2.25 + 0.0975 + i * 0.205, 0, FL - 0.0175), rnd.choice(["wood_old", "wood_old", "wood_new"]))
    for x in (-HX, HX):
        for y in (-HY, 0.0, HY):
            box("Post", (0.16, 0.16, EAVE - 0.16 - FL), (x, y, (FL + EAVE - 0.16) / 2), "wood_oldz", bevel=0.01)
        box("TopPlate", (0.18, 3.7, 0.16), (x, 0, EAVE - 0.08), "wood_old", bevel=0.008)
        for y0, y1 in ((-HY, -HY + 0.55), (0.0, -0.55), (0.0, 0.55), (HY, HY - 0.55)):
            beam("KneeBrace", (x, y0, EAVE - 0.7), (x, y1, EAVE - 0.16), 0.08, 0.1, "wood_old")
    for y in (-HY, 0.0, HY):
        box("TieBeam", (4.62, 0.12, 0.16), (0, y, EAVE + 0.08), "wood_old", bevel=0.008)
    for y in ys:
        for s in (-1, 1):
            beam("Rafter", (s * (HX + OV), y, R(HX + OV) - 0.07), (0, y, R(0) - 0.07), 0.06, 0.14, "wood_old")
    for y in (-HY, HY):
        box("KingPost", (0.12, 0.12, R(0) - 0.14 - EAVE - 0.16), (0, y, (R(0) - 0.14 + EAVE + 0.16) / 2), "wood_oldz", bevel=0.006)
    box("Ridge", (0.08, 3.9, 0.18), (0, 0, R(0) - 0.16), "wood_old", bevel=0.006)
    for s in (-1, 1):
        nrm = Vector((s * math.sin(math.atan(tan)), 0, math.cos(math.atan(tan))))
        for xp in (0.75, 1.55, 2.3):
            beam("Purlin", (s * xp, -2.0, R(xp) + 0.03), (s * xp, 2.0, R(xp) + 0.03), 0.08, 0.06, "wood_new", up=nrm)
    box("Step", (1.8, 0.3, 0.2), (0, -1.95, 0.1), "wood_old", bevel=0.01)
    # припасы внутри
    crate((-1.35, 1.15, FL), 0.6, rz=0.05, m="wood_new", seed=21)
    crate((-1.35, 1.15, FL + 0.64), 0.52, rz=0.25, m="wood_new", seed=22)
    crate((-0.62, 1.25, FL), 0.55, rz=-0.1, m="wood_old", seed=23)
    crate((-1.6, 0.4, FL), 0.45, rz=0.4, m="wood_new", seed=24)
    for p, r, a in (((1.15, 1.25, FL), 0.25, 0.2), ((1.6, 0.95, FL), 0.24, 1.3), ((1.35, 1.1, FL + 0.17), 0.23, 0.7), ((0.75, 1.3, FL), 0.22, -0.3)):
        sack(p, r, a)
    barrel((1.6, -0.9, FL), m="blue")
    # ---------------- стены, ворота, кровля (стадия 2) ----------------
    PART = "shell"
    win = lambda u: [(1.35, 2.05)] if abs(u) < 0.36 else []
    for s in (-1, 1):
        vboards(-1.79, 1.79, 'YZ', s * 2.255, 0.24, lambda u: EAVE, lambda i, u: ["wood_oldz"] * 3 + ["wood_newz"], skip=win, rnd=rnd)
        xw = s * 2.28
        board("WinSill", (0.08, 0.86, 0.05), (xw, 0, 1.33), "wood_new")
        board("WinHead", (0.07, 0.84, 0.06), (xw, 0, 2.08), "wood_new")
        for y in (-0.39, 0.39):
            board("WinJamb", (0.07, 0.06, 0.74), (xw, y, 1.7), "wood_new")
        box("WinGlass", (0.012, 0.72, 0.7), (s * 2.25, 0, 1.7), "glass")
        board("WinMullion", (0.05, 0.04, 0.7), (xw, 0, 1.7), "wood_new")
        board("WinTransom", (0.05, 0.72, 0.04), (xw, 0, 1.7), "wood_new")
    roofline = lambda u: R(abs(u)) - 0.17 if abs(u) < HX + 0.1 else EAVE
    vboards(-2.27, 2.27, 'XZ', 1.825, 0.24, roofline, ["wood_oldz", "wood_oldz", "wood_oldz", "wood_newz"], rnd=rnd)
    vboards(-2.27, 2.27, 'XZ', -1.825, 0.24, roofline, ["wood_oldz", "wood_oldz", "wood_newz"], rnd=rnd,
            skip=lambda u: [(0.0, 2.44)] if abs(u) < 1.03 else [])
    box("GateHeader", (2.2, 0.08, 0.16), (0, -1.86, 2.5), "wood_new", bevel=0.008)
    gate_leaf((-1.0, -1.87, 0), 1.0, 1.98, FL + 0.02, -0.36, ["wood_oldz", "wood_newz"], rnd, sign=1)
    gate_leaf((1.0, -1.87, 0), 1.0, 1.98, FL + 0.02, 0.0, ["wood_oldz", "wood_newz"], rnd, sign=-1)
    box("Sign", (1.15, 0.03, 0.3), (0, -1.86, 2.86), "white", bevel=0.004)
    text("СКЛАД", (0, -1.877, 2.86), 0.21)
    for y in (-2.04, 2.04):
        for s in (-1, 1):
            beam("Barge", (s * (HX + OV + 0.04), y, R(HX + OV) + 0.02), (0, y, R(0) + 0.06), 0.03, 0.2, "wood_new")
    roof_sheets(R, HX + OV + 0.06, -2.06, 2.06, 5, ["old_sheet", "old_sheet", "old_sheet", "rust_sheet"], rnd, lift=0.03)
    al = math.atan(tan)
    for s in (-1, 1):
        box("RidgeCap", (0.26, 4.18, 0.008), (s * 0.12, 0, R(0.12) + 0.1), "old_sheet", rot=(0, s * al, 0))
    barrel((2.6, -1.25, 0), r=0.3, h=0.8, m="wood_newz")
    # ---------------- тент на стропилах (стадия 1) ----------------
    PART = "tarp"
    supports = [0.0, 0.75, 1.55, 2.3]
    def tarp_z(ax):
        if ax > HX + OV:
            return R(HX + OV) + 0.05 - (ax - HX - OV) * 2.2
        for a, b in zip(supports, supports[1:] + [HX + OV]):
            if a <= ax <= b:
                return R(ax) + 0.07 - 0.06 * math.sin(math.pi * (ax - a) / (b - a))
        return R(ax) + 0.07
    for s in (-1, 1):
        def fn(u, v, s=s):
            ax = -0.04 + v * (HX + OV + 0.22)
            y = -2.0 + 4.0 * u
            return Vector((s * ax, y, tarp_z(ax) + 0.012 * math.sin(y * 9 + ax * 4)))
        cloth("Tarp", 26, 16, fn, "tarp", thick=0.008)
        for y in (-1.98, 1.98):
            top = Vector((s * (HX + OV + 0.2), y, tarp_z(HX + OV + 0.2)))
            stake = Vector((s * 2.82, y * 1.07, 0.12))
            tube("TarpRope", [top.lerp(stake, t) - Vector((0, 0, 0.06 * math.sin(math.pi * t))) for t in (0, 0.25, 0.5, 0.75, 1.0)], 0.009, "rope", sides=5)
            beam("Stake", stake + Vector((0, 0, -0.12)), stake + Vector((s * 0.06, 0, 0.2)), 0.04, 0.04, "wood_new", bevel=0.004)

# =====================================================================
#          СОСТОЯНИЕ 3: ЛОГИСТИЧЕСКИЙ КОМПЛЕКС (стадия 3)
# =====================================================================
C_HX, C_HY = 2.3, 1.85
GEAR = Vector((3.45, -1.73, 1.4))     # большая шестерня подъёмника (ось Y)
CRANK = Vector((3.45, -1.75, 1.17))   # шестерня-рукоятка (r 0.06), передаточное число 2.83
CHAIN = Vector((2.95, -1.6, 2.45))    # верх цепи — под тележкой укосины
HOOK = Vector((2.95, -1.6, 1.0))      # крюк в нижнем положении (ящик стоит на поддоне)
R_GEAR, R_PINION = 0.17, 0.06

def gear_xz(name, center, r_root, r_tip, n, y0, y1, m):
    pts = []
    for i in range(n):
        a0 = 2 * math.pi * i / n
        for da, r in ((0.0, r_root), (0.18, r_tip), (0.5, r_tip), (0.68, r_root)):
            a = a0 + da * 2 * math.pi / n
            pts.append((center.x + r * math.cos(a), center.z + r * math.sin(a)))
    o = prism_xz(name, pts, center.y + y0, center.y + y1, m, bevel=0.003)
    return o

def siding(plane, c, u0, u1, z0, z1, skip=None, span=None, out=1, step=0.13):
    """Обшивка внахлёст: горизонтальные доски, нижний край чуть отставлен от стены."""
    z = z0
    while z < z1 - 0.03:
        h = min(0.15, z1 - z + 0.02)
        a, b = (u0, u1) if span is None else span(z + h / 2)
        if b - a > 0.08:
            segs = [(a, b)]
            for sa, sb in (skip(z + h / 2) if skip else []):
                nxt = []
                for p, q in segs:
                    if sb <= p or sa >= q: nxt.append((p, q)); continue
                    if sa > p: nxt.append((p, sa))
                    if sb < q: nxt.append((sb, q))
                segs = nxt
            for p, q in segs:
                if q - p < 0.06: continue
                if plane == 'XZ':
                    board("Siding", (q - p, 0.022, h), ((p + q) / 2, c, z + h / 2), "siding", rot=(out * 0.07, 0, 0))
                else:
                    board("Siding", (0.022, q - p, h), (c, (p + q) / 2, z + h / 2), "siding", rot=(0, -out * 0.07, 0))
        z += step

def build_complex():
    global PART; PART = "body"
    rnd = random.Random(33); random.seed(33)
    HX, HY = C_HX, C_HY
    FL, BT, EAVE, RID, OV = 0.42, 1.45, 2.95, 4.0, 0.3
    tan = (RID - EAVE) / HX
    R = lambda x: EAVE + 0.1 + (HX - abs(x)) * tan          # верх обрешётки кровли
    OW = 1.1                                                 # полуширина проёма ворот
    TOPO = 2.75                                              # верх проёма
    # фундамент, ступени
    box("Plinth", (4.8, 3.9, FL - 0.05), (0, 0, (FL - 0.05) / 2), "stone", bevel=0.02)
    box("PlinthCap", (4.86, 3.96, 0.06), (0, 0, FL - 0.03), "concrete", bevel=0.01)
    box("Step1", (2.6, 0.16, 0.28), (0, -2.03, 0.14), "concrete", bevel=0.012)
    box("Step2", (2.6, 0.12, 0.14), (0, -2.17, 0.07), "concrete", bevel=0.012)
    # кирпичный цоколь стен, пилястры, подоконный пояс
    hb = BT - FL
    box("BrickBack", (4.6, 0.25, hb), (0, HY - 0.125, FL + hb / 2), "brick")
    for s in (-1, 1):
        box("BrickSide", (0.25, 2 * HY - 0.5, hb), (s * (HX - 0.125), 0, FL + hb / 2), "brick")
        box("BrickFront", (HX - OW, 0.25, hb), (s * (OW + HX) / 2, -HY + 0.125, FL + hb / 2), "brick")
        for sy in (-1, 1):
            box("Pilaster", (0.38, 0.38, EAVE - FL), (s * (HX - 0.16), sy * (HY - 0.16), (FL + EAVE) / 2), "brick")
        box("Jamb", (0.3, 0.38, TOPO + 0.05 - FL), (s * (OW + 0.15), -HY + 0.16, (FL + TOPO + 0.05) / 2), "brick")
    for nm, size, loc in (("Belt", (4.66, 0.3, 0.06), (0, HY - 0.13, BT + 0.03)), ("Belt", (4.66, 0.3, 0.06), (0, -HY + 0.13, BT + 0.03)),
                          ("Belt", (0.3, 3.76, 0.06), (-HX + 0.13, 0, BT + 0.03)), ("Belt", (0.3, 3.76, 0.06), (HX - 0.13, 0, BT + 0.03))):
        if nm == "Belt" and loc[1] < -1 and True:
            for s in (-1, 1):
                box("Belt", ((HX - OW + 0.06), 0.3, 0.06), (s * (OW + HX) / 2, loc[1], loc[2]), "concrete", bevel=0.008)
            continue
        box(nm, size, loc, "concrete", bevel=0.008)
    # верх стен: несущая коробка (штукатурка внутри) + обшивка внахлёст снаружи
    up0 = BT + 0.06; hu = EAVE - up0
    box("WallBack", (4.5, 0.14, hu), (0, HY - 0.1, up0 + hu / 2), "plaster")
    for s in (-1, 1):
        box("WallSide", (0.14, 2 * HY - 0.3, hu), (s * (HX - 0.1), 0, up0 + hu / 2), "plaster")
        box("WallFront", (HX - OW - 0.25, 0.14, hu), (s * (OW + 0.3 + HX) / 2 - s * 0.02, -HY + 0.1, up0 + hu / 2), "plaster")
    box("WallOverGate", (2 * OW + 0.6, 0.14, EAVE - TOPO), (0, -HY + 0.1, (EAVE + TOPO) / 2), "plaster")
    for y in (-HY + 0.1, HY - 0.1):
        prism_xz("Gable", [(-HX + 0.03, EAVE), (HX - 0.03, EAVE), (0, R(0) - 0.12)], y - 0.07, y + 0.07, "plaster")
    span_g = lambda z: (-(R(0) - 0.13 - z) / tan, (R(0) - 0.13 - z) / tan) if z > EAVE else (-HX + 0.34, HX - 0.34)
    gate_skip = lambda z: [(-OW - 0.3, OW + 0.3)] if z < TOPO + 0.08 else []
    siding('XZ', -HY + 0.02, 0, 0, up0, R(0) - 0.2, skip=gate_skip, span=span_g, out=1)
    siding('XZ', HY - 0.02, 0, 0, up0, R(0) - 0.2, span=span_g, out=-1)
    for s in (-1, 1):
        siding('YZ', s * (HX - 0.02), -HY + 0.34, HY - 0.34, up0, EAVE, out=s)
    # окна на боковых стенах
    for s in (-1, 1):
        x = s * (HX + 0.0)
        box("Window", (0.05, 0.8, 0.62), (x, 0.2, 2.15), "trim", bevel=0.005)
        box("WinGlass", (0.03, 0.66, 0.48), (x, 0.2, 2.15), "glass")
        box("WinBar", (0.065, 0.04, 0.48), (x, 0.2, 2.15), "trim")
        box("WinSill", (0.12, 0.9, 0.05), (x + s * 0.03, 0.2, 1.82), "concrete", bevel=0.006)
    # кровля, конёк, вентиляция, водостоки
    al = math.atan(tan)
    roof_sheets(R, HX + OV, -2.08, 2.08, 5, "galv", rnd, period=0.09, amp=0.016, skylight={(-1, 1), (1, 3)})
    for s in (-1, 1):
        box("RidgeCap", (0.28, 4.2, 0.008), (s * 0.13, 0, R(0.13) + 0.06), "galv", rot=(0, s * al, 0))
        for y in (-2.07, 2.07):
            beam("Barge", (s * (HX + OV + 0.02), y, R(HX + OV) - 0.02), (0, y, R(0) + 0.03), 0.035, 0.18, "trim")
        ze = R(HX + OV) - 0.06
        cyl("Gutter", 0.065, 4.2, (s * (HX + OV + 0.03), 0, ze), "galv", axis='Y', verts=14)
        tube("Downpipe", [(s * (HX + OV + 0.03), -1.6, ze - 0.05), (s * (HX + OV + 0.03), -1.6, ze - 0.2), (s * (HX + 0.08), -1.62, ze - 0.45),
                          (s * (HX + 0.08), -1.62, 0.25), (s * (HX + 0.16), -1.62, 0.1)], 0.045, "galv", sides=10)
    cyl("RoofVent", 0.13, 0.22, (0, 0.8, R(0) + 0.14), "galv", verts=16)
    cyl("RoofVentCap", 0.19, 0.1, (0, 0.8, R(0) + 0.3), "galv", verts=16, r2=0.02)
    # рулонные ворота: направляющие, короб, полотно поднято на две трети
    for s in (-1, 1):
        box("GateRail", (0.06, 0.09, TOPO - FL), (s * (OW - 0.03), -HY + 0.05, (FL + TOPO) / 2), "steel", bevel=0.004)
    box("ShutterBox", (2 * OW + 0.3, 0.3, 0.3), (0, -HY - 0.12, TOPO + 0.15), "green", bevel=0.01)
    corrugated("Shutter", 0.62, 2 * OW - 0.06, "green", frame_m(Vector((0, -HY + 0.05, TOPO - 0.31)), (0, 0, -1), (1, 0, 0)), period=0.1, amp=0.012)
    box("ShutterBar", (2 * OW - 0.06, 0.06, 0.05), (0, -HY + 0.05, TOPO - 0.63), "iron", bevel=0.004)
    cyl("ShutterHandle", 0.015, 0.22, (0, -HY + 0.0, TOPO - 0.66), "steel", axis='X', verts=8)
    # фонари и вывеска
    for s in (-1, 1):
        p0 = Vector((s * 1.65, -HY - 0.02, 2.55))
        tube("LampArm", [p0, p0 + Vector((0, -0.12, 0.12)), p0 + Vector((0, -0.28, 0.14))], 0.016, "iron", sides=6)
        cyl("LampShade", 0.13, 0.1, p0 + Vector((0, -0.3, 0.08)), "green", verts=16, r2=0.035)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, segments=10, ring_count=6, location=p0 + Vector((0, -0.3, 0.02)))
        finish(bpy.context.object, "lampglass", smooth=True)
    box("Sign", (1.55, 0.03, 0.34), (0, -HY - 0.03, 3.42), "trim", bevel=0.005)
    text("СКЛАД №1", (0, -HY - 0.047, 3.42), 0.2)
    PART = "yard"   # интерьер, сортировочный навес и кран — отдельный меш (меньше 1 МиБ на файл)
    # внутри: стеллаж вдоль задней стены (виден в проём ворот), поддоны с грузом
    for x in (-1.75, -0.58, 0.58, 1.75):
        for y in (1.05, 1.55):
            box("RackPost", (0.06, 0.06, 2.2), (x, y, FL + 1.1), "blue", bevel=0.004)
    for z in (0.55, 1.3, 2.05):
        for y in (1.05, 1.55):
            box("RackBeam", (3.56, 0.05, 0.09), (0, y, FL + z), "orange", bevel=0.004)
        board("RackDeck", (3.5, 0.5, 0.02), (0, 1.3, FL + z + 0.055), "wood_new")
    for k, x in enumerate((-1.25, 0.0, 1.2)):
        crate((x, 1.3, FL + 0.6), 0.45, rz=rnd.uniform(-0.15, 0.15), m="wood_new", seed=40 + k)
        sack((x + 0.15, 1.3, FL + 1.35), 0.2, rnd.uniform(-0.3, 0.3))
        crate((x - 0.1, 1.3, FL + 2.1), 0.36, rz=rnd.uniform(-0.2, 0.2), m="wood_old", seed=50 + k)
    pallet((-0.55, 0.1, FL), 1.0, 0.8, rz=0.08)
    crate((-0.75, 0.1, FL + 0.145), 0.5, rz=0.1, m="wood_new", seed=60)
    crate((-0.25, 0.05, FL + 0.145), 0.42, rz=-0.2, m="wood_new", seed=61)
    for p, r, a in (((0.75, -0.3, FL), 0.24, 0.3), ((1.05, 0.1, FL), 0.23, 1.2), ((0.85, -0.05, FL + 0.16), 0.22, 0.7)):
        sack(p, r, a)
    # сортировочный навес справа
    box("SortPad", (1.45, 2.8, 0.1), (3.0, 0.32, 0.05), "concrete", bevel=0.01)
    for y in (-0.95, 1.62):
        box("SortPost", (0.12, 0.12, 2.2), (3.62, y, 1.1), "wood_newz", bevel=0.008)
    box("SortBeam", (0.12, 2.75, 0.16), (3.62, 0.33, 2.28), "wood_new", bevel=0.008)
    sl = Vector((1.5, 0, -0.5)).normalized()
    for y in (-0.95, 0.33, 1.62):
        beam("SortRafter", (HX, y, 2.88), (3.78, y, 2.36), 0.06, 0.12, "wood_new")
    beam("SortFascia", (HX, -1.02, 2.8), (3.78, -1.02, 2.3), 0.04, 0.12, "trim")
    for k in range(3):
        yc = -0.62 + k * 0.92
        corrugated("SortRoof", 0.94, 1.65, "galv", frame_m(Vector((3.08, yc, 2.70 + (0.006 if k % 2 else 0))), (0, -1, 0), sl), period=0.09, amp=0.014)
    box("SortSign", (1.05, 0.025, 0.2), (3.0, -1.06, 2.36), "white", bevel=0.003)
    text("СОРТИРОВКА", (3.0, -1.075, 2.36), 0.1)
    for k, (y, paint) in enumerate(((-0.5, "yellow"), (0.35, "blue"), (1.2, "green"))):
        crate((3.0, y, 0.1), 0.7, rz=0.0, m="wood_new", lid=False, seed=70 + k)
        box("BinPlate", (0.02, 0.5, 0.22), (3.385, y, 0.55), paint, bevel=0.003)
        if k == 0:
            box("BinPlate", (0.5, 0.02, 0.22), (3.0, y - 0.385, 0.55), paint, bevel=0.003)
        if k == 0:   # камень
            for i in range(9):
                rock("BinStone", rnd.uniform(0.08, 0.13), (3.0 + rnd.uniform(-0.2, 0.2), y + rnd.uniform(-0.2, 0.2), 0.62 + rnd.uniform(0, 0.08)), "rubble", jitter=0.3, sub=1)
        elif k == 1:   # металлолом
            for i in range(7):
                box("Scrap", (rnd.uniform(0.3, 0.55), 0.05, 0.05), (3.0 + rnd.uniform(-0.1, 0.1), y + rnd.uniform(-0.18, 0.18), 0.6 + i * 0.02), rnd.choice(["rust", "steel"]),
                    rot=(0, rnd.uniform(-0.2, 0.2), rnd.uniform(0, 3)))
        else:   # дрова
            for i in range(6):
                cyl("Log", rnd.uniform(0.05, 0.07), 0.6, (3.0, y - 0.2 + (i % 3) * 0.18, 0.62 + (i // 3) * 0.1), "logs", axis='X', verts=10)
    # поворотная укосина-кран с ручной лебёдкой на шестернях
    box("CraneBase", (0.5, 0.5, 0.12), (3.45, -1.6, 0.06), "concrete", bevel=0.01)
    box("CranePost", (0.16, 0.16, 2.8), (3.45, -1.6, 1.52), "yellow", bevel=0.008)
    box("CraneCap", (0.22, 0.22, 0.03), (3.45, -1.6, 2.935), "steel")
    for z, hgt in ((2.75, 0.02), (2.59, 0.02)):
        box("JibFlange", (1.15, 0.1, hgt), (2.95, -1.6, z), "yellow", bevel=0.003)
    box("JibWeb", (1.15, 0.025, 0.14), (2.95, -1.6, 2.67), "yellow", bevel=0.002)
    beam("JibBrace", (3.42, -1.6, 2.1), (2.95, -1.6, 2.58), 0.05, 0.05, "yellow")
    box("JibStop", (0.03, 0.12, 0.08), (2.4, -1.6, 2.53), "iron")
    box("Trolley", (0.18, 0.14, 0.06), (CHAIN.x, -1.6, 2.555), "iron", bevel=0.005)
    for dy in (-0.06, 0.06):
        for dx in (-0.06, 0.06):
            cyl("TrolleyWheel", 0.025, 0.02, (CHAIN.x + dx, -1.6 + dy, 2.61), "steel", axis='Y', verts=10)
    cyl("Sheave", 0.05, 0.03, (CHAIN.x, -1.6, CHAIN.z + 0.05), "iron", axis='Y', verts=14)
    box("SheaveCheek", (0.12, 0.05, 0.1), (CHAIN.x, -1.6, CHAIN.z + 0.06), "iron", bevel=0.004)
    box("WinchPlate", (0.34, 0.02, 0.56), (3.45, -1.69, 1.3), "iron", bevel=0.004)
    for dx, dz in ((-0.13, 0.04), (0.13, 0.04), (-0.13, 0.54), (0.13, 0.54)):
        bolt((3.45 + dx, -1.7, 1.3 - 0.25 + dz - 0.02), axis='-Y', r=0.012, h=0.01)
    tube("Cable", [(3.45, -1.66, 1.48), (3.45, -1.66, 2.5), (3.38, -1.6, 2.56), (CHAIN.x + 0.07, -1.6, 2.56), (CHAIN.x + 0.03, -1.6, CHAIN.z + 0.1)], 0.007, "steel", sides=5)
    pallet((CHAIN.x, -1.6, 0), 0.8, 0.7)
    # подвижные части лебёдки
    PART = "gear"
    gear_xz("Gear", GEAR, R_GEAR - 0.016, R_GEAR + 0.006, 26, -0.015, 0.015, "iron")
    cyl("GearHub", 0.04, 0.07, GEAR + Vector((0, 0.0, 0)), "steel", axis='Y', verts=12)
    cyl("Drum", 0.06, 0.05, GEAR + Vector((0, 0.04, 0)), "steel", axis='Y', verts=14)
    for i in range(5):
        a = 2 * math.pi * i / 5
        cyl("GearHole", 0.028, 0.034, GEAR + Vector((0.095 * math.cos(a), -0.001, 0.095 * math.sin(a))), "dark", axis='Y', verts=10)
    PART = "crank"
    gear_xz("Pinion", CRANK, R_PINION - 0.014, R_PINION + 0.008, 9, -0.016, 0.016, "steel")
    cyl("CrankHub", 0.025, 0.05, CRANK + Vector((0, -0.03, 0)), "steel", axis='Y', verts=10)
    box("CrankArm", (0.2, 0.02, 0.04), CRANK + Vector((0.09, -0.06, 0)), "iron", bevel=0.004)
    cyl("CrankHandle", 0.018, 0.13, CRANK + Vector((0.18, -0.13, 0)), "wood_new", axis='Y', verts=10)
    PART = "chain"
    L = CHAIN.z - HOOK.z
    n = int(L / 0.045)
    for i in range(n):
        z = CHAIN.z - (i + 0.5) * L / n
        bpy.ops.mesh.primitive_torus_add(major_radius=0.02, minor_radius=0.006, major_segments=8, minor_segments=4,
                                         location=(CHAIN.x, CHAIN.y, z), rotation=(math.pi / 2, 0, (math.pi / 2) * (i % 2)))
        o = bpy.context.object; o.name = "ChainLink"; o.scale = (1, 1.5, 1)
        finish(o, "steel", smooth=True)
    PART = "hook"
    box("HookBlock", (0.07, 0.05, 0.1), HOOK + Vector((0, 0, -0.05)), "yellow", bevel=0.008)
    hk = [HOOK + Vector((0, 0, -0.09)), HOOK + Vector((0, 0, -0.16))]
    hk += [HOOK + Vector((0.04 + 0.04 * math.cos(a), 0, -0.16 + 0.04 * math.sin(a))) for a in [math.pi + k * 0.45 for k in range(1, 8)]]
    tube("Hook", hk, 0.011, "steel", sides=6)
    crate(HOOK + Vector((0, 0, -0.855)), 0.5, rz=0.0, m="wood_new", seed=80)
    top = HOOK.z - 0.855 + 0.53
    for sx in (-1, 1):
        for sy in (-1, 1):
            tube("Sling", [HOOK + Vector((0, 0, -0.17)), Vector((HOOK.x + sx * 0.22, HOOK.y + sy * 0.22, top))], 0.008, "rope", sides=4)

# =====================================================================
#                        СБОРКА, СЦЕНА, РЕНДЕР
# =====================================================================
BUILDERS = {"ruins": build_ruins, "barn": build_barn, "complex": build_complex}
PARTS = {
    "ruins": {"body": "StorageRuins"},
    "barn": {"frame": "StorageBarnFrame", "shell": "StorageBarnShell", "tarp": "StorageBarnTarp"},
    "complex": {"body": "StorageComplex", "yard": "StorageComplexYard", "gear": "StorageGear", "crank": "StorageCrank", "chain": "StorageChain", "hook": "StorageHook"},
}
PIVOTS = {"complex": {"gear": GEAR, "crank": CRANK, "chain": CHAIN, "hook": HOOK}}
OFFS = {"ruins": -6.6, "barn": 0.0, "complex": 6.9}
states = list(BUILDERS) if STATE == "all" else [STATE]
for st in states:
    before = snapshot()
    BUILDERS[st]()
    objs = objs_since(before)
    for o in objs: o["state"] = st
    if STATE == "all": xform(objs, (OFFS[st], 0, 0))

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0)); g = bpy.context.object; g.name = "Ground"
finish(g, "ground", c=col_env)
for st in states:
    bpy.ops.mesh.primitive_circle_add(radius=3.3, fill_type='NGON', location=(OFFS[st] if STATE == "all" else 0, 0, 0.003), vertices=48)
    dd = bpy.context.object; dd.name = "TroddenDirt"; dd.scale = (1.15, 0.95, 1); finish(dd, "dirt", c=col_env)
bpy.ops.object.light_add(type='SUN', rotation=(math.radians(48), math.radians(8), math.radians(-38)))
sun = bpy.context.object; sun.data.energy = 3.6; sun.data.angle = math.radians(3); link(sun, col_env)
w = bpy.data.worlds.new("Sky"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.55, 0.65, 0.78, 1); bg.inputs["Strength"].default_value = 0.9

def camera(name, loc, target, lens=40):
    bpy.ops.object.camera_add(location=loc); c = bpy.context.object; c.name = name; c.data.lens = lens
    c.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    link(c, col_env); return c

if STATE == "all":
    cams = {"all": camera("CamAll", (0.2, -15.5, 10.5), (0.2, 0, 1.2), 30),
            "all_game": camera("CamAllGame", (0.2, -12.0, 13.0), (0.2, 0, 0.8), 28)}
else:
    cams = {
        "front34": camera("CamFront34", (-6.2, -8.0, 4.6), (0.3, 0, 1.5), 35),
        "back34": camera("CamBack34", (6.8, 7.0, 4.8), (0, 0, 1.4), 35),
        "game": camera("CamGameIso", (0.0, -8.6, 9.9), (0.4, 0, 1.2), 38),
    }
sc.camera = next(iter(cams.values()))

tris = 0
dg = bpy.context.evaluated_depsgraph_get()
for o in col_main.objects:
    if o.type == 'MESH':
        e = o.evaluated_get(dg); me = e.to_mesh(); me.calc_loop_triangles(); tris += len(me.loop_triangles); e.to_mesh_clear()
print("STATE", STATE, "OBJECTS", len(col_main.objects), "TRIS", tris)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_ROOT, f"storage_{STATE}.blend"))

def set_visible(fn):
    for o in col_main.objects:
        o.hide_render = not fn(o)

if "--render" in sys.argv:
    r = sc.render; r.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    i = sys.argv.index("--render")
    sc.cycles.samples = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit() else 32
    sc.cycles.use_denoising = True
    r.resolution_x, r.resolution_y = (1600, 900) if STATE == "all" else (1280, 960)
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
    only = os.environ.get("STORAGE_CAMS", ",".join(cams)).split(",")
    variants = {"barn": {"s2": lambda o: o.get("part") != "tarp", "s1": lambda o: o.get("part") != "shell"}}.get(STATE, {"": lambda o: True})
    if STATE == "all": variants = {"": lambda o: o.get("part") != "tarp"}
    for vk, vf in variants.items():
        set_visible(vf)
        for k, c in cams.items():
            if k not in only: continue
            sc.camera = c; r.filepath = os.path.join(OUT_ROOT, f"render_{STATE}{'_' + vk if vk else ''}_{k}.png")
            bpy.ops.render.render(write_still=True); print("RENDERED", STATE, vk, k, flush=True)
    set_visible(lambda o: True)

# =====================================================================
# Запекание: все детали состояния делят один атлас (цвет, нормали, AO,
# шероховатость, металл); каждая часть — свой меш, подвижные — с центром на оси.
# =====================================================================
if "--bake" in sys.argv and STATE in BUILDERS:
    i = sys.argv.index("--bake")
    SIZE = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit() else 2048
    OUT = os.path.join(OUT_ROOT, f"bake_{STATE}"); os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in col_main.objects if o.type == 'MESH']
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        for md in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
        o.select_set(False)
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:   # невидимые грани на земле — долой
        bm = bmesh.new(); bm.from_mesh(o.data)
        kill = [f for f in bm.faces if f.normal.z < -0.95 and f.calc_center_median().z < 0.01]
        if kill and len(kill) < len(bm.faces):
            bmesh.ops.delete(bm, geom=kill, context='FACES'); bm.to_mesh(o.data)
        bm.free()
    def join(objs, name):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs: o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        j = bpy.context.object; j.name = name; j.data.name = name
        return j
    NAMES = PARTS[STATE]
    by_part = {k: [o for o in meshes if o.get("part") == k] for k in NAMES}
    groups = {k: join(by_part[k], v) for k, v in NAMES.items()}
    baked = list(groups.values())
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked:
        uv = o.data.uv_layers.new(name="BakeUV"); o.data.uv_layers.active = uv
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.002, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    sc.render.bake.margin = 6
    mats = {m for o in baked for m in o.data.materials if m}
    pre = f"storage_{STATE}"
    def target(name, non_color):
        img = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
        if non_color: img.colorspace_settings.name = 'Non-Color'
        for m in mats:
            nt = m.node_tree
            n = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
            n.name = "BakeTarget"; n.image = img
            for x in nt.nodes: x.select = False
            n.select = True; nt.nodes.active = n
        return img
    def bake(kind, file, non_color, samples, **kw):
        sc.cycles.samples = samples
        t = target(file, non_color)
        bpy.ops.object.select_all(action='DESELECT')
        for o in baked: o.select_set(True)
        bpy.context.view_layer.objects.active = baked[0]
        bpy.ops.object.bake(type=kind, use_clear=True, **kw)
        t.filepath_raw = f"{OUT}/{file}.png"; t.file_format = 'PNG'; t.save(); print("BAKED", file, flush=True)
    bake('DIFFUSE', f"{pre}_albedo", False, 16, pass_filter={'COLOR'})
    bake('NORMAL', f"{pre}_normal", True, 16, normal_space='TANGENT')
    bake('ROUGHNESS', f"{pre}_roughness", True, 8)
    bake('AO', f"{pre}_ao", True, int(os.environ.get("STORAGE_AO_SAMPLES", "48")))
    for m in mats:   # металличность — через временную эмиссию
        b = m.node_tree.nodes["Principled BSDF"]
        lk = b.inputs["Metallic"].links
        for l in list(b.inputs["Emission Color"].links): m.node_tree.links.remove(l)
        if lk: m.node_tree.links.new(lk[0].from_socket, b.inputs["Emission Color"])
        else:
            v = b.inputs["Metallic"].default_value; b.inputs["Emission Color"].default_value = (v, v, v, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    bake('EMIT', f"{pre}_metallic", True, 1)
    atlas = bpy.data.materials.new(f"Storage_{STATE}_Atlas")
    for o in baked:
        for l in [l for l in o.data.uv_layers if l.name != "BakeUV"]: o.data.uv_layers.remove(l)
        o.data.materials.clear(); o.data.materials.append(atlas)
    for k, piv in PIVOTS.get(STATE, {}).items():
        o = groups[k]; o.data.transform(Matrix.Translation(-piv)); o.location = piv
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{pre}_game.glb", use_selection=True, export_apply=True,
                              export_materials='PLACEHOLDER', export_tangents=False)
    for o in baked:
        o.data.calc_loop_triangles(); print("PART", o.name, "tris", len(o.data.loop_triangles), "loc", tuple(round(v, 3) for v in o.location))
    bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/{pre}_baked.blend")
