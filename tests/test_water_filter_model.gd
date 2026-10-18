extends SceneTree
## Присланный очиститель: два состояния, восстановление, износ/ремонт, коллизии и сейвы.
const Save = preload("res://scripts/core/save_manager.gd")
const SAVE_PATH := "user://test_water_filter_model.json"
var world: Node3D
var errors: Array[String] = []

func _initialize() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	root.add_child(world)
	call_deferred("run_checks")

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FAIL: " + message)

func model_stats(model: Node3D) -> Dictionary:
	var triangles := 0
	var bounds := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
		var box: AABB = t * mi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for s in mi.mesh.get_surface_count():
			triangles += mi.mesh.surface_get_array_index_len(s) / 3
	return {"triangles": triangles, "bounds": bounds}

func run_checks() -> void:
	for i in 4: await process_frame
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var filter = world.find_child("WaterFilter", true, false)
	var player = world.get_node("Player")
	var inv = player.inventory
	check(filter is ProductionMachine, "Очиститель наследует общую механику станков")
	check(filter.visual_node == filter.get_node("Visual") and filter.ruined_visual == filter.get_node("Ruined"), "Обе ссылки на визуальные состояния разрешены")
	check(not filter.rebuilt and not filter.visual_node.visible and filter.ruined_visual.visible, "На старте мира показан разрушенный очиститель")
	check(filter.get_node_or_null("Visual/TopRawDrum") == null, "Старая модель из примитивов удалена")
	check(filter.get_node("Ruined/WaterFilterRuined").scene_file_path.ends_with("water_filter_ruined.tscn"), "Руины очистителя заменяют общую кучу камней")
	var repaired: Dictionary = model_stats(filter.visual_node)
	var ruined: Dictionary = model_stats(filter.ruined_visual)
	for pair in [["repaired", repaired], ["ruined", ruined]]:
		var stats: Dictionary = pair[1]; var box: AABB = stats.bounds
		print("FILTER ", pair[0], " triangles=", stats.triangles, " bounds=", box)
		check(stats.triangles >= 25000 and stats.triangles < 40000, "Бюджет 25–40 тыс. треугольников: " + pair[0])
		check(absf(box.position.y) < 0.04, "Модель стоит на земле: " + pair[0])
		check(box.size.x < 2.35 and box.size.z < 2.35 and box.size.y > 1.65 and box.size.y < 2.3, "Габариты станка: " + pair[0])
	check(absf(repaired.bounds.size.y - 2.15) < 0.05, "Высота исправной модели 2.15 м")
	check(ruined.triangles != repaired.triangles, "Руины имеют другую геометрию, а не только перекраску")
	var main: MeshInstance3D = filter.visual_node.find_child("FilterRepaired_00_00", true, false)
	var broken: MeshInstance3D = filter.ruined_visual.find_child("FilterBrokenBase_00_00", true, false)
	check(main != null and broken != null, "Присланная геометрия присутствует в двух состояниях")
	if main and broken:
		var clean_mat := main.mesh.surface_get_material(0) as StandardMaterial3D
		var damaged_mat := broken.mesh.surface_get_material(0) as StandardMaterial3D
		check(clean_mat.albedo_texture.get_width() == 1024 and clean_mat.normal_enabled, "PBR-цвет и нормали сохранены")
		check(clean_mat.albedo_texture == damaged_mat.albedo_texture, "Два состояния используют общий атлас")
		check(damaged_mat.vertex_color_use_as_albedo and broken.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null, "Ржавчина/грязь по вершинам руин")
	# Failed restoration cannot change the visual or consume resources.
	inv.items.clear(); inv.credits = 0
	check(not filter.rebuild(player), "Восстановление без ресурсов не проходит")
	check(filter.ruined_visual.visible and not filter.rebuilt, "Неудачный ремонт оставляет руины")
	check(Save.save_game(world, SAVE_PATH), "Сохранение разрушенного состояния")
	filter.force_rebuilt()
	check(Save.load_game(world, SAVE_PATH), "Загрузка разрушенного состояния")
	check(not filter.rebuilt and filter.ruined_visual.visible, "Сейв возвращает разрушенную модель")
	inv.items.clear(); inv.items["sand"] = 8; inv.items["wood"] = 4; inv.credits = 100
	check(filter.rebuild(player), "Восстановление за прежнюю стоимость")
	check(inv.credits == 70 and inv.get_item_count("sand") == 0 and inv.get_item_count("wood") == 0, "Списано 8 песка + 4 дерева + 30 кредитов")
	check(filter.visual_node.visible and not filter.ruined_visual.visible, "После восстановления показана присланная исправная модель")
	await process_frame
	check(not filter.get_node("SolidBody/RepairedTowerShape").disabled and filter.get_node("SolidBody/RuinedTowerShape").disabled, "Коллизия исправной колонны включена")
	check(Save.save_game(world, SAVE_PATH), "Сохранение исправного состояния")
	filter.set_rebuilt(false)
	check(Save.load_game(world, SAVE_PATH), "Загрузка исправного состояния")
	check(filter.rebuilt and filter.visual_node.visible and not filter.ruined_visual.visible, "Сейв возвращает исправную модель")
	# Wear breakdown uses the broken variant; normal maintenance restores the original.
	filter.wear.set_condition(0.0)
	check(filter.ruined_visual.visible and not filter.visual_node.visible, "Полный износ показывает поломку")
	await process_frame
	check(filter.get_node("SolidBody/RepairedTowerShape").disabled and not filter.get_node("SolidBody/RuinedTowerShape").disabled, "Коллизия разрушенной колонны включена")
	check(not filter.start_recipe("filter_water", player), "Поломанный очиститель не производит воду")
	check(Save.save_game(world, SAVE_PATH), "Сохранение поломки по износу")
	filter.wear.repair(100)
	check(Save.load_game(world, SAVE_PATH), "Загрузка поломки по износу")
	check(filter.rebuilt and filter.wear.is_broken() and filter.ruined_visual.visible, "Поломка по износу сохраняет правильный внешний вид")
	inv.items["bolt"] = 2; inv.items["wooden_handle"] = 1
	check(filter.repair_machine(player), "Ремонт износа прежними деталями")
	check(filter.visual_node.visible and not filter.ruined_visual.visible, "После обслуживания возвращена исправная модель")
	filter.wear.set_condition(25)
	check(filter.visual_node.visible, "Частичный износ не разрушает геометрию")
	filter.set_powered(false)
	check(filter.visual_node.visible, "Пауза без электричества не означает разрушение")
	filter.set_powered(true)
	inv.items["water"] = 2; inv.items["sand"] = 1; inv.items["sawdust"] = 1; inv.items["stone_dust"] = 1; player.energy = 100
	check(filter.start_recipe("filter_water", player), "Исправный очиститель фильтрует воду")
	filter._process(filter.process_duration + 0.1)
	check(inv.get_item_count("clean_water") == 2 or int(filter.pending_outputs.get("clean_water", 0)) == 2, "Выход воды не изменён")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if errors.is_empty(): print("PASS: test_water_filter_model")
	quit(0 if errors.is_empty() else 1)
