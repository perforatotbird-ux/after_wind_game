extends SceneTree

## Тест энергосети: замедленный заряд батареи (КПД 1/3), источники питания
## Сеть/Ветряк/Батарея, остановка анимации дробилки при обесточивании,
## причина обесточивания в HUD, переключение рубильником батареи, сейв режима.

const WorldScene = preload("res://scenes/world/world.tscn")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")
const PowerGridScript = preload("res://scripts/energy/power_grid.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")

var _test_executed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	root.add_child(WorldScene.instantiate())

func check(ok: bool, msg: String) -> void:
	if ok:
		print("  ✅ " + msg)
	else:
		_errors.append(msg)
		print("  ❌ " + msg)

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("========================================")
	print("🧪 ТЕСТ ЭНЕРГОСЕТИ: заряд, источники, анимация при обесточивании")
	print("========================================")
	var world = root.get_node_or_null("World")
	if not world: _fail("Узел World не найден")
	var player = world.get_node_or_null("Player")
	var inv = player.inventory
	var grid = world.get_node_or_null("PowerGrid")
	var turbine = world.find_child("WindTurbine", true, false)
	var crusher = world.find_child("StoneCrusher", true, false)
	var battery = world.find_child("BatteryBank", true, false)
	var animator = crusher.find_child("Animator", true, false)
	var hud = world.get_node_or_null("HUD")
	var weather = world.find_child("WeatherManager", true, false)
	if not grid or not turbine or not crusher or not battery or not animator: _fail("Не найдены узлы энергосети")
	# Глава 2: дробилка стартует разрушенной — для проверки сети включаем её.
	crusher.force_rebuilt()
	player.energy = 100.0
	weather.set_weather(WeatherManagerScript.WeatherType.SUNNY) # генерация 2.0 кВт

	# ---------- 1. Заряд батареи втрое медленнее ----------
	print("\n--- 1. КПД заряда ×1/3 ---")
	grid.source_mode = PowerGridScript.SourceMode.BOTH
	grid.current_stored = 50.0
	grid._update_grid(1.0) # генерация 2.0, потребление 0 (день, фонари выключены)
	check(absf(grid.current_stored - (50.0 + 2.0 / 3.0)) < 0.01,
		"Заряд за 1 с излишка 2 кВт: +%.2f вместо +2.0 (КПД 1/3)" % (grid.current_stored - 50.0))

	# ---------- 2. Режим «Ветряк»: слабая генерация не тянет дробилку ----------
	print("\n--- 2. Источник «Ветряк» ---")
	grid.source_mode = PowerGridScript.SourceMode.TURBINE
	inv.add_item("stone", 20)
	player.energy = 100.0
	check(crusher.start_batch("crush_stone", 5, player), "Партия дробилки запущена")
	grid._update_grid(0.1) # генерация 2.0 < потребление 3.0
	check(not grid.has_power, "Ветряк (2.0 кВт) не тянет дробилку (3.0 кВт) — сеть обесточена")
	check(not crusher.power_ok, "Дробилка приостановлена")
	check(not animator.is_running(), "Анимация дробилки остановлена (маховики не крутятся)")
	# Шторм: генерации хватает — производство продолжается
	weather.set_weather(WeatherManagerScript.WeatherType.HEAVY_RAIN) # 8.5 кВт
	grid._update_grid(0.1)
	check(grid.has_power and crusher.power_ok, "В шторм (8.5 кВт) дробилка работает от ветряка")
	check(animator.is_running(), "Анимация дробилки снова крутится")

	# ---------- 3. Режим «Батарея»: нагрузка на ёмкость, пауза снимает спрос ----------
	print("\n--- 3. Источник «Батарея» ---")
	weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)
	grid.source_mode = PowerGridScript.SourceMode.BATTERY
	turbine.is_operational = false # генерация 0
	grid.current_stored = 20.0
	grid._update_grid(1.0)
	check(grid.has_power, "Батарея питает дробилку, пока есть заряд")
	check(absf(grid.current_stored - (20.0 - 3.0)) < 0.05, "Батарея тратится на всю нагрузку (20 → %.1f)" % grid.current_stored)
	grid.current_stored = 0.01
	grid._update_grid(0.1)
	check(not grid.has_power and not crusher.power_ok, "Пустая батарея — сеть обесточена")
	check(absf(crusher.get_power_demand()) < 0.001, "Обесточенная дробилка в режиме «Батарея» не держит спрос")
	# Ветряк вернулся: батарея заряжается с КПД 1/3, при 15 % питание возвращается
	turbine.is_operational = true
	var frames: int = 0
	while not grid.has_power and frames < 60:
		grid._update_grid(1.0)
		frames += 1
	check(grid.has_power, "Батарея зарядилась до 15 %% за %d с (КПД 1/3) — питание вернулось" % frames)
	check(crusher.power_ok, "Дробилка продолжила работу после восстановления")

	# ---------- 4. Рубильник на батарее ----------
	print("\n--- 4. Переключение источника у батареи ---")
	grid.source_mode = PowerGridScript.SourceMode.BOTH
	var mode_before: int = int(grid.source_mode)
	battery.interact(player)
	check(int(grid.source_mode) == mode_before + 1, "[E] у батареи переключает источник (%d → %d)" % [mode_before, int(grid.source_mode)])
	check("Источник: Ветряк" in battery.get_prompt(), "Подсказка батареи показывает источник: %s" % battery.get_prompt())
	battery.interact(player)
	check(int(grid.source_mode) == PowerGridScript.SourceMode.BATTERY, "Второе переключение — режим «Батарея»")
	grid.source_mode = PowerGridScript.SourceMode.BOTH
	crusher.cancel_batch()

	# ---------- 5. HUD: причина обесточивания и источник ----------
	print("\n--- 5. HUD: объяснение и режим ---")
	hud.update_power_display(0.0, 100.0, 2.0, 3.0, false, PowerGridScript.SourceMode.TURBINE)
	var text: String = hud.power_label.text
	check("Обесточена" in text and "тратится 3.0" in text and "генерация 2.0" in text,
		"HUD объясняет обесточивание: %s" % text)
	check("Ветряк" in text, "HUD показывает выбранный источник")
	hud.update_power_display(45.0, 100.0, 2.0, 1.0, true, PowerGridScript.SourceMode.BATTERY)
	check("Батарея" in hud.power_label.text and "45%" in hud.power_label.text,
		"HUD показывает заряд и режим «Батарея»: %s" % hud.power_label.text)

	# ---------- 6. Режим сохраняется ----------
	print("\n--- 6. Сейв режима источника ---")
	grid.source_mode = PowerGridScript.SourceMode.TURBINE
	check(SaveManager.save_game(world), "Игра сохранена")
	grid.source_mode = PowerGridScript.SourceMode.BOTH
	check(SaveManager.load_game(world), "Игра загружена")
	check(int(grid.source_mode) == PowerGridScript.SourceMode.TURBINE, "Режим источника восстановлен из сейва («Ветряк»)")
	grid.source_mode = PowerGridScript.SourceMode.BOTH

	print("========================================")
	if _errors.is_empty():
		print("🎉 ВСЕ ПРОВЕРКИ ЭНЕРГОСЕТИ ПРОЙДЕНЫ!")
		print("========================================")
		quit(0)
	else:
		for e in _errors:
			print("ПРОВАЛЕН: ", e)
		print("========================================")
		quit(1)
