extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")

var _test_executed: bool = false
var _notifications: Array[String] = []

func _init() -> void:
	print("Инициализация теста сна, голода, жажды и здоровья...")
	var world_node = WorldScene.instantiate()
	root.add_child(world_node)

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

func _run_tests() -> void:
	print("====================================================")
	print("🧪 ЗАПУСК ТЕСТОВ: ЗДОРОВЬЕ И ГОЛОД/ЖАЖДА ВО ВРЕМЯ СНА")
	print("====================================================")

	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return

	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Узел Player не найден в сцене")
		return

	player.notification_received.connect(func(msg: String):
		_notifications.append(msg)
	)

	var dc = world.get_node_or_null("DayNightCycle")
	if not dc:
		_fail("Узел DayNightCycle не найден в сцене")
		return

	# -------------------------------------------------------------
	# Проверка 1: Сон при нулевой еде и воде наносит урон здоровью
	# и НЕ подбрасывает сытость и жажду до 20-35%
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Сон на 2 часа при 0 сытости и 0 жажды ---")
	player.health = 100.0
	player.energy = 50.0
	player.hunger = 0.0
	player.thirst = 0.0
	player.hours_without_sleep = 5.0
	_notifications.clear()

	player.start_rest(2.0, true)

	print("  • После 2 ч сна с 0 еды/воды: Здоровье=%.1f, Жажда=%.1f, Сытость=%.1f" % [player.health, player.thirst, player.hunger])

	if player.health >= 90.0:
		_fail("Здоровье не уменьшилось при сне с 0 еды и 0 воды! Текущее здоровье: %.1f" % player.health)
		return

	# За 2 часа при 0 жажды (0.25 HP/с) и 0 сытости (0.15 HP/с) урон должен составить ~48 HP
	# (100 - 48 = ~52 HP)
	if player.health > 60.0 or player.health < 45.0:
		_fail("Урон здоровью за 2 ч сна с 0 еды/воды должен быть ~48 HP, получено здоровье: %.1f" % player.health)
		return

	if player.thirst > 0.001:
		_fail("Жажда после сна подпрыгнула до %.1f%% вместо того чтобы остаться на 0%%!" % player.thirst)
		return

	if player.hunger > 0.001:
		_fail("Сытость после сна подпрыгнула до %.1f%% вместо того чтобы остаться на 0%%!" % player.hunger)
		return

	print("  • Проверка 1 пройдена: здоровье упало со 100 до %.1f HP, сытость и жажда остались 0%%" % player.health)

	# -------------------------------------------------------------
	# Проверка 2: Длительный сон 12 часов при 0 еды и 0 воды приводит к истощению/обмороку
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Длительный сон 12 часов при 0 еды и воде ---")
	player.health = 40.0
	player.energy = 20.0
	player.hunger = 0.0
	player.thirst = 0.0
	_notifications.clear()

	player.start_rest(12.0, true)

	print("  • Результат после сна: Здоровье=%.1f, Уведомления: %s" % [player.health, str(_notifications)])
	if player.thirst > 0.001 or player.hunger > 0.001:
		_fail("Сытость или жажда после сна подпрыгнули (Жажда=%.1f, Сытость=%.1f)!" % [player.thirst, player.hunger])
		return

	var collapse_found: bool = false
	for n in _notifications:
		if "Вы упали без сил от истощения" in n or "потеряли сознание" in n:
			collapse_found = true
			break

	if not collapse_found:
		_fail("При 40 HP и 12 ч сна без еды и воды персонаж должен был упасть в обморок!")
		return

	print("  • Проверка 2 пройдена: зафиксирован обморок от истощения во время сна")

	# -------------------------------------------------------------
	# Проверка 3: Обычный здоровый сон (сытость и жажда >= 25%) нормально лечит здоровье
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Здоровый сон (сытость 100%, жажда 100%) лечит здоровье ---")
	paused = false
	player._collapse_active = false
	player.health = 50.0
	player.energy = 20.0
	player.hunger = 100.0
	player.thirst = 100.0
	player.hours_without_sleep = 12.0
	_notifications.clear()

	player.start_rest(6.0, true)

	print("  • После 6 ч здорового сна: Здоровье=%.1f, Энергия=%.1f, Жажда=%.1f, Сытость=%.1f" % [player.health, player.energy, player.thirst, player.hunger])
	if player.health < 99.0:
		_fail("При достаточном питании и питье 6 ч сна должны восстановить здоровье (>=99%%), текущее: %.1f" % player.health)
		return

	if player.energy < 99.0:
		_fail("6 ч сна должны восстановить энергию (>=99%%), текущая: %.1f" % player.energy)
		return

	if player.thirst >= 100.0 or player.hunger >= 100.0:
		_fail("Сытость и жажда должны были уменьшиться за 6 ч сна!")
		return

	print("  • Проверка 3 пройдена: здоровый сон восстановил здоровье и энергию до 100%")

	print("\n====================================================")
	print("🎉 ВСЕ ТЕСТЫ ЗДОРОВЬЯ, ГОЛОДА И ЖАЖДЫ ВО СНЕ ПРОЙДЕНЫ!")
	print("====================================================")
	quit(0)
