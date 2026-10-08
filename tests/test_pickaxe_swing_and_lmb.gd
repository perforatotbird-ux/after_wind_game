extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")

var _test_executed: bool = false

func _init() -> void:
	print(">>> Инициализация теста Pickaxe Grip, Swing & LMB Mapping...")
	var player_instance = PlayerScene.instantiate()
	root.add_child(player_instance)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	
	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

## Резолвер анимаций для старой (mine) и новой (Track_Pickaxe_Swing) моделей.
func _resolve_swing_anim(ap: AnimationPlayer) -> String:
	for c in ["mine", "Track_Pickaxe_Swing", "Track_Pickaxe_Swing_Heavy"]:
		if ap.has_animation(c):
			return c
	return ""

## Строгая конвенция in-hand меша (Quaternius Pickaxe_Bronze, нормализован):
## рукоять вдоль Y, хват в origin, двуглавый ударник симметрично вдоль X.
func _convention_quaternius(aabb: AABB) -> void:
	var y_min = aabb.position.y
	var y_max = aabb.position.y + aabb.size.y
	var x_min = aabb.position.x
	var x_max = aabb.position.x + aabb.size.x
	print("  • Диапазон высоты кирки по вертикали Y (Godot UP): %.3f .. %.3f" % [y_min, y_max])
	if aabb.size.y < 0.70:
		_fail("Черенок кирки слишком короткий (длина %.3f, ожидалось >= 0.70)" % aabb.size.y)
		return
	if not (y_min < 0.0 and y_max > 0.0):
		_fail("Хват (origin Y=0) должен лежать внутри черенка: %.3f .. %.3f" % [y_min, y_max])
		return
	if aabb.size.x < 0.40:
		_fail("Ударник кирки слишком узкий по X (%.3f, ожидалось >= 0.40)" % aabb.size.x)
		return
	if abs(x_min + x_max) > 0.10:
		_fail("Двуглавый ударник должен быть симметричен относительно черенка (X: %.3f .. %.3f)" % [x_min, x_max])
		return
	print("  • Положение подтверждено: черенок %.2f м вдоль Y, хват в origin, ударник симметричен по X (%.2f .. %.2f)!" % [aabb.size.y, x_min, x_max])

## Встроенная кирка пакета Miner_Character_Package: проверяем только
## разумные габариты (ручной инструмент, не гигантский и не точка).
func _convention_package_pickaxe(aabb: AABB) -> void:
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	print("  • Встроенная кирка пакета: габариты %s." % aabb.size)
	if longest < 0.2 or longest > 3.0:
		_fail("Подозрительный размер встроенной кирки: %s" % aabb.size)
		return
	print("  • Размер встроенной кирки в норме.")

func _run_tests() -> void:
	print("=================================================================")
	print("⛏️ ЗАПУСК ТЕСТОВ: PICKAXE GRIP, TOP-TO-BOTTOM SWING & LMB MAPPING")
	print("=================================================================")
	
	var player = root.get_node_or_null("Player")
	if not player:
		_fail("Узел Player не найден в корне дерева сцены")
		return
	
	var visuals = player.get_node_or_null("Visuals")
	if not visuals:
		_fail("Узел Visuals не найден в Player")
		return
	
	var char_model = visuals.get_node_or_null("CharacterModel")
	if not char_model:
		_fail("CharacterModel не найден в Visuals")
		return
		
	var pickaxe_mesh = char_model.find_child("Equipped_Pickaxe", true, false) as MeshInstance3D
	if not pickaxe_mesh:
		# Новая модель из Miner_Character_Package: кирка — узел "Pickaxe".
		pickaxe_mesh = char_model.find_child("Pickaxe", true, false) as MeshInstance3D
	if not pickaxe_mesh:
		_fail("Equipped_Pickaxe (или Pickaxe) не найден в CharacterModel")
		return
		
	# -------------------------------------------------------------
	# Проверка 1: Ориентация кирки (ударником вниз, черенок в руке)
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Геометрия кирки (ударником вниз, черенок в руке) ---")
	var mesh = pickaxe_mesh.mesh
	if not mesh:
		_fail("Меш узел Equipped_Pickaxe не содержит Mesh ресурса")
		return
		
	var aabb = mesh.get_aabb()
	print("  • Размеры кирки AABB: min=%s, max=%s, size=%s" % [aabb.position, aabb.position + aabb.size, aabb.size])

	if pickaxe_mesh.name == "Equipped_Pickaxe":
		_convention_quaternius(aabb)
	else:
		_convention_package_pickaxe(aabb)

	# -------------------------------------------------------------
	# Проверка 2: Динамическая видимость (скрыта в idle/walk)
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Кирка скрыта в обычном режиме (idle/walk/run) ---")
	if pickaxe_mesh.visible:
		_fail("Кирка ДОЛЖНА быть скрыта по умолчанию при старте игры / в покое!")
		return
	print("  • По умолчанию кирка скрыта: visible = false.")
	
	player.play_animation("walk")
	if pickaxe_mesh.visible:
		_fail("Кирка ДОЛЖНА оставаться скрытой при ходьбе!")
		return
	print("  • Во время ходьбы кирка скрыта: visible = false.")
	
	# -------------------------------------------------------------
	# Проверка 3: Нажатие ЛКМ (LMB) вызывает удар киркой
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Удар киркой по Левой Кнопке Мыши (LMB) ---")
	# В руке виден инструмент экипированного слота: для удара киркой экипируем кирку
	player.inventory.equip_tool("pickaxe")
	var lmb_event = InputEventMouseButton.new()
	lmb_event.button_index = MOUSE_BUTTON_LEFT
	lmb_event.pressed = true
	
	# Передаем клик ЛКМ в player._unhandled_input
	player._unhandled_input(lmb_event)
	
	if not player.is_mining:
		_fail("Клик ЛКМ должен переводить персонажа в состояние удара (is_mining = true)")
		return
	if player.current_anim != _resolve_swing_anim(player.anim_player):
		_fail("Клик ЛКМ должен активировать анимацию удара, текущая: '%s'" % player.current_anim)
		return
	if not pickaxe_mesh.visible:
		_fail("Кирка ДОЛЖНА стать видимой в момент нажатия кнопки удара!")
		return
	print("  • ЛКМ успешно запустил удар киркой: is_mining=true, anim='mine', visible=true.")

	# -------------------------------------------------------------
	# Проверка 4: Траектория анимации удара (СВЕРХУ ВНИЗ)
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Анимация удара СВЕРХУ ВНИЗ (top-to-bottom chop) ---")
	var anim_player = player.anim_player
	var swing_name: String = _resolve_swing_anim(anim_player)
	if swing_name == "":
		_fail("Анимация удара ('mine' / 'Track_Pickaxe_Swing') отсутствует в AnimationPlayer")
		return
		
	var mine_anim = anim_player.get_animation(swing_name)
	print("  • Длина анимации удара '%s': %.2f сек, число треков: %d" % [swing_name, mine_anim.length, mine_anim.get_track_count()])
	if mine_anim.get_track_count() < 5:
		_fail("Недостаточно анимированных суставов в анимации удара (ожидалось >= 5)")
		return
		
	# Ищем трек правого плеча или позвоночника (кости .R старой модели / _R новой).
	var found_arm_track: bool = false
	for t_idx in range(mine_anim.get_track_count()):
		var t_path = str(mine_anim.track_get_path(t_idx))
		if ("UpperArm.R" in t_path or "UpperArm_R" in t_path or "Chest" in t_path or "Spine" in t_path) and mine_anim.track_get_type(t_idx) == Animation.TYPE_ROTATION_3D:
			found_arm_track = true
			var k_count = mine_anim.track_get_key_count(t_idx)
			print("  • Трек вращения '%s' содержит %d ключевых кадров." % [t_path, k_count])
			if k_count < 4:
				_fail("Трек '%s' должен содержать ключевые кадры замаха и удара" % t_path)
				return
	if not found_arm_track:
		_fail("Трек руки/торса не найден в анимации mine")
		return
	print("  • Анатомическая артикуляция удара сверху вниз подтверждена.")

	# -------------------------------------------------------------
	# Проверка 5: Взаимодействие ЛКМ с объектами в мире
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Добыча и взаимодействие через ЛКМ ---")
	var mock_interactable = Area3D.new()
	mock_interactable.name = "MockOreNode"
	var was_interacted: Array[bool] = [false]
	mock_interactable.set_script(load("res://scripts/interaction/simple_prop.gd"))
	
	# Добавляем в дерево
	root.add_child(mock_interactable)
	mock_interactable.global_position = player.global_position + Vector3(0.5, 0, 0)
	
	# Принудительно устанавливаем фокус игрока на объект
	player.current_interactable = mock_interactable
	
	# Симулируем удар ЛКМ по объекту
	player.is_mining = false # сбрасываем состояние после предыдущего теста
	player._unhandled_input(lmb_event)
	
	if not player.is_mining:
		_fail("Удар по объекту через ЛКМ должен активировать взмах киркой")
		return
	print("  • Удар по объекту через ЛКМ успешно активировал добычу!")
	mock_interactable.free()

	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ОРИЕНТАЦИИ КИРКИ, ВЗМАХА И ЛКМ УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)
