extends SceneTree

## Тест модели озера, интерактивной механики, шейдера, сбора сырой воды и размещения в мире.

const ResourceNodeScript = preload("res://scripts/resources/resource_node.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const Seasons = preload("res://scripts/core/seasons.gd")

class MockPlayer extends Node:
	var inventory: Node
	var energy: float = 100.0
	var messages: Array[String] = []

	func notify(t: String) -> void:
		messages.append(t)

	func consume_energy(amount: float) -> bool:
		energy = maxf(0.0, energy - amount)
		return true

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		printerr("FAIL: " + msg)

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	Seasons.current_season = ""
	_test_lake_model_assets()
	_test_lake_scene_and_properties()
	_test_water_harvesting()
	_test_winter_freezing()
	_test_world_integration()

	if errors.is_empty():
		print("PASS: test_lake_model — модель озера, интерактивность, забор воды и мир проверены успешно")
		quit(0)
	else:
		for e in errors:
			printerr("ПРОВАЛЕН: " + e)
		quit(1)

func _test_lake_model_assets() -> void:
	var model_scene = load("res://assets/models/lake/lake_model.tscn")
	check(model_scene != null, "Не удалось загрузить res://assets/models/lake/lake_model.tscn")
	if not model_scene:
		return

	var model = model_scene.instantiate()
	root.add_child(model)

	var expected_groups: Array[String] = [
		"SculptedBank", "LakeBasin", "EarthStrata", "ShrubLeaves",
		"GrassTufts", "ShrubBranches", "ReedLeaves", "CattailHeads",
		"ShorePebbles", "WaterSurface", "WetShoreline"
	]
	for g in expected_groups:
		check(model.has_node(g), "В LakeModel отсутствует группа %s" % g)

	# Проверка треугольников и мешей
	var total_tris: int = 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		check(mi.mesh != null, "MeshInstance3D %s не имеет меша" % mi.name)
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				total_tris += mi.mesh.surface_get_array_index_len(i) / 3
	check(total_tris > 50000, "Ожидалось > 50000 треугольников в озере, факт: %d" % total_tris)

	# Проверка шейдера воды
	var water_mat = load("res://assets/models/lake/lake_water_material.tres")
	check(water_mat != null and water_mat is ShaderMaterial, "lake_water_material.tres должен быть ShaderMaterial")
	if water_mat is ShaderMaterial:
		check(water_mat.shader != null, "У lake_water_material.tres не назначен шейдер")

	# Проверка EarthStrata: узел существует, но скрыт (не торчит срез диорамы над лугом)
	var earth = model.get_node_or_null("EarthStrata")
	check(earth != null, "EarthStrata должен присутствовать в LakeModel")
	if earth:
		check(not earth.visible, "EarthStrata должен быть скрыт (visible = false), чтобы срез диорамы не выступал над поверхностью")

	# Проверка сглаживания внешнего края берега SculptedBank до Y = 0.0
	var bank = model.get_node_or_null("SculptedBank")
	check(bank != null, "SculptedBank должен присутствовать в LakeModel")
	if bank:
		var max_outer_y: float = -999.0
		for mi in bank.find_children("*", "MeshInstance3D", true, false):
			var mesh: ArrayMesh = mi.mesh
			var arrays = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var a = atan2(-v.z / 0.91, v.x)
				var r = sqrt(v.x * v.x + (-v.z / 0.91) * (-v.z / 0.91))
				var r_in = 3.35 * (1.0 + 0.068 * sin(a * 3.0 + 0.4) + 0.039 * sin(a * 5.0 - 0.9) + 0.017 * sin(a * 9.0))
				var r_out = 4.92 / pow(pow(absf(cos(a)), 4.0) + pow(absf(sin(a)), 4.0), 0.25) * (1.0 + 0.013 * sin(a * 7.0) + 0.009 * sin(a * 11.0))
				var t = (r - r_in * 0.948) / (r_out - r_in * 0.948)
				if t >= 0.99:
					max_outer_y = maxf(max_outer_y, v.y)
		check(max_outer_y <= 0.001, "Внешний край берега озера должен лежать вровень с землёй Y=0.0 (факт: %.4f)" % max_outer_y)

	model.queue_free()

func _test_lake_scene_and_properties() -> void:
	var lake_scene = load("res://scenes/resources/lake.tscn")
	check(lake_scene != null, "Не удалось загрузить res://scenes/resources/lake.tscn")
	if not lake_scene:
		return

	var lake = lake_scene.instantiate()
	root.add_child(lake)

	check(lake is ResourceNodeScript, "Lake должен наследоваться от ResourceNode")
	check(lake.resource_id == "water", "resource_id должен быть 'water'")
	check(lake.object_name == "Озеро" or lake.resource_display_name == "Озеро", "Имя ресурса должно быть 'Озеро'")
	check(lake.required_tool == "bucket", "required_tool должен быть 'bucket'")
	check(lake.action_verb == "Набрать", "action_verb должен быть 'Набрать'")
	check(lake.max_hits >= 5, "max_hits озера должно быть >= 5 (задано %d)" % lake.max_hits)
	check(lake.yield_per_hit >= 2.0, "yield_per_hit озера должно быть >= 2.0")
	check(lake.freezes_in_winter == true, "freezes_in_winter озера должно быть true")
	check(lake.collision_layer == 8, "collision_layer озера должен быть 8 (Interactables)")

	# Зона взаимодействия
	var col = lake.get_node_or_null("CollisionShape3D")
	check(col != null and col.shape is CylinderShape3D, "У озера должен быть CylinderShape3D для взаимодействия")
	if col and col.shape is CylinderShape3D:
		check((col.shape as CylinderShape3D).radius >= 6.0, "Радиус взаимодействия с озером должен быть >= 6.0 м")

	# Физическое ограничение глубокой воды
	var solid = lake.get_node_or_null("SolidBody")
	check(solid != null and solid is StaticBody3D, "У озера должен быть SolidBody для предотвращения проваливания")

	# Проверка отсутствия тряски/мигания при заборе воды
	var initial_scale: Vector3 = lake.visual_node.scale
	lake._play_hit_effect()
	check(lake.visual_node.scale == initial_scale, "Озеро не должно масштабироваться или мигать при заборе воды (_play_hit_effect)")

	lake.queue_free()

func _test_water_harvesting() -> void:
	var lake_scene = load("res://scenes/resources/lake.tscn")
	var lake = lake_scene.instantiate()
	root.add_child(lake)

	var player = MockPlayer.new()
	player.inventory = InventoryScript.new()
	player.add_child(player.inventory)
	root.add_child(player)

	# 1. Без ведра забор невозможен
	lake.interact(player)
	check(player.inventory.get_item_count("water") == 0, "Без ведра вода не должна добываться")
	check(player.messages.size() > 0 and player.messages[-1].contains("Требуется"), "Должно быть предупреждение о ведре")

	# 2. Экипируем ведро и набираем воду
	player.inventory.equip_tool("bucket")
	var hits_before: int = lake.current_hits
	lake.interact(player)
	var water_count: int = player.inventory.get_item_count("water")
	check(water_count == int(lake.yield_per_hit), "Забор воды должен давать yield_per_hit единиц сырой воды (факт: %d)" % water_count)
	check(lake.current_hits == hits_before - 1, "Число ударов должно уменьшиться на 1")

	# 3. Полное исчерпание и уход на респаун
	while lake.current_hits > 0:
		lake.interact(player)

	check(lake.is_depleted, "После исчерпания ударов озеро должно быть is_depleted")
	check(lake.get_prompt().contains("истощён"), "Подсказка должна сообщать об истощении озера")
	# Озеро НЕ должно исчезать или сжиматься в точку
	check(lake.visual_node != null and lake.visual_node.visible == true, "Озеро не должно скрываться при истощении жилы (visual_node.visible must be true)")
	check(lake.visual_node.scale == lake._original_scale, "Озеро не должно сжиматься при истощении (scale must remain _original_scale)")

	lake.queue_free()
	player.queue_free()

func _test_winter_freezing() -> void:
	var lake_scene = load("res://scenes/resources/lake.tscn")
	var lake = lake_scene.instantiate()
	root.add_child(lake)

	var player = MockPlayer.new()
	player.inventory = InventoryScript.new()
	player.inventory.equip_tool("bucket")
	player.add_child(player.inventory)
	root.add_child(player)

	# Весна — вода доступна
	Seasons.activate(Seasons.SPRING, 1)
	check(not lake.is_frozen(), "Весной озеро не должно быть замёрзшим")
	check(lake.get_prompt().contains("[E]"), "Весной с озера можно брать воду")

	# Зима — открытый водоём замерзает
	Seasons.activate(Seasons.WINTER, 1)
	check(lake.is_frozen(), "Зимой открытое озеро должно замерзать")
	check(lake.get_prompt().contains("замёрзла"), "Подсказка должна содержать 'замёрзла': %s" % lake.get_prompt())

	var water_before: int = player.inventory.get_item_count("water")
	lake.interact(player)
	check(player.inventory.get_item_count("water") == water_before, "Из замёрзшего озера нельзя набирать воду")
	check(player.messages.size() > 0 and player.messages[-1].contains("замёрзла"), "Должно быть уведомление о замёрзшей воде")

	Seasons.activate(Seasons.SPRING, 1)
	lake.queue_free()
	player.queue_free()

func _test_world_integration() -> void:
	var world_text: String = FileAccess.get_file_as_string("res://scenes/world/world.tscn")
	check(not world_text.is_empty(), "Не удалось прочитать res://scenes/world/world.tscn")

	# Старая жила WaterWell должна быть полностью убрана
	check(not world_text.contains("WaterWell"), "В сценарном файле world.tscn не должно остаться WaterWell")
	check(not world_text.contains("water_node.tscn"), "В сценарном файле world.tscn не должно остаться water_node.tscn")

	# Новое озеро Lake должно присутствовать в Resources
	check(world_text.contains('path="res://scenes/resources/lake.tscn"'), "В world.tscn должен быть ExtResource lake.tscn")
	check(world_text.contains('[node name="Lake" parent="Resources"'), "В world.tscn узел Lake должен быть дочерним к Resources")

	# Координаты озера: рядом с лесом (-15, 0, 12)
	check(world_text.contains("-15, 0, 12"), "Озеро должно быть размещено на координатах (-15, 0, 12) рядом с лесом")
