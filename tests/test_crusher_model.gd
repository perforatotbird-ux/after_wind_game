extends SceneTree
## Новая дробилка из Blender: запечённый атлас, подвижные части с центрами на осях,
## анимация в работе (маховики, шкив ×4.8, шатун, камни, лампа, щебень и пыль) и её
## затухание после остановки; коллизии и место на базе.
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")

var errors: Array[String] = []
var world: Node
var frames := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n

func _initialize() -> void:
	# 1. Ресурсы — текстовые .tres меньше 1 МиБ; промт и референс на месте.
	for f in ["crusher_body_mesh", "crusher_flywheel_mesh", "crusher_jaw_mesh", "crusher_pulley_mesh", "crusher_stones_mesh",
			"crusher_lamp_mesh", "crusher_material", "crusher_lamp_material", "crusher_albedo", "crusher_normal", "crusher_orm"]:
		var path := "res://assets/models/crusher/%s.tres" % f
		check(FileAccess.file_exists(path), "Нет ресурса %s" % path)
		if FileAccess.file_exists(path):
			check(FileAccess.get_file_as_bytes(path).size() < 1024 * 1024, "%s больше 1 МиБ" % path)
	for f in ["res://docs/art/crusher_reference.svg", "res://docs/art/crusher_reference_prompt.md"]:
		check(FileAccess.file_exists(f), "Нет %s" % f)
	# 2. Сцена.
	var crusher: Node3D = load("res://scenes/machines/crusher.tscn").instantiate()
	root.add_child(crusher)
	check(crusher.get("machine_type") == "crusher", "Дробилка потеряла тип станка")
	for old in ["Visual/Body", "Visual/Hopper", "Visual/Chute"]:
		check(crusher.get_node_or_null(old) == null, "Остался старый узел %s" % old)
	check(float(crusher.get("shake_strength")) < 0.5, "Корпус дробилки трясётся слишком сильно")
	var model := crusher.get_node_or_null("Visual/Model") as MeshInstance3D
	check(model != null and model.mesh != null, "Нет меша корпуса")
	var total := 0
	if model and model.mesh:
		var mat := model.mesh.surface_get_material(0) as StandardMaterial3D
		check(mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024, "Нет запечённой текстуры цвета")
		if mat:
			check(mat.normal_enabled and mat.normal_texture != null, "Нет карты нормалей")
			check(mat.ao_enabled and mat.ao_texture != null, "Нет запечённого AO")
			check(mat.roughness_texture != null and mat.metallic_texture != null, "Нет карты шероховатости/металла")
		var box: AABB = model.mesh.get_aabb()
		check(box.size.y > 1.5 and box.size.y < 2.2, "Высота дробилки %.2f вне 1.5–2.2 м" % box.size.y)
		check(box.size.x < 2.6 and box.size.z < 3.0, "Дробилка слишком широкая: %s" % box.size)
		check(box.position.y > -0.05, "Модель уходит под землю")
		check(box.end.z > 1.0, "Лоток не смотрит во двор (+Z)")
		total += _tris(model.mesh)
	# Подвижные части — отдельные меши; центр меша — на оси вращения.
	for part in ["Flywheel", "Jaw", "Pulley", "Stones", "Lamp"]:
		var mi := crusher.get_node_or_null("Visual/" + part) as MeshInstance3D
		check(mi != null and mi.mesh != null, "Нет подвижной части %s" % part)
		if mi and mi.mesh:
			total += _tris(mi.mesh)
	check(total > 6000 and total < 30000, "Неожиданное число треугольников: %d" % total)
	var fly := crusher.get_node_or_null("Visual/Flywheel") as MeshInstance3D
	if fly and fly.mesh:
		var fb: AABB = fly.mesh.get_aabb()
		check(fb.size.y > 1.0 and fb.size.y < 1.15 and absf(fb.get_center().y) < 0.03 and absf(fb.get_center().z) < 0.03, "Маховик не центрирован на валу: %s" % fb)
		check(fb.size.x > 1.3, "Нет второго маховика/вала: %s" % fb)
	var pul := crusher.get_node_or_null("Visual/Pulley") as MeshInstance3D
	if pul and pul.mesh:
		var pb: AABB = pul.mesh.get_aabb()
		check(absf(pb.get_center().y) < 0.02 and absf(pb.get_center().z) < 0.02 and pb.size.y < 0.3, "Шкив не центрирован на оси: %s" % pb)
	# 3. Анимация.
	var anim = crusher.get_node_or_null("Visual/Animator")
	check(anim != null and anim.has_method("is_running"), "Нет аниматора дробилки")
	if anim:
		anim._ready()
		var lamp_mat := (crusher.get_node("Visual/Lamp") as MeshInstance3D).material_override as StandardMaterial3D
		check(lamp_mat != null, "Лампа без своего материала")
		crusher.process_duration = 100000.0
		crusher.is_machine_running = true
		var jaw0: Vector3 = crusher.get_node("Visual/Jaw").position
		for i in 60:
			anim._process(0.05)
		check(is_equal_approx(anim.speed, 1.0), "Дробилка не вышла на полный ход: %.2f" % anim.speed)
		var f0: float = anim.flywheel_angle
		var p0: float = anim.pulley_angle
		anim._process(0.01)
		var df: float = wrapf(anim.flywheel_angle - f0, -PI, PI)
		var dp: float = wrapf(anim.pulley_angle - p0, -PI, PI)
		check(df > 0.0 and absf(dp / df - anim.pulley_ratio) < 0.05, "Шкив не крутится в %.1f раза быстрее маховика (%.3f / %.3f)" % [anim.pulley_ratio, dp, df])
		check(is_equal_approx(crusher.get_node("Visual/Flywheel").rotation.x, -anim.flywheel_angle), "Маховик не повёрнут")
		var moved := false
		for i in 5:
			anim._process(0.03)
			moved = moved or crusher.get_node("Visual/Jaw").position.distance_to(jaw0) > 0.01
		check(moved, "Шатун не ходит по эксцентрику")
		check(lamp_mat != null and lamp_mat.emission_energy_multiplier > 0.5, "Лампа «работа» не горит")
		check((crusher.get_node("Visual/GravelParticles") as GPUParticles3D).emitting, "Не сыплется щебень")
		check((crusher.get_node("Visual/DustParticles") as GPUParticles3D).emitting, "Нет пыли")
		# Остановка: лампа гаснет сразу, маховик крутится по инерции и останавливается.
		crusher.is_machine_running = false
		anim._process(0.05)
		check(lamp_mat != null and lamp_mat.emission_energy_multiplier < 0.01, "Лампа горит после остановки")
		check(anim.speed > 0.5, "Маховик остановился мгновенно, без выбега")
		for i in 100:
			anim._process(0.05)
		check(anim.speed == 0.0, "Маховик не остановился")
		check(not (crusher.get_node("Visual/GravelParticles") as GPUParticles3D).emitting, "Щебень сыплется у стоящей дробилки")
	var shapes: Array = crusher.get_node("SolidBody").find_children("*", "CollisionShape3D", true, false)
	check(shapes.size() >= 3, "Мало коллизий: корпус, рама, мотор")
	crusher.queue_free()
	# 4. В мире дробилка не наезжает на соседние станки и грядки.
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var props: Node = world.get_node("Props")
	var cr: Node3D = props.get_node("StoneCrusher")
	var r: Rect2 = MeadowDecor.node_footprint(cr)
	check(r.size.x > 1.5 and r.size.y > 1.5, "Слишком маленький след дробилки")
	for n in ["Smelter", "Workbench", "WaterFilter", "RepairableStorage", "BatteryBank", "FarmlandPlot1"]:
		var other := props.get_node_or_null(n) as Node3D
		if other:
			check(not r.intersects(MeadowDecor.node_footprint(other)), "Дробилка пересекается с %s" % n)
	if errors.is_empty():
		print("PASS: test_crusher_model — модель дробилки, атлас, подвижные части, анимация, место на базе")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true
