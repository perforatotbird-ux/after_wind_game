extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 2...")
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
	print("========================================")
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 2: СУТОЧНЫЙ ЦИКЛ И УСТАЛОСТЬ")
	print("========================================")
	
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	
	var day_cycle = world.get_node_or_null("DayNightCycle")
	if not day_cycle: _fail("DayNightCycle отсутствует в сцене мира")
	
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player отсутствует в сцене")
	
	var hud = world.get_node_or_null("HUD")
	if not hud: _fail("HUD отсутствует в сцене")
	
	var house = world.find_child("RepairableHouse", true, false)
	if not house: _fail("RepairableHouse отсутствует в сцене")
	
	print("✅ Все ключевые узлы (DayNightCycle, Player, HUD, House) найдены.")
	
	# 1. Проверка начального времени (08:00, Утро, День 1)
	if day_cycle.current_day != 1: _fail("Начальный день != 1")
	if day_cycle.get_current_phase() != "Утро": _fail("Начальная фаза != Утро")
	if day_cycle.is_night(): _fail("is_night() возвращает true для 08:00")
	print("✅ Начальное время: День 1, 08:00 (Утро).")
	
	# 2. Проверка смены фаз суток
	day_cycle.current_hour = 13.0
	if day_cycle.get_current_phase() != "День": _fail("Фаза в 13:00 != День")
	
	day_cycle.current_hour = 19.0
	if day_cycle.get_current_phase() != "Вечер": _fail("Фаза в 19:00 != Вечер")
	
	day_cycle.current_hour = 23.5
	if day_cycle.get_current_phase() != "Ночь": _fail("Фаза в 23:30 != Ночь")
	if not day_cycle.is_night(): _fail("is_night() возвращает false для 23:30")
	print("✅ Смена фаз суток (Утро -> День -> Вечер -> Ночь) функционирует корректно.")
	
	# 3. Проверка градации усталости персонажа
	player.energy = 100.0
	if player.get_speed_multiplier() != 1.0: _fail("Скорость при 100% != 1.0")
	if not player.can_sprint(): _fail("Спринт недоступен при 100% энергии")
	
	player.energy = 35.0
	if player.get_speed_multiplier() >= 1.0: _fail("Скорость не снизилась при 35% энергии")
	if not player.can_sprint(): _fail("Спринт должен быть еще доступен при 35%")
	
	player.energy = 10.0
	if player.can_sprint(): _fail("Спринт должен блокироваться при энергии < 20%")
	if player.get_speed_multiplier() > 0.75: _fail("Скорость недостаточно снижена при 10%")
	
	player.energy = 0.0
	if player.can_sprint(): _fail("Спринт должен блокироваться при 0% энергии")
	if player.get_speed_multiplier() > 0.55: _fail("Скорость должна быть 50% при истощении")
	print("✅ Градация усталости (Бодр -> Легкая усталость -> Блокировка спринта -> Истощение) подтверждена.")
	
	# 4. Проверка ночного сна и перемотки на новый день
	# Повышаем стадию дома до 2 (восстановлен с кроватью)
	house.current_stage = 2
	day_cycle.current_hour = 23.0 # Глубокая ночь
	player.energy = 5.0 # Персонаж истощен
	
	house.sleep(player)
	
	if day_cycle.current_day != 2: _fail("Сон не переключил сутки на День 2 (текущий: %d)" % day_cycle.current_day)
	if abs(day_cycle.current_hour - 6.0) > 0.1: _fail("Сон не установил утреннее время 06:00 (текущее: %.1f)" % day_cycle.current_hour)
	if player.energy < 99.9: _fail("Сон не восстановил энергию игрока до 100%")
	if not player.can_sprint(): _fail("Спринт не разблокировался после сна")
	print("✅ Механика сна в доме: время перемотано на День 2 (06:00, Утро), силы восстановлены на 100%!")
	
	# 5. Проверка обновления HUD
	if hud.time_label.text.is_empty(): _fail("TimeLabel пуст")
	print("✅ Отображение времени в интерфейсе HUD: '%s'." % hud.time_label.text)
	
	print("========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 2 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	
	quit(0)
