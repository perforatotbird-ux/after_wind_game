extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const GeneratorPanelScene = preload("res://scripts/ui/generator_panel.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования SolidFuelGenerator...")
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
	print("🧪 ЗАПУСК ТЕСТОВ: ТВЕРДОТОПЛИВНЫЙ ГЕНЕРАТОР (SOLID GENERATOR)")
	print("====================================================")

	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return

	var generator = world.get_node_or_null("Props/SolidGenerator")
	if not generator:
		_fail("Узел Props/SolidGenerator не найден в сцене World")
		return

	# 1. Проверка класса, групп и начального состояния
	if not (generator is SolidFuelGenerator):
		_fail("Props/SolidGenerator не является экземпляром SolidFuelGenerator")
		return

	if not generator.is_in_group("power_generators"):
		_fail("Генератор не добавлен в группу power_generators")
		return

	if not generator.is_in_group("interactables"):
		_fail("Генератор не добавлен в группу interactables")
		return

	if generator.is_running:
		_fail("Начальное состояние генератора должно быть выключено (is_running == false)")
		return

	if generator.get_current_output() != 0.0:
		_fail("Начальная мощность генератора должна быть 0.0 кВт")
		return

	if generator.fuel_slots.size() != 4:
		_fail("Мини-инвентарь генератора должен иметь ровно 4 слота, получено: %d" % generator.fuel_slots.size())
		return

	print("  • Базовые свойства и группы проверены успешно")

	# 2. Проверка мини-инвентаря и валидации топлива
	# Попытка добавить неподходящий предмет
	var rejected = generator.add_fuel("stone", 5)
	if rejected != 0:
		_fail("Генератор не должен принимать не-топливо ('stone'), принято: %d" % rejected)
		return

	# Добавление дерева
	var added_wood = generator.add_fuel("wood", 10)
	if added_wood != 10:
		_fail("Ожидалось добавление 10 дерева, добавлено: %d" % added_wood)
		return
	if generator.fuel_slots[0]["item_id"] != "wood" or generator.fuel_slots[0]["count"] != 10:
		_fail("Слот 0 должен содержать 10 дерева")
		return

	# Добавление угля во второй слот
	var added_coal = generator.add_fuel("coal", 5)
	if added_coal != 5:
		_fail("Ожидалось добавление 5 угля, добавлено: %d" % added_coal)
		return
	if generator.fuel_slots[1]["item_id"] != "coal" or generator.fuel_slots[1]["count"] != 5:
		_fail("Слот 1 должен содержать 5 угля")
		return

	# Добавление брикетов в третий слот
	var added_briq = generator.add_fuel("fuel_briquette", 8)
	if added_briq != 8:
		_fail("Ожидалось добавление 8 брикетов, добавлено: %d" % added_briq)
		return
	if generator.fuel_slots[2]["item_id"] != "fuel_briquette" or generator.fuel_slots[2]["count"] != 8:
		_fail("Слот 2 должен содержать 8 топливных брикетов")
		return

	# Проверка переполнения стека (макс 20 на слот)
	var added_excess = generator.add_fuel("wood", 25)
	# В слоте 0 было 10, влезло 10 (стало 20), оставшиеся 15 пошли в свободный слот 3 (стало 15)
	if added_excess != 25:
		_fail("Ожидалось успешное распределение 25 дерева по слотам, добавлено: %d" % added_excess)
		return
	if generator.fuel_slots[0]["count"] != 20:
		_fail("Слот 0 должен быть заполнен до 20 дерева")
		return
	if generator.fuel_slots[3]["item_id"] != "wood" or generator.fuel_slots[3]["count"] != 15:
		_fail("Слот 3 должен принять остаток 15 дерева")
		return

	print("  • Загрузка мини-инвентаря и лимиты стеков проверены")

	# Очистка для теста горения
	generator.take_all_fuel()
	for s in generator.fuel_slots:
		if s["count"] != 0:
			_fail("После take_all_fuel слоты должны быть пусты")
			return

	# 3. Тест генерации мощности на разном топливе
	# 3.1 Дерево: 2.0 кВт, 30 сек
	generator.add_fuel("wood", 2)
	var started = generator.start_generator()
	if not started or not generator.is_running:
		_fail("Не удалось запустить генератор с деревом")
		return
	if generator.active_fuel_type != "wood":
		_fail("Активный тип топлива должен быть 'wood', получено: %s" % generator.active_fuel_type)
		return
	if generator.current_output != 2.0:
		_fail("Мощность на дереве должна быть 2.0 кВт, получено: %f" % generator.current_output)
		return
	if generator.get_current_output() != 2.0:
		_fail("get_current_output() должен возвращать 2.0 кВт")
		return
	if generator.fuel_slots[0]["count"] != 1:
		_fail("В слоте должно остаться 1 дерево (1 сгорело при старте)")
		return

	generator.stop_generator()
	generator.take_all_fuel()
	generator.active_fuel_type = ""
	generator.fuel_burn_left = 0.0
	generator.current_output = 0.0

	# 3.2 Уголь: 4.0 кВт, 75 сек
	generator.add_fuel("coal", 1)
	generator.start_generator()
	if generator.active_fuel_type != "coal":
		_fail("Активный тип топлива должен быть 'coal'")
		return
	if generator.current_output != 4.0:
		_fail("Мощность на угле должна быть 4.0 кВт, получено: %f" % generator.current_output)
		return
	if generator.fuel_burn_total != 75.0:
		_fail("Время горения угля должно быть 75.0 с, получено: %f" % generator.fuel_burn_total)
		return

	generator.stop_generator()
	generator.take_all_fuel()
	generator.active_fuel_type = ""
	generator.fuel_burn_left = 0.0
	generator.current_output = 0.0

	# 3.3 Топливные брикеты: 6.0 кВт, 120 сек
	generator.add_fuel("fuel_briquette", 1)
	generator.start_generator()
	if generator.active_fuel_type != "fuel_briquette":
		_fail("Активный тип топлива должен быть 'fuel_briquette'")
		return
	if generator.current_output != 6.0:
		_fail("Мощность на брикетах должна быть 6.0 кВт, получено: %f" % generator.current_output)
		return
	if generator.fuel_burn_total != 120.0:
		_fail("Время горения брикета должно быть 120.0 с, получено: %f" % generator.fuel_burn_total)
		return

	print("  • Различная мощность топлива подтверждена: Wood=2.0kW, Coal=4.0kW, Briquette=6.0kW")

	# 4. Проверка автоматического переключения топлива при прогорании
	generator.stop_generator()
	generator.take_all_fuel()
	generator.active_fuel_type = ""
	generator.fuel_burn_left = 0.0
	generator.current_output = 0.0

	# Загружаем 1 дерево в слот 0 и 1 брикет в слот 1
	generator.fuel_slots[0] = {"item_id": "wood", "count": 1}
	generator.fuel_slots[1] = {"item_id": "fuel_briquette", "count": 1}
	generator.start_generator()
	if generator.active_fuel_type != "wood" or generator.current_output != 2.0:
		_fail("Генератор должен был начать с дерева (слот 0)")
		return

	# Симулируем окончание горения дерева
	generator.fuel_burn_left = 0.001
	generator._process(0.01) # переключится на брикет из слота 1
	if generator.active_fuel_type != "fuel_briquette":
		_fail("Генератор должен был автоматически переключиться на 'fuel_briquette', получено: %s" % generator.active_fuel_type)
		return
	if generator.current_output != 6.0:
		_fail("После переключения на брикет мощность должна стать 6.0 кВт, получено: %f" % generator.current_output)
		return
	print("  • Автоматический переход между слотами топлива подтвержден")

	# 5. Интеграция с PowerGrid
	var power_grid = world.get_node_or_null("PowerGrid")
	if not power_grid:
		_fail("PowerGrid не найден в сцене World")
		return

	power_grid._update_grid(0.1)
	if power_grid.current_generation < 6.0:
		_fail("PowerGrid должен учитывать генерацию твердотопливного генератора (>= 6.0 кВт), получено: %f" % power_grid.current_generation)
		return
	print("  • Интеграция с PowerGrid подтверждена: генерация в сети = %.2f кВт" % power_grid.current_generation)

	# 6. Тестирование UI панели генератора
	var ui_panel = GeneratorPanelScene.new()
	var player = world.get_node_or_null("Player")
	ui_panel.setup(generator, player)
	world.add_child(ui_panel)
	if not is_instance_valid(ui_panel):
		_fail("Ошибка инстанцирования GeneratorPanel")
		return

	# Проверяем кнопки заправки и забора
	ui_panel._on_take_all_pressed()
	ui_panel.queue_free()
	print("  • UI панель генератора успешно создана, инициализирована и освобождена")

	# 7. Тестирование сохранения и загрузки (SaveManager)
	generator.take_all_fuel()
	generator.fuel_slots[0] = {"item_id": "coal", "count": 7}
	generator.fuel_slots[1] = {"item_id": "wood", "count": 12}
	generator.is_running = true
	generator.active_fuel_type = "coal"
	generator.current_output = 4.0
	generator.fuel_burn_left = 42.5
	generator.fuel_burn_total = 75.0
	generator.total_energy_produced = 1.35

	var test_save_path = "user://test_solid_generator_save.json"
	var save_ok = SaveManager.save_game(world, test_save_path)
	if not save_ok:
		_fail("Не удалось сохранить игру через SaveManager")
		return

	# Сбрасываем генератор
	generator.take_all_fuel()
	generator.is_running = false
	generator.active_fuel_type = ""
	generator.current_output = 0.0
	generator.fuel_burn_left = 0.0

	var load_ok = SaveManager.load_game(world, test_save_path)
	if not load_ok:
		_fail("Не удалось загрузить игру через SaveManager")
		return

	if not generator.is_running:
		_fail("После загрузки генератор должен быть включен")
		return
	if generator.active_fuel_type != "coal":
		_fail("После загрузки активное топливо должно быть 'coal', получено: %s" % generator.active_fuel_type)
		return
	if generator.current_output != 4.0:
		_fail("После загрузки мощность должна быть 4.0 кВт, получено: %f" % generator.current_output)
		return
	if abs(generator.fuel_burn_left - 42.5) > 0.01:
		_fail("После загрузки остаток времени горения должен быть ~42.5 с, получено: %f" % generator.fuel_burn_left)
		return
	if generator.fuel_slots[0]["item_id"] != "coal" or generator.fuel_slots[0]["count"] != 7:
		_fail("После загрузки слот 0 должен содержать 7 угля")
		return
	if generator.fuel_slots[1]["item_id"] != "wood" or generator.fuel_slots[1]["count"] != 12:
		_fail("После загрузки слот 1 должен содержать 12 дерева")
		return

	# Очистка файла теста
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(test_save_path)

	print("  • Сериализация и восстановление состояния (SaveManager) проверены")

	print("\n====================================================")
	print("🎉 ВСЕ ТЕСТЫ SOLID FUEL GENERATOR УСПЕШНО ПРОЙДЕНЫ!")
	print("====================================================")
	quit(0)
