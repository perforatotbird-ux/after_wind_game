extends SceneTree
## Склад продукции из Blender в трёх состояниях: руины (стадия 0), амбар (каркас + тент на
## стадии 1, каркас + стены и кровля на стадии 2), логистический комплекс (стадия 3) с ручным
## подъёмником на шестернях. Ресурсы, смена стадий, коллизии, анимация, место на базе.
const MeadowDecor = preload("res://scripts/world/meadow_decor.gd")

var errors: Array[String] = []
var world: Node
var storage: Node3D
var frames := 0
var step := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n

func _stage_box(stage: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in stage.find_children("*", "MeshInstance3D", false, false):
		var b: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _stage_tris(stage: Node3D) -> int:
	var n := 0
	for mi in stage.find_children("*", "MeshInstance3D", false, false):
		n += _tris((mi as MeshInstance3D).mesh)
	return n

func _initialize() -> void:
	# 1. Ресурсы — текстовые .tres меньше 1 МиБ; промт и референс на месте.
	var files := ["storage_ruins_mesh", "storage_barn_frame_mesh", "storage_barn_shell_mesh", "storage_barn_tarp_mesh",
		"storage_complex_mesh", "storage_complex_yard_mesh", "storage_complex_gear_mesh", "storage_complex_crank_mesh",
		"storage_complex_chain_mesh", "storage_complex_hook_mesh"]
	for st in ["ruins", "barn", "complex"]:
		for k in ["albedo", "normal", "orm", "material"]:
			files.append("storage_%s_%s" % [st, k])
	for f in files:
		var path := "res://assets/models/storage/%s.tres" % f
		check(FileAccess.file_exists(path), "Нет ресурса %s" % path)
		if FileAccess.file_exists(path):
			check(FileAccess.get_file_as_bytes(path).size() < 1024 * 1024, "%s больше 1 МиБ" % path)
	for f in ["res://docs/art/storage_reference.svg", "res://docs/art/storage_reference_prompt.md"]:
		check(FileAccess.file_exists(f), "Нет %s" % f)
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)

func _check_scene() -> void:
	storage = world.get_node("Props/RepairableStorage")
	for old in ["BrokenCrate1", "CollapsedBeam", "Pallet", "Canopy", "BarnBody", "BarnRoof", "WarehouseBody", "WarehouseRoof"]:
		check(storage.find_child(old, true, false) == null, "Остался старый примитив %s" % old)
	var need := {0: ["Model"], 1: ["Frame", "Tarp"], 2: ["Frame", "Shell"], 3: ["Model", "Yard", "Gear", "Crank", "Chain", "Hook"]}
	for i in 4:
		var stage := storage.get_node_or_null("Visuals/Stage%d" % i) as Node3D
		check(stage != null, "Нет Visuals/Stage%d" % i)
		if stage == null:
			continue
		for n in need[i]:
			var mi := stage.get_node_or_null(n) as MeshInstance3D
			check(mi != null and mi.mesh != null, "Нет меша Stage%d/%s" % [i, n])
			if mi and mi.mesh:
				var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
				check(mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024, "Stage%d/%s без запечённого атласа" % [i, n])
				if mat:
					check(mat.normal_enabled and mat.ao_enabled and mat.roughness_texture != null and mat.metallic_texture != null,
						"Stage%d/%s: нет нормалей/AO/ORM" % [i, n])
		var box := _stage_box(stage)
		var tris := _stage_tris(stage)
		check(box.position.y > -0.12, "Stage%d уходит под землю: %s" % [i, box])
		check(box.size.x < 7.0 and box.size.z < 4.8, "Stage%d слишком большая: %s" % [i, box.size])
		check(tris > 5000 and tris < 50000, "Stage%d: неожиданное число треугольников %d" % [i, tris])
		match i:
			0: check(box.size.y > 2.0 and box.size.y < 3.0, "Руины высотой %.2f, ждём 2–3 м" % box.size.y)
			1, 2: check(box.size.y > 3.3 and box.size.y < 4.2, "Амбар высотой %.2f, ждём 3.3–4.2 м" % box.size.y)
			3: check(box.size.y > 3.9 and box.size.y < 4.8, "Комплекс высотой %.2f, ждём 3.9–4.8 м" % box.size.y)
	# Стадии 1 и 2 — одно состояние: общий каркас, разные «одежды».
	var f1 := storage.get_node_or_null("Visuals/Stage1/Frame") as MeshInstance3D
	var f2 := storage.get_node_or_null("Visuals/Stage2/Frame") as MeshInstance3D
	if f1 and f2:
		check(f1.mesh == f2.mesh, "Каркас амбара на стадиях 1 и 2 должен быть общим")
	var shell := storage.get_node_or_null("Visuals/Stage2/Shell") as MeshInstance3D
	if shell and shell.mesh:
		check(shell.get_aabb().end.z > 1.8, "Ворота амбара не смотрят во двор (+Z)")
	# Подвижные части подъёмника: центр меша — на оси.
	var gear := storage.get_node_or_null("Visuals/Stage3/Gear") as MeshInstance3D
	if gear and gear.mesh:
		var gb := gear.get_aabb()
		check(gb.get_center().length() < 0.03 and gb.size.x > 0.3 and gb.size.x < 0.4, "Шестерня не центрирована на оси: %s" % gb)
	var chain := storage.get_node_or_null("Visuals/Stage3/Chain") as MeshInstance3D
	if chain and chain.mesh:
		var cb := chain.get_aabb()
		check(absf(cb.end.y) < 0.05 and cb.size.y > 1.3, "Цепь должна свисать от точки подвеса: %s" % cb)

func _set_stage(i: int) -> void:
	storage.current_stage = i
	storage._update_visuals()

func _check_stage_switch(i: int) -> void:
	for k in 4:
		var vis: bool = (storage.get_node("Visuals/Stage%d" % k) as Node3D).visible
		check(vis == (k == i), "Стадия %d: Stage%d visible=%s" % [i, k, vis])
	var sort := storage.get_node("StaticBody3D/Stage3Sorting") as CollisionShape3D
	check(sort.disabled == (i != 3), "Стадия %d: коллизия сортировочного навеса disabled=%s" % [i, sort.disabled])
	check(not (storage.get_node("StaticBody3D/SolidShape") as CollisionShape3D).disabled, "Основная коллизия склада выключена")

func _check_hoist() -> void:
	var anim = storage.get_node_or_null("Visuals/Stage3/HoistAnimator")
	check(anim != null and anim.has_method("lift_fraction"), "Нет аниматора подъёмника")
	if anim == null:
		return
	var hook := storage.get_node("Visuals/Stage3/Hook") as Node3D
	var chain := storage.get_node("Visuals/Stage3/Chain") as Node3D
	var gear := storage.get_node("Visuals/Stage3/Gear") as Node3D
	var crank := storage.get_node("Visuals/Stage3/Crank") as Node3D
	anim.time = 0.0
	anim._apply()
	var hook0: float = hook.position.y
	check(is_zero_approx(anim.lift) and is_zero_approx(gear.rotation.z), "В начале цикла ящик должен стоять на поддоне")
	check(absf(hook0 - 1.0) < 0.01, "Крюк в покое не над поддоном: %.3f" % hook0)
	anim.time = anim.cycle_time * 0.5
	anim._apply()
	check(is_equal_approx(anim.lift, anim.lift_height), "Ящик не поднялся до верха: %.3f" % anim.lift)
	check(absf(hook.position.y - hook0 - anim.lift_height) < 0.03, "Крюк не поднялся вместе с цепью")
	check(chain.scale.y < 0.8, "Цепь не укоротилась: %.2f" % chain.scale.y)
	check(absf(gear.rotation.z - anim.lift_height / anim.drum_radius) < 0.001, "Шестерня не повернулась на подъём / радиус барабана")
	check(absf(crank.rotation.z + gear.rotation.z * anim.gear_ratio) < 0.001, "Рукоять не крутится в %.2f раза быстрее и навстречу" % anim.gear_ratio)
	var moved := false
	var a0: float = hook.rotation.z
	for k in 10:
		anim._process(0.1)
		moved = moved or absf(hook.rotation.z - a0) > 0.005
	check(moved, "Поднятый ящик не покачивается")
	anim.time = anim.cycle_time * 0.95
	anim._apply()
	check(is_zero_approx(anim.lift) and absf(hook.position.y - hook0) < 0.01, "Ящик не вернулся на поддон")

func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	match step:
		0:
			_check_scene()
			_set_stage(0)
		1:
			_check_stage_switch(0)
			_set_stage(1)
		2:
			_check_stage_switch(1)
			_set_stage(2)
		3:
			_check_stage_switch(2)
			_set_stage(3)
		4:
			_check_stage_switch(3)
			_check_hoist()
			var r: Rect2 = MeadowDecor.node_footprint(storage)
			check(r.size.x > 4.0 and r.size.y > 3.5, "Слишком маленький след склада: %s" % r)
			for n in ["Smelter", "StoneCrusher", "Workbench", "RepairableHouse", "BatteryBank", "DispatchStation", "WindTurbine", "FarmlandPlot1", "FarmlandPlot2"]:
				var other := world.get_node("Props").get_node_or_null(n) as Node3D
				if other:
					check(not r.intersects(MeadowDecor.node_footprint(other)), "Склад пересекается с %s" % n)
		5:
			if errors.is_empty():
				print("PASS: test_storage_model — склад в трёх состояниях, атласы, стадии, коллизии, подъёмник, место на базе")
				quit(0)
			else:
				for e in errors:
					print("ПРОВАЛЕН: ", e)
				quit(1)
			return true
	step += 1
	return false
