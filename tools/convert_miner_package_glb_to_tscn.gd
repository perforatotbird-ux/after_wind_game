extends SceneTree

## Запекает ready-минера (Miner_Ready_Package):
## assets/models/character/miner_ready.glb + UAL1/UAL2 (Universal Animation Library)
## в самодостаточную scenes/player/miner_package_model.tscn.
## UAL-анимации ремаппятся на скелет майнера (bone_map из ReadyMinerController),
## position-треки выкидываются, чтобы кости не уносило.
## Итог: idle/walk/run/mine — родные Armature|*, спринт/чоп/атака — ual_*.

const BONE_MAP: Dictionary = {
	"pelvis": "Hip",
	"spine_01": "Spine1",
	"spine_02": "Spine2",
	"spine_03": "Spine2",
	"neck_01": "Neck",
	"Head": "Head",
	"clavicle_l": "Clavicle.l",
	"upperarm_l": "Forearm.l",
	"lowerarm_l": "Arm.l",
	"hand_l": "Hand.l",
	"clavicle_r": "Clavicle.r",
	"upperarm_r": "Forearm.r",
	"lowerarm_r": "Arm.r",
	"hand_r": "Hand.r",
	"thigh_l": "Thigh.l",
	"calf_l": "Calf.l",
	"foot_l": "Foot.l",
	"toe_l": "Toe.l",
	"thigh_r": "Thigh.r",
	"calf_r": "Calf.r",
	"foot_r": "Foot.r",
	"toe_r": "Toe.r",
}

# src_name в UAL -> dest_name в модели игрока
const UAL_MAP: Dictionary = {
	"res://assets/models/character/UAL1_Standard.glb": [
		["Idle", "ual_Idle"],
		["Walk", "ual_Walk"],
		["Sprint", "ual_Sprint"],
		["Dance", "ual_Dance"],
		["Hit_Chest", "ual_Hit"],
		["Death01", "ual_Death"],
		["Sword_Attack", "ual_Attack"],
	],
	"res://assets/models/character/UAL2_Standard.glb": [
		["TreeChopping", "ual_Chop"],
	],
}

const LOOP_ANIMS: Array[String] = [
	"Armature|Iddle01", "Armature|Armature|Iddle01",
	"Armature|Walk", "Armature|Armature|Walk",
	"ual_Walk", "ual_Sprint", "ual_Dance",
]

func _init() -> void:
	print(">>> Baking ready miner (Miner.glb + UAL) to miner_package_model.tscn...")
	_convert()
	quit(0)

func _convert() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file("res://assets/models/character/miner_ready_fixed.glb", state) != OK:
		print("FAIL: cannot read miner_ready_fixed.glb")
		return
	var node: Node = doc.generate_scene(state)
	node.name = "MinerPackageModel"

	var ap: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	if ap == null:
		print("FAIL: no AnimationPlayer in baked miner")
		node.free()
		return
	print("Native animations: ", ap.get_animation_list())

	_remap_ual_into(ap)
	for a_name in LOOP_ANIMS:
		if ap.has_animation(a_name):
			ap.get_animation(a_name).loop_mode = Animation.LOOP_LINEAR
	print("All animations: ", ap.get_animation_list())
	for a_name in ap.get_animation_list():
		print("  %s len=%.2f tracks=%d" % [a_name, ap.get_animation(a_name).length, ap.get_animation(a_name).get_track_count()])

	var sk: Skeleton3D = node.find_child("Skeleton3D", true, false)
	if sk:
		print("Bones: ", sk.get_bone_count())

	_set_owner_recursive(node, node)
	var packed := PackedScene.new()
	if packed.pack(node) != OK:
		print("FAIL: pack error")
		node.free()
		return
	var save_err := ResourceSaver.save(packed, "res://scenes/player/miner_package_model.tscn")
	print("OK: saved miner_package_model.tscn" if save_err == OK else "FAIL: save error")
	node.free()

func _remap_ual_into(ap: AnimationPlayer) -> void:
	var target_lib: AnimationLibrary = null
	if ap.has_animation_library(""):
		target_lib = ap.get_animation_library("")
	else:
		target_lib = AnimationLibrary.new()
		ap.add_animation_library("", target_lib)
	# Префикс треков модели: "Armature/Skeleton3D:Bone" (берём из родной анимации).
	var prefix: String = _detect_prefix(ap)
	print("Track prefix: ", prefix)
	for ual_path in UAL_MAP.keys():
		var ual_packed: PackedScene = load(ual_path)
		if ual_packed == null:
			print("WARN: cannot load ", ual_path)
			continue
		var inst: Node = ual_packed.instantiate()
		var src_ap: AnimationPlayer = _find_ap(inst)
		if src_ap == null or not src_ap.has_animation_library(""):
			print("WARN: no animations in ", ual_path)
			inst.free()
			continue
		var src_lib: AnimationLibrary = src_ap.get_animation_library("")
		print(ual_path, " provides: ", _lib_names(src_lib))
		for pair in UAL_MAP[ual_path]:
			_remap_one(src_lib, pair[0], pair[1], target_lib, prefix)
		inst.free()

func _remap_one(src_lib: AnimationLibrary, src_name: String, dest_name: String, target_lib: AnimationLibrary, prefix: String) -> void:
	if not src_lib.has_animation(src_name):
		print("WARN: UAL missing: ", src_name)
		return
	var anim: Animation = src_lib.get_animation(src_name).duplicate()
	var to_remove: Array[int] = []
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			to_remove.append(t)
			continue
		var path_str := String(anim.track_get_path(t))
		var bone: String = path_str.get_slice(":", 1) if path_str.contains(":") else path_str.get_file()
		if BONE_MAP.has(bone):
			anim.track_set_path(t, NodePath(prefix + BONE_MAP[bone]))
		else:
			to_remove.append(t)
	to_remove.reverse()
	for t in to_remove:
		anim.remove_track(t)
	target_lib.add_animation(dest_name, anim)
	print("  remapped %s -> %s (%d tracks)" % [src_name, dest_name, anim.get_track_count()])

func _detect_prefix(ap: AnimationPlayer) -> String:
	for a_name in ap.get_animation_list():
		var anim: Animation = ap.get_animation(a_name)
		for t in range(anim.get_track_count()):
			var p := String(anim.track_get_path(t))
			if p.contains(":"):
				return p.get_slice(":", 0) + ":"
	return "Armature/Skeleton3D:"

func _lib_names(lib: AnimationLibrary) -> Array:
	var out: Array = []
	for a_name in lib.get_animation_list():
		out.append(a_name)
	return out

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f: AnimationPlayer = _find_ap(c)
		if f:
			return f
	return null

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
