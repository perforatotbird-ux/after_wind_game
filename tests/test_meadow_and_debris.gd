extends SceneTree
## Луг: без шаров глины/песка на карте, шейдер земли, трава, цветы, кусты и мелкий мусор
## не залезают на станки, жилы и двор; глина и песок остаются в жилах.
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const MeadowGround = preload("res://scripts/world/meadow_ground.gd")
const VoxelDeposit = preload("res://scripts/world/voxel_deposit.gd")

var errors: Array[String] = []
var world: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 4:
		_run()
		return _finish()
	return false

func _run() -> void:
	# 1. На карте больше нет отдельных узлов глины и песка.
	var text: String = FileAccess.get_file_as_string("res://scenes/world/world.tscn")
	check(not text.contains("clay_node.tscn") and not text.contains("sand_node.tscn"), "В мире остались шары глины/песка")
	for n in world.find_children("*", "Area3D", true, false):
		if n is VoxelDeposit:
			continue
		var rid = n.get("resource_id")
		check(rid != "clay" and rid != "sand", "Ресурсный узел %s (%s) всё ещё на карте" % [n.name, rid])
	check(world.get_node_or_null("DirtYard") == null, "Старый плоский квадрат двора не удалён")
	# 2. Глина и песок — из жил.
	var sand := 0
	var clay := 0
	for d in world.get_tree().get_nodes_in_group(VoxelDeposit.GROUP):
		sand += d.count_material(VoxelDeposit.Mat.SAND)
		clay += d.count_material(VoxelDeposit.Mat.CLAY)
	check(sand >= 40 and clay >= 40, "Мало глины/песка в жилах: песок %d, глина %d" % [sand, clay])
	# 3. Земля — шейдер луга с вытоптанным двором.
	var ground: Node = world.get_node("Ground")
	var mats: Array = []
	for mi in ground.find_children("*", "MeshInstance3D", true, false):
		var m = mi.material_override if mi.material_override else (mi.mesh.surface_get_material(0) if mi.mesh else null)
		mats.append(m)
	check(not mats.is_empty() and mats.all(func(m): return m is ShaderMaterial), "Земля не использует шейдер луга")
	check(MeadowGround.yard_signed_distance(Vector2.ZERO) < 0.0, "Центр двора не внутри двора")
	check(MeadowGround.yard_signed_distance(Vector2(30, 30)) > 0.0, "Дальний луг внутри двора")
	# 4. Декор сгенерирован в нужных количествах.
	var meadow: Node = world.get_node("Meadow")
	var c: Dictionary = meadow.counts
	check(int(c.get("grass", 0)) >= 6000, "Мало травы: %s" % c.get("grass"))
	check(int(c.get("flowers", 0)) >= 300, "Мало цветов")
	check(int(c.get("bushes", 0)) >= 25, "Мало кустов")
	for k in ["pebbles", "sticks", "leaves", "mushrooms", "planks", "bricks", "sheets"]:
		check(int(c.get(k, 0)) >= 10, "Мало мусора «%s»" % k)
	# 5. Кусты твёрдые и не стоят во дворе/на станках/жилах.
	var bushes: Array = world.get_tree().get_nodes_in_group(MeadowDecor.BUSH_GROUP)
	check(bushes.size() == int(c.get("bushes", -1)), "Число кустов не совпадает")
	var blocked: Array[Rect2] = []
	for d in world.get_tree().get_nodes_in_group(VoxelDeposit.GROUP):
		blocked.append(d.get_footprint_rect())
	for n in world.get_node("Props").get_children():
		if n is Node3D and n.name != "Rocks":
			blocked.append(MeadowDecor.node_footprint(n))
	for b in bushes:
		check(b is StaticBody3D and not b.find_children("*", "CollisionShape3D", true, false).is_empty(), "Куст %s без коллизии" % b.name)
		var p := Vector2(b.global_position.x, b.global_position.z)
		check(MeadowGround.yard_signed_distance(p) > 0.5, "Куст %s во дворе" % b.name)
		for r in blocked:
			check(not r.has_point(p), "Куст %s стоит на станке/жиле" % b.name)
	# 6. Ни травинки и ни соринки внутри станков; на жилах растёт только трава
	# (она прячется при раскопке), прочий декор жилы обходит.
	var prop_rects: Array[Rect2] = blocked.slice(world.get_tree().get_nodes_in_group(VoxelDeposit.GROUP).size())
	var bad := 0
	var total := 0
	for mmi in meadow.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = mmi.multimesh
		var rects: Array[Rect2] = prop_rects if String(mmi.name).begins_with("Grass") else blocked
		for i in mm.instance_count:
			var o: Vector3 = mmi.global_transform * mm.get_instance_transform(i).origin
			var p := Vector2(o.x, o.z)
			total += 1
			for r in rects:
				if r.has_point(p):
					bad += 1
					break
	check(total > 8000, "Мало экземпляров декора: %d" % total)
	check(bad == 0, "%d экземпляров декора внутри станков/жил" % bad)
	# 7. Детерминизм: пересборка даёт те же кусты.
	var before: Array = meadow.bush_positions.duplicate()
	meadow.generate()
	check(meadow.bush_positions == before, "Генерация декора не детерминирована")

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_meadow_and_debris — луг, кусты, мусор, глина/песок только в жилах")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
