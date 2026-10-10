extends SceneTree
## Новая модель печи-плавильни из Blender: запечённый атлас, светящаяся топка спереди,
## коллизии, габариты и то, что печь не залезает на соседние станки.
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")

var errors: Array[String] = []
var world: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	# 1. Ресурсы модели — текстовые .tres, каждый меньше 1 МиБ.
	for f in ["smelter_body_mesh", "smelter_glow_mesh", "smelter_material", "smelter_glow_material", "smelter_albedo", "smelter_normal", "smelter_orm"]:
		var path := "res://assets/models/smelter/%s.tres" % f
		check(FileAccess.file_exists(path), "Нет ресурса %s" % path)
		if FileAccess.file_exists(path):
			check(FileAccess.get_file_as_bytes(path).size() < 1024 * 1024, "%s больше 1 МиБ" % path)
	# 2. Сцена печи.
	var smelter: Node3D = load("res://scenes/machines/smelter.tscn").instantiate()
	root.add_child(smelter)
	check(smelter.get("machine_type") == "furnace", "Печь потеряла тип станка")
	for old in ["Visual/Body", "Visual/Chimney", "Visual/DoorFrame"]:
		check(smelter.get_node_or_null(old) == null, "Остался старый узел %s" % old)
	var model := smelter.get_node_or_null("Visual/Model") as MeshInstance3D
	check(model != null and model.mesh != null, "Нет меша модели")
	if model and model.mesh:
		var mat := model.mesh.surface_get_material(0) as StandardMaterial3D
		check(mat != null, "Нет материала атласа")
		if mat:
			check(mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024, "Нет запечённой текстуры цвета")
			check(mat.normal_enabled and mat.normal_texture != null, "Нет карты нормалей")
			check(mat.roughness_texture != null and mat.metallic_texture != null, "Нет карты шероховатости/металла")
			var img: Image = mat.albedo_texture.get_image()
			check(img.get_width() > 0, "Текстура цвета пуста")
		var tris: int = 0
		for s in model.mesh.get_surface_count():
			tris += (model.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		check(tris > 3000 and tris < 20000, "Неожиданное число треугольников: %d" % tris)
		var box: AABB = model.mesh.get_aabb()
		check(box.size.y > 3.3 and box.size.y < 4.6, "Высота печи %.2f вне 3.3–4.6 м" % box.size.y)
		check(box.size.x < 3.2, "Печь с мехами и ящиком шире 3.2 м: %.2f" % box.size.x)
		check(box.position.y > -0.1, "Модель уходит под землю")
	var glow := smelter.get_node_or_null("Visual/FireGlowMesh") as MeshInstance3D
	check(glow != null and glow.mesh != null, "Нет светящейся топки")
	if glow and glow.mesh:
		var gm := glow.mesh.surface_get_material(0) as StandardMaterial3D
		check(gm != null and gm.emission_enabled, "Топка не светится")
		check(glow.mesh.get_aabb().get_center().z > 0.3, "Топка не на фасаде (+Z)")
	var light := smelter.get_node_or_null("Visual/FireLight") as OmniLight3D
	check(light != null and light.position.z > 1.0, "Свет топки не перед фасадом")
	var shapes: Array = smelter.get_node("SolidBody").find_children("*", "CollisionShape3D", true, false)
	check(shapes.size() >= 3, "Нет коллизий корпуса, мехов и ящика")
	smelter.queue_free()
	# 3. В мире печь не наезжает на соседей.
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var props: Node = world.get_node("Props")
	var sm: Node3D = props.get_node("Smelter")
	var r: Rect2 = MeadowDecor.node_footprint(sm)
	check(r.size.x > 2.0 and r.size.y > 2.0, "Слишком маленький след печи")
	for n in ["StoneCrusher", "Workbench", "WaterFilter", "RepairableStorage", "BatteryBank"]:
		var other := props.get_node_or_null(n) as Node3D
		if other:
			check(not r.intersects(MeadowDecor.node_footprint(other)), "Печь пересекается с %s" % n)
	if errors.is_empty():
		print("PASS: test_smelter_model — новая модель печи, атлас, свечение, коллизии, место на базе")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
