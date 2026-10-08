extends SceneTree

## Запекает модель главного героя (ready-шахтёр) с ПРАВИЛЬНО ретаргетированными
## анимациями Universal Animation Library 1/2 (Quaternius, CC0)
## в самодостаточную scenes/player/miner_package_model.tscn.
##
## Почему не работало раньше:
##  * родные клипы miner_ready.glb (Iddle01/Walk/Mine) двигают в основном IK-контроллеры
##    (Footik/Handik). IK-констрейнты Blender в glTF не экспортируются, поэтому в Godot
##    ноги/руки стояли на месте — «анимаций нет»;
##  * UAL-клипы копировались как локальные кватернионы 1:1, хотя у скелетов разные
##    rest-позы (T-pose vs A-pose) и оси костей — ретаргет давал мусор и не использовался.
##
## Что делает этот инструмент:
##  1. Ретаргет в мировом пространстве: для каждой пары костей строится
##     «анатомический» базис (направление на дочернюю кость + боковой/передний вектор),
##     корректирующий разницу rest-поз; дельта вращения источника переносится на героя.
##     Смещение таза масштабируется по высоте таза.
##  2. Нерабочие IK-клипы удаляются, в AnimationPlayer остаются только логические клипы
##     idle/walk/run/jog/mine/chop/dig/scoop/water/plant/harvest/eat/interact/... .
##  3. Добавляется кость ToolSocket.R (дочерняя к Hand.r, ось рукояти +Y, лезвие +X,
##     масштаб в метрах) и BoneAttachment3D «ToolSocket_R» — к нему player.gd цепляет
##     топор/лопату/ведро.
##  4. Встроенная в меш кирка отделяется в собственный MeshInstance3D «Pickaxe» на сокете,
##     чтобы её можно было скрывать при смене инструмента.
##
## Запуск (из корня проекта):
##   Godot --headless --path . -s tools/retarget_ual_to_miner.gd
##   Godot --headless --path . -s tools/retarget_ual_to_miner.gd -- --probe   (метрики клипов)

const MINER_GLB := "res://assets/models/character/miner_ready_fixed.glb"
const UAL1_GLB := "res://assets/models/character/UAL1_Standard.glb"
const UAL2_GLB := "res://assets/models/character/UAL2_Standard.glb"
const OUT_SCENE := "res://scenes/player/miner_package_model.tscn"
## Текстура героя — ссылкой на импортированный PNG вместо 16 МБ встроенного Image.
const MINER_TEXTURE := "res://assets/models/character/miner_ready_RGB_Alpha.png"
## Библиотека клипов — отдельным ресурсом (сцена остаётся лёгкой, клипы можно переиспользовать).
const OUT_LIBRARY := "res://assets/animations/miner_ual_animations.tres"
const FPS := 30.0
## Масштаб CharacterModel в player.tscn (0.36): 1 ед. модели = 0.36 м.
const MODEL_UNIT_M := 0.36

# Пары: кость героя -> кость UAL.
const BONE_MAP: Dictionary = {
	"Hip": "pelvis",
	"Spine1": "spine_01",
	"Spine2": "spine_03",
	"Neck": "neck_01",
	"Head": "Head",
	"Clavicle.l": "clavicle_l", "Forearm.l": "upperarm_l", "Arm.l": "lowerarm_l", "Hand.l": "hand_l",
	"Clavicle.r": "clavicle_r", "Forearm.r": "upperarm_r", "Arm.r": "lowerarm_r", "Hand.r": "hand_r",
	"Thigh.l": "thigh_l", "Calf.l": "calf_l", "Foot.l": "foot_l", "Toe.l": "ball_l",
	"Thigh.r": "thigh_r", "Calf.r": "calf_r", "Foot.r": "foot_r", "Toe.r": "ball_r",
	"Index1.l": "index_01_l", "Index2.l": "index_02_l", "Index3.l": "index_03_l",
	"Middle1.l": "middle_01_l", "Middle2.l": "middle_02_l", "Middle3.l": "middle_03_l",
	"Ring1.l": "ring_01_l", "Ring2.l": "ring_02_l", "Ring3.l": "ring_03_l",
	"Pinky1.l": "pinky_01_l", "Pinky2.l": "pinky_02_l", "Pinky3.l": "pinky_03_l",
	"Thumb1.l": "thumb_01_l", "Thumb2.l": "thumb_02_l",
	"Index1.r": "index_01_r", "Index2.r": "index_02_r", "Index3.r": "index_03_r",
	"Middle1.r": "middle_01_r", "Middle2.r": "middle_02_r", "Middle3.r": "middle_03_r",
	"Ring1.r": "ring_01_r", "Ring2.r": "ring_02_r", "Ring3.r": "ring_03_r",
	"Pinky1.r": "pinky_01_r", "Pinky2.r": "pinky_02_r", "Pinky3.r": "pinky_03_r",
	"Thumb1.r": "thumb_01_r", "Thumb2.r": "thumb_02_r",
}

# Кость -> [дочерняя кость героя для направления, дочерняя кость UAL, тип вторичного вектора]
# Вторичный вектор: "L" — влево по телу, "F" — вперёд, "K_l"/"K_r" — линия костяшек кисти.
const AIM: Dictionary = {
	"Hip": ["Spine1", "spine_01", "L"],
	"Spine1": ["Spine2", "spine_03", "L"],
	"Spine2": ["Neck", "neck_01", "L"],
	"Neck": ["Head", "Head", "L"],
	"Clavicle.l": ["Forearm.l", "upperarm_l", "F"], "Forearm.l": ["Arm.l", "lowerarm_l", "F"], "Arm.l": ["Hand.l", "hand_l", "F"],
	"Clavicle.r": ["Forearm.r", "upperarm_r", "F"], "Forearm.r": ["Arm.r", "lowerarm_r", "F"], "Arm.r": ["Hand.r", "hand_r", "F"],
	"Hand.l": ["Middle1.l", "middle_01_l", "K_l"], "Hand.r": ["Middle1.r", "middle_01_r", "K_r"],
	"Thigh.l": ["Calf.l", "calf_l", "F"], "Calf.l": ["Foot.l", "foot_l", "F"], "Foot.l": ["Toe.l", "ball_l", "L"],
	"Thigh.r": ["Calf.r", "calf_r", "F"], "Calf.r": ["Foot.r", "foot_r", "F"], "Foot.r": ["Toe.r", "ball_r", "L"],
	"Index1.l": ["Index2.l", "index_02_l", "K_l"], "Index2.l": ["Index3.l", "index_03_l", "K_l"],
	"Middle1.l": ["Middle2.l", "middle_02_l", "K_l"], "Middle2.l": ["Middle3.l", "middle_03_l", "K_l"],
	"Ring1.l": ["Ring2.l", "ring_02_l", "K_l"], "Ring2.l": ["Ring3.l", "ring_03_l", "K_l"],
	"Pinky1.l": ["Pinky2.l", "pinky_02_l", "K_l"], "Pinky2.l": ["Pinky3.l", "pinky_03_l", "K_l"],
	"Thumb1.l": ["Thumb2.l", "thumb_02_l", "K_l"],
	"Index1.r": ["Index2.r", "index_02_r", "K_r"], "Index2.r": ["Index3.r", "index_03_r", "K_r"],
	"Middle1.r": ["Middle2.r", "middle_02_r", "K_r"], "Middle2.r": ["Middle3.r", "middle_03_r", "K_r"],
	"Ring1.r": ["Ring2.r", "ring_02_r", "K_r"], "Ring2.r": ["Ring3.r", "ring_03_r", "K_r"],
	"Pinky1.r": ["Pinky2.r", "pinky_02_r", "K_r"], "Pinky2.r": ["Pinky3.r", "pinky_03_r", "K_r"],
	"Thumb1.r": ["Thumb2.r", "thumb_02_r", "K_r"],
}

# Логические клипы: имя -> [glb, клип UAL, кадр начала, кадр конца (-1 = до конца), loop, скорость]
const CLIPS: Dictionary = {
	"idle": [UAL1_GLB, "Idle_Loop", 0, -1, true, 1.0],
	"walk": [UAL1_GLB, "Walk_Loop", 0, -1, true, 1.0],
	"jog": [UAL1_GLB, "Jog_Fwd_Loop", 0, -1, true, 1.0],
	"run": [UAL1_GLB, "Sprint_Loop", 0, -1, true, 1.0],
	# Удар киркой сверху вниз: замах за голову -> удар перед собой (контакт ~0.42 c).
	"mine": [UAL2_GLB, "OverhandThrow", 0, 36, false, 1.2],
	# Рубка топором (горизонтальный удар).
	"chop": [UAL2_GLB, "TreeChopping_Loop", 0, -1, false, 1.0],
	# Вскопка лопатой и набор воды ведром: наклон к земле перед собой.
	"dig": [UAL2_GLB, "Farm_Harvest", 0, -1, false, 1.45],
	# Набор воды: только наклон-зачерпывание-подъём (0.2–2.0 c клипа), ~1.0 c в игре.
	"scoop": [UAL2_GLB, "Farm_Harvest", 6, 60, false, 1.8],
	"water": [UAL2_GLB, "Farm_Watering", 0, -1, false, 1.0],
	"harvest": [UAL2_GLB, "Farm_Harvest", 0, -1, false, 1.0],
	"plant": [UAL2_GLB, "Farm_PlantSeed", 0, -1, false, 1.0],
	"eat": [UAL2_GLB, "Consume", 0, -1, false, 1.0],
	"interact": [UAL1_GLB, "Interact", 0, -1, false, 1.0],
	"pickup": [UAL1_GLB, "PickUp_Table", 0, -1, false, 1.0],
	"carry_walk": [UAL2_GLB, "Walk_Carry_Loop", 0, -1, true, 1.0],
	"talk": [UAL1_GLB, "Idle_Talking_Loop", 0, -1, true, 1.0],
	"sit": [UAL1_GLB, "Sitting_Idle_Loop", 0, -1, true, 1.0],
	"hit": [UAL1_GLB, "Hit_Chest", 0, -1, false, 1.0],
	"death": [UAL1_GLB, "Death01", 0, -1, false, 1.0],
	"jump_start": [UAL1_GLB, "Jump_Start", 0, -1, false, 1.0],
	"jump_loop": [UAL1_GLB, "Jump_Loop", 0, -1, true, 1.0],
	"jump_land": [UAL1_GLB, "Jump_Land", 0, -1, false, 1.0],
}

## Клипы удара: для них вычисляется момент контакта (metadata/contact_time).
const STRIKE_CLIPS: Array[String] = ["mine", "chop"]
## Клипы ходьбы: вычисляется скорость шага (metadata/ground_speed, м/с) против скольжения стоп.
const LOCOMOTION_CLIPS: Array[String] = ["walk", "jog", "run", "carry_walk"]

class Rig:
	var root: Node
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var world: Transform3D   # скелет -> корень сцены
	var names: Dictionary = {} # name -> idx
	var rest_g: Array[Transform3D] = [] # world rest каждой кости
	var order: Array[int] = []
	var track_path_prefix: String = ""

var src_cache: Dictionary = {}
var probe := false

func _init() -> void:
	probe = "--probe" in OS.get_cmdline_user_args()
	var ok := _run()
	quit(0 if ok else 1)

func _load_rig(path: String) -> Rig:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot read " + path)
		return null
	var r := Rig.new()
	r.root = doc.generate_scene(state)
	r.sk = r.root.find_child("Skeleton3D", true, false)
	r.ap = r.root.find_child("AnimationPlayer", true, false)
	var t := Transform3D.IDENTITY
	var n: Node = r.sk
	while n != r.root and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	r.world = t
	for i in r.sk.get_bone_count():
		r.names[r.sk.get_bone_name(i)] = i
		r.rest_g.append(r.world * r.sk.get_bone_global_rest(i))
	r.order = _topo(r.sk)
	r.track_path_prefix = String(r.root.get_path_to(r.sk)) + ":"
	return r

func _topo(sk: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	for i in sk.get_bone_count():
		_visit(sk, i, seen, out)
	return out

func _visit(sk: Skeleton3D, i: int, seen: Dictionary, out: Array[int]) -> void:
	if seen.has(i):
		return
	var p := sk.get_bone_parent(i)
	if p != -1:
		_visit(sk, p, seen, out)
	seen[i] = true
	out.append(i)

func _pos(r: Rig, bone: String) -> Vector3:
	return r.rest_g[r.names[bone]].origin

func _rot(t: Transform3D) -> Basis:
	return t.basis.orthonormalized()

func _frame(primary: Vector3, secondary: Vector3) -> Basis:
	var y := primary.normalized()
	var z := (secondary - y * secondary.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)

func _body_vectors(r: Rig, is_src: bool) -> Dictionary:
	var tl: String = "thigh_l" if is_src else "Thigh.l"
	var tr: String = "thigh_r" if is_src else "Thigh.r"
	var left := (_pos(r, tl) - _pos(r, tr))
	left.y = 0.0
	left = left.normalized()
	var fwd := left.cross(Vector3.UP).normalized()
	var res := {"L": left, "F": fwd}
	for side in ["l", "r"]:
		var i1: String = ("index_01_" + side) if is_src else ("Index1." + side)
		var p1: String = ("pinky_01_" + side) if is_src else ("Pinky1." + side)
		res["K_" + side] = _pos(r, i1) - _pos(r, p1)
	return res

func _run() -> bool:
	print(">>> Retarget UAL -> miner")
	var dst := _load_rig(MINER_GLB)
	if dst == null:
		return false
	var srcs := {}
	for p in [UAL1_GLB, UAL2_GLB]:
		srcs[p] = _load_rig(p)
		if srcs[p] == null:
			return false
	var s0: Rig = srcs[UAL1_GLB]
	var vs := _body_vectors(s0, true)
	var vd := _body_vectors(dst, false)
	# Поворот по рысканью: направление взгляда UAL -> направление взгляда героя.
	var yaw := atan2(vd["F"].x, vd["F"].z) - atan2(vs["F"].x, vs["F"].z)
	var R0 := Basis(Vector3.UP, yaw)
	print("facing src=", vs["F"], " dst=", vd["F"], " yaw=", rad_to_deg(yaw))
	# Коррекции rest-поз: C = B_src * B_dst^-1 (в мире героя).
	var corr := {}
	var src_rest_rot := {}
	for d_name in dst.order.map(func(i): return dst.sk.get_bone_name(i)):
		if not BONE_MAP.has(d_name):
			continue
		var s_name: String = BONE_MAP[d_name]
		var s_rest: Transform3D = s0.rest_g[s0.names[s_name]]
		src_rest_rot[d_name] = R0 * _rot(s_rest)
		if AIM.has(d_name):
			var a: Array = AIM[d_name]
			var pd: Vector3 = _pos(dst, a[0]) - _pos(dst, d_name)
			var ps: Vector3 = R0 * (_pos(s0, a[1]) - _pos(s0, s_name))
			var sec_d: Vector3 = vd[a[2]]
			var sec_s: Vector3 = R0 * vs[a[2]]
			corr[d_name] = _frame(ps, sec_s) * _frame(pd, sec_d).inverse()
		else:
			var par := dst.sk.get_bone_parent(dst.names[d_name])
			corr[d_name] = corr.get(dst.sk.get_bone_name(par), Basis.IDENTITY)
	# Масштаб смещения таза: высота таза над стопами.
	var hd: float = _pos(dst, "Hip").y - minf(_pos(dst, "Foot.l").y, _pos(dst, "Toe.l").y)
	var hs: float = _pos(s0, "pelvis").y - minf(_pos(s0, "foot_l").y, _pos(s0, "ball_l").y)
	var hip_scale: float = hd / hs
	print("hip height dst=%.3f src=%.3f scale=%.3f" % [hd, hs, hip_scale])

	var lib := AnimationLibrary.new()
	var clips: Dictionary = CLIPS
	if probe and OS.get_environment("PROBE_CLIPS") != "":
		clips = {}
		for spec in OS.get_environment("PROBE_CLIPS").split(","):
			var parts := spec.split("@")
			clips[parts[0]] = [UAL2_GLB if parts[1] == "2" else UAL1_GLB, parts[0], 0, -1, false, 1.0]
	for clip_name in clips.keys():
		var c: Array = clips[clip_name]
		var s: Rig = srcs[c[0]]
		var anim := _retarget(s, dst, c[1], c[2], c[3], c[4], R0, corr, src_rest_rot, hip_scale)
		if anim == null:
			continue
		_reduce_keys(anim)
		anim.set_meta("play_speed", float(c[5]))
		if clip_name in STRIKE_CLIPS:
			anim.set_meta("contact_time", _contact_time(dst, anim))
		if clip_name in LOCOMOTION_CLIPS:
			anim.set_meta("ground_speed", _ground_speed(dst, anim))
		print("  %-10s <- %-18s len=%.2f speed=%.2f %s" % [clip_name, c[1], anim.length, c[5], str(anim.get_meta_list().map(func(m): return "%s=%.3f" % [m, anim.get_meta(m)]))])
		lib.add_animation(clip_name, anim)
		if probe:
			_probe_clip(dst, anim, clip_name)
	if probe:
		return true

	_build_scene(dst, lib)
	return true

func _sample_local(s: Rig, anim: Animation, t: float) -> Array:
	# Локальные позы всех костей источника в момент t.
	var n := s.sk.get_bone_count()
	var pos: Array = []
	var rot: Array = []
	var scl: Array = []
	for i in n:
		pos.append(s.sk.get_bone_rest(i).origin)
		rot.append(s.sk.get_bone_rest(i).basis.get_rotation_quaternion())
		scl.append(s.sk.get_bone_rest(i).basis.get_scale())
	for tr in anim.get_track_count():
		var path := String(anim.track_get_path(tr))
		var bn := path.get_slice(":", 1)
		if not s.names.has(bn):
			continue
		var bi: int = s.names[bn]
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				pos[bi] = anim.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				rot[bi] = anim.rotation_track_interpolate(tr, t)
			Animation.TYPE_SCALE_3D:
				scl[bi] = anim.scale_track_interpolate(tr, t)
	var glob: Array = []
	glob.resize(n)
	for i in s.order:
		var local := Transform3D(Basis(rot[i]).scaled(scl[i]), pos[i])
		var p := s.sk.get_bone_parent(i)
		glob[i] = (glob[p] * local) if p != -1 else local
	for i in n:
		glob[i] = s.world * glob[i]
	return glob

func _find_anim(s: Rig, name: String) -> Animation:
	for lib_name in s.ap.get_animation_library_list():
		var l := s.ap.get_animation_library(lib_name)
		if l.has_animation(name):
			return l.get_animation(name)
	return null

func _retarget(s: Rig, dst: Rig, src_name: String, f0: int, f1: int, loop: bool, R0: Basis, corr: Dictionary, src_rest_rot: Dictionary, hip_scale: float) -> Animation:
	var src_anim := _find_anim(s, src_name)
	if src_anim == null:
		push_warning("UAL clip missing: " + src_name)
		return null
	var total_frames := int(round(src_anim.length * FPS))
	var end_f: int = total_frames if f1 < 0 else mini(f1, total_frames)
	var frames: int = end_f - f0
	var out := Animation.new()
	out.length = frames / FPS
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var prefix := dst.track_path_prefix
	var tracks := {}
	for d_name in BONE_MAP.keys():
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(prefix + d_name))
		out.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		tracks[d_name] = tr
	var hip_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hip_tr, NodePath(prefix + "Hip"))
	var s_pelvis: int = s.names["pelvis"]
	var src_hip_rest: Vector3 = s.rest_g[s_pelvis].origin
	var dst_hip_i: int = dst.names["Hip"]
	var dst_hip_rest_world: Vector3 = dst.rest_g[dst_hip_i].origin
	var prev_q := {}
	var dst_world_rot := _rot(dst.world)
	for f in range(frames + 1):
		var t_src: float = minf((f0 + f) / FPS, src_anim.length)
		var t: float = f / FPS
		var sg: Array = _sample_local(s, src_anim, t_src)
		# Мировые вращения героя.
		var wd: Array = []
		wd.resize(dst.sk.get_bone_count())
		for i in dst.order:
			var nm := dst.sk.get_bone_name(i)
			var p := dst.sk.get_bone_parent(i)
			if BONE_MAP.has(nm):
				var si: int = s.names[BONE_MAP[nm]]
				var ws: Basis = R0 * _rot(sg[si])
				wd[i] = ws * (src_rest_rot[nm] as Basis).inverse() * (corr[nm] as Basis) * _rot(dst.rest_g[i])
			else:
				var parent_w: Basis = wd[p] if p != -1 else dst_world_rot
				wd[i] = parent_w * dst.sk.get_bone_rest(i).basis.orthonormalized()
		for nm in BONE_MAP.keys():
			var i: int = dst.names[nm]
			var p := dst.sk.get_bone_parent(i)
			var parent_w: Basis = wd[p] if p != -1 else dst_world_rot
			var q: Quaternion = (parent_w.inverse() * (wd[i] as Basis)).get_rotation_quaternion().normalized()
			if prev_q.has(nm) and (prev_q[nm] as Quaternion).dot(q) < 0.0:
				q = -q
			prev_q[nm] = q
			out.rotation_track_insert_key(tracks[nm], t, q)
		# Таз: смещение источника, повернутое и отмасштабированное.
		var delta: Vector3 = R0 * ((sg[s_pelvis] as Transform3D).origin - src_hip_rest) * hip_scale
		var hip_world := dst_hip_rest_world + delta
		var hip_local: Vector3 = dst.world.affine_inverse() * hip_world
		out.position_track_insert_key(hip_tr, t, hip_local)
	return out

func _fk(dst: Rig, anim: Animation, t: float) -> Array:
	# Глобальные позы костей героя (пространство скелета) — ручной FK по трекам клипа.
	var sk := dst.sk
	var n := sk.get_bone_count()
	var pos: Array = []
	var rot: Array = []
	for i in n:
		pos.append(sk.get_bone_rest(i).origin)
		rot.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
	for tr in anim.get_track_count():
		var bi := sk.find_bone(String(anim.track_get_path(tr)).get_slice(":", 1))
		if bi == -1:
			continue
		if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			rot[bi] = anim.rotation_track_interpolate(tr, t)
		elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
			pos[bi] = anim.position_track_interpolate(tr, t)
	var glob: Array = []
	glob.resize(n)
	for i in dst.order:
		var local := Transform3D(Basis(rot[i]).scaled(sk.get_bone_rest(i).basis.get_scale()), pos[i])
		var p := sk.get_bone_parent(i)
		glob[i] = (glob[p] * local) if p != -1 else local
	return glob

var dump := {}

## Момент контакта: кисть впервые опускается ниже 15% размаха по высоте после верхней точки.
func _contact_time(dst: Rig, anim: Animation) -> float:
	var hand := dst.sk.find_bone("Hand.r")
	var ys: Array[float] = []
	var n := int(anim.length * FPS)
	for f in range(n + 1):
		ys.append((dst.world * (_fk(dst, anim, f / FPS)[hand] as Transform3D).origin).y)
	var top := 0
	for f in ys.size():
		if ys[f] > ys[top]:
			top = f
	var lo: float = ys.slice(top).min()
	var thr: float = lo + (ys[top] - lo) * 0.15
	for f in range(top, ys.size()):
		if ys[f] <= thr:
			return f / FPS
	return anim.length * 0.5

## Скорость шага клипа в метрах игрока: скорость опорной стопы (пальцы у земли) относительно тела.
func _ground_speed(dst: Rig, anim: Animation) -> float:
	var toes := [dst.sk.find_bone("Toe.l"), dst.sk.find_bone("Toe.r")]
	var n := int(anim.length * FPS)
	var poses: Array = []
	for f in range(n + 1):
		poses.append(_fk(dst, anim, f / FPS))
	var speeds: Array[float] = []
	for k in toes:
		var min_y := INF
		for g in poses:
			min_y = minf(min_y, (g[k] as Transform3D).origin.y)
		for f in range(1, poses.size()):
			var a: Vector3 = (poses[f - 1][k] as Transform3D).origin
			var b: Vector3 = (poses[f][k] as Transform3D).origin
			if b.y < min_y + 0.06 and a.y < min_y + 0.06:
				speeds.append(Vector2(b.x - a.x, b.z - a.z).length() * FPS)
	if speeds.is_empty():
		return 0.0
	speeds.sort()
	return speeds[speeds.size() / 2] * MODEL_UNIT_M

func _probe_clip(dst: Rig, anim: Animation, clip_name: String) -> void:
	# Печатает траекторию правой кисти и диапазон высоты стоп (мир, ед. модели);
	# сохраняет позы в /tmp/miner_pose_dump.json для визуальной проверки.
	var sk := dst.sk
	var hand := sk.find_bone("Hand.r")
	var feet := [sk.find_bone("Toe.l"), sk.find_bone("Toe.r")]
	var line := ""
	var foot_min := INF
	var foot_max := -INF
	var steps := int(OS.get_environment("PROBE_STEPS")) if OS.get_environment("PROBE_STEPS") != "" else 8
	var frames := []
	for k in range(steps + 1):
		var t := anim.length * k / steps
		var g: Array = _fk(dst, anim, t)
		var hp: Vector3 = dst.world * (g[hand] as Transform3D).origin
		line += "(%.1f,%.1f,%.1f) " % [hp.x, hp.y, hp.z]
		for fi in feet:
			var fy: float = (dst.world * (g[fi] as Transform3D).origin).y
			foot_min = minf(foot_min, fy)
			foot_max = maxf(foot_max, fy)
		var fr := {}
		for i in sk.get_bone_count():
			var tt: Transform3D = g[i]
			fr[sk.get_bone_name(i)] = [tt.basis.x.x, tt.basis.x.y, tt.basis.x.z, tt.basis.y.x, tt.basis.y.y, tt.basis.y.z, tt.basis.z.x, tt.basis.z.y, tt.basis.z.z, tt.origin.x, tt.origin.y, tt.origin.z]
		frames.append(fr)
	dump[clip_name] = frames
	print("%-10s len=%.2f toe_y=[%.2f..%.2f] hand_r: %s" % [clip_name, anim.length, foot_min, foot_max, line])
	var f := FileAccess.open("/tmp/miner_pose_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(dump))
	f.close()

# ---------------------------------------------------------------------------
# Сборка сцены
# ---------------------------------------------------------------------------

func _build_scene(dst: Rig, lib: AnimationLibrary) -> void:
	var node := dst.root
	node.name = "MinerPackageModel"
	var sk := dst.sk
	# 1. Сокет инструмента (кость + BoneAttachment3D).
	var socket_global := _socket_global_rest(dst)
	var hand := sk.find_bone("Hand.r")
	var sock := sk.find_bone("ToolSocket.R")
	if sock == -1:
		sock = sk.get_bone_count()
		sk.add_bone("ToolSocket.R")
		sk.set_bone_parent(sock, hand)
	var local_rest := sk.get_bone_global_rest(hand).affine_inverse() * socket_global
	sk.set_bone_rest(sock, local_rest)
	sk.set_bone_pose_position(sock, local_rest.origin)
	sk.set_bone_pose_rotation(sock, local_rest.basis.get_rotation_quaternion())
	sk.set_bone_pose_scale(sock, local_rest.basis.get_scale())
	var att := BoneAttachment3D.new()
	att.name = "ToolSocket_R"
	att.bone_name = "ToolSocket.R"
	sk.add_child(att)
	# 2. Отделяем кирку от тела.
	var body: MeshInstance3D = sk.find_child("*", false, false) as MeshInstance3D
	for c in sk.get_children():
		if c is MeshInstance3D:
			body = c
	body.name = "Miner_Body"
	var body_mat := (body.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
	if body_mat and ResourceLoader.exists(MINER_TEXTURE):
		var tex: Texture2D = load(MINER_TEXTURE)
		if body_mat.albedo_texture and body_mat.albedo_texture.get_size() != tex.get_size():
			push_warning("texture size differs: %s vs %s" % [body_mat.albedo_texture.get_size(), tex.get_size()])
		body_mat.albedo_texture = tex
	if body_mat:
		# В glb нет metallicFactor -> по спецификации glTF он равен 1.0, и одежда
		# рендерится тёмным «хромом». Герой не металлический.
		body_mat.metallic = 0.0
		body_mat.roughness = 0.85
	var pick := _split_pickaxe(body, sk, socket_global)
	if pick:
		att.add_child(pick)
	var helmet := _split_helmet(body)
	if helmet:
		sk.add_child(helmet)
	# 3. Анимации.
	var ap: AnimationPlayer = dst.ap
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		node.add_child(ap)
	for l in ap.get_animation_library_list():
		ap.remove_animation_library(l)
	lib.add_animation("RESET", _make_reset(dst))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_LIBRARY.get_base_dir()))
	var lerr := ResourceSaver.save(lib, OUT_LIBRARY)
	print("OK: saved " + OUT_LIBRARY if lerr == OK else "FAIL: library save error %d" % lerr)
	lib = load(OUT_LIBRARY)
	ap.add_animation_library("", lib)
	ap.autoplay = "idle"
	print("Animations: ", lib.get_animation_list())
	_set_owner_recursive(node, node)
	var packed := PackedScene.new()
	if packed.pack(node) != OK:
		push_error("pack failed")
		return
	var err := ResourceSaver.save(packed, OUT_SCENE)
	print("OK: saved " + OUT_SCENE if err == OK else "FAIL: save error %d" % err)

func _make_reset(dst: Rig) -> Animation:
	var a := Animation.new()
	a.length = 0.001
	for nm in BONE_MAP.keys():
		var i: int = dst.names[nm]
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath(dst.track_path_prefix + nm))
		a.rotation_track_insert_key(tr, 0.0, dst.sk.get_bone_rest(i).basis.get_rotation_quaternion())
	var hp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hp, NodePath(dst.track_path_prefix + "Hip"))
	a.position_track_insert_key(hp, 0.0, dst.sk.get_bone_rest(dst.names["Hip"]).origin)
	return a

## Сокет в пространстве скелета: начало — центр хвата кулака, +Y — ось рукояти
## (от мизинца к указательному, к навершию), +X — от запястья к пальцам (лезвие),
## масштаб — метры (1 / MODEL_UNIT_M).
func _socket_global_rest(dst: Rig) -> Transform3D:
	var sk := dst.sk
	var g := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
	var hand: Vector3 = g.call("Hand.r")
	var knuckles: Vector3 = (g.call("Index1.r") + g.call("Middle1.r") + g.call("Ring1.r") + g.call("Pinky1.r")) / 4.0
	var y: Vector3 = (g.call("Index1.r") - g.call("Pinky1.r")).normalized()
	var x: Vector3 = knuckles - hand
	x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y).normalized()
	# Ладонь — сторона большого пальца.
	var thumb: Vector3 = g.call("Thumb1.r") - hand
	var palm_sign := 1.0 if thumb.dot(z) > 0.0 else -1.0
	var hand_len := (knuckles - hand).length()
	var origin := hand + (knuckles - hand) * 1.25 + z * palm_sign * hand_len * 0.30
	var b := Basis(x, y, z).scaled(Vector3.ONE / MODEL_UNIT_M)
	return Transform3D(b, origin)

func _split_pickaxe(body: MeshInstance3D, sk: Skeleton3D, socket_global: Transform3D) -> MeshInstance3D:
	var mesh := body.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bpv := 8 if (mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
	# Связные компоненты (с учётом сварки по позиции).
	var weld := {}
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		var key := Vector3i(roundi(verts[i].x * 10000), roundi(verts[i].y * 10000), roundi(verts[i].z * 10000))
		if not weld.has(key):
			weld[key] = i
		parent[i] = weld[key]
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for f in range(0, idx.size(), 3):
		var a: int = find.call(idx[f])
		for k in [1, 2]:
			var b: int = find.call(idx[f + k])
			if a != b:
				parent[b] = a
	var comps := {}
	for i in verts.size():
		var r: int = find.call(i)
		if not comps.has(r):
			comps[r] = []
		comps[r].append(i)
	# Skin: индекс кости в скине -> имя.
	var skin: Skin = body.skin
	var hand_bind := -1
	for bi in skin.get_bind_count():
		var bn := skin.get_bind_name(bi)
		if bn == "" and skin.get_bind_bone(bi) >= 0:
			bn = sk.get_bone_name(skin.get_bind_bone(bi))
		if bn == "Hand.r":
			hand_bind = bi
	var pick_set := {}
	var handle: Array = []
	var head: Array = []
	for r in comps:
		var vs: Array = comps[r]
		var aabb := AABB(verts[vs[0]], Vector3.ZERO)
		var on_hand := 0
		for v in vs:
			aabb = aabb.expand(verts[v])
			var best := 0
			for k in range(1, bpv):
				if weights[v * bpv + k] > weights[v * bpv + best]:
					best = k
			if bones[v * bpv + best] == hand_bind:
				on_hand += 1
		if on_hand == vs.size() and aabb.get_longest_axis_size() > 1.0:
			for v in vs:
				pick_set[v] = true
			if aabb.size.y > aabb.size.x:
				handle = vs
			else:
				head = vs
	if handle.is_empty() or head.is_empty():
		push_warning("pickaxe components not found")
		return null
	# Оси кирки в bind-пространстве (= rest).
	var h_min := Vector3(INF, INF, INF)
	var h_max := -h_min
	for v in handle:
		h_min = h_min.min(verts[v]); h_max = h_max.max(verts[v])
	var head_c := Vector3.ZERO
	var hd_min := Vector3(INF, INF, INF)
	var hd_max := -hd_min
	for v in head:
		head_c += verts[v]
		hd_min = hd_min.min(verts[v]); hd_max = hd_max.max(verts[v])
	head_c /= head.size()
	var handle_bottom := Vector3((h_min.x + h_max.x) / 2, h_min.y, (h_min.z + h_max.z) / 2)
	var handle_top := Vector3((h_min.x + h_max.x) / 2, h_max.y, (h_min.z + h_max.z) / 2)
	var py := (handle_top - handle_bottom).normalized()
	var blade := Vector3(hd_max.x - hd_min.x, 0, hd_max.z - hd_min.z)
	var px := (blade - py * blade.dot(py)).normalized()
	var pz := px.cross(py).normalized()
	# Хват — на 40% длины рукояти от низа (как у остальных инструментов).
	var grip := handle_bottom + (handle_top - handle_bottom) * 0.40
	var pframe := Transform3D(Basis(px, py, pz), grip)
	var to_local := pframe.affine_inverse()
	# Новый меш кирки (статический, в метрах, в системе сокета).
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var body_idx := PackedInt32Array()
	for f in range(0, idx.size(), 3):
		if pick_set.has(idx[f]):
			for k in 3:
				var v: int = idx[f + k]
				if not remap.has(v):
					remap[v] = nv.size()
					nv.append((to_local * verts[v]) * MODEL_UNIT_M)
					nn.append((to_local.basis * normals[v]).normalized())
					nuv.append(uvs[v] if uvs.size() > v else Vector2.ZERO)
				ni.append(remap[v])
		else:
			body_idx.append_array([idx[f], idx[f + 1], idx[f + 2]])
	var mat := mesh.surface_get_material(0)
	var pick_arrays := []
	pick_arrays.resize(Mesh.ARRAY_MAX)
	pick_arrays[Mesh.ARRAY_VERTEX] = nv
	pick_arrays[Mesh.ARRAY_NORMAL] = nn
	pick_arrays[Mesh.ARRAY_TEX_UV] = nuv
	pick_arrays[Mesh.ARRAY_INDEX] = ni
	var pmesh := ArrayMesh.new()
	pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pick_arrays)
	pmesh.surface_set_material(0, mat)
	pmesh.resource_name = "Pickaxe"
	var pmi := MeshInstance3D.new()
	pmi.name = "Pickaxe"
	pmi.mesh = pmesh
	# Тело без кирки.
	arrays[Mesh.ARRAY_INDEX] = body_idx
	var flags := mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var bmesh := ArrayMesh.new()
	bmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	bmesh.surface_set_material(0, mat)
	bmesh.resource_name = "Miner_Body"
	body.mesh = bmesh
	print("pickaxe split: %d tris, body %d tris" % [ni.size() / 3, body_idx.size() / 3])
	return pmi

## Каска с фонарём — отдельные куски меша выше макушки (y > HELMET_MIN_Y в bind-пространстве).
## Выносим в собственный skinned MeshInstance3D «Character_Helmet» (set_hat_visible).
const HELMET_MIN_Y := 4.45

func _split_helmet(body: MeshInstance3D) -> MeshInstance3D:
	var mesh := body.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Компоненты по рёбрам треугольников (со сваркой позиций).
	var weld := {}
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		var key := Vector3i(roundi(verts[i].x * 10000), roundi(verts[i].y * 10000), roundi(verts[i].z * 10000))
		if not weld.has(key):
			weld[key] = i
		parent[i] = weld[key]
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for f in range(0, idx.size(), 3):
		var a: int = find.call(idx[f])
		for k in [1, 2]:
			var b: int = find.call(idx[f + k])
			if a != b:
				parent[b] = a
	var min_y := {}
	for i in verts.size():
		var r: int = find.call(i)
		min_y[r] = minf(min_y.get(r, INF), verts[i].y)
	var helmet_idx := PackedInt32Array()
	var body_idx := PackedInt32Array()
	for f in range(0, idx.size(), 3):
		var r: int = find.call(idx[f])
		if min_y[r] > HELMET_MIN_Y:
			helmet_idx.append_array([idx[f], idx[f + 1], idx[f + 2]])
		else:
			body_idx.append_array([idx[f], idx[f + 1], idx[f + 2]])
	if helmet_idx.is_empty():
		return null
	var mat := mesh.surface_get_material(0)
	var flags := mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var make := func(ind: PackedInt32Array, res_name: String) -> ArrayMesh:
		var a2 := arrays.duplicate()
		a2[Mesh.ARRAY_INDEX] = ind
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2, [], {}, flags)
		m.surface_set_material(0, mat)
		m.resource_name = res_name
		return m
	body.mesh = make.call(body_idx, "Miner_Body")
	var h := MeshInstance3D.new()
	h.name = "Character_Helmet"
	h.mesh = make.call(helmet_idx, "Character_Helmet")
	h.skin = body.skin
	h.skeleton = NodePath("..")
	print("helmet split: %d tris" % (helmet_idx.size() / 3))
	return h

## Убирает ключи, которые восстанавливаются линейной интерполяцией соседей (размер сцены).
func _reduce_keys(anim: Animation, rot_eps: float = 0.007, pos_eps: float = 0.006) -> void:
	for tr in anim.get_track_count():
		var tt := anim.track_get_type(tr)
		if tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_POSITION_3D:
			continue
		var n := anim.track_get_key_count(tr)
		if n <= 2:
			continue
		var times: Array[float] = []
		var vals: Array = []
		for k in n:
			times.append(anim.track_get_key_time(tr, k))
			vals.append(anim.track_get_key_value(tr, k))
		var keep: Array[int] = [0]
		var last := 0
		for k in range(1, n - 1):
			# Проверяем, можно ли выкинуть все ключи между last и k+1.
			var ok := true
			for m in range(last + 1, k + 1):
				var w: float = (times[m] - times[last]) / (times[k + 1] - times[last])
				if tt == Animation.TYPE_ROTATION_3D:
					var q: Quaternion = (vals[last] as Quaternion).slerp(vals[k + 1], w)
					if q.angle_to(vals[m]) > rot_eps:
						ok = false
						break
				else:
					var v: Vector3 = (vals[last] as Vector3).lerp(vals[k + 1], w)
					if v.distance_to(vals[m]) > pos_eps:
						ok = false
						break
			if not ok:
				keep.append(k)
				last = k
		keep.append(n - 1)
		for k in range(n - 1, -1, -1):
			if not keep.has(k):
				anim.track_remove_key(tr, k)

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
