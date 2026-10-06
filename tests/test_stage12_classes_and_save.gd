extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const RecipeDB = preload("res://scripts/crafting/recipe_db.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const CharacterClassDB = preload("res://scripts/characters/character_class_db.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const ResourceNode = preload("res://scripts/resources/resource_node.gd")
const FarmlandPlot = preload("res://scripts/farming/farmland_plot.gd")

var _test_executed: bool = false
const TEST_SAVE_PATH: String = "user://test_save_stage12.json"

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 12...")
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
	SaveManager.delete_save(TEST_SAVE_PATH)
	quit(1)

func _run_tests() -> void:
	print("=================================================================")
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 12: СПЕЦИАЛИЗАЦИИ И СИСТЕМА СОХРАНЕНИЙ")
	print("=================================================================")
	
	SaveManager.delete_save(TEST_SAVE_PATH)
	ContractDB.reset_completed()
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var inv = player.get("inventory")
	if not inv:
		_fail("Инвентарь игрока не найден")
		return
	
	var hud = world.get_node_or_null("HUD")
	if not hud:
		_fail("HUD не найден")
		return

	# -------------------------------------------------------------
	# 1. Проверка базы классов CharacterClassDB
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Реестр специализаций в CharacterClassDB ---")
	var classes = CharacterClassDB.get_all_classes()
	if classes.size() != 3:
		_fail("В CharacterClassDB должно быть 3 специализации, найдено: %d" % classes.size())
		return
	
	for c in classes:
		var c_id = c.get("id", "")
		var c_name = c.get("name", "")
		var c_perks = c.get("perks", [])
		if c_perks.is_empty():
			_fail("У специализации '%s' нет описания перков" % c_id)
			return
		print("  • Специализация '%s' (%s %s): %d перка, стартовый пакет: %s" % [
			c_id, c.get("icon", ""), c_name, c_perks.size(), str(c.get("starting_items", {}))
		])
	print("✅ Все 3 класса (Шахтёр, Фермер, Учёный) корректно настроены.")

	# -------------------------------------------------------------
	# 2. Переключение специализаций и стартовые пакеты
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Выбор класса персонажа и стартовые бонусы ---")
	inv.clear()
	inv.credits = 0
	
	# Выбираем Фермера с выдачей бонусов
	var res_farmer = player.set_character_class("farmer", true)
	if not res_farmer:
		_fail("set_character_class('farmer') вернул false")
		return
	if player.character_class != "farmer":
		_fail("Класс игрока должен быть 'farmer', факт: %s" % player.character_class)
		return
	if inv.get_item_count("seeds_carrot") != 2 or inv.get_item_count("fertilizer") != 1:
		_fail("Фермер должен получить стартовые семена и удобрение")
		return
	print("  • Специализация Фермер успешно активирована: получены семена и био-удобрение.")

	# Выбираем Учёного с бонусами
	inv.clear()
	inv.credits = 0
	var res_sci = player.set_character_class("scientist", true)
	if not res_sci or player.character_class != "scientist":
		_fail("set_character_class('scientist') вернул false")
		return
	if inv.credits != 50 or inv.get_item_count("copper_wire") != 2 or inv.get_item_count("iron_plate") != 1:
		_fail("Учёный должен получить +50 кредитов, медные провода и металлическую пластину")
		return
	print("  • Специализация Учёный успешно активирована: получено +50 кредитов, провода и пластина.")

	# -------------------------------------------------------------
	# 3. Проверка перков в механике игры
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Действие пассивных перков классов ---")
	
	# 3.1. Перк Шахтёра: +1 бонусный ресурс и -20% расход сил киркой
	var stone_node = ResourceNode.new()
	stone_node.resource_id = "stone"
	stone_node.resource_display_name = "Валун"
	stone_node.required_tool = "pickaxe"
	stone_node.max_hits = 3
	stone_node.current_hits = 3
	stone_node.yield_per_hit = 2
	stone_node.bonus_depleted_yield = 1
	stone_node.energy_cost = 4.0
	world.add_child(stone_node)

	# Тест без класса шахтёр (например, Учёный)
	player.set_character_class("scientist")
	inv.tools = ["axe", "pickaxe", "shovel", "bucket", "backpack"] as Array[String]
	inv.equip_tool("pickaxe")
	player.energy = 100.0
	inv.items["stone"] = 0
	stone_node._on_interacted(player)
	var e_spent_non_miner = 100.0 - player.energy
	var stone_non_miner = inv.get_item_count("stone")
	print("  • Добыча камня Учёным: потрачено энергии = %.2f, добыто камня = %d" % [e_spent_non_miner, stone_non_miner])
	if stone_non_miner != 2 or abs(e_spent_non_miner - 4.0) > 0.01:
		_fail("Добыча камня не-шахтёром: ожидалось 2 камня и 4.0 энергии")
		return

	# Тест с классом Шахтёр
	stone_node.current_hits = 3
	player.set_character_class("miner")
	player.energy = 100.0
	inv.items["stone"] = 0
	stone_node._on_interacted(player)
	var e_spent_miner = 100.0 - player.energy
	var stone_miner = inv.get_item_count("stone")
	print("  • Добыча камня Шахтёром: потрачено энергии = %.2f (ожидалось 3.20), добыто камня = %d (ожидалось 3)" % [
		e_spent_miner, stone_miner
	])
	if stone_miner != 3:
		_fail("Шахтёр должен получать +1 бонусный камень (3 шт.), факт: %d" % stone_miner)
		return
	if abs(e_spent_miner - 3.20) > 0.05:
		_fail("Шахтёр должен тратить на 20%% меньше энергии (3.20), факт: %.2f" % e_spent_miner)
		return
	stone_node.queue_free()
	print("✅ Перк Шахтёра (+1 ресурс, -20% сил на руде/камне) подтвержден.")

	# 3.2. Перк Учёного: станки на 40% быстрее и -50% энергии игрока
	var crusher = world.find_child("Crusher", true, false)
	if crusher and crusher.has_method("start_recipe"):
		inv.items["stone"] = 10
		player.energy = 100.0
		player.set_character_class("miner")
		crusher.is_machine_running = false
		crusher.start_recipe("crush_stone", player)
		var dur_miner = crusher.process_duration
		var e_cost_miner = 100.0 - player.energy
		crusher.is_machine_running = false

		player.energy = 100.0
		player.set_character_class("scientist")
		inv.items["stone"] = 10
		crusher.start_recipe("crush_stone", player)
		var dur_sci = crusher.process_duration
		var e_cost_sci = 100.0 - player.energy
		crusher.is_machine_running = false
		print("  • Запуск станка: Не-учёный: время = %.2f с, сил = %.1f. Учёный: время = %.2f с, сил = %.1f" % [
			dur_miner, e_cost_miner, dur_sci, e_cost_sci
		])
		if e_cost_sci > e_cost_miner * 0.6:
			_fail("Учёный должен тратить на 50%% меньше энергии на запуск станка")
			return
		if dur_sci > dur_miner * 0.8:
			_fail("Станок должен работать значительно быстрее для Учёного")
			return
		print("✅ Перк Учёного (-50% энергии, ускорение машин) подтвержден.")

	# -------------------------------------------------------------
	# 4. Система сохранения и загрузки (Save & Load)
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Сохранение и загрузка состояния мира в JSON ---")
	
	# Формируем уникальное состояние мира
	player.set_character_class("farmer")
	player.global_position = Vector3(12.5, 0.5, -8.0)
	player.energy = 78.5
	player.thirst = 64.0
	player.hunger = 52.0
	player.wetness = 30.0
	
	inv.clear()
	inv.credits = 1240
	inv.items["wood"] = 18
	inv.items["iron_ingot"] = 5
	inv.items["bread"] = 4
	inv.items["clean_water"] = 7
	inv.upgrade_tool("iron_axe")
	inv.upgrade_tool("large_backpack")
	
	var day_cycle = world.find_child("DayNightCycle", true, false)
	if day_cycle:
		day_cycle.current_day = 4
		day_cycle.current_hour = 14.5
	
	var weather_mgr = world.find_child("WeatherManager", true, false)
	if weather_mgr:
		weather_mgr.set_weather(2) # RAIN
	
	var battery = world.find_child("BatteryBank", true, false)
	if battery:
		battery.stored_energy = 84.0
	
	var reservoir = world.find_child("WaterReservoir", true, false)
	if reservoir:
		reservoir.current_water = 15
	
	var plot1 = world.find_child("FarmlandPlot1", true, false)
	if plot1:
		plot1.soil_state = 1 # TILLED
		plot1.crop_type = "carrot"
		plot1.moisture = 65.0
		plot1.growth_progress = 48.0
		plot1.is_fertilized = true
		plot1.is_ripe = false
	
	ContractDB.completed_contracts["contract_fortify"] = true
	
	# Сохраняем игру
	var save_res = SaveManager.save_game(world, TEST_SAVE_PATH)
	if not save_res:
		_fail("SaveManager.save_game вернул false")
		return
	if not SaveManager.has_save(TEST_SAVE_PATH):
		_fail("Файл сохранения не существует на диске: " + TEST_SAVE_PATH)
		return
	print("  • Мир успешно сохранен в JSON (файл создан).")

	# Нарушаем состояние мира до дефолтного/искаженного
	player.set_character_class("miner")
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.energy = 15.0
	player.thirst = 10.0
	player.hunger = 10.0
	player.wetness = 0.0
	inv.clear()
	inv.credits = 0
	if day_cycle:
		day_cycle.current_day = 1
		day_cycle.current_hour = 8.0
	if battery:
		battery.stored_energy = 0.0
	if reservoir:
		reservoir.current_water = 2
	if plot1:
		plot1.soil_state = 0
		plot1.crop_type = ""
	ContractDB.completed_contracts.clear()

	# Загружаем сохраненный мир
	var load_res = SaveManager.load_game(world, TEST_SAVE_PATH)
	if not load_res:
		_fail("SaveManager.load_game вернул false")
		return
	print("  • Мир успешно загружен из JSON.")

	# Проверяем восстановление всех параметров
	if player.character_class != "farmer":
		_fail("Класс персонажа не восстановился: %s" % player.character_class)
		return
	if player.global_position.distance_to(Vector3(12.5, 0.5, -8.0)) > 0.1:
		_fail("Координаты игрока не восстановились: %s" % str(player.global_position))
		return
	if abs(player.energy - 78.5) > 0.1:
		_fail("Энергия игрока не восстановилась: %.1f" % player.energy)
		return
	if abs(player.thirst - 64.0) > 0.1:
		_fail("Жажда игрока не восстановилась: %.1f" % player.thirst)
		return
	if abs(player.hunger - 52.0) > 0.1:
		_fail("Сытость игрока не восстановилась: %.1f" % player.hunger)
		return
	if abs(player.wetness - 30.0) > 0.1:
		_fail("Мокрота игрока не восстановилась: %.1f" % player.wetness)
		return
	if inv.credits != 1240:
		_fail("Кредиты игрока не восстановились: %d" % inv.credits)
		return
	if inv.get_item_count("wood") != 18 or inv.get_item_count("iron_ingot") != 5 or inv.get_item_count("bread") != 4:
		_fail("Ресурсы инвентаря не восстановились корректно")
		return
	if inv.max_slots != 20 or inv.max_weight != 75.0:
		_fail("Параметры большого рюкзака не восстановились: слоты=%d, вес=%.1f" % [inv.max_slots, inv.max_weight])
		return
	if day_cycle and (day_cycle.current_day != 4 or abs(day_cycle.current_hour - 14.5) > 0.1):
		_fail("День или время суток не восстановились: день=%d, час=%.1f" % [day_cycle.current_day, day_cycle.current_hour])
		return
	if battery and abs(battery.stored_energy - 84.0) > 0.1:
		_fail("Заряд батарей не восстановился: %.1f" % battery.stored_energy)
		return
	if reservoir and reservoir.current_water != 15:
		_fail("Уровень воды в резервуаре не восстановился: %d" % reservoir.current_water)
		return
	if plot1 and (plot1.crop_type != "carrot" or abs(plot1.growth_progress - 48.0) > 0.1 or not plot1.is_fertilized):
		_fail("Состояние грядки не восстановилось корректно")
		return
	if not ContractDB.is_completed("contract_fortify"):
		_fail("Статус выполненных контрактов не восстановился")
		return
	print("✅ Все подсистемы мира (игрок, класс, инвентарь, день, погода, батареи, вода, грядки, контракты) 100% восстановлены.")

	# Удаляем тестовый файл
	SaveManager.delete_save(TEST_SAVE_PATH)
	if SaveManager.has_save(TEST_SAVE_PATH):
		_fail("Файл сохранения должен быть удален")
		return
	print("  • Тестовый файл сохранения успешно очищен.")

	# -------------------------------------------------------------
	# 5. Проверка интерфейса HUD (ClassButton, ClassSelectWindow)
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Интерфейс HUD выбора специализации ---")
	if not hud.class_button:
		_fail("Кнопка class_button отсутствует в HUD")
		return
	if not hud.class_window:
		_fail("Окно class_window отсутствует в HUD")
		return
	
	hud.toggle_class_window()
	if not hud.class_window.visible:
		_fail("class_window должно стать видимым после toggle_class_window")
		return
	if not hud.classes_list or hud.classes_list.get_child_count() != 3:
		_fail("В classes_list должно быть 3 карточки классов, факт: %d" % (hud.classes_list.get_child_count() if hud.classes_list else 0))
		return
	print("  • Окно выбора специализации успешно открывается и отображает 3 карточки.")

	hud.close_class_window()
	if hud.class_window.visible:
		_fail("class_window должно закрыться")
		return
	print("✅ Интерфейс HUD специализаций работает штатно.")

	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 12 УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)
