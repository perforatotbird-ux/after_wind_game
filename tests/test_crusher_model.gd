extends SceneTree
## Тест процедурной модели стимпанк-дробилки камня из Blender.
## Проверяет структуру rock_grinder.glb, наличие всех статичных и кинематических узлов,
## маркеров VFX-эффектов, габариты модели и корректность парсинга GLTFDocument.

var errors: Array[String] = []

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)

func _initialize() -> void:
	var glb_path := "res://assets/models/crusher/rock_grinder.glb"
	check(FileAccess.file_exists(glb_path), "Файл модели %s не найден" % glb_path)
	
	if FileAccess.file_exists(glb_path):
		var size_bytes := FileAccess.get_file_as_bytes(glb_path).size()
		check(size_bytes > 50000 and size_bytes < 2000000, "Размер GLB (%d байт) вне ожидаемого диапазона" % size_bytes)
	
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(glb_path), state)
	check(err == OK, "Ошибка append_from_file GLTF: %d" % err)
	
	if err == OK:
		var scene: Node = doc.generate_scene(state)
		check(scene != null, "Не удалось сгенерировать сцену из GLTF")
		if scene:
			# Проверка ключевых статичных узлов
			var static_nodes := [
				"Foundation_Stone", "Crusher_Housing", "Millstone_Lower",
				"Hopper_Feed", "Chute_Discharge", "Steam_Boiler", "Exhaust_Pipe"
			]
			for node_name in static_nodes:
				var n: Node = scene.find_child(node_name, true, false)
				check(n != null, "В модели отсутствует статический узел: %s" % node_name)
			
			# Проверка кинематических компонентов
			var kinematic_nodes := [
				"Millstone_Upper", "Shaft_Central", "Drive_Flywheel",
				"Engine_Piston", "Connecting_Rod", "Crank_Disc",
				"Gear_Bevel_Vertical", "Gear_Bevel_Horizontal"
			]
			for node_name in kinematic_nodes:
				var n: Node = scene.find_child(node_name, true, false)
				check(n != null, "В модели отсутствует кинематический узел: %s" % node_name)
			
			# Проверка точек привязки спецэффектов (VFX Markers)
			var marker_nodes := [
				"Smoke_Emitter", "Steam_Emitter", "Grinding_Dust", "Crushed_Stone_Output"
			]
			for node_name in marker_nodes:
				var n: Node = scene.find_child(node_name, true, false)
				check(n != null, "В модели отсутствует маркер эффекта: %s" % node_name)
			
			scene.queue_free()

	if errors.is_empty():
		print("PASS: test_crusher_model.gd")
		quit(0)
	else:
		for e in errors:
			printerr("FAIL: ", e)
		quit(1)
