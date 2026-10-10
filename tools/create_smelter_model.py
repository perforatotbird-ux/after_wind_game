"""Плавильная печь «После бури» — процедурная модель для Blender 5.x (pip install bpy).
Запуск из корня проекта:
  python3 tools/create_smelter_model.py                 # smelter.blend + smelter.glb
  python3 tools/create_smelter_model.py --render 40     # + рендеры Cycles с 3 камер
  python3 tools/create_smelter_model.py --bake 2048     # + запекание атласа для игры
Папка результата — переменная SMELTER_OUT (по умолчанию ./smelter_build).
Затем: godot --headless --path . -s tools/import_smelter_model.gd -- <SMELTER_OUT>/bake"""
import bpy, bmesh, math, random, sys, os
OUT_ROOT = os.path.abspath(os.environ.get("SMELTER_OUT", "smelter_build"))
os.makedirs(OUT_ROOT, exist_ok=True)
open(os.path.join(OUT_ROOT, ".gdignore"), "w").close()  # Godot не импортирует промежуточные файлы
from mathutils import Vector, Matrix
random.seed(11)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col_main = bpy.data.collections.new("Smelter"); sc.collection.children.link(col_main)
col_env = bpy.data.collections.new("Stage"); sc.collection.children.link(col_env)

# ---------- материалы ----------
def mat(name, color, rough=0.8, metal=0.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m

def srgb(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def brick_mat():
    m = bpy.data.materials.new("Brick"); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    b = N["Principled BSDF"]; b.inputs["Roughness"].default_value = 0.9
    uv = N.new("ShaderNodeTexCoord")
    br = N.new("ShaderNodeTexBrick")
    br.inputs["Color1"].default_value = (*srgb('#a5503a'), 1)
    br.inputs["Color2"].default_value = (*srgb('#7d3a27'), 1)
    br.inputs["Mortar"].default_value = (*srgb('#8a7f72'), 1)
    br.inputs["Scale"].default_value = 4.0
    br.inputs["Mortar Size"].default_value = 0.018
    br.inputs["Brick Width"].default_value = 0.5
    br.inputs["Row Height"].default_value = 0.25
    br.offset = 0.5
    L.new(uv.outputs["UV"], br.inputs["Vector"])
    noise = N.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 18
    mix = N.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'
    mix.inputs["Factor"].default_value = 0.35
    L.new(br.outputs["Color"], mix.inputs[6]); L.new(noise.outputs["Color"], mix.inputs[7])
    L.new(mix.outputs[2], b.inputs["Base Color"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35
    inv = N.new("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
    L.new(br.outputs["Fac"], inv.inputs[1]); L.new(inv.outputs[0], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m

def noisy_mat(name, c1, c2, scale=6, rough=0.9, bump_s=0.4, metal=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    b = N["Principled BSDF"]; b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    tc = N.new("ShaderNodeTexCoord")
    nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale; nz.inputs["Detail"].default_value = 6
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = N.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*srgb(c1), 1); ramp.color_ramp.elements[1].color = (*srgb(c2), 1)
    L.new(nz.outputs["Fac"], ramp.inputs["Fac"]); L.new(ramp.outputs["Color"], b.inputs["Base Color"])
    bump = N.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = bump_s
    L.new(nz.outputs["Fac"], bump.inputs["Height"]); L.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m

def corrugated_mat():
    m = noisy_mat("MetalSheet", '#7f8a90', '#9aa4aa', scale=12, rough=0.55, bump_s=0.1, metal=0.7)
    nt = m.node_tree; N = nt.nodes; L = nt.links
    tc = [n for n in N if n.type == 'TEX_COORD'][0]
    w = N.new("ShaderNodeTexWave"); w.inputs["Scale"].default_value = 9; w.wave_profile = 'SIN'
    L.new(tc.outputs["Object"], w.inputs["Vector"])
    bp = N.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.8
    L.new(w.outputs["Fac"], bp.inputs["Height"]); L.new(bp.outputs["Normal"], N["Principled BSDF"].inputs["Normal"])
    for n in N:
        if n.type == 'BUMP' and n != bp:
            N.remove(n)
    return m

M = {
    "brick": brick_mat(),
    "stone": noisy_mat("Stone", '#6d6964', '#9a958d', scale=4, bump_s=0.5),
    "clay": noisy_mat("Clay", '#7a5a40', '#b48a63', scale=5, bump_s=0.6),
    "iron": noisy_mat("Iron", '#2c2f33', '#4a4f55', scale=10, rough=0.6, bump_s=0.15, metal=0.85),
    "pipe": noisy_mat("Pipe", '#5d636a', '#8a9097', scale=8, rough=0.45, bump_s=0.05, metal=0.9),
    "rivet": mat("Rivet", srgb('#8d9298'), 0.4, 0.9),
    "wood": noisy_mat("Wood", '#5e4529', '#8b6a43', scale=3, bump_s=0.3),
    "leather": noisy_mat("Leather", '#4e301b', '#7a4e2e', scale=9, rough=0.7, bump_s=0.3),
    "coal": mat("Coal", srgb('#18181a'), 0.55),
    "ember": mat("Ember", srgb('#3a1a0c'), 0.7, emit=srgb('#ff4a00'), emit_strength=4),
    "fire": mat("FireBack", srgb('#5a1a0c'), 0.9, emit=srgb('#d84a10'), emit_strength=1.6),
    "molten": mat("Molten", srgb('#c04010'), 0.3, emit=srgb('#ff5a00'), emit_strength=2.5),
    "sheet": corrugated_mat(),
    "ground": noisy_mat("Ground", '#4d6b2c', '#6f8f3a', scale=1.5, bump_s=0.2),
    "dirt": noisy_mat("Dirt", '#5c4430', '#7a5c40', scale=2, bump_s=0.3),
}

def link(o, c=None):
    for cc in o.users_collection: cc.objects.unlink(o)
    (c or col_main).objects.link(o)
    return o

def finish(o, m, bevel=0.0, smooth=False, c=None):
    link(o, c)
    o.data.materials.clear(); o.data.materials.append(M[m] if isinstance(m, str) else m)
    if bevel > 0:
        md = o.modifiers.new("Bevel", 'BEVEL'); md.width = bevel; md.segments = 1; md.limit_method = 'ANGLE'
    if smooth:
        for p in o.data.polygons: p.use_smooth = True
    return o

def box(name, size, loc, m, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, m, bevel)

def cyl(name, r, h, loc, m, rot=(0, 0, 0), verts=24, r2=None, bevel=0.0, smooth=True):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.object; o.name = name
    return finish(o, m, bevel, smooth)

def rock(name, r, loc, m, jitter=0.25, sub=1, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, subdivisions=sub, location=loc)
    o = bpy.context.object; o.name = name
    for v in o.data.vertices:
        v.co *= 1 + random.uniform(-jitter, jitter)
    o.scale = scale; bpy.ops.object.transform_apply(scale=True)
    return finish(o, m)

def frustum(name, w0, w1, h, z0, m):
    bm = bmesh.new()
    vs = []
    for z, w in ((z0, w0), (z0 + h, w1)):
        for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vs.append(bm.verts.new((x * w / 2, y * w / 2, z)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((vs[i], vs[j], vs[j + 4], vs[i + 4]))
    bm.faces.new(vs[0:4][::-1]); bm.faces.new(vs[4:8])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); col_main.objects.link(o)
    o.data.materials.append(M[m])
    return o

def cube_uv(o, size=1.0):
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects: x.select_set(False)
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project(cube_size=size, correct_aspect=False, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')

# ---------- размеры (м) ----------
PL_W, PL_H = 2.3, 0.35
B_W0, B_W1, B_H = 2.0, 1.7, 1.5
Z_B0 = PL_H; Z_B1 = PL_H + B_H
FRONT = -1  # фасад смотрит в -Y

def body_half(z):
    t = (z - Z_B0) / B_H
    return (B_W0 + (B_W1 - B_W0) * t) / 2

# ---------- цоколь из рваного камня ----------
box("PlinthCore", (PL_W - 0.06, PL_W - 0.06, PL_H - 0.02), (0, 0, PL_H / 2), "stone")
for row in range(2):
    zc = PL_H * (0.25 + 0.5 * row)
    for side in range(4):
        pos = -PL_W / 2 + (0.08 if row else 0.0)
        while pos < PL_W / 2 - 0.05:
            w = random.uniform(0.28, 0.46); w = min(w, PL_W / 2 - pos)
            c = pos + w / 2
            d = random.uniform(0.18, 0.26)
            sz = (w - 0.03, d, PL_H / 2 - 0.025)
            out = PL_W / 2 - d / 2 + 0.02
            loc = [(c, -out), (out, c), (-c, out), (-out, -c)][side]
            rot = (random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), [0, math.pi / 2, math.pi, -math.pi / 2][side] + random.uniform(-0.03, 0.03))
            box("PlinthStone", sz, (loc[0], loc[1], zc + random.uniform(-0.01, 0.01)), "stone", rot, bevel=0.035)
            pos += w

# ---------- кирпичный корпус с аркой топки ----------
body = frustum("BrickBody", B_W0, B_W1, B_H, Z_B0, "brick")
OW, OH = 0.72, 0.66  # проём топки
OZ0 = Z_B0 + 0.2
arch_cz = OZ0 + OH - OW / 2
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -B_W0 / 2, OZ0 + (OH - OW / 2) / 2)); cut1 = bpy.context.object
cut1.scale = (OW, 0.9, OH - OW / 2); bpy.ops.object.transform_apply(scale=True)
bpy.ops.mesh.primitive_cylinder_add(radius=OW / 2, depth=0.9, location=(0, -B_W0 / 2, arch_cz), rotation=(math.pi / 2, 0, 0), vertices=32); cut2 = bpy.context.object
for cut in (cut1, cut2):
    md = body.modifiers.new("Arch", 'BOOLEAN'); md.object = cut; md.operation = 'DIFFERENCE'
bpy.context.view_layer.objects.active = body
for md in list(body.modifiers):
    bpy.ops.object.modifier_apply(modifier=md.name)
for cut in (cut1, cut2): bpy.data.objects.remove(cut)
for p_ in body.data.polygons: p_.material_index = 0
while len(body.data.materials) > 1: body.data.materials.pop()
cube_uv(body, 1.0)
# внутренняя камера (светится)
box("FireChamber", (OW + 0.1, 0.5, OH + 0.05), (0, -B_W0 / 2 + 0.55, OZ0 + OH / 2), "fire")
box("FireFloor", (OW + 0.1, 0.62, 0.04), (0, -B_W0 / 2 + 0.3, OZ0 + 0.02), "coal")
for i in range(14):
    x = random.uniform(-OW / 2 + 0.07, OW / 2 - 0.07); y = -B_W0 / 2 + random.uniform(0.15, 0.5)
    rock("Coal", random.uniform(0.05, 0.08), (x, y, OZ0 + 0.06), random.choice(["coal", "ember", "ember"]), 0.3)
# клинчатые кирпичи арки
slope = math.atan((B_W0 - B_W1) / 2 / B_H)
for k in range(11):
    a = math.pi * k / 10
    r = OW / 2 + 0.07
    x = -math.cos(a) * r; z = arch_cz + math.sin(a) * r
    y = -body_half(z) - 0.015
    box("ArchBrick", (0.09, 0.08, 0.15), (x, y, z), "brick", (slope, -(math.pi / 2 - a), 0), bevel=0.01)
for sx in (-1, 1):
    for k in range(3):
        z = OZ0 + 0.06 + k * 0.13
        box("JambBrick", (0.15, 0.08, 0.11), (sx * (OW / 2 + 0.07), -body_half(z) - 0.015, z), "brick", (slope, 0, 0), bevel=0.01)
# порог
box("Sill", (OW + 0.3, 0.2, 0.06), (0, -body_half(OZ0) - 0.04, OZ0 - 0.02), "stone", bevel=0.02)
# приоткрытая железная дверца на петлях справа
hx = OW / 2 + 0.03; hy = -body_half(OZ0 + OH / 2) - 0.05
door = box("FireDoor", (OW * 0.95, 0.04, OH * 0.95), (0, 0, 0), "iron", bevel=0.008)
door.data.transform(Matrix.Translation((-OW * 0.95 / 2, 0, 0)))
door.location = (hx + OW * 0.95 * 0 + 0.0, hy, OZ0 + OH / 2); door.rotation_euler = (0, 0, math.radians(115))
door.location.x = hx + 0.0
handle = cyl("DoorHandle", 0.025, 0.12, (0, 0, 0), "rivet", (math.pi / 2, 0, 0), 12)
handle.parent = door; handle.location = (-OW * 0.8, -0.06, 0)
for dz in (-0.2, 0.2):
    cyl("Hinge", 0.03, 0.1, (hx, hy, OZ0 + OH / 2 + dz), "iron", (0, 0, 0), 12)

# ---------- железные обручи с заклёпками ----------
for t in (0.28, 0.84):
    z = Z_B0 + B_H * t
    hw = body_half(z) + 0.022
    for s in range(4):
        rot = [0, math.pi / 2, math.pi, -math.pi / 2][s]
        d = Vector((0, -hw, 0)); d.rotate(Matrix.Rotation(rot, 3, 'Z'))
        if s == 0 and OZ0 - 0.05 < z < OZ0 + OH + 0.05:
            # обруч огибает топку
            for sx in (-1, 1):
                L = hw - OW / 2 - 0.14
                box("Band", (L, 0.035, 0.1), (sx * (OW / 2 + 0.14 + L / 2), -hw, z), "iron", (slope, 0, 0), bevel=0.006)
        else:
            box("Band", (2 * hw + 0.04, 0.035, 0.1), (d.x, d.y, z), "iron", (slope, 0, rot), bevel=0.006)
        for k in range(7):
            u = -hw + 0.12 + k * (2 * hw - 0.24) / 6
            if s == 0 and OZ0 - 0.05 < z < OZ0 + OH + 0.05 and abs(u) < OW / 2 + 0.14:
                continue
            p = Vector((u, -hw - 0.02, z)); p.rotate(Matrix.Rotation(rot, 3, 'Z'))
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=p, segments=6, ring_count=4)
            finish(bpy.context.object, "rivet", smooth=True)

# венчающий ряд кирпича
cap = box("BrickCap", (B_W1 + 0.08, B_W1 + 0.08, 0.1), (0, 0, Z_B1 + 0.05), "brick", bevel=0.015)
cube_uv(cap, 1.0)

# ---------- глиняная шахта (купол) ----------
Z_S0 = Z_B1 + 0.1; S_H = 0.85
prof = []  # (r, z)
for i in range(13):
    t = i / 12
    r = 0.84 - 0.46 * (t ** 0.75) + 0.07 * math.sin(t * math.pi)
    prof.append((r, Z_S0 + S_H * t))
bm = bmesh.new(); seg = 40; rings = []
for r, z in prof:
    ring = [bm.verts.new((r * math.cos(2 * math.pi * j / seg), r * math.sin(2 * math.pi * j / seg), z)) for j in range(seg)]
    rings.append(ring)
for a_, b_ in zip(rings, rings[1:]):
    for j in range(seg):
        k = (j + 1) % seg
        bm.faces.new((a_[j], a_[k], b_[k], b_[j]))
me = bpy.data.meshes.new("ClayShaft"); bm.to_mesh(me); bm.free()
shaft = bpy.data.objects.new("ClayShaft", me); col_main.objects.link(shaft)
shaft.data.materials.append(M["clay"])
for p in shaft.data.polygons: p.use_smooth = True
tex = bpy.data.textures.new("ClayLumps", 'CLOUDS'); tex.noise_scale = 0.18
md = shaft.modifiers.new("Sub", 'SUBSURF'); md.levels = 1; md.render_levels = 2
md = shaft.modifiers.new("Lumps", 'DISPLACE'); md.texture = tex; md.strength = 0.04; md.mid_level = 0.5
# трещины — тёмные тонкие «борозды»
crack_m = mat("Crack", srgb('#3d2a1c'), 0.95)
for (ang, z0, zz) in ((2.6, 0.15, 0.35), (4.1, 0.05, 0.3), (5.6, 0.25, 0.5)):
    pts = []
    for i in range(5):
        t = i / 4; z = Z_S0 + S_H * (z0 + (zz - z0) * t)
        rr = [r for r, zp in prof if zp >= z][0] if any(zp >= z for _, zp in prof) else prof[-1][0]
        a = ang + random.uniform(-0.06, 0.06)
        pts.append(Vector((math.cos(a) * (rr + 0.045), math.sin(a) * (rr + 0.045), z)))
    for p, q in zip(pts, pts[1:]):
        mid = (p + q) / 2; d = q - p
        bpy.ops.mesh.primitive_cube_add(size=1, location=mid)
        o = bpy.context.object; o.scale = (0.012, 0.012, d.length)
        o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        bpy.ops.object.transform_apply(scale=True)
        finish(o, crack_m)
# заплата из профлиста после бури
ang = math.radians(-60); zp = Z_S0 + 0.36
rr = 0.84 - 0.46 * (0.42 ** 0.75) + 0.07 * math.sin(0.42 * math.pi) + 0.05
patch = box("StormPatch", (0.5, 0.012, 0.42), (0, 0, 0), "sheet")
patch.location = (math.cos(ang) * rr, math.sin(ang) * rr, zp)
patch.rotation_euler = (math.radians(-28), math.radians(-8), ang + math.pi / 2)
bpy.context.view_layer.update()  # иначе matrix_world заплаты ещё старая
for dx in (-0.2, 0.2):
    for dz in (-0.16, 0.16):
        q = Matrix.Translation(patch.location) @ patch.rotation_euler.to_matrix().to_4x4() @ Vector((dx, -0.012, dz))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.014, location=q, segments=6, ring_count=4)
        finish(bpy.context.object, "rivet", smooth=True)

# ---------- труба с колпаком ----------
Z_C0 = Z_S0 + S_H - 0.05; C_H = 1.15; C_R = 0.18
cyl("Chimney", C_R, C_H, (0, 0, Z_C0 + C_H / 2), "pipe", verts=28)
cyl("ChimneyCollar", C_R + 0.05, 0.12, (0, 0, Z_C0 + 0.04), "clay", verts=28)
for t in (0.32, 0.72):
    cyl("ChimneyRing", C_R + 0.018, 0.06, (0, 0, Z_C0 + C_H * t), "iron", verts=28)
Z_CAP = Z_C0 + C_H + 0.16
cyl("RainCap", 0.38, 0.17, (0, 0, Z_CAP + 0.06), "iron", verts=28, r2=0.02)
for k in range(4):
    a = k * math.pi / 2 + math.pi / 4
    box("CapLeg", (0.025, 0.025, 0.2), (math.cos(a) * C_R * 0.8, math.sin(a) * C_R * 0.8, Z_C0 + C_H + 0.07), "iron")

# ---------- мехи на столе (строятся справа, затем поворачиваются за печь, +Y) и фурма ----------
_before_bellows = set(bpy.data.objects)
BX = B_W0 / 2 + 0.6
TOP_Z = 0.62
box("BellowsTableTop", (0.95, 0.6, 0.06), (BX, 0, TOP_Z), "wood", bevel=0.01)
for sx in (-1, 1):
    for sy in (-1, 1):
        box("BellowsLeg", (0.08, 0.08, TOP_Z), (BX + sx * 0.38, sy * 0.22, TOP_Z / 2 - 0.02), "wood", (0, 0, random.uniform(-0.05, 0.05)), bevel=0.01)
# мехи: нижняя доска на столе, верхняя наклонена, между ними кожа с гармошкой
def drop_outline(n=20):
    pts = []
    for i in range(n):
        a = math.pi * 2 * i / n
        pts.append((math.cos(a) * 0.42, math.sin(a) * 0.24 * (0.55 + 0.45 * (math.cos(a) + 1) / 2)))
    return pts
OUT = drop_outline()
BELLOWS_PIVOT = Vector((BX - 0.36, 0, TOP_Z + 0.1))
HIGH_TILT = math.radians(-16)
def board_matrix(lift, tilt):
    return Matrix.Translation(BELLOWS_PIVOT + Vector((0, 0, lift))) @ Matrix.Rotation(tilt, 4, 'Y') @ Matrix.Translation(Vector((0.4, 0, 0)))
def drop_board(name, mw):
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, 0)) for x, y in OUT])
    bmesh.ops.solidify(bm, geom=[f], thickness=0.04)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); col_main.objects.link(o)
    o.data.materials.append(M["wood"]); o.matrix_world = mw
    return o
M_LOW = board_matrix(-0.06, 0.0); M_HIGH = board_matrix(0.0, HIGH_TILT)
drop_board("BellowsBoardLow", M_LOW)
drop_board("BellowsBoardHigh", M_HIGH)
bm = bmesh.new(); rings = []
STEPS = 7
for k in range(STEPS):
    t = k / (STEPS - 1)
    shrink = 0.86 if k % 2 == 1 else 1.0
    ring = []
    for x, y in OUT:
        lo = M_LOW @ Vector((x * 0.97, y * 0.97, 0.04)); hi = M_HIGH @ Vector((x * 0.97, y * 0.97, -0.0))
        p = lo.lerp(hi, t)
        c = (M_LOW @ Vector((0.0, 0, 0.04))).lerp(M_HIGH @ Vector((0.0, 0, 0)), t)
        q = c + (p - c) * shrink
        ring.append(bm.verts.new(q))
    rings.append(ring)
for r1, r2 in zip(rings, rings[1:]):
    for j in range(len(OUT)):
        k = (j + 1) % len(OUT)
        bm.faces.new((r1[j], r1[k], r2[k], r2[j]))
me = bpy.data.meshes.new("BellowsLeather"); bm.to_mesh(me); bm.free()
lea = bpy.data.objects.new("BellowsLeather", me); col_main.objects.link(lea)
lea.data.materials.append(M["leather"])
for p_ in lea.data.polygons: p_.use_smooth = True
hp = M_HIGH @ Vector((0.5, 0, 0.18))
cyl("BellowsHandle", 0.025, 0.36, hp, "wood", (0, math.radians(-20), 0), 10)
# фурма: железная трубка от сопла мехов в корпус
noz = BELLOWS_PIVOT + Vector((-0.02, 0, 0.0))
cyl("Nozzle", 0.05, 0.12, noz + Vector((0.02, 0, 0)), "iron", (0, math.pi / 2, 0), 14, r2=0.035)
wall = Vector((body_half(TOP_Z + 0.1) - 0.05, 0, TOP_Z + 0.1))
d = wall - noz
o = cyl("Tuyere", 0.045, d.length, (noz + wall) / 2, "iron", verts=14)
o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
cyl("TuyereFlange", 0.08, 0.03, (wall.x + 0.03, 0, wall.z), "iron", (0, math.pi / 2 - slope, 0), 16)

# поворот мехов за печь: в игре справа и слева стоят соседние станки
for o in set(bpy.data.objects) - _before_bellows:
    if o.parent is None:
        o.matrix_world = Matrix.Rotation(math.pi / 2, 4, 'Z') @ o.matrix_world

# ---------- желоб слива и форма для слитков (спереди слева) ----------
SZ = Z_B0 + 0.08
spout = box("TapSpout", (0.12, 0.42, 0.06), (-0.62, -body_half(SZ) - 0.17, SZ - 0.06), "clay", (math.radians(14), 0, math.radians(18)), bevel=0.015)
for sx in (-1, 1):
    box("SpoutRim", (0.025, 0.42, 0.05), (-0.62 + sx * 0.055, -body_half(SZ) - 0.17, SZ - 0.03), "clay", (math.radians(14), 0, math.radians(18)))
box("MoltenTrickle", (0.06, 0.36, 0.01), (-0.62, -body_half(SZ) - 0.17, SZ - 0.025), "molten", (math.radians(14), 0, math.radians(18)))
MX, MY = -0.82, -B_W0 / 2 - 0.62
box("IngotMold", (0.62, 0.36, 0.14), (MX, MY, 0.07), "iron", (0, 0, math.radians(12)), bevel=0.012)
for k in range(3):
    q = Vector((-0.2 + k * 0.2, 0, 0)); q.rotate(Matrix.Rotation(math.radians(12), 3, 'Z'))
    box("IngotGlow" if k < 2 else "IngotCold", (0.15, 0.24, 0.02), (MX + q.x, MY + q.y, 0.142), "molten" if k < 2 else "pipe", (0, 0, math.radians(12)))

# ---------- ящик угля (слева) ----------
KX, KY = -0.85, B_W0 / 2 + 0.55
for k, (w, d_, h, x, y) in enumerate([(0.7, 0.04, 0.45, 0, -0.27), (0.7, 0.04, 0.45, 0, 0.27), (0.04, 0.5, 0.45, -0.33, 0), (0.04, 0.5, 0.45, 0.33, 0)]):
    for p in range(3):
        box("CratePlank", (w, d_, 0.13), (KX + x, KY + y, 0.08 + p * 0.15), "wood", (0, 0, 0), bevel=0.008)
box("CrateBottom", (0.66, 0.5, 0.03), (KX, KY, 0.03), "wood")
for i in range(26):
    rock("CoalLump", random.uniform(0.05, 0.085), (KX + random.uniform(-0.27, 0.27), KY + random.uniform(-0.2, 0.2), 0.38 + random.uniform(0, 0.12)), "coal", 0.35)
for i in range(7):
    rock("CoalSpill", random.uniform(0.04, 0.06), (KX + random.uniform(-0.6, -0.4), KY + random.uniform(-0.3, 0.2), 0.03), "coal", 0.35)
# пара брошенных кирпичей и щипцы
box("LooseBrick", (0.25, 0.12, 0.065), (1.4, 0.35, 0.033), "brick", (0, 0, 1.2), bevel=0.01)
box("LooseBrick", (0.25, 0.12, 0.065), (1.45, 0.62, 0.033), "brick", (0, 0, 2.0), bevel=0.01)
for s in (-1, 1):
    cyl("TongArm", 0.012, 0.7, (-0.15 + s * 0.02, -1.55, 0.015), "iron", (math.pi / 2, 0, math.radians(70 + s * 4)), 8)

# ---------- свет топки ----------
bpy.ops.object.light_add(type='POINT', location=(0, -B_W0 / 2 + 0.2, OZ0 + 0.3))
fl = bpy.context.object; fl.name = "FireLight"; fl.data.energy = 120; fl.data.color = (1.0, 0.55, 0.2); fl.data.shadow_soft_size = 0.2
link(fl)
bpy.ops.object.light_add(type='POINT', location=(MX, MY, 0.35))
ml = bpy.context.object; ml.data.energy = 25; ml.data.color = (1.0, 0.6, 0.25); link(ml)

# ---------- сцена: земля, солнце, небо, камеры ----------
bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0)); g = bpy.context.object; g.name = "Ground"
finish(g, "ground", c=col_env)
bpy.ops.mesh.primitive_circle_add(radius=2.6, fill_type='NGON', location=(0, -0.2, 0.004), vertices=48); dd = bpy.context.object; dd.name = "TroddenDirt"
finish(dd, "dirt", c=col_env)
bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), math.radians(10), math.radians(-35)))
sun = bpy.context.object; sun.data.energy = 3.2; sun.data.angle = math.radians(3); link(sun, col_env)
w = bpy.data.worlds.new("Sky"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs["Color"].default_value = (0.55, 0.65, 0.78, 1); bg.inputs["Strength"].default_value = 0.9

def camera(name, loc, target, lens=40):
    bpy.ops.object.camera_add(location=loc); c = bpy.context.object; c.name = name; c.data.lens = lens
    c.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    link(c, col_env); return c

cams = {
    "front34": camera("CamFront34", (-4.9, -7.0, 3.4), (0, 0, 1.6), 38),
    "side": camera("CamBack34", (5.6, 6.0, 3.2), (0, 0.3, 1.6), 38),
    "game": camera("CamGameIso", (-7.0, -7.0, 7.4), (0, 0, 0.9), 50),
}
sc.camera = cams["front34"]

# сбор статистики
tris = 0
dg = bpy.context.evaluated_depsgraph_get()
for o in col_main.objects:
    if o.type == 'MESH':
        e = o.evaluated_get(dg); me = e.to_mesh(); me.calc_loop_triangles(); tris += len(me.loop_triangles); e.to_mesh_clear()
print("OBJECTS", len(col_main.objects), "TRIS", tris)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_ROOT, "smelter.blend"))

# экспорт в glTF для Godot (только печь)
for o in bpy.context.view_layer.objects: o.select_set(o.name in col_main.objects and o.type == 'MESH')
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_ROOT, "smelter.glb"), use_selection=True, export_apply=True)

if "--render" in sys.argv:
    r = sc.render; r.engine = 'CYCLES'; sc.cycles.device = 'CPU'
    sc.cycles.samples = int(sys.argv[sys.argv.index("--render") + 1]) if len(sys.argv) > sys.argv.index("--render") + 1 else 48
    sc.cycles.use_denoising = True
    r.resolution_x, r.resolution_y = 1280, 960
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
    for k, c in cams.items():
        sc.camera = c; r.filepath = os.path.join(OUT_ROOT, f"render_{k}.png")
        bpy.ops.render.render(write_still=True); print("RENDERED", k)

# =====================================================================
# Запекание для игры: python3 build_furnace.py --bake [размер]
# Все непрозрачные детали -> один меш с атласом (цвет, нормали, ORM),
# светящиеся (огонь, угли, металл) -> отдельный меш без текстур.
# =====================================================================
if "--bake" in sys.argv:
    i = sys.argv.index("--bake")
    SIZE = int(sys.argv[i + 1]) if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit() else 2048
    OUT = os.path.join(OUT_ROOT, "bake")
    import os; os.makedirs(OUT, exist_ok=True)
    GLOW_MATS = {"Ember", "FireBack", "Molten"}
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [o for o in col_main.objects if o.type == 'MESH']
    # применяем модификаторы и трансформации, отвязываем от родителей
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        if o.parent:
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
        for md in list(o.modifiers):
            if md.type == 'SUBSURF':
                md.levels = 1
            bpy.ops.object.modifier_apply(modifier=md.name)
        o.select_set(False)
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action='DESELECT')
    # у всех мешей должен быть слой UVMap (для кирпича), даже нулевой
    for o in meshes:
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
        o.data.uv_layers[0].name = "UVMap"
    # убираем невидимые нижние грани (на земле, на цоколе, под венцом) — экономим атлас
    hidden_z = (0.0, Z_B0, Z_B1, Z_S0)
    for o in meshes:
        bm = bmesh.new(); bm.from_mesh(o.data)
        kill = [f for f in bm.faces if f.normal.z < -0.95 and any(abs(f.calc_center_median().z - hz) < 0.03 for hz in hidden_z)]
        if kill and len(kill) < len(bm.faces):
            bmesh.ops.delete(bm, geom=kill, context='FACES')
            bm.to_mesh(o.data)
        bm.free()
    glow = [o for o in meshes if o.data.materials and o.data.materials[0].name in GLOW_MATS]
    solid = [o for o in meshes if o not in glow]
    def join(objs, name):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs: o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        j = bpy.context.object; j.name = name; j.data.name = name
        return j
    body = join(solid, "SmelterBody")
    glow_o = join(glow, "SmelterGlow")
    # автоматическая развёртка под атлас — второй UV-слой
    bake_uv = body.data.uv_layers.new(name="BakeUV")
    body.data.uv_layers.active = bake_uv
    body.data.uv_layers["UVMap"].active_render = True
    bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 4
    imgs = {}
    def target(name, non_color):
        img = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
        if non_color: img.colorspace_settings.name = 'Non-Color'
        imgs[name] = img
        for m in body.data.materials:
            if m is None: continue
            nt = m.node_tree
            n = nt.nodes.get("BakeTarget") or nt.nodes.new("ShaderNodeTexImage")
            n.name = "BakeTarget"; n.image = img
            for x in nt.nodes: x.select = False
            n.select = True; nt.nodes.active = n
        return img
    def bake(kind, **kw):
        bpy.ops.object.bake(type=kind, margin=6, use_clear=True, **kw)
    t = target("smelter_albedo", False)
    bake('DIFFUSE', pass_filter={'COLOR'})
    t.filepath_raw = f"{OUT}/smelter_albedo.png"; t.file_format = 'PNG'; t.save()
    t = target("smelter_normal", True)
    bake('NORMAL', normal_space='TANGENT')
    t.filepath_raw = f"{OUT}/smelter_normal.png"; t.file_format = 'PNG'; t.save()
    t = target("smelter_roughness", True)
    bake('ROUGHNESS')
    t.filepath_raw = f"{OUT}/smelter_roughness.png"; t.file_format = 'PNG'; t.save()
    # металличность: временно выводим значение Metallic в эмиссию
    saved = []
    for m in body.data.materials:
        if m is None: continue
        b = m.node_tree.nodes["Principled BSDF"]
        val = b.inputs["Metallic"].default_value
        saved.append((b, b.inputs["Emission Color"].default_value[:], b.inputs["Emission Strength"].default_value))
        b.inputs["Emission Color"].default_value = (val, val, val, 1); b.inputs["Emission Strength"].default_value = 1.0
    t = target("smelter_metallic", True)
    bake('EMIT')
    t.filepath_raw = f"{OUT}/smelter_metallic.png"; t.file_format = 'PNG'; t.save()
    for b, c, st in saved:
        b.inputs["Emission Color"].default_value = c; b.inputs["Emission Strength"].default_value = st
    # экспорт геометрии: только BakeUV, один материал
    body.data.uv_layers.remove(body.data.uv_layers["UVMap"])
    atlas = bpy.data.materials.new("SmelterAtlas")
    body.data.materials.clear(); body.data.materials.append(atlas)
    for o in (glow_o,):
        o.data.materials.clear(); o.data.materials.append(M["molten"])
        while o.data.uv_layers: o.data.uv_layers.remove(o.data.uv_layers[0])
    for p in body.data.polygons: pass
    bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); glow_o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/smelter_game.glb", use_selection=True, export_apply=True,
                              export_materials='PLACEHOLDER', export_tangents=False)
    dg = bpy.context.evaluated_depsgraph_get()
    for o in (body, glow_o):
        o.data.calc_loop_triangles(); print("BAKED", o.name, "tris", len(o.data.loop_triangles), "verts", len(o.data.vertices))
    bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/smelter_baked.blend")
