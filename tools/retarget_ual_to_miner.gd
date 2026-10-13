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
##  4. Тело/каска/кирка берутся из модели tools/rig_hero_model.py (кирка — отдельный меш
##     «Pickaxe» на сокете, чтобы её можно было скрывать при смене инструмента); меши и
##     текстуры (WebP) сохраняются текстовыми ресурсами в assets/models/character/hero/.
##
## Запуск (из корня проекта):
##   Godot --headless --path . -s tools/retarget_ual_to_miner.gd
##   Godot --headless --path . -s tools/retarget_ual_to_miner.gd -- --probe   (метрики клипов)
##   Godot --headless --path . -s tools/retarget_ual_to_miner.gd -- --hero <HERO_OUT> [--textures]
##        (модель из rig_hero_model.py; --textures — пересжать текстуры героя из PNG запекания)

## Папка сборки героя tools/rig_hero_model.py (HERO_OUT): hero_rigged.gltf — скелет и skinned-меши
## (тело Miner_Body + каска Character_Helmet, кость ToolSocket.R), hero_pickaxe.gltf — кирка в
## системе сокета хвата (метры), PNG запекания. В репозиторий не входит (промежуточные файлы),
## путь задаётся «-- --hero <папка>»; по умолчанию res://hero_build.
var MINER_GLB := "res://hero_build/hero_rigged.gltf"
var HERO_PICKAXE := "res://hero_build/hero_pickaxe.gltf"
var HERO_BUILD := "res://hero_build"
## Текстуры (PortableCompressedTexture2D) и материалы героя.
const HERO_DIR := "res://assets/models/character/hero/"
const UAL1_GLB := "res://assets/models/character/UAL1_Standard.glb"
const UAL2_GLB := "res://assets/models/character/UAL2_Standard.glb"
const OUT_SCENE := "res://scenes/player/miner_package_model.tscn"
## Текстура героя — ссылкой на импортированный PNG вместо 16 МБ встроенного Image.
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
	"mine": [UAL2_GLB, "OverhandThrow", 0, 36, false, 2.4],
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

## Кости, у которых rest-поза героя переносится в rest-позу UAL без выравнивания по осям.
const REST_MATCH_BONES: Array[String] = ["Foot.l", "Toe.l", "Foot.r", "Toe.r"]
## Клипы с инструментом в правой руке: пальцы правой кисти фиксируются в кулаке-хвате
## (в OverhandThrow кисть раскрывается при «броске» — кирка «висела» рядом с ладонью).
const GRIP_CLIPS: Array[String] = ["mine", "chop", "dig", "scoop", "water"]
const GRIP_FINGERS: Array[String] = [
	"Index1.r", "Index2.r", "Index3.r", "Middle1.r", "Middle2.r", "Middle3.r",
	"Ring1.r", "Ring2.r", "Ring3.r", "Pinky1.r", "Pinky2.r", "Pinky3.r", "Thumb1.r", "Thumb2.r"]
## Эталон кулака: кадр UAL, где правая кисть сжата (Idle_Loop, кадр 0).
const FIST_REF := [UAL1_GLB, "Idle_Loop", 0]

## Наклон черенка кирки к костяшкам в сокете хвата, градусы.
const PICKAXE_GRIP_TILT_DEG := 35.0
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
	var args := OS.get_cmdline_user_args()
	probe = "--probe" in args
	var hi := args.find("--hero")
	if hi != -1 and hi + 1 < args.size():
		HERO_BUILD = args[hi + 1]
	MINER_GLB = HERO_BUILD.path_join("hero_rigged.gltf")
	HERO_PICKAXE = HERO_BUILD.path_join("hero_pickaxe.gltf")
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
		if d_name in REST_MATCH_BONES:
			# Стопа: в rest-позах обоих скелетов стопа стоит на полу плашмя, поэтому
			# rest должен переходить в rest (коррекция = I), а не «кость в кость».
			# У героя кость Foot идёт от лодыжки круто вниз к Toe (~68°), у UAL foot->ball
			# пологая (~31°): выравнивание по направлению задирало носки вверх на ~37°.
			corr[d_name] = Basis.IDENTITY
		elif AIM.has(d_name):
			var a: Array = AIM[d_name]
			var pd: Vector3 = _pos(dst, a[0]) - _pos(dst, d_name)
			var ps: Vector3 = R0 * (_pos(s0, a[1]) - _pos(s0, s_name))
			var sec_d: Vector3 = vd[a[2]]
			var sec_s: Vector3 = R0 * vs[a[2]]
			corr[d_name] = _frame(ps, sec_s) * _frame(pd, sec_d).inverse()
		elif d_name in REST_MATCH_BONES:
			pass
		else:
			var par := dst.sk.get_bone_parent(dst.names[d_name])
			corr[d_name] = corr.get(dst.sk.get_bone_name(par), Basis.IDENTITY)
	# Масштаб смещения таза: высота таза над стопами.
	var hd: float = _pos(dst, "Hip").y - minf(_pos(dst, "Foot.l").y, _pos(dst, "Toe.l").y)
	var hs: float = _pos(s0, "pelvis").y - minf(_pos(s0, "foot_l").y, _pos(s0, "ball_l").y)
	var hip_scale: float = hd / hs
	print("hip height dst=%.3f src=%.3f scale=%.3f" % [hd, hs, hip_scale])

	var fist := _retarget(srcs[FIST_REF[0]], dst, FIST_REF[1], FIST_REF[2], FIST_REF[2] + 1, false, R0, corr, src_rest_rot, hip_scale)
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
		if clip_name in GRIP_CLIPS:
			_apply_fist(anim, fist)
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

	_build_scene(dst, lib, fist)
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

## Заменяет треки пальцев правой кисти постоянным кулаком из эталона.
func _apply_fist(anim: Animation, fist: Animation) -> void:
	for nm in GRIP_FINGERS:
		var src_tr := -1
		for t in fist.get_track_count():
			if String(fist.track_get_path(t)).ends_with(":" + nm):
				src_tr = t
		var dst_tr := -1
		for t in anim.get_track_count():
			if String(anim.track_get_path(t)).ends_with(":" + nm) and anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				dst_tr = t
		if src_tr == -1 or dst_tr == -1:
			continue
		var q: Quaternion = fist.track_get_key_value(src_tr, 0)
		while anim.track_get_key_count(dst_tr) > 0:
			anim.track_remove_key(dst_tr, 0)
		anim.rotation_track_insert_key(dst_tr, 0.0, q)
		anim.rotation_track_insert_key(dst_tr, anim.length, q)

func _build_scene(dst: Rig, lib: AnimationLibrary, fist: Animation) -> void:
	var node := dst.root
	node.name = "MinerPackageModel"
	var sk := dst.sk
	# 1. Сокет инструмента (кость + BoneAttachment3D). В новой модели кость ToolSocket.R
	# уже стоит в кулаке (центр хвата на оси черенка, rig_hero_model.py) — берём её rest
	# и только переводим масштаб в метры; иначе считаем по сжатому кулаку UAL.
	var hand := sk.find_bone("Hand.r")
	var sock := sk.find_bone("ToolSocket.R")
	var socket_global: Transform3D
	if sock != -1:
		var g := sk.get_bone_global_rest(sock)
		socket_global = Transform3D(g.basis.orthonormalized().scaled(Vector3.ONE / MODEL_UNIT_M), g.origin)
	else:
		socket_global = _socket_global_rest(dst, fist)
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
	# 2. Тело, каска и кирка: меши — отдельными сжатыми ресурсами, материал с атласом.
	var mats := _hero_materials()
	var body := sk.find_child("Miner_Body", false, false) as MeshInstance3D
	var helmet := sk.find_child("Character_Helmet", false, false) as MeshInstance3D
	for mi in [body, helmet]:
		if mi == null:
			push_error("в %s нет Miner_Body/Character_Helmet" % MINER_GLB)
			return
		mi.mesh = _save_mesh(mi.mesh, mats["body"], HERO_DIR + "hero_%s_mesh.tres" % ("body" if mi == body else "helmet"), true)
	var pdoc := GLTFDocument.new()
	var pstate := GLTFState.new()
	if pdoc.append_from_file(HERO_PICKAXE, pstate) != OK:
		push_error("cannot read " + HERO_PICKAXE)
		return
	var proot := pdoc.generate_scene(pstate)
	var psrc := proot.find_child("Pickaxe", true, false) as MeshInstance3D
	var pick := MeshInstance3D.new()
	pick.name = "Pickaxe"
	# Отделённый инструмент исходного AI-меша имел силуэт топора.
	# Игровая кирка одинакова в idle и mine; ресурс создаёт create_hoe_model.gd.
	pick.mesh = load("res://assets/models/tools/pickaxe_equipped_mesh.tres")
	# В исходной модели черенок перпендикулярен предплечью. В ударе (UAL OverhandThrow) кулак
	# повёрнут большим пальцем внутрь, и длинная кирка уходила вбок; наклон черенка к костяшкам
	# (+X сокета) — естественный хват: головка опускается вперёд-вниз, к цели.
	pick.transform = Transform3D(Basis(Vector3.BACK, -deg_to_rad(PICKAXE_GRIP_TILT_DEG)), Vector3.ZERO)
	proot.free()
	att.add_child(pick)
	print("socket rest (skeleton space): ", socket_global.orthonormalized())
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

## Текстуры героя: при «-- --textures» PNG из папки --hero из rig_hero_model.py сжимаются в
## PortableCompressedTexture2D (WebP, текстовые .tres), иначе берутся уже сохранённые.
func _hero_tex(dir: String, file: String, size: int, is_normal: bool, quality: float) -> Texture2D:
	var out := HERO_DIR + file + ".tres"
	if dir != "":
		var img := Image.load_from_file(dir.path_join(file + ".png"))
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != size:
			img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var t := PortableCompressedTexture2D.new()
		t.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, is_normal, quality)
		ResourceSaver.save(t, out)
	return load(out)

func _hero_orm(dir: String, pre: String, size: int) -> Texture2D:
	var out := HERO_DIR + pre + "_orm.tres"
	if dir != "":
		var rough := Image.load_from_file(dir.path_join(pre + "_roughness.png"))
		var metal := Image.load_from_file(dir.path_join(pre + "_metallic.png"))
		for im in [rough, metal]:
			im.convert(Image.FORMAT_RGB8)
			if im.get_width() != size:
				im.resize(size, size, Image.INTERPOLATE_LANCZOS)
		var orm := Image.create(size, size, false, Image.FORMAT_RGB8)
		for y in size:
			for x in size:
				orm.set_pixel(x, y, Color(1.0, rough.get_pixel(x, y).r, metal.get_pixel(x, y).r))
		var t := PortableCompressedTexture2D.new()
		t.create_from_image(orm, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.8)
		ResourceSaver.save(t, out)
	return load(out)

func _hero_materials() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var dir := HERO_BUILD if "--textures" in args else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HERO_DIR))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var res := {}
	for part in [["body", "hero_body", 2048, 1024], ["pickaxe", "hero_pickaxe", 512, 512]]:
		var path: String = HERO_DIR + part[1] + "_material.tres"
		if dir == "" and ResourceLoader.exists(path):
			res[part[0]] = load(path)
			continue
		var m := StandardMaterial3D.new()
		m.resource_name = part[1]
		m.albedo_texture = _hero_tex(dir, part[1] + "_albedo", part[2], false, 0.82)
		m.normal_enabled = true
		m.normal_texture = _hero_tex(dir, part[1] + "_normal", part[3], true, 0.82)
		var orm := _hero_orm(dir, part[1], part[3])
		m.roughness = 1.0
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 1.0
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		ResourceSaver.save(m, path)
		res[part[0]] = load(path)
	return res

## Меш с материалом — отдельным ресурсом (касательные для карты нормалей, сжатые атрибуты).
func _save_mesh(src: Mesh, material: Material, path: String, skinned: bool) -> Mesh:
	var st := SurfaceTool.new()
	st.create_from(src, 0)
	st.generate_tangents()
	var arrays: Array = st.commit_to_arrays()
	var out := ArrayMesh.new()
	# Сжатые атрибуты ломают GPU-скиннинг (вершины «улетают») — только для статичной кирки.
	var flags := 0 if skinned else Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	if skinned and (src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS):
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	out.surface_set_material(0, material)
	out.resource_name = path.get_file().get_basename()
	ResourceSaver.save(out, path)
	return load(path)

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

## Сокет в пространстве скелета. Считается по СЖАТОМУ кулаку (эталон FIST_REF):
## начало — центр отверстия кулака (центр окружности через суставы согнутых пальцев,
## усреднённый по указательному..мизинцу), +Y — ось рукояти от мизинца к указательному
## (сторона большого пальца -> голова инструмента), +X — от запястья к костяшкам
## (лезвие/боёк смотрит туда же, куда костяшки), масштаб — метры (1 / MODEL_UNIT_M).
## Сокет — дочерняя кость Hand.r, поэтому положение в кулаке переносится в rest-позу кисти.
func _socket_global_rest(dst: Rig, fist: Animation) -> Transform3D:
	var sk := dst.sk
	var glob: Array = _fk(dst, fist, 0.0)
	var hand_i := sk.find_bone("Hand.r")
	var inv: Transform3D = (glob[hand_i] as Transform3D).affine_inverse()
	var lp := func(n: String) -> Vector3: return inv * (glob[sk.find_bone(n)] as Transform3D).origin
	var centers: Array[Vector3] = []
	for f in ["Index", "Middle", "Ring", "Pinky"]:
		centers.append(_circumcenter(lp.call(f + "1.r"), lp.call(f + "2.r"), lp.call(f + "3.r")))
	var origin := Vector3.ZERO
	for c in centers:
		origin += c
	origin /= centers.size()
	var y: Vector3 = (lp.call("Index1.r") - lp.call("Pinky1.r")).normalized()
	var knuckles: Vector3 = (lp.call("Index1.r") + lp.call("Middle1.r") + lp.call("Ring1.r") + lp.call("Pinky1.r")) / 4.0
	var x: Vector3 = knuckles - y * knuckles.dot(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var local := Transform3D(Basis(x, y, z).scaled(Vector3.ONE / MODEL_UNIT_M), origin)
	print("grip socket (Hand.r local): origin=%s radius=%.3f" % [origin, (lp.call("Middle2.r") - centers[1]).length()])
	return sk.get_bone_global_rest(hand_i) * local

func _circumcenter(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var n := ab.cross(ac)
	if n.length_squared() < 1e-12:
		return (a + b + c) / 3.0
	return a + (n.cross(ab) * ac.length_squared() + ac.cross(n) * ab.length_squared()) / (2.0 * n.length_squared())

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
