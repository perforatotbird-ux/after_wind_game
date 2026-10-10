"""Дробилка камня «После бури» — процедурная модель для Blender 5.x (pip install bpy).
Референс: docs/art/crusher_reference.svg, промт: docs/art/crusher_reference_prompt.md.
Запуск из корня проекта:
  python3 tools/create_crusher_model.py                 # crusher.blend + crusher.glb
  python3 tools/create_crusher_model.py --render 32     # + рендеры Cycles с 3 камер
  python3 tools/create_crusher_model.py --bake 2048     # + запекание атласа для игры
Папка результата — переменная CRUSHER_OUT (по умолчанию ./crusher_build).
Затем: godot --headless --path . -s tools/import_crusher_model.gd -- <CRUSHER_OUT>/bake

Оси Blender: Z — вверх, фасад (лоток) смотрит в -Y (в Godot это +Z).
Подвижные детали собираются в отдельные меши с центром на оси вращения:
маховики с валом, шатун (подвижная щека), шкив мотора, камни в бункере, лампа."""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix
OUT_ROOT = os.path.abspath(os.environ.get("CRUSHER_OUT", "crusher_build"))
os.makedirs(OUT_ROOT, exist_ok=True)
open(os.path.join(OUT_ROOT, ".gdignore"), "w").close()  # Godot не импортирует промежуточные файлы
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col_main = bpy.data.collections.new("Crusher"); sc.collection.children.link(col_main)
col_env = bpy.data.collections.new("Stage"); sc.collection.children.link(col_env)

# ---------- оси вращения (Blender) ----------
SHAFT = Vector((0.0, 0.25, 1.05))      # вал маховиков и эксцентрик шатуна
PULLEY = Vector((0.665, 1.0, 0.55))    # шкив мотора
STONES = Vector((0.0, -0.2, 1.5))      # камни в бункере
FLY_X = 0.665
R_FLY = 0.52
R_PUL = 0.095
PIVOTS = {"fly": SHAFT, "jaw": SHAFT, "pulley": PULLEY, "stones": STONES}
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

M = {
    "paint": pbr("YellowPaint", '#cf981e', '#dca628', rough=0.5, scale=4, bump=0.04, wear='#3b3936', rust=0.3),
    "paint_dark": pbr("YellowPaintDark", '#ad7d16', '#bf8c1c', rough=0.55, scale=4, bump=0.04, wear='#3b3936', rust=0.4),
    "hazard": pbr("HazardStripes", '#d9a520', '#e8b830', rough=0.55, scale=8, bump=0.05, wear='#3b3936', stripes=7.0, rust=0.3),
    "iron": pbr("CastIron", '#24262a', '#34373b', rough=0.55, metal=0.85, scale=14, bump=0.12, wear='#7d8288', wear_metal=1.0),
    "steel": pbr("Steel", '#5f646a', '#80868c', rough=0.38, metal=0.9, scale=10, bump=0.03, bevel=0.006),
    "rust": pbr("RustySteel", '#4a2c1b', '#7a4626', rough=0.85, metal=0.35, scale=9, bump=0.35, rust=0.6),
    "plate": pbr("WornPlate", '#5a5c5e', '#77797b', rough=0.65, metal=0.75, scale=6, bump=0.25, rust=0.8),
    "weld": pbr("Weld", '#2a2a2a', '#4a4440', rough=0.7, metal=0.7, scale=60, bump=0.8, bevel=0.0),
    "galv": pbr("Galvanized", '#868e93', '#aab2b6', rough=0.42, metal=0.85, scale=4, bump=0.08, voronoi=22, rust=0.25),
    "wood": pbr("Sleeper", '#4f463c', '#7d705e', rough=0.9, scale=3, bump=0.5, grain=(0.12, 1.0, 1.0), bevel=0.02),
    "motor": pbr("MotorPaint", '#3f5a3b', '#56744f', rough=0.5, scale=6, bump=0.04, wear='#5e6266', rust=0.35),
    "rubber": pbr("Rubber", '#111111', '#1d1d1d', rough=0.8, scale=20, bump=0.1, bevel=0.004),
    "red": pbr("RedPaint", '#8e1f17', '#b0301f', rough=0.5, scale=6, bump=0.04, wear='#4a4a4a', rust=0.2),
    "button": pbr("ButtonRed", '#c4231a', '#e03a26', rough=0.35, scale=6, bump=0.0, bevel=0.004),
    "white": pbr("SignPlate", '#d8d2c4', '#ece6d8', rough=0.6, scale=9, bump=0.1, wear='#5a5650', rust=0.3, bevel=0.003),
    "ink": pbr("SignInk", '#1d1b19', '#2a2724', rough=0.7, scale=9, bump=0.0, bevel=0.0),
    "stone": pbr("Stone", '#6e6a63', '#a29d94', rough=0.85, scale=7, bump=0.6, bevel=0.0),
    "gravel": pbr("Gravel", '#57544f', '#8c877f', rough=0.9, scale=30, bump=0.9, voronoi=40, bevel=0.0),
    "dark": pbr("Shadowed", '#141312', '#1f1d1b', rough=0.9, scale=5, bump=0.0, bevel=0.0),
    "lamp": pbr("LampGreen", '#2a7a34', '#3fa14a', rough=0.2, scale=5, bump=0.0, bevel=0.0, emit='#5cff6e', emit_strength=6.0),
    "ground": pbr("Ground", '#3f5e22', '#62822f', rough=0.95, scale=1.5, bump=0.2, bevel=0.0),
    "dirt": pbr("Dirt", '#54402d', '#7a5c40', rough=0.95, scale=2, bump=0.3, bevel=0.0),
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

# =====================================================================
#                              МОДЕЛЬ
# =====================================================================
# ---------- рама: шпалы и двутавры ----------
for i, y in enumerate((-0.6, 0.95)):
    box(f"Sleeper{i}", (2.0, 0.24, 0.14), (random.uniform(-0.03, 0.03), y, 0.07), "wood", rot=(0, 0, random.uniform(-0.03, 0.03)), bevel=0.012)
for sx in (-1, 1):
    x = 0.45 * sx
    prism_xz(f"IBeam{sx}", [(x - 0.06, 0.14), (x + 0.06, 0.14), (x + 0.06, 0.158), (x + 0.008, 0.158), (x + 0.008, 0.282),
                            (x + 0.06, 0.282), (x + 0.06, 0.30), (x - 0.06, 0.30), (x - 0.06, 0.282), (x - 0.008, 0.282),
                            (x - 0.008, 0.158), (x - 0.06, 0.158)], -0.85, 1.25, "rust", bevel=0.003)
    for y in (-0.6, 0.95):
        for dx in (-0.045, 0.045):
            bolt((x + dx, y + 0.06, 0.158), r=0.012, h=0.012, m="rust", washer=False)
box("BasePlate", (1.12, 1.17, 0.02), (0, 0.035, 0.31), "plate", bevel=0.004)
# ---------- корпус: щёки с рёбрами ----------
CHEEK = [(-0.5, 0.32), (0.6, 0.32), (0.6, 0.62), (0.45, 0.95), (0.05, 0.95), (0.05, 1.12), (-0.5, 1.12)]
for sx in (-1, 1):
    x0, x1 = sorted((0.40 * sx, 0.48 * sx))
    prism_yz(f"Cheek{sx}", CHEEK, x0, x1, "paint", bevel=0.01)
    xo = 0.48 * sx
    xr0, xr1 = sorted((xo, xo + 0.045 * sx))
    for y, top in ((-0.3, 1.12), (0.0, 1.12), (0.3, 0.95)):
        prism_yz("Rib", [(y - 0.022, 0.36), (y + 0.022, 0.36), (y + 0.022, top - 0.03), (y - 0.022, top - 0.03)], xr0, xr1, "paint", bevel=0.006)
    xf0, xf1 = sorted((0.40 * sx, 0.57 * sx))
    box(f"CheekFoot{sx}", (abs(xf1 - xf0), 1.1, 0.04), ((xf0 + xf1) / 2, 0.05, 0.34), "paint_dark", bevel=0.006)
    for y in (-0.42, -0.15, 0.15, 0.45):
        bolt((0.535 * sx, y, 0.36), r=0.015)
    for y, z in ((-0.42, 1.07), (-0.15, 1.07), (0.38, 0.88)):
        bolt((xo, y, z), axis='X' if sx > 0 else '-X', r=0.014)
box("FrontWall", (0.80, 0.08, 0.67), (0, -0.46, 0.785), "paint", bevel=0.01)
for x in (-0.25, 0.0, 0.25):
    box("FrontRib", (0.045, 0.04, 0.62), (x, -0.515, 0.79), "paint", bevel=0.006)
box("FrontLip", (0.98, 0.06, 0.05), (0, -0.48, 1.115), "paint_dark", bevel=0.008)
# сварная заплата
box("Patch", (0.2, 0.012, 0.22), (0.13, -0.541, 0.66), "plate", rot=(0, math.radians(4), 0), bevel=0.003)
c, s_ = math.cos(math.radians(4)), math.sin(math.radians(4))
corners = [(-0.1, -0.11), (0.1, -0.11), (0.1, 0.11), (-0.1, 0.11)]
weld_pts = []
for i in range(4):
    (ax, az), (bx, bz) = corners[i], corners[(i + 1) % 4]
    for k in range(6):
        u = k / 6; lx = ax + (bx - ax) * u; lz = az + (bz - az) * u
        weld_pts.append((0.13 + lx * c + lz * s_, -0.546, 0.66 - lx * s_ + lz * c))
tube("WeldBead", weld_pts, 0.007, "weld", sides=5, closed=True)
for lx, lz in ((-0.07, -0.08), (0.07, -0.08), (0.07, 0.08), (-0.07, 0.08)):
    bolt((0.13 + lx * c + lz * s_, -0.547, 0.66 - lx * s_ + lz * c), axis='-Y', r=0.013, h=0.01)
box("Discharge", (0.80, 0.30, 0.13), (0, -0.30, 0.385), "dark")
# задний ящик распорной плиты, тяги с пружинами
box("ToggleBox", (0.80, 0.16, 0.30), (0, 0.50, 0.51), "paint", bevel=0.01)
for x in (-0.22, 0.22):
    cyl("TensionRod", 0.016, 0.24, (x, 0.70, 0.5), "steel", axis='Y', verts=10)
    tube("Spring", [(x + 0.04 * math.cos(t * 0.5), 0.6 + t * 0.0045, 0.5 + 0.04 * math.sin(t * 0.5)) for t in range(0, 36)], 0.007, "iron", sides=5)
    cyl("Nut", 0.026, 0.03, (x, 0.80, 0.5), "steel", axis='Y', verts=6, smooth=False)
# подшипники вала
for sx in (-1, 1):
    x = 0.44 * sx
    box(f"BearingFoot{sx}", (0.15, 0.32, 0.05), (x, SHAFT.y, 0.975), "iron", bevel=0.006)
    box(f"BearingBody{sx}", (0.13, 0.22, 0.09), (x, SHAFT.y, 1.04), "iron", bevel=0.008)
    cyl(f"BearingCap{sx}", 0.1, 0.13, (x, SHAFT.y, SHAFT.z), "iron", axis='X', verts=24, bevel=0.006)
    for y in (SHAFT.y - 0.13, SHAFT.y + 0.13):
        bolt((x, y, 1.0), r=0.014)
    cyl("GreaseNipple", 0.008, 0.04, (x, SHAFT.y, SHAFT.z + 0.115), "steel", verts=8)
    cyl("GreaseCap", 0.012, 0.012, (x, SHAFT.y, SHAFT.z + 0.14), "paint", verts=8)
# ---------- бункер ----------
HB = (-0.40, 0.40, -0.475, 0.075, 1.12)   # низ: x0, x1, y0, y1, z
HT = (-0.65, 0.65, -0.70, 0.30, 1.69)     # верх
def hopper_ring(z0, z1, off):
    def at(z):
        u = (z - HB[4]) / (HT[4] - HB[4])
        return [HB[i] + (HT[i] - HB[i]) * u for i in range(4)]
    a, b = at(z0), at(z1)
    bm = bmesh.new()
    def quad(c, z):
        x0, x1, y0, y1 = c
        return [bm.verts.new(v) for v in ((x0 - off, y0 - off, z), (x1 + off, y0 - off, z), (x1 + off, y1 + off, z), (x0 - off, y1 + off, z))]
    lo, hi = quad(a, z0), quad(b, z1)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm
hop = from_bm("Hopper", hopper_ring(HB[4], HT[4], 0.0), "paint")
sd = hop.modifiers.new("Solid", 'SOLIDIFY'); sd.thickness = 0.022; sd.offset = 1.0
bv = hop.modifiers.new("Bevel", 'BEVEL'); bv.width = 0.006; bv.limit_method = 'ANGLE'
hop.data.shade_smooth()
for z0 in (1.3, 1.5):
    o = from_bm("HopperBand", hopper_ring(z0, z0 + 0.045, 0.012), "paint_dark")
    o.modifiers.new("Solid", 'SOLIDIFY').thickness = 0.01
x0, x1, y0, y1 = HT[0] - 0.02, HT[1] + 0.02, HT[2] - 0.02, HT[3] + 0.02
for nm, size, loc in (("RimF", (x1 - x0, 0.05, 0.07), (0, y0 + 0.025, 1.725)), ("RimB", (x1 - x0, 0.05, 0.07), (0, y1 - 0.025, 1.725)),
                      ("RimL", (0.05, y1 - y0 - 0.1, 0.07), (x0 + 0.025, (y0 + y1) / 2, 1.725)), ("RimR", (0.05, y1 - y0 - 0.1, 0.07), (x1 - 0.025, (y0 + y1) / 2, 1.725))):
    box(nm, size, loc, "hazard", bevel=0.008)
for (bx, by), (tx, ty) in (((HB[0], HB[2]), (HT[0], HT[2])), ((HB[1], HB[2]), (HT[1], HT[2])), ((HB[1], HB[3]), (HT[1], HT[3])), ((HB[0], HB[3]), (HT[0], HT[3]))):
    sx = 1 if bx > 0 else -1; sy = 1 if by > -0.2 else -1
    tube("HopperCorner", [(bx + 0.012 * sx, by + 0.012 * sy, HB[4] + 0.02), (tx + 0.012 * sx, ty + 0.012 * sy, HT[4] - 0.01)], 0.022, "paint_dark", sides=4)
for z in (1.33, 1.53, 1.665):
    u = (z - HB[4]) / (HT[4] - HB[4])
    xh = HB[1] + (HT[1] - HB[1]) * u; y = HB[2] + (HT[2] - HB[2]) * u - 0.012
    for k in range(9):
        x = -xh + 0.06 + k * (2 * xh - 0.12) / 8
        if z == 1.33 and abs(x) < 0.26: continue
        rivet((x, y - 0.004, z + 0.02), axis='-Y')
# табличка «ДРОБИЛКА» на проволоке
tilt = math.atan2(HT[2] - HB[2], HT[4] - HB[4])   # наклон грани (< 0)
zc = 1.395; u = (zc - HB[4]) / (HT[4] - HB[4]); yf = HB[2] + (HT[2] - HB[2]) * u
nrm = Vector((0, -math.cos(-tilt), -math.sin(-tilt)))
sign_c = Vector((0, yf, zc)) + nrm * 0.032
box("Sign", (0.46, 0.01, 0.15), sign_c, "white", rot=(-tilt, 0, 0), bevel=0.004)
FONT = "/usr/share/fonts/liberation-sans/LiberationSans-Bold.ttf"
font = bpy.data.fonts.load(FONT) if os.path.exists(FONT) else None
bpy.ops.object.text_add(location=sign_c + nrm * 0.007)
tx = bpy.context.object; tx.data.body = "ДРОБИЛКА"
if font: tx.data.font = font
tx.data.size = 0.085; tx.data.extrude = 0.0015; tx.data.align_x = 'CENTER'; tx.data.align_y = 'CENTER'
tx.rotation_euler = (math.pi / 2 - tilt, 0, 0)
bpy.ops.object.convert(target='MESH'); tx = bpy.context.object; tx.name = "SignText"
finish(tx, "ink")
for sx in (-1, 1):
    p = sign_c + Vector((0.19 * sx, 0, 0)) + Vector((0, math.sin(-tilt), -math.cos(-tilt))) * -0.075
    tube("SignWire", [p + Vector((0.012 * math.cos(a), 0.012 * math.sin(a) * 0.6, 0.02 + 0.03 * math.sin(a))) for a in [k * 0.7 for k in range(10)]], 0.0025, "steel", sides=4, closed=True)
# дно бункера: щебень, чтобы не было видно пустоты
bm = bmesh.new()
nx, ny = 10, 8
zb = 1.5
uu = (zb - HB[4]) / (HT[4] - HB[4])
bx0 = HB[0] + (HT[0] - HB[0]) * uu + 0.01; bx1 = -bx0
by0 = HB[2] + (HT[2] - HB[2]) * uu + 0.01; by1 = HB[3] + (HT[3] - HB[3]) * uu - 0.01
vs = [[bm.verts.new((bx0 + (bx1 - bx0) * i / nx, by0 + (by1 - by0) * j / ny, zb + (0.05 * random.random() if 0 < i < nx and 0 < j < ny else 0))) for i in range(nx + 1)] for j in range(ny + 1)]
for j in range(ny):
    for i in range(nx):
        bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
from_bm("RubbleBed", bm, "gravel", smooth=True)
# ---------- лоток и щебень ----------
L0, L1 = Vector((0, -0.40, 0.42)), Vector((0, -1.0, 0.21))
ang = math.atan2(L0.z - L1.z, L0.y - L1.y)
ln = (L0 - L1).length; mid = (L0 + L1) / 2
box("ChuteBottom", (0.56, ln, 0.012), mid, "galv", rot=(ang, 0, 0), bevel=0.003)
for sx in (-1, 1):
    box("ChuteSide", (0.012, ln, 0.11), mid + Vector((0.28 * sx, 0, 0.05)), "galv", rot=(ang, 0, 0), bevel=0.003)
    tube("ChuteLeg", [(0.25 * sx, -0.93, 0.2), (0.27 * sx, -0.95, 0.0)], 0.014, "rust", sides=6)
box("ChuteGravel", (0.5, ln * 0.85, 0.02), mid + Vector((0, -0.03, 0.016)), "gravel", rot=(ang, 0, 0))
bm = bmesh.new()
pile_c = Vector((0.02, -1.13, 0.0))
segs, rings = 24, 6
center = bm.verts.new(pile_c + Vector((0, 0, 0.15)))
rv = []
for k in range(1, rings + 1):
    rr = 0.33 * k / rings
    row = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rj = rr * (1 + 0.12 * math.sin(a * 3 + 1) + 0.06 * random.uniform(-1, 1))
        h = 0.15 * (1 - (k / rings) ** 1.4) + 0.012 * random.uniform(-1, 1) * (k < rings)
        row.append(bm.verts.new(pile_c + Vector((rj * math.cos(a), rj * math.sin(a) * 0.9, max(0.0, h)))))
    rv.append(row)
for i in range(segs):
    bm.faces.new((center, rv[0][i], rv[0][(i + 1) % segs]))
for k in range(rings - 1):
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((rv[k][i], rv[k + 1][i], rv[k + 1][j], rv[k][j]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
from_bm("GravelPile", bm, "gravel", smooth=True)
for i in range(9):
    a = random.uniform(0, 2 * math.pi); r = random.uniform(0.18, 0.42)
    rock("Pebble", random.uniform(0.025, 0.05), (pile_c.x + r * math.cos(a), pile_c.y + r * math.sin(a), 0.02), "stone", sub=1, scale=(1, 1, 0.7))
# ---------- мотор, кронштейн, кабель ----------
box("MotorBase", (0.62, 0.42, 0.03), (0.25, 1.0, 0.315), "plate", bevel=0.004)
for y in (0.84, 1.16):
    for x in (0.0, 0.5):
        bolt((x, y, 0.33), r=0.012, h=0.012)
for x in (0.12, 0.38):
    box("MotorFoot", (0.06, 0.34, 0.08), (x, 1.0, 0.37), "motor", bevel=0.006)
cyl("MotorBody", 0.15, 0.40, (0.25, PULLEY.y, PULLEY.z), "motor", axis='X', verts=28)
for k in range(16):
    a = 2 * math.pi * k / 16
    if abs(math.sin(a) + 1) < 0.25: continue
    box("MotorFin", (0.34, 0.012, 0.03), (0.25, PULLEY.y + 0.162 * math.cos(a), PULLEY.z + 0.162 * math.sin(a)), "motor", rot=(a - math.pi / 2, 0, 0))
cyl("MotorBellFront", 0.155, 0.05, (0.475, PULLEY.y, PULLEY.z), "motor", axis='X', verts=28)
cyl("MotorBellCap", 0.12, 0.03, (0.515, PULLEY.y, PULLEY.z), "iron", axis='X', verts=24)
cyl("FanCowl", 0.155, 0.09, (0.0, PULLEY.y, PULLEY.z), "motor", axis='X', verts=28)
cyl("FanGrill", 0.13, 0.01, (-0.048, PULLEY.y, PULLEY.z), "dark", axis='X', verts=24)
for k in range(5):
    box("GrillBar", (0.006, 0.26, 0.012), (-0.052, PULLEY.y, PULLEY.z - 0.1 + k * 0.05), "steel")
box("TerminalBox", (0.13, 0.13, 0.08), (0.25, PULLEY.y, PULLEY.z + 0.19), "motor", bevel=0.008)
box("NamePlate", (0.1, 0.004, 0.05), (0.25, PULLEY.y - 0.158, PULLEY.z + 0.04), "steel", rot=(math.radians(10), 0, 0))
cyl("CableGland", 0.02, 0.04, (0.25, PULLEY.y + 0.085, PULLEY.z + 0.19), "dark", axis='Y', verts=10)
tube("Cable", [(0.25, 1.1, 0.74), (0.24, 1.2, 0.68), (0.2, 1.3, 0.45), (0.12, 1.34, 0.15), (0.0, 1.36, 0.025), (-0.3, 1.34, 0.022),
               (-0.6, 1.24, 0.022), (-0.8, 1.1, 0.025), (-0.87, 1.0, 0.06), (-0.88, 0.99, 0.3), (-0.88, 0.99, 0.62), (-0.89, 0.98, 0.85)], 0.016, "rubber", sides=8)
tube("PowerCable", [(-0.92, 0.98, 0.85), (-0.94, 1.0, 0.5), (-0.97, 1.04, 0.05), (-1.05, 1.2, 0.022), (-1.08, 1.32, 0.022)], 0.014, "rubber", sides=8)
cyl("Plug", 0.026, 0.07, (-1.085, 1.36, 0.026), "dark", axis='Y', verts=10)
# ---------- пульт ----------
box("ControlBlock", (0.2, 0.2, 0.06), (-0.9, 0.95, 0.03), "stone", bevel=0.01)
box("ControlPost", (0.045, 0.045, 0.82), (-0.9, 0.95, 0.46), "steel", bevel=0.004)
box("ControlBox", (0.21, 0.14, 0.25), (-0.9, 0.95, 0.985), "red", bevel=0.012)
box("ControlLid", (0.23, 0.16, 0.02), (-0.9, 0.95, 1.12), "red", bevel=0.006)
cyl("StopButton", 0.032, 0.03, (-0.9, 0.95 - 0.085, 0.95), "button", axis='Y', verts=16)
cyl("ButtonRing", 0.045, 0.012, (-0.9, 0.95 - 0.074, 0.95), "dark", axis='Y', verts=16)
box("ControlLabel", (0.12, 0.004, 0.03), (-0.9, 0.95 - 0.071, 1.05), "white")
cyl("LampBase", 0.03, 0.025, (-0.9, 0.95, 1.142), "dark", verts=14)
# ---------- маховики и вал ----------
PART = "fly"
cyl("Shaft", 0.05, 1.66, SHAFT, "steel", axis='X', verts=16)
for sx in (-1, 1):
    x = FLY_X * sx
    ring_x(f"Rim{sx}", R_FLY, R_FLY - 0.065, 0.09, (x, SHAFT.y, SHAFT.z), "iron", segs=56)
    ring_x(f"RimLip{sx}", R_FLY - 0.06, R_FLY - 0.08, 0.05, (x, SHAFT.y, SHAFT.z), "iron", segs=48, bevel=0.003)
    for k in range(6):
        a0 = k * math.pi / 3
        pts = []
        for i in range(10):
            t = i / 9; r = 0.07 + t * 0.40; a = a0 + 0.38 * math.sin(t * math.pi) * sx
            pts.append((SHAFT.y + r * math.cos(a), SHAFT.z + r * math.sin(a)))
        sweep_x("Spoke", pts, x, 0.06, 0.04, "iron", taper=lambda u: 1.25 - 0.45 * u, bevel=0.008)
    cyl(f"Hub{sx}", 0.085, 0.15, (x, SHAFT.y, SHAFT.z), "iron", axis='X', verts=24, bevel=0.008)
    cyl(f"HubNut{sx}", 0.05, 0.04, (x + 0.09 * sx, SHAFT.y, SHAFT.z), "steel", axis='X', verts=6, smooth=False, bevel=0.003)
    box(f"RimMark{sx}", (0.092, 0.06, 0.012), (x, SHAFT.y, SHAFT.z + R_FLY + 0.004), "paint", bevel=0.002)
    if sx > 0:  # ручей под ремень
        for dx in (-0.034, 0.034):
            ring_x("BeltLip", R_FLY + 0.018, R_FLY - 0.01, 0.012, (x + dx, SHAFT.y, SHAFT.z), "iron", segs=56, bevel=0.002)
# ---------- шатун (подвижная щека) ----------
PART = "jaw"
cyl("PitmanHousing", 0.16, 0.66, SHAFT, "paint", axis='X', verts=28, bevel=0.01)
for sx in (-1, 1):
    cyl("PitmanFlange", 0.175, 0.03, SHAFT + Vector((0.33 * sx, 0, 0)), "paint_dark", axis='X', verts=28, bevel=0.005)
    for k in range(6):
        a = k * math.pi / 3 + 0.3
        bolt(SHAFT + Vector((0.345 * sx, 0.13 * math.cos(a), 0.13 * math.sin(a))), axis='X' if sx > 0 else '-X', r=0.011, h=0.01, washer=False)
prism_yz("PitmanBody", [(0.08, 1.0), (0.33, 1.0), (0.10, 0.50), (-0.18, 0.50)], -0.32, 0.32, "paint", bevel=0.01)
for x in (-0.2, 0.0, 0.2):
    prism_yz("PitmanRib", [(0.30, 0.98), (0.37, 0.98), (0.13, 0.52), (0.08, 0.52)], x - 0.02, x + 0.02, "paint_dark", bevel=0.005)
cyl("PitmanGrease", 0.018, 0.05, SHAFT + Vector((0, 0, 0.18)), "steel", verts=10)
cyl("PitmanGreaseCap", 0.024, 0.02, SHAFT + Vector((0, 0, 0.21)), "red", verts=10)
# ---------- шкив мотора ----------
PART = "pulley"
cyl("MotorShaft", 0.022, 0.2, (0.6, PULLEY.y, PULLEY.z), "steel", axis='X', verts=12)
cyl("PulleyCore", R_PUL, 0.06, PULLEY, "steel", axis='X', verts=28)
for dx in (-0.034, 0.034):
    cyl("PulleyLip", R_PUL + 0.025, 0.012, PULLEY + Vector((dx, 0, 0)), "steel", axis='X', verts=28, bevel=0.002)
cyl("PulleyHub", 0.04, 0.1, PULLEY + Vector((0.02, 0, 0)), "iron", axis='X', verts=16)
box("PulleyMark", (0.004, 0.02, 0.06), PULLEY + Vector((0.042, 0, 0.07)), "paint")
box("PulleyKey", (0.1, 0.012, 0.01), PULLEY + Vector((0.02, 0, 0.042)), "iron")
# ---------- ремень (неподвижный контур) ----------
PART = "body"
c1 = Vector((SHAFT.y, SHAFT.z)); c2 = Vector((PULLEY.y, PULLEY.z))
r1, r2 = R_FLY + 0.012, R_PUL + 0.012
d = c2 - c1; dist = d.length; base = math.atan2(d.y, d.x); al = math.acos((r1 - r2) / dist)
pts = []
for i in range(40):
    a = base + al + (2 * math.pi - 2 * al) * i / 39
    pts.append((c1.x + r1 * math.cos(a), c1.y + r1 * math.sin(a)))
for i in range(16):
    a = base - al + (2 * al) * i / 15
    pts.append((c2.x + r2 * math.cos(a), c2.y + r2 * math.sin(a)))
sweep_x("Belt", pts, FLY_X, 0.022, 0.045, "rubber", closed=True)
# ---------- камни в бункере ----------
PART = "stones"
spots = [(-0.38, -0.5), (-0.15, -0.55), (0.12, -0.52), (0.36, -0.45), (-0.42, -0.22), (-0.2, -0.28), (0.05, -0.25),
         (0.3, -0.2), (-0.35, 0.02), (-0.1, 0.0), (0.18, 0.05), (0.42, 0.0), (-0.02, -0.4), (0.25, -0.35), (-0.28, -0.4)]
for i, (x, y) in enumerate(spots):
    r = random.uniform(0.07, 0.115)
    rock(f"HopperStone{i}", r, (x, y, 1.53 + r * 0.55 + random.uniform(0, 0.05)), "stone", sub=2, scale=(1.0, random.uniform(0.75, 1.0), random.uniform(0.6, 0.85)))
# ---------- лампа ----------
PART = "lamp"
cyl("Lamp", 0.026, 0.035, (-0.9, 0.95, 1.172), "lamp", verts=14)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.026, location=(-0.9, 0.95, 1.19), segments=14, ring_count=7)
o = bpy.context.object; o.name = "LampDome"; finish(o, "lamp", smooth=True)
PART = "body"

# ---------- сцена: земля, солнце, небо, камеры ----------
bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0)); g = bpy.context.object; g.name = "Ground"
finish(g, "ground", c=col_env)
bpy.ops.mesh.primitive_circle_add(radius=2.2, fill_type='NGON', location=(0, 0.0, 0.003), vertices=48); dd = bpy.context.object; dd.name = "TroddenDirt"
finish(dd, "dirt", c=col_env)
bpy.ops.object.light_add(type='SUN', rotation=(math.radians(48), math.radians(8), math.radians(-38)))
sun = bpy.context.object; sun.data.energy = 3.6; sun.data.angle = math.radians(3); link(sun, col_env)
w = bpy.data.worlds.new("Sky"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.55, 0.65, 0.78, 1); bg.inputs["Strength"].default_value = 0.9

def camera(name, loc, target, lens=40):
    bpy.ops.object.camera_add(location=loc); c = bpy.context.object; c.name = name; c.data.lens = lens
    c.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    link(c, col_env); return c

cams = {
    "front34": camera("CamFront34", (-3.3, -4.4, 2.5), (0.05, 0.05, 0.85), 40),
    "back34": camera("CamBack34", (3.6, 3.9, 2.4), (0, 0.2, 0.8), 40),
    "game": camera("CamGameIso", (-4.6, -4.6, 5.0), (0, 0, 0.7), 50),
}
sc.camera = cams["front34"]

tris = 0
dg = bpy.context.evaluated_depsgraph_get()
for o in col_main.objects:
    if o.type == 'MESH':
        e = o.evaluated_get(dg); me = e.to_mesh(); me.calc_loop_triangles(); tris += len(me.loop_triangles); e.to_mesh_clear()
print("OBJECTS", len(col_main.objects), "TRIS", tris)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_ROOT, "crusher.blend"))
for o in bpy.context.view_layer.objects: o.select_set(o.name in col_main.objects and o.type == 'MESH')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_ROOT, "crusher.glb"), use_selection=True, export_apply=True)

if "--render" in sys.argv:
    r = sc.render; r.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    i = sys.argv.index("--render")
    sc.cycles.samples = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit() else 32
    sc.cycles.use_denoising = True
    r.resolution_x, r.resolution_y = 1280, 960
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
    only = os.environ.get("CRUSHER_CAMS", "front34,back34,game").split(",")
    for k, c in cams.items():
        if k not in only: continue
        sc.camera = c; r.filepath = os.path.join(OUT_ROOT, f"render_{k}.png")
        bpy.ops.render.render(write_still=True); print("RENDERED", k)

# =====================================================================
# Запекание: все непрозрачные детали делят один атлас (цвет, нормали, AO,
# шероховатость, металл); каждая подвижная группа — свой меш с центром на оси.
# =====================================================================
if "--bake" in sys.argv:
    i = sys.argv.index("--bake")
    SIZE = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit() else 2048
    OUT = os.path.join(OUT_ROOT, "bake"); os.makedirs(OUT, exist_ok=True)
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
    NAMES = {"body": "CrusherBody", "fly": "CrusherFlywheel", "jaw": "CrusherJaw", "pulley": "CrusherPulley", "stones": "CrusherStones", "lamp": "CrusherLamp"}
    by_part = {k: [o for o in meshes if o.get("part") == k] for k in NAMES}
    groups = {k: join(by_part[k], v) for k, v in NAMES.items()}
    baked = [groups[k] for k in ("body", "fly", "jaw", "pulley", "stones")]
    # общая развёртка всех запекаемых групп (мультиредактирование)
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked:
        uv = o.data.uv_layers.new(name="BakeUV"); o.data.uv_layers.active = uv
        o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.0025, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    sc.render.bake.margin = 8
    mats = {m for o in baked for m in o.data.materials if m}
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
    bake('DIFFUSE', "crusher_albedo", False, 16, pass_filter={'COLOR'})
    bake('NORMAL', "crusher_normal", True, 16, normal_space='TANGENT')
    bake('ROUGHNESS', "crusher_roughness", True, 8)
    bake('AO', "crusher_ao", True, int(os.environ.get("CRUSHER_AO_SAMPLES", "48")))
    for m in mats:   # металличность — через временную эмиссию
        b = m.node_tree.nodes["Principled BSDF"]
        lk = b.inputs["Metallic"].links
        for l in list(b.inputs["Emission Color"].links): m.node_tree.links.remove(l)
        if lk: m.node_tree.links.new(lk[0].from_socket, b.inputs["Emission Color"])
        else:
            v = b.inputs["Metallic"].default_value; b.inputs["Emission Color"].default_value = (v, v, v, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    bake('EMIT', "crusher_metallic", True, 1)
    # экспорт: только BakeUV, общий материал-заглушка, центры на осях вращения
    atlas = bpy.data.materials.new("CrusherAtlas")
    for o in baked:
        for l in [l for l in o.data.uv_layers if l.name != "BakeUV"]: o.data.uv_layers.remove(l)
        o.data.materials.clear(); o.data.materials.append(atlas)
    lamp = groups["lamp"]
    while lamp.data.uv_layers: lamp.data.uv_layers.remove(lamp.data.uv_layers[0])
    lamp.data.materials.clear(); lamp.data.materials.append(M["lamp"])
    for k, piv in PIVOTS.items():
        o = groups[k]; o.data.transform(Matrix.Translation(-piv)); o.location = piv
    bpy.ops.object.select_all(action='DESELECT')
    for o in groups.values(): o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/crusher_game.glb", use_selection=True, export_apply=True,
                              export_materials='PLACEHOLDER', export_tangents=False)
    for o in groups.values():
        o.data.calc_loop_triangles(); print("PART", o.name, "tris", len(o.data.loop_triangles), "loc", tuple(round(v, 3) for v in o.location))
    bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/crusher_baked.blend")
