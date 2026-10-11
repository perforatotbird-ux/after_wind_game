extends SceneTree
## Новая модель героя (tools/rig_hero_model.py -> tools/retarget_ual_to_miner.gd):
## лёгкий skinned меш с атласом, рост ~1.75 м, стоит на земле, кирка — отдельный меш
## на сокете хвата и проходит через кулак, каска — отдельный skinned меш.

var player: Node3D
var frames := 0
var errors: Array[String] = []

func _initialize() -> void:
	player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)

func _skinned_min_max(mi: MeshInstance3D, sk: Skeleton3D) -> Array:
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var to_pl: Transform3D = player.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	for i in range(0, vs.size(), 5):
		var p := Vector3.ZERO
		for j in 4:
			var w := ws[i * 4 + j]
			if w <= 0.0:
				continue
			var bi := bones[i * 4 + j]
			var b := mi.skin.get_bind_bone(bi)
			if b < 0:
				b = sk.find_bone(mi.skin.get_bind_name(bi))
			p += w * (sk.get_bone_global_pose(b) * mi.skin.get_bind_pose(bi) * vs[i])
		var y := (to_pl * p).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return [lo, hi]

func _process(_d: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	player.set_process(false)
	player.set_physics_process(false)
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
	var body: MeshInstance3D = player.find_child("Miner_Body", true, false)
	var helmet: MeshInstance3D = player.find_child("Character_Helmet", true, false)
	var pick: MeshInstance3D = player.find_child("Pickaxe", true, false)
	if sk == null or ap == null or body == null or helmet == null or pick == null:
		errors.append("нет скелета/AnimationPlayer/Miner_Body/Character_Helmet/Pickaxe")
		return _finish()
	# 1. Лёгкие меши и атлас.
	var tris: int = body.mesh.surface_get_array_index_len(0) / 3
	if tris < 8000 or tris > 22000:
		errors.append("тело: %d треугольников (ожидается 8–22 тыс.)" % tris)
	var mat := body.mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null or mat.albedo_texture == null or mat.albedo_texture.get_width() < 1024 or not mat.normal_enabled:
		errors.append("у тела нет атласа цвета/нормалей")
	if helmet.skin == null or helmet.mesh.surface_get_material(0) != mat:
		errors.append("каска должна быть skinned и с атласом тела")
	# 2. Рост и стопы на земле (idle).
	ap.play("idle"); ap.seek(0.0, true); ap.pause(); ap.advance(0.0)
	sk.force_update_all_bone_transforms()
	var mm := _skinned_min_max(body, sk)
	var top: float = _skinned_min_max(helmet, sk)[1]
	print("  • idle: низ %.3f м, макушка каски %.3f м, тело %d tris" % [mm[0], top, tris])
	if absf(mm[0]) > 0.08:
		errors.append("стопы не на земле: низ модели %.3f м" % mm[0])
	if top < 1.55 or top > 1.95:
		errors.append("рост героя %.2f м вне 1.55–1.95" % top)
	# 3. Кирка — на сокете хвата, черенок проходит через кулак.
	if pick.get_parent() == null or pick.get_parent().name != "ToolSocket_R":
		errors.append("кирка не на ToolSocket_R")
	var pv: PackedVector3Array = pick.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var near := INF
	var far := 0.0
	for v in pv:
		near = minf(near, (pick.transform * v).length())
		far = maxf(far, (pick.transform * v).length())
	if near > 0.05:
		errors.append("черенок не проходит через кулак (%.3f м от центра хвата)" % near)
	if far < 0.5 or far > 1.4:
		errors.append("размер кирки подозрителен: %.2f м от хвата до головки" % far)
	var hand := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hand.r")).origin
	var sock := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("ToolSocket.R")).origin
	if hand.distance_to(sock) > 0.15:
		errors.append("сокет хвата далеко от кисти: %.2f м" % hand.distance_to(sock))
	return _finish()

func _finish() -> bool:
	if errors.is_empty():
		print("HERO MODEL OK")
		quit(0)
	else:
		for e in errors:
			print("FAIL: " + e)
		quit(1)
	return true
