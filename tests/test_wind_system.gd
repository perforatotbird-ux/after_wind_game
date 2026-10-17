extends SceneTree

## Тест системы ветра и ветряка (Разделы 54, 57, 84).
## Проверяет: слои скорости ветра (погода/сезон/событие/сутки), порывы, Бофорт,
## кривую мощности ветряка (cut-in / кубический рост / номинал / защита),
## вращение ротора, износ, ремонт деталями и вывод в HUD.

const WorldScene = preload("res://scenes/world/world.tscn")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")
const WindSystemScript = preload("res://scripts/world/wind_system.gd")
const MachineWearScript = preload("res://scripts/crafting/machine_wear.gd")
const PowerGridScript = preload("res://scripts/energy/power_grid.gd")

var _test_executed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	print("Инициализация теста системы ветра...")
	root.add_child(WorldScene.instantiate())

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	_run_tests()
	if _errors.is_empty():
		print("🎉 ВСЕ ПРОВЕРКИ СИСТЕМЫ ВЕТРА ПРОЙДЕНЫ!")
		quit(0)
	else:
		for e in _errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true

func _fail(reason: String) -> void:
	_errors.append(reason)
	print("ПРОВАЛЕН: ", reason)

func check(cond: bool, label: String) -> void:
	if cond:
		print("  ✅ ", label)
	else:
		_fail(label)

func _run_tests() -> void:
	print("========================================")
	print("🌀 Тест: система ветра и ветрогенератор")
	print("========================================")

	var world = root.get_node_or_null("World")
	if not world: _fail("Мир не найден"); return
	var player = world.get_node_or_null("Player")
	if not player: _fail("Player не найден"); return
	var inv = player.inventory
	var hud = world.get_node_or_null("HUD")
	var weather_mgr = world.get_node_or_null("WeatherManager")
	var grid = world.get_node_or_null("PowerGrid")
	var wind = world.get_node_or_null("WindSystem")
	var turbine = world.find_child("WindTurbine", true, false)
	if not hud or not weather_mgr or not grid: _fail("Нет HUD/WeatherManager/PowerGrid"); return
	if not wind: _fail("WindSystem отсутствует в World"); return
	if not turbine: _fail("WindTurbine отсутствует в Props"); return
	check(wind.is_in_group(WindSystemScript.GROUP), "WindSystem зарегистрирован в группе 'wind_system'")

	# -------------------------------------------------------------
	# 1. Слои скорости: база погоды
	# -------------------------------------------------------------
	print("\n--- 1. База ветра по погоде ---")
	wind.clear_override()
	var expected_base: Dictionary = {
		WeatherManagerScript.WeatherType.SUNNY: 2.0,
		WeatherManagerScript.WeatherType.OVERCAST: 5.0,
		WeatherManagerScript.WeatherType.RAIN: 9.0,
		WeatherManagerScript.WeatherType.SNOW: 10.0,
		WeatherManagerScript.WeatherType.HEAVY_RAIN: 15.0,
	}
	for w_type in expected_base.keys():
		weather_mgr.set_weather(w_type)
		check(absf(wind.get_weather_base_wind() - expected_base[w_type]) < 0.001,
			"Погода %d → база ветра %.1f м/с" % [int(w_type), expected_base[w_type]])

	var season_mult: float = wind.get_season_multiplier()
	check(season_mult >= 0.7 and season_mult <= 1.3, "Множитель сезона в разумных границах: %.2f" % season_mult)
	var event_mult: float = wind.get_event_multiplier()
	check(event_mult >= 0.3 and event_mult <= 2.0, "Множитель события в разумных границах: %.2f" % event_mult)
	if "get_day_multiplier" in wind:
		var day_mult: float = wind.get_day_multiplier()
		check(absf(day_mult - WindSystemScript.DAY_MULT) < 0.001 or absf(day_mult - WindSystemScript.NIGHT_MULT) < 0.001,
			"Суточный множитель дня/ночи: %.2f" % day_mult)

	# Живой ветер плавно подходит к цели, а не прыгает.
	weather_mgr.set_weather(WeatherManagerScript.WeatherType.SUNNY)
	wind.clear_override()
	wind.wind_speed = 25.0
	var target: float = wind.get_weather_base_wind() * season_mult * event_mult
	var before_dist: float = absf(wind.wind_speed - target)
	wind._process(2.0)
	var after_dist: float = absf(wind.wind_speed - target)
	check(after_dist < before_dist, "Ветер плавно идёт к цели погоды (%.1f → %.1f, цель %.1f)" % [25.0, wind.wind_speed, target])

	# -------------------------------------------------------------
	# 2. Форсирование, порывы, Бофорт
	# -------------------------------------------------------------
	print("\n--- 2. Форсирование ветра и шкала Бофорта ---")
	wind.set_wind_speed(8.4)
	check(absf(wind.get_wind_speed() - 8.4) < 0.001, "Форсированный ветер держится точно: %.1f м/с" % wind.get_wind_speed())
	check(not wind.is_gusting(), "В форсированном режиме порывы выключены")
	check(wind.is_forced(), "Ветер помечен как форсированный")
	var beaufort_cases: Array = [[0.2, "Штиль"], [2.0, "Лёгкий"], [8.4, "Свежий"], [13.0, "Сильный"], [26.0, "Сильный шторм"]]
	for case in beaufort_cases:
		wind.set_wind_speed(float(case[0]))
		check(wind.get_wind_name() == String(case[1]),
			"%.1f м/с → «%s» (Бофорт %d)" % [float(case[0]), wind.get_wind_name(), wind.get_beaufort()])
	wind.set_wind_speed(1.0)
	check(wind.is_calm(), "1.0 м/с — затишье для ветряка")
	check("м/с" in wind.get_status_text(), "Статус ветра для интерфейса: %s" % wind.get_status_text())

	# Форсирование снимается сменой погоды.
	weather_mgr.set_weather(WeatherManagerScript.WeatherType.RAIN)
	check(not wind.is_forced(), "Смена погоды снимает форсирование ветра")

	# -------------------------------------------------------------
	# 3. Кривая мощности ветряка
	# -------------------------------------------------------------
	print("\n--- 3. Кривая мощности ветряка ---")
	wind.set_wind_speed(0.0)
	check(turbine.get_current_output() == 0.0, "Штиль (0 м/с) — выработки нет")
	wind.set_wind_speed(WindSystemScript.WEATHER_BASE_WIND[WeatherManagerScript.WeatherType.SUNNY] - 0.5)
	check(turbine.get_current_output() == 0.0, "Ниже cut-in (2.5 м/с) — выработки нет")
	check(turbine.get_state_text() == "Простаивает (затишье)", "Состояние «Простаивает (затишье)»")

	wind.set_wind_speed(5.0)
	var out_5: float = turbine.get_current_output()
	wind.set_wind_speed(9.0)
	var out_9: float = turbine.get_current_output()
	wind.set_wind_speed(13.0)
	var out_13: float = turbine.get_current_output()
	check(out_5 > 0.0 and out_5 < out_9 and out_9 < out_13,
		"Кубический рост выработки: 5→%.2f, 9→%.2f, 13→%.2f кВт" % [out_5, out_9, out_13])
	check(absf(out_13 - turbine.base_output) < 0.001, "На номинале (13 м/с) — полная мощность %.1f кВт" % turbine.base_output)
	wind.set_wind_speed(20.0)
	check(absf(turbine.get_current_output() - turbine.base_output) < 0.001, "Между номиналом и cut-out мощность держится на %.1f кВт" % turbine.base_output)
	wind.set_wind_speed(turbine.CUT_OUT_WIND + 2.0)
	check(turbine.get_current_output() == 0.0, "Выше cut-out (%.0f м/с) — аварийная защита, выработки нет" % (turbine.CUT_OUT_WIND + 2.0))
	check(turbine.get_state_text() == "Защита: штормовой ветер", "Состояние «Защита: штормовой ветер»")

	# Ротор: крутится при рабочем ветре, стоит в затишье и в защите.
	wind.set_wind_speed(9.0)
	var rot_a: Basis = turbine.rotor_node.global_transform.basis
	turbine._process(0.5)
	var rot_b: Basis = turbine.rotor_node.global_transform.basis
	check(not rot_a.is_equal_approx(rot_b), "Ротор вращается при рабочем ветре")
	wind.set_wind_speed(2.0)
	turbine._process(0.5)
	var rot_c: Basis = turbine.rotor_node.global_transform.basis
	check(rot_b.is_equal_approx(rot_c), "В затишье ротор стоит")
	wind.set_wind_speed(30.0)
	turbine._process(0.5)
	check(rot_c.is_equal_approx(turbine.rotor_node.global_transform.basis), "В защите от шторма ротор стоит")

	# Запечённая анимация GLB заглушена — ротором управляет только скрипт.
	var baked_stopped: bool = true
	for ap in turbine.find_children("*", "AnimationPlayer", true, false):
		if ap.active or ap.is_playing():
			baked_stopped = false
	check(baked_stopped, "Запечённая анимация GLB отключена (ротором управляет скрипт)")

	# -------------------------------------------------------------
	# 4. Износ, поломка и ремонт деталями
	# -------------------------------------------------------------
	print("\n--- 4. Износ, поломка и ремонт ---")
	wind.set_wind_speed(15.0)
	turbine.wear.set_condition(100.0)
	var cond_before: float = turbine.wear.condition
	for i in 60:
		turbine._process(1.0)
	check(turbine.wear.condition < cond_before, "Работа под нагрузкой изнашивает машину (%.2f → %.2f)" % [cond_before, turbine.wear.condition])

	turbine.wear.set_condition(50.0)
	check(absf(turbine.get_condition_output_mult() - turbine.WORN_OUTPUT_MULT) < 0.001,
		"Изношенная машина теряет КПД (множитель %.2f)" % turbine.get_condition_output_mult())
	check(turbine.get_state_text() == "Изношен — КПД снижен", "Состояние «Изношен»")
	check(turbine.needs_repair(), "Изношенной машине предлагается ремонт")
	check("Ремонт ветряка" in turbine.get_prompt(), "Подсказка предлагает ремонт: %s" % turbine.get_prompt())

	# Детали вносятся частями: одна деталь — ещё не ремонт.
	inv.add_item("gear", 1)
	var used_before: int = inv.get_item_count("gear")
	turbine.interact(player)
	check(inv.get_item_count("gear") < used_before, "Внесённая деталь списана из рюкзака")
	check(absf(turbine.wear.condition - 50.0) < 0.001, "Частичного комплекта для ремонта недостаточно")

	# Полный комплект: состояние восстанавливается полностью.
	for item_id in turbine.repair_cost.keys():
		inv.add_item(str(item_id), int(turbine.repair_cost[item_id]))
	turbine.interact(player)
	check(absf(turbine.wear.condition - turbine.wear.max_condition) < 0.001,
		"Полный комплект деталей восстанавливает машину на 100 %% (факт: %.1f)" % turbine.wear.condition)
	check(not turbine.needs_repair(), "После ремонта ремонт больше не предлагается")
	check("Осмотреть" in turbine.get_prompt(), "Подсказка снова «Осмотреть»: %s" % turbine.get_prompt())

	# Сломанная машина не даёт тока до ремонта.
	turbine.wear.set_condition(0.0)
	check(turbine.get_current_output() == 0.0, "Сломанный ветряк не даёт выработки")
	check(turbine.get_state_text() == "Сломан — нужен ремонт", "Состояние «Сломан — нужен ремонт»")
	turbine.wear.set_condition(100.0)

	# -------------------------------------------------------------
	# 5. Сеть, HUD и сохранение
	# -------------------------------------------------------------
	print("\n--- 5. Сеть, HUD и сохранение ---")
	wind.set_wind_speed(15.0)
	turbine.is_operational = true
	grid.source_mode = PowerGridScript.SourceMode.BOTH
	grid.current_stored = 40.0
	grid._update_grid(1.0)
	check(absf(grid.current_generation - turbine.get_current_output()) < 0.001,
		"Сеть берёт выработку ветряка (%.2f кВт)" % grid.current_generation)

	hud.update_power_display(grid.current_stored, grid.max_capacity, grid.current_generation, grid.current_consumption, true, grid.get("source_mode"))
	check("м/с" in hud.power_label.text, "HUD показывает силу ветра: %s" % hud.power_label.text)
	check("Ветрогенератор" in turbine.get_status_text(), "Отчёт ветряка: %s" % turbine.get_status_text())

	var wind_state: Dictionary = wind.get_save_state()
	check(wind_state.has("wind_speed"), "Состояние ветра сохраняется")
	var turb_state: Dictionary = turbine.get_save_state()
	check(turb_state.has("condition") and turb_state.has("delivered"), "Состояние ветряка сохраняется (износ и внесённые детали)")
	turbine.wear.set_condition(73.0)
	turbine.apply_save_state({"condition": 42.5, "delivered": {"gear": 1}})
	check(absf(turbine.wear.condition - 42.5) < 0.001, "Износ восстанавливается из сейва (%.1f)" % turbine.wear.condition)
	turbine.apply_save_state(turb_state)
	check(absf(turbine.wear.condition - float(turbine.get_save_state()["condition"])) < 0.001, "Сейв ветряка применён обратно")
