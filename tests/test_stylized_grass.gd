extends SceneTree
## Стилизованная трава: густой ковёр изогнутых листьев с LOD, клевер, лёгкие пучки,
## трава растёт на жилах и пропадает над выкопанными блоками; гладкая моховая земля.
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")
const MeadowGrass = preload("res://scripts/world/meadow_grass.gd")
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
	var meadow: Node = world.find_children("*", "", true, false).filter(func(n): return n is MeadowDecor).front()
	check(meadow != null, "Нет узла луга")
	if meadow == null:
		return
	var c: Dictionary = meadow.counts
	# 1. Густой ковёр и клевер.
	check(int(c.get("grass", 0)) >= 30000, "Трава недостаточно густая: %s" % c.get("grass"))
	check(int(c.get("clover", 0)) >= 1000, "Мало клевера: %s" % c.get("clover"))
	# 2. Пучки лёгкие и правильной высоты.
	for kind in MeadowGrass.VARIANTS.keys():
		for v in int(MeadowGrass.VARIANTS[kind]):
			var mesh: Mesh = MeadowGrass.get_mesh(kind, v)
			check(mesh != null, "Нет меша травы %s/%d" % [kind, v])
			if mesh == null:
				continue
			check(MeadowGrass.triangle_count(mesh) <= 120, "Пучок %s/%d слишком тяжёлый: %d" % [kind, v, MeadowGrass.triangle_count(mesh)])
			var h: float = mesh.get_aabb().size.y
			if kind == MeadowGrass.Kind.LUSH:
				check(h > 0.2 and h < 0.55, "Высота сочного пучка %.2f" % h)
			elif kind == MeadowGrass.Kind.TALL:
				check(h > 0.45, "Высокая трава слишком низкая: %.2f" % h)
	# 3. Шейдер: двусторонние листья с просвечиванием.
	var code: String = (MeadowGrass.get_grass_material().shader as Shader).code
	check(code.contains("cull_disabled") and code.contains("BACKLIGHT"), "Шейдер травы без двусторонности/просвечивания")
	# 4. LOD: ближние пучки обрезаются, дальний план включается после них.
	var near := 0
	var far := 0
	for mmi in world.get_tree().get_nodes_in_group(MeadowDecor.GRASS_GROUP):
		near += 1
		check(mmi.visibility_range_end > 0.0, "Ближняя трава %s без дальности видимости" % mmi.name)
	for mmi in meadow.find_children("GrassFar_*", "MultiMeshInstance3D", true, false):
		far += 1
		check(mmi.visibility_range_begin > 0.0, "Дальняя трава %s видна вблизи" % mmi.name)
	check(near > 50 and far > 10, "Нет разбиения травы на куски/LOD: %d/%d" % [near, far])
	# 5. Земля — гладкий мох без пиксельной текстуры.
	var ground_src: String = FileAccess.get_file_as_string("res://scripts/world/meadow_ground.gd")
	check(not ground_src.contains("grass_tex") and not ground_src.contains("VoxelTextures"), "Земля всё ещё с пиксельной текстурой")
	# 6. Трава на жиле пропадает, когда выкопан блок под ней.
	check(not meadow._deposit_grass.is_empty(), "На жилах нет травы")
	if not meadow._deposit_grass.is_empty():
		var ref: Array = meadow._deposit_grass[0]
		var d: Node = ref[2]
		var xf: Transform3D = ref[3]
		var cell: Vector3i = d.global_to_cell(Vector3(xf.origin.x, -0.25, xf.origin.z))
		check(int(c.get("grass_hidden", 0)) == 0, "Трава спрятана до раскопок")
		d.voxels[d._index(cell)] = VoxelDeposit.Mat.AIR
		d.rebuild()
		check(int(meadow.counts.get("grass_hidden", 0)) > 0, "Трава не пропала над выкопанным блоком")
		# Сам буфер экземпляров в headless не читается, поэтому проверяем счётчик.
	# 7. Генерация не тормозит загрузку.
	var t0 := Time.get_ticks_msec()
	meadow.generate()
	var dt := Time.get_ticks_msec() - t0
	check(dt < 3000, "Генерация луга слишком долгая: %d мс" % dt)

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_stylized_grass — густая стилизованная трава, LOD, клевер, трава на жилах")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
