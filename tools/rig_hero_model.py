"""Главный герой «Шахтёр» из присланной AI-модели (статичный меш ~1.5 млн треугольников).

Что делает (Blender 4.x/5.x, bpy):
  1. импортирует исходный GLB, сваривает вершины;
  2. отделяет кирку (рукоять-цилиндр + головку) и закрывает дыры в кулаке;
  3. масштабирует героя до роста 4.85 ед. (как прежний шахтёр: в player.tscn масштаб 0.36 -> ~1.75 м);
  4. делает игровую low-poly копию (тело ~16k треугольников, кирка ~1.5k), новую UV-развёртку
     и запекает с high-poly цвет/нормали/шероховатость/металл (тело 2048/1024, кирка 512);
  5. строит скелет с именами костей прежнего шахтёра (Hip, Spine1/2, Neck, Head, Clavicle/
     Forearm(=плечо)/Arm(=предплечье)/Hand, пальцы, Thigh/Calf/Foot/Toe, ToolSocket.R),
     автоматически взвешивает тело (bone heat) и правит веса по зонам (каска, рюкзак, ноги, кисти);
  6. экспортирует <OUT>/hero_rigged.gltf (тело + каска, skinned) и <OUT>/hero_pickaxe.gltf
     (кирка в системе сокета хвата, метры: +Y — рукоять к головке, +X — к лезвию) + PNG текстур.
     (glTF со встроенным буфером; промежуточные файлы, в репозиторий не входят).
Дальше: godot --headless --path . -s tools/retarget_ual_to_miner.gd -- --hero <OUT> --textures

Запуск: HERO_SRC=<исходный.glb> HERO_OUT=/data/hero python3 tools/rig_hero_model.py [--bake 2048] [--preview]
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

SRC = os.environ.get("HERO_SRC", "hero_source.glb")
OUT = os.environ.get("HERO_OUT", os.path.abspath("hero_build"))
os.makedirs(OUT, exist_ok=True)
TEX = 2048
if "--bake" in sys.argv:
    i = sys.argv.index("--bake")
    if len(sys.argv) > i + 1 and sys.argv[i + 1].isdigit():
        TEX = int(sys.argv[i + 1])
BODY_TRIS = int(os.environ.get("HERO_BODY_TRIS", "16000"))
PICK_TRIS = int(os.environ.get("HERO_PICK_TRIS", "1500"))
HEIGHT = 4.85          # рост в единицах модели (как у прежнего шахтёра)
MODEL_UNIT_M = 0.36    # масштаб CharacterModel в player.tscn
HELMET_Z = 0.875       # низ полей каски (в исходных единицах, рост 1.027)

# ---------------------------------------------------------------------------
# Ориентиры исходной модели (Blender: Z вверх, герой смотрит в -Y, его правая рука — -X).
# Сняты по сечениям меша; в исходных единицах (рост 1.027).
XC = 0.012
J = {
    "Hip": (XC, 0.0, 0.34), "Spine1": (XC, 0.0, 0.45), "Spine2": (XC, 0.0, 0.60),
    "Neck": (XC, 0.0, 0.76), "Head": (XC, -0.005, 0.81), "HeadTop": (XC, -0.005, 1.0),
    "Clavicle.r": (XC - 0.04, 0.0, 0.72), "Clavicle.l": (XC + 0.04, 0.0, 0.72),
    "Forearm.r": (-0.145, 0.01, 0.69), "Forearm.l": (0.165, 0.01, 0.69),     # плечо
    "Arm.r": (-0.19, 0.0, 0.53), "Arm.l": (0.205, 0.0, 0.53),                # локоть
    "Hand.r": (-0.20, -0.01, 0.41), "Hand.l": (0.215, -0.01, 0.42),          # запястье
    "HandEnd.r": (-0.195, 0.0, 0.335), "HandEnd.l": (0.227, -0.03, 0.31),
    "Thigh.r": (-0.07, 0.0, 0.32), "Thigh.l": (0.10, 0.0, 0.32),
    "Calf.r": (-0.092, -0.005, 0.19), "Calf.l": (0.123, -0.005, 0.19),
    "Foot.r": (-0.106, 0.0, 0.09), "Foot.l": (0.136, 0.0, 0.09),
    "Toe.r": (-0.108, -0.06, 0.025), "Toe.l": (0.138, -0.06, 0.025),
    "ToeEnd.r": (-0.108, -0.10, 0.02), "ToeEnd.l": (0.138, -0.10, 0.02),
}
# Ось рукояти кирки: x(y), z(y) — прямая через центры сечений черенка.
AX_X = (-0.1737, -0.0362)
AX_Z = (0.3553, -0.0199)
HANDLE_R = 0.026
FIST_C = Vector((-0.195, 0.0, 0.37))


def log(*a):
    print("[hero]", *a, flush=True)


def axis_pt(y):
    return Vector((AX_X[0] + AX_X[1] * y, y, AX_Z[0] + AX_Z[1] * y))


def active(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def flat_mat(name, rgb, rough=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    return m


# ===========================================================================
# 1. Импорт и сварка
# ===========================================================================
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
src = [o for o in sc.objects if o.type == 'MESH'][0]
for o in list(sc.objects):
    if o is not src:
        bpy.data.objects.remove(o)
src.parent = None
active(src)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bm = bmesh.new(); bm.from_mesh(src.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0002)
log("welded verts", len(bm.verts))

# ===========================================================================
# 2. Кирка: цилиндр рукояти (вдоль всей длины, сквозь кулак) + головка перед героем
# ===========================================================================
def is_pick(co):
    # головка и передняя часть рукояти — всё перед корпусом справа
    if co.y < -0.16 and co.x < -0.05 and co.z > 0.1:
        return True
    if -0.16 <= co.y < 0.26:
        a = axis_pt(co.y)
        r = math.hypot(co.x - a.x, co.z - a.z)
        if -0.095 < co.y < 0.06:
            return r < HANDLE_R           # внутри кулака — только сам черенок
        return r < (0.055 if co.y > 0.16 else 0.033)   # вне кулака (у торца — набалдашник)
    return False

pick_v = {v.index for v in bm.verts if is_pick(v.co)}
pick_f = [f for f in bm.faces if all(v.index in pick_v for v in f.verts)]
log("pickaxe faces", len(pick_f))
bm_p = bm.copy()
bm_p.faces.ensure_lookup_table()
keep_p = {f.index for f in pick_f}
bmesh.ops.delete(bm_p, geom=[f for f in bm_p.faces if f.index not in keep_p], context='FACES')
bmesh.ops.delete(bm, geom=pick_f, context='FACES')
for b_ in (bm, bm_p):
    loose = [v for v in b_.verts if not v.link_faces]
    bmesh.ops.delete(b_, geom=loose, context='VERTS')

def close_holes(b_, mat_index, max_edges=400):
    edges = [e for e in b_.edges if e.is_boundary]
    n0 = len(b_.faces)
    res = bmesh.ops.holes_fill(b_, edges=edges, sides=max_edges)
    for f in res["faces"]:
        f.material_index = mat_index
    return len(res["faces"])

body = src
body.name = "Body_HP"
glove = flat_mat("HoleFill_Glove", (0.78, 0.52, 0.08), 0.75)
wood = flat_mat("HoleFill_Wood", (0.36, 0.22, 0.12), 0.8)
body.data.materials.append(glove)
nf = close_holes(bm, 1)
bm.to_mesh(body.data); bm.free()
pick = bpy.data.objects.new("Pickaxe_HP", bpy.data.meshes.new("Pickaxe_HP"))
sc.collection.objects.link(pick)
for m in body.data.materials:
    pick.data.materials.append(m)
pick.data.materials.append(wood)
np_ = close_holes(bm_p, 2)
bm_p.to_mesh(pick.data); bm_p.free()
log("holes filled body", nf, "pickaxe", np_)

# ===========================================================================
# 3. Масштаб: рост HEIGHT
# ===========================================================================
S = HEIGHT / max(v.co.z for v in body.data.vertices)
log("scale", S)
for o in (body, pick):
    o.data.transform(Matrix.Scale(S, 4))
J = {k: Vector(v) * S for k, v in J.items()}
FIST_C *= S

def axis_pt_s(y_s):
    return axis_pt(y_s / S) * S

# ===========================================================================
# 4. Low-poly + развёртка
# ===========================================================================
def lowpoly(hp, name, target):
    lp = hp.copy(); lp.data = hp.data.copy(); lp.name = name; lp.data.name = name
    sc.collection.objects.link(lp)
    active(lp)
    md = lp.modifiers.new("dec", 'DECIMATE')
    md.ratio = min(1.0, target / tris(hp))
    md.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
    for l in list(lp.data.uv_layers):
        lp.data.uv_layers.remove(l)
    lp.data.uv_layers.new(name="UV")
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    lp.data.materials.clear()
    log(name, "tris", tris(lp))
    return lp

body_lp = lowpoly(body, "Miner_Body", BODY_TRIS)
pick_lp = lowpoly(pick, "Pickaxe", PICK_TRIS)

# ===========================================================================
# 5. Запекание high -> low
# ===========================================================================
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'
sc.render.bake.margin = 8
sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = 0.03 * S / 4.7
sc.render.bake.max_ray_distance = 0.12 * S / 4.7

def prep_metal_emission(mats):
    for m in mats:
        b = m.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        lk = b.inputs["Metallic"].links
        for l in list(b.inputs["Emission Color"].links):
            m.node_tree.links.remove(l)
        if lk:
            m.node_tree.links.new(lk[0].from_socket, b.inputs["Emission Color"])
        else:
            v = b.inputs["Metallic"].default_value
            b.inputs["Emission Color"].default_value = (v, v, v, 1)
        b.inputs["Emission Strength"].default_value = 1.0

def clear_emission(mats):
    for m in mats:
        b = m.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        for l in list(b.inputs["Emission Color"].links):
            m.node_tree.links.remove(l)
        b.inputs["Emission Strength"].default_value = 0.0

def bake_set(hp, lp, pre, size, nsize):
    tmp = bpy.data.materials.new(pre + "_bake"); tmp.use_nodes = True
    lp.data.materials.clear(); lp.data.materials.append(tmp)
    node = tmp.node_tree.nodes.new("ShaderNodeTexImage")
    tmp.node_tree.nodes.active = node
    def run(kind, suffix, s, non_color, samples, **kw):
        img = bpy.data.images.new(pre + suffix, s, s, alpha=False)
        if non_color:
            img.colorspace_settings.name = 'Non-Color'
        node.image = img
        sc.cycles.samples = samples
        bpy.ops.object.select_all(action='DESELECT')
        hp.select_set(True); lp.select_set(True)
        bpy.context.view_layer.objects.active = lp
        bpy.ops.object.bake(type=kind, use_clear=True, **kw)
        img.filepath_raw = os.path.join(OUT, pre + suffix + ".png"); img.file_format = 'PNG'; img.save()
        log("baked", pre + suffix)
    run('DIFFUSE', "_albedo", size, False, 4, pass_filter={'COLOR'})
    run('NORMAL', "_normal", nsize, True, 4, normal_space='TANGENT')
    run('ROUGHNESS', "_roughness", nsize, True, 2)
    mats = [m for m in hp.data.materials if m]
    prep_metal_emission(mats)
    run('EMIT', "_metallic", nsize, True, 1)
    clear_emission(mats)
    lp.data.materials.clear()
    lp.data.materials.append(bpy.data.materials.new(pre + "_material"))

if "--bake" in sys.argv:
    bake_set(body, body_lp, "hero_body", TEX, TEX // 2)
    bake_set(pick, pick_lp, "hero_pickaxe", TEX // 4, TEX // 4)
else:
    body_lp.data.materials.append(bpy.data.materials.new("hero_body_material"))
    pick_lp.data.materials.append(bpy.data.materials.new("hero_pickaxe_material"))

# ===========================================================================
# 6. Скелет (имена — как у прежнего шахтёра miner_ready_fixed.glb)
# ===========================================================================
arm_data = bpy.data.armatures.new("HeroArmature")
arm = bpy.data.objects.new("HeroArmature", arm_data)
sc.collection.objects.link(arm)
active(arm)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None, deform=True, connect=False, roll_z=None):
    b = eb.new(name)
    b.head = head; b.tail = tail
    if (b.tail - b.head).length < 1e-4:
        b.tail = b.head + Vector((0, 0, 0.05))
    if parent:
        b.parent = eb[parent]; b.use_connect = connect
    b.use_deform = deform
    if roll_z is not None:
        b.align_roll(roll_z)
    return b

F = Vector((0, -1, 0))  # вперёд
bone("Hip", J["Hip"], J["Spine1"], roll_z=F)
bone("Spine1", J["Spine1"], J["Spine2"], "Hip", roll_z=F)
bone("Spine2", J["Spine2"], J["Neck"], "Spine1", roll_z=F)
bone("Neck", J["Neck"], J["Head"], "Spine2", roll_z=F)
bone("Head", J["Head"], J["HeadTop"], "Neck", roll_z=F)
for s in ("l", "r"):
    bone("Clavicle." + s, J["Clavicle." + s], J["Forearm." + s], "Spine2", roll_z=F)
    bone("Forearm." + s, J["Forearm." + s], J["Arm." + s], "Clavicle." + s, roll_z=F)
    bone("Arm." + s, J["Arm." + s], J["Hand." + s], "Forearm." + s, roll_z=F)
    wrist = J["Hand." + s]; end = J["HandEnd." + s]
    d = (end - wrist).normalized()
    k = (F - d * F.dot(d)).normalized()          # линия костяшек: мизинец -> указательный (вперёд)
    side = d.cross(k).normalized()
    hl = (end - wrist).length
    knuck = wrist + d * hl * 0.62
    bone("Hand." + s, wrist, knuck, "Arm." + s, roll_z=k)
    ph = hl * 0.16
    for fi, (fname, off) in enumerate((("Index", 1.0), ("Middle", 0.33), ("Ring", -0.33), ("Pinky", -1.0))):
        base = knuck + k * off * hl * 0.17 - d * abs(off) * hl * 0.05
        prev = "Hand." + s
        for j in (1, 2, 3):
            h = base + d * ph * (j - 1); t = base + d * ph * j
            bone(f"{fname}{j}.{s}", h, t, prev, deform=False, roll_z=k)
            prev = f"{fname}{j}.{s}"
    tb = wrist + d * hl * 0.3 + k * hl * 0.3
    bone("Thumb1." + s, tb, tb + (d + k).normalized() * ph, "Hand." + s, deform=False, roll_z=k)
    bone("Thumb2." + s, tb + (d + k).normalized() * ph, tb + (d + k).normalized() * ph * 2, "Thumb1." + s, deform=False, roll_z=k)
    bone("Thigh." + s, J["Thigh." + s], J["Calf." + s], "Hip", roll_z=F)
    bone("Calf." + s, J["Calf." + s], J["Foot." + s], "Thigh." + s, roll_z=F)
    bone("Foot." + s, J["Foot." + s], J["Toe." + s], "Calf." + s, roll_z=Vector((0, 0, 1)))
    bone("Toe." + s, J["Toe." + s], J["ToeEnd." + s], "Foot." + s, roll_z=Vector((0, 0, 1)))

# Сокет хвата: начало — на оси рукояти у центра кулака; рамка X — к лезвию (по направлению
# запястье -> костяшки), Y — по рукояти к головке, Z = X x Y. Оси кости glTF-импорт Godot
# переносит как есть (Godot X,Y,Z = Blender X,Y,Z кости после Z-up -> Y-up), поэтому кость
# направлена вдоль рукояти (Y) с креном, при котором её Z совпадает с pz.
g0 = axis_pt_s(FIST_C.y)
py = (axis_pt_s(-0.6 * S) - axis_pt_s(0.2 * S)).normalized()
d_r = (J["HandEnd.r"] - J["Hand.r"]).normalized()
px = (d_r - py * d_r.dot(py)).normalized()
pz = px.cross(py).normalized()
sb = bone("ToolSocket.R", g0, g0 + py * 0.3, "Hand.r", deform=False, roll_z=pz)
bpy.ops.object.mode_set(mode='OBJECT')
SOCKET = Matrix((px, py, pz)).transposed().to_4x4(); SOCKET.translation = g0
log("socket origin", tuple(round(c, 3) for c in g0), "py", tuple(round(c, 3) for c in py), "px", tuple(round(c, 3) for c in px))
bx = arm.data.bones["ToolSocket.R"].matrix_local.to_3x3()
log("socket bone axes X·px=%.3f Y·py=%.3f Z·pz=%.3f" % (bx.col[0].dot(px), bx.col[1].dot(py), bx.col[2].dot(pz)))

# ===========================================================================
# 7. Веса: bone heat + правки по зонам
# ===========================================================================
active(body_lp); arm.select_set(True); bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
body_lp.select_set(False)
deform = [b.name for b in arm.data.bones if b.use_deform]
vg = {g.name: g for g in body_lp.vertex_groups}
for n in deform:
    if n not in vg:
        vg[n] = body_lp.vertex_groups.new(name=n)
gi = {g.index: g.name for g in body_lp.vertex_groups}
nv = len(body_lp.data.vertices)
W = np.zeros((nv, len(deform)))
col = {n: i for i, n in enumerate(deform)}
for v in body_lp.data.vertices:
    for g in v.groups:
        n = gi.get(g.group)
        if n in col:
            W[v.index, col[n]] = g.weight
CO = np.array([v.co[:] for v in body_lp.data.vertices]) / S   # исходные единицы
zero = (W.sum(1) < 1e-4).sum()
log("bone heat: unweighted verts", int(zero), "of", nv)

def seg_dist(p, a, b):
    ab = b - a; t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)

TAIL = {b.name: (np.array(b.head_local) / S, np.array(b.tail_local) / S) for b in arm.data.bones}
def bones_mask(names):
    m = np.zeros(len(deform), bool)
    for n in names:
        m[col[n]] = True
    return m

def restrict(sel, allowed, fallback_dist=True):
    """Оставить у вершин sel только кости allowed; если весов не осталось — по расстоянию до костей."""
    m = bones_mask(allowed)
    W[np.ix_(sel, ~m)] = 0.0
    empty = sel & (W.sum(1) < 1e-4)
    if empty.any() and fallback_dist:
        idx = np.where(empty)[0]
        D = np.stack([seg_dist(CO[idx], *TAIL[n]) for n in allowed], 1)
        w = 1.0 / np.maximum(D, 0.004) ** 4
        w /= w.sum(1, keepdims=True)
        for j, n in enumerate(allowed):
            W[idx, col[n]] = w[:, j]

x, y, z = CO[:, 0], CO[:, 1], CO[:, 2]
dx = x - XC
side_l = dx > 0
ARM = lambda s: ["Clavicle." + s, "Forearm." + s, "Arm." + s, "Hand." + s]
LEG = lambda s: ["Thigh." + s, "Calf." + s, "Foot." + s, "Toe." + s]
TORSO = ["Hip", "Spine1", "Spine2", "Neck"]
# каска — жёстко на голове
helmet = z > HELMET_Z
restrict(helmet, ["Head"])
# голова/лицо
restrict((z > 0.80) & ~helmet & (np.abs(dx) < 0.14), ["Head", "Neck"])
# рюкзак — жёстко на корпусе
pack = (y > 0.085) & (z > 0.38) & (z < 0.84) & (np.abs(dx) < 0.2)
restrict(pack, ["Spine2", "Spine1"])
# кисти/перчатки — только кости своей руки
for s, sgn in (("r", -1), ("l", 1)):
    hand = (sgn * dx > 0.15) & (z < 0.47) & (z > 0.27)
    restrict(hand, ["Hand." + s, "Arm." + s])
    W[hand & (z < 0.40), col["Arm." + s]] *= 0.0
# ноги ниже паха — только кости своей ноги
crotch = 0.29
for s, m_ in (("l", side_l), ("r", ~side_l)):
    leg = m_ & (z < crotch) & (np.abs(dx) < 0.17)
    restrict(leg, LEG(s) + (["Hip"] if True else []))
    W[leg & (z < 0.24), col["Hip"]] = 0.0
# корпус (кроме рук) не берёт веса рук ниже плеч
torso = (np.abs(dx) < 0.12) & (z > crotch) & (z < 0.64) & ~pack
restrict(torso, TORSO + LEG("l")[:1] + LEG("r")[:1])
# не больше 4 влияний, нормировка
order = np.argsort(-W, 1)
for i in range(nv):
    W[i, order[i, 4:]] = 0.0
s_ = W.sum(1, keepdims=True); s_[s_ < 1e-8] = 1.0
W /= s_
for n in deform:
    g = vg[n]
    g.remove(range(nv))
    j = col[n]
    for i in np.where(W[:, j] > 1e-4)[0]:
        g.add([int(i)], float(W[i, j]), 'REPLACE')
# сглаживание весов
active(body_lp)
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=2, expand=0.0)
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
# После сглаживания снова фиксируем жёсткие зоны (каска, рюкзак).
for v in body_lp.data.vertices:
    p = CO[v.index]
    if p[2] > HELMET_Z:
        for g in list(v.groups):
            body_lp.vertex_groups[g.group].remove([v.index])
        vg["Head"].add([v.index], 1.0, 'REPLACE')

# Каска — отдельный skinned меш (player.gd: set_hat_visible).
active(body_lp)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')
for p in body_lp.data.polygons:
    p.select = bool(all(CO[vi][2] > HELMET_Z - 0.004 for vi in p.vertices) and sum(CO[vi][2] for vi in p.vertices) / len(p.vertices) > HELMET_Z)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.separate(type='SELECTED'); bpy.ops.object.mode_set(mode='OBJECT')
helm = [o for o in sc.objects if o.name.startswith("Miner_Body.")][0]
helm.name = "Character_Helmet"; helm.data.name = "Character_Helmet"
log("helmet tris", tris(helm), "body tris", tris(body_lp))

# ===========================================================================
# 8. Кирка в системе сокета (метры). Вершина (lx,ly,lz) пишется как (lx,-lz,ly):
#    glTF-экспорт переводит Blender (x,y,z) -> (x,z,-y), и в Godot получаются (lx,ly,lz).
# ===========================================================================
inv = SOCKET.inverted()
conv = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
pick_lp.data.transform(conv @ Matrix.Scale(MODEL_UNIT_M, 4) @ inv)
pick_lp.data.update()

# ===========================================================================
# 9. Экспорт
# ===========================================================================
for o in (body_lp, helm):
    for md in o.modifiers:
        if md.type == 'ARMATURE':
            md.object = arm
bpy.ops.object.select_all(action='DESELECT')
for o in (arm, body_lp, helm):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hero_rigged.glb"), use_selection=True,
                          export_materials='PLACEHOLDER', export_animations=False, export_skins=True,
                          export_tangents=False, export_yup=True)
bpy.ops.object.select_all(action='DESELECT')
pick_lp.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hero_pickaxe.glb"), use_selection=True,
                          export_materials='PLACEHOLDER', export_animations=False, export_tangents=False, export_yup=True)
def glb_to_gltf(name):
    """GLB -> .gltf со встроенным base64-буфером (в Blender 5 нет GLTF_EMBEDDED)."""
    import json, struct, base64
    d = open(os.path.join(OUT, name + ".glb"), "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + n]); o = 20 + n
    bl = struct.unpack("<I", d[o:o + 4])[0]
    js["buffers"][0]["uri"] = "data:application/octet-stream;base64," + base64.b64encode(
        d[o + 8:o + 8 + bl][:js["buffers"][0]["byteLength"]]).decode()
    with open(os.path.join(OUT, name + ".gltf"), "w") as f:
        json.dump(js, f, separators=(",", ":"))
glb_to_gltf("hero_rigged"); glb_to_gltf("hero_pickaxe")
for o in (body, pick):
    bpy.data.objects.remove(o)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "hero_rigged.blend"))
log("EXPORT OK", OUT)
