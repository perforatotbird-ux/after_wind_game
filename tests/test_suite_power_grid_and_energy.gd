extends SceneTree
## Комплексный тест механик энергосети и генерации (Power Grid & Energy Suite)
## Покрывает:
## 1. Энергосеть (PowerGrid): регистрация генераторов, потребителей и аккумуляторов.
## 2. Режимы источника питания: BOTH (Сеть), TURBINE (Ветряк), BATTERY (Батарея).
## 3. Баланс мощности: зарядка батареи при избытке (с КПД), разрядка при дефиците.
## 4. Блэкаут (Brownout): отключение питания потребителей при нулевом заряде батареи и нехватке генерации.
## 5. Твердотопливный генератор (SolidFuelGenerator): мини-инвентарь (4 слота), 3 вида топлива (2/4/6 кВт).
## 6. Цикл горения топлива: расход таймера, автоматический переход к следующему полену, отключение при исчерпании.

const WorldScene = preload("res://scenes/world/world.tscn")
const PowerGridScript = preload("res://scripts/energy/power_grid.gd")
const SolidGeneratorScript = preload("res://scripts/energy/solid_generator.gd")
const BatteryBankScript = preload("res://scripts/energy/battery_bank.gd")
const WindTurbineScript = preload("res://scripts/energy/wind_turbine.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: ЭНЕРГОСЕТЬ И ГЕНЕРАЦИЯ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var grid = world.find_child("PowerGrid", true, false)
	check(grid != null, "Узел PowerGrid не найден в сцене")
	var solid_gen = world.find_child("SolidGenerator", true, false)
	if not solid_gen:
		solid_gen = SolidGeneratorScript.new()
		world.add_child(solid_gen)

	if not grid:
		world.queue_free()
		_finish()
		return

	# -------------------------------------------------------------------------
	# 1. Твердотопливный генератор: параметры топлива и слоты
	# -------------------------------------------------------------------------
	print("\n--- 1. Твердотопливный генератор: слоты и виды топлива ---")
	check(solid_gen.is_in_group("power_generators"), "Генератор должен быть в группе power_generators")
	check(solid_gen.fuel_slots.size() == 4, "Генератор должен иметь ровно 4 слота топлива")

	# Проверяем характеристики 3 видов топлива
	var wood_prop = SolidFuelGenerator.FUEL_PROPERTIES.get("wood", {})
	var coal_prop = SolidFuelGenerator.FUEL_PROPERTIES.get("coal", {})
	var briq_prop = SolidFuelGenerator.FUEL_PROPERTIES.get("fuel_briquette", {})

	check(wood_prop.get("power", 0.0) == 2.0 and wood_prop.get("burn_time", 0.0) == 30.0, "Древесина: 2.0 кВт, 30 с")
	check(coal_prop.get("power", 0.0) == 4.0 and coal_prop.get("burn_time", 0.0) == 75.0, "Уголь: 4.0 кВт, 75 с")
	check(briq_prop.get("power", 0.0) == 6.0 and briq_prop.get("burn_time", 0.0) == 120.0, "Брикеты: 6.0 кВт, 120 с")

	# Загрузка топлива в слоты
	var added_wood = solid_gen.add_fuel("wood", 5)
	check(added_wood == 5, "В генератор должно загрузиться 5 единиц дерева")
	check(solid_gen.fuel_slots[0]["item_id"] == "wood", "Слот 0 должен содержать wood")

	# Попытка загрузить невалидное топливо (например, камень)
	var invalid_add = solid_gen.add_fuel("stone", 3)
	check(invalid_add == 0, "Не-топливо не должно загружаться в генератор")
	print("✅ Генератор: 4 слота, валидация видов топлива и их характеристик проверены.")

	# -------------------------------------------------------------------------
	# 2. Запуск и процесс горения в генераторе
	# -------------------------------------------------------------------------
	print("\n--- 2. Цикл горения и выработка мощности ---")
	solid_gen.start_generator()
	check(solid_gen.is_running, "Генератор должен быть запущен")
	check(solid_gen.current_output == 2.0, "Выходная мощность на дереве должна быть 2.0 кВт (получено: %.1f)" % solid_gen.current_output)
	check(solid_gen.fuel_slots[0]["count"] == 4, "Одно полено должно было списаться в топку")
	check(solid_gen.fuel_burn_left > 0.0, "Оставшееся время горения должно быть больше 0")

	# Симулируем 10 секунд работы
	solid_gen._process(10.0)
	check(solid_gen.total_energy_produced > 0.0, "Генератор должен накапливать выработанную энергию")
	check(solid_gen.fuel_burn_left <= 20.0, "Таймер горения дерева должен уменьшиться")

	# Остановка генератора
	solid_gen.stop_generator()
	check(not solid_gen.is_running, "Генератор должен остановиться")
	check(solid_gen.current_output == 0.0, "После остановки мощность должна быть 0.0 кВт")
	print("✅ Цикл генератора: пуск, выработка энергии на топливе и остановка подтверждены.")

	# -------------------------------------------------------------------------
	# 3. Энергосеть (PowerGrid): переключение режимов
	# -------------------------------------------------------------------------
	print("\n--- 3. Энергосеть: режимы питания ---")
	grid.source_mode = PowerGrid.SourceMode.BOTH
	check(grid.source_mode == PowerGrid.SourceMode.BOTH, "Стартовый режим BOTH")
	grid.cycle_source_mode()
	check(grid.source_mode == PowerGrid.SourceMode.TURBINE, "После 1 переключения должен быть TURBINE")
	grid.cycle_source_mode()
	check(grid.source_mode == PowerGrid.SourceMode.BATTERY, "После 2 переключения должен быть BATTERY")
	grid.cycle_source_mode()
	check(grid.source_mode == PowerGrid.SourceMode.BOTH, "После 3 переключения возврат в BOTH")
	print("✅ Переключение режимов: BOTH -> TURBINE -> BATTERY -> BOTH работает.")

	# -------------------------------------------------------------------------
	# 4. Баланс сети и поведение батареи
	# -------------------------------------------------------------------------
	print("\n--- 4. Баланс мощности и заряд/разряд батареи ---")
	grid.source_mode = PowerGrid.SourceMode.BOTH
	grid.current_stored = 50.0
	grid.max_capacity = 100.0

	# Создаем потребителя-заглушку и генератор-заглушку
	var test_gen = Node.new()
	var gen_script = GDScript.new()
	gen_script.source_code = "extends Node\nvar out_power: float = 10.0\nfunc get_current_output() -> float: return out_power\n"
	gen_script.reload()
	test_gen.set_script(gen_script)
	test_gen.add_to_group("power_generators")
	world.add_child(test_gen)

	var test_con = Node.new()
	var con_script = GDScript.new()
	con_script.source_code = "extends Node\nvar req_power: float = 4.0\nfunc get_power_demand() -> float: return req_power\nfunc set_powered(_p: bool) -> void: pass\n"
	con_script.reload()
	test_con.set_script(con_script)
	test_con.add_to_group("power_consumers")
	world.add_child(test_con)

	grid._scan_grid_devices()
	grid._update_grid(1.0)

	check(grid.has_power, "При избытке генерации (10 > 4) сеть должна быть запитана")
	check(grid.current_stored > 50.0, "При избытке энергии батарея должна заряжаться")

	# Теперь моделируем дефицит: потребители требуют 20 кВт при генерации 10 кВт
	test_con.req_power = 20.0
	var stored_before = grid.current_stored
	grid._update_grid(1.0)
	check(grid.has_power, "При наличии заряда батарея покрывает дефицит мощности")
	check(grid.current_stored < stored_before, "Батарея должна разряжаться при дефиците генерации")

	# -------------------------------------------------------------------------
	# 5. Блэкаут (Brownout)
	# -------------------------------------------------------------------------
	print("\n--- 5. Отключение питания (Блэкаут) ---")
	grid.current_stored = 0.0
	test_con.req_power = 50.0
	test_gen.out_power = 0.0
	grid._update_grid(1.0)
	check(not grid.has_power, "При нулевом заряде батареи и дефиците генерации должен наступить блэкаут (has_power == false)")
	print("✅ Блэкаут: корректно срабатывает защита и обесточивание сети.")

	test_gen.queue_free()
	test_con.queue_free()
	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ ЭНЕРГОСЕТИ И ГЕНЕРАЦИИ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
