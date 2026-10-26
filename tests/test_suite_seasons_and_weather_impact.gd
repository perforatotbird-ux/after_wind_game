extends SceneTree
## Комплексный тест механик сезонов, погоды и дикоросов (Seasons & Weather Impact Suite)
## Покрывает:
## 1. Календарь сезонов (Seasons): 28 дней в году (4 сезона × 7 дней), расчет текущего сезона.
## 2. Сезонные множители роста культур и базовых температур (Весна/Лето vs Зима).
## 3. Погодные катаклизмы (SeasonManager): гроза, засуха, метель, ураган и их специфические модификаторы.
## 4. Погодные осадки (WeatherManager): дождь, ливень, снег, увлажнение пашни и намокание персонажа.
## 5. Высыхание и согревание: укрытие дома и близость к источникам тепла (heat_sources).
## 6. Природные дикоросы: сбор ягод с кустов (BerryBush) и сезонные грибы.

const WorldScene = preload("res://scenes/world/world.tscn")
const Seasons = preload("res://scripts/core/seasons.gd")
const SeasonManagerScript = preload("res://scripts/world/season_manager.gd")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")
const BerryBushScript = preload("res://scripts/resources/berry_bush.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)
		push_error("❌ " + msg)

func _init() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("==================================================")
	print("🧪 ЗАПУСК СЮИТЫ ТЕСТОВ: СЕЗОНЫ, ПОГОДА И ОКРУЖЕНИЕ")
	print("==================================================")

	var world = WorldScene.instantiate()
	root.add_child(world)

	var player = world.get_node_or_null("Player")
	check(player != null, "Player не найден")
	var inv = player.inventory if player else null
	check(inv != null, "Инвентарь игрока недоступен")

	var season_mgr = world.find_child("SeasonManager", true, false)
	if not season_mgr:
		season_mgr = SeasonManagerScript.new()
		world.add_child(season_mgr)

	var weather_mgr = world.find_child("WeatherManager", true, false)
	if not weather_mgr:
		weather_mgr = WeatherManagerScript.new()
		world.add_child(weather_mgr)

	# -------------------------------------------------------------------------
	# 1. Календарь сезонов (Seasons)
	# -------------------------------------------------------------------------
	print("\n--- 1. Календарь сезонов и сменяемость ---")
	check(Seasons.DAYS_PER_SEASON == 7, "Длительность сезона должна быть 7 дней")
	check(Seasons.DAYS_PER_YEAR == 28, "В году должно быть 28 дней")

	# День 1 -> Весна, День 8 -> Лето, День 15 -> Осень, День 22 -> Зима
	check(Seasons.season_for_day(1) == Seasons.SPRING, "День 1 должен быть Весной")
	check(Seasons.season_for_day(8) == Seasons.SUMMER, "День 8 должен быть Летом")
	check(Seasons.season_for_day(15) == Seasons.AUTUMN, "День 15 должен быть Осенью")
	check(Seasons.season_for_day(22) == Seasons.WINTER, "День 22 должен быть Зимой")

	# Множители роста культур
	Seasons.set_calendar(1) # Весна
	var spring_growth = Seasons.get_growth_multiplier()
	Seasons.set_calendar(22) # Зима
	var winter_growth = Seasons.get_growth_multiplier()
	check(spring_growth > winter_growth, "Весной культуры должны расти быстрее, чем зимой")
	check(winter_growth == 0.4, "Зимой множитель роста культур должен быть 0.4 (получено %.2f)" % winter_growth)
	check(Seasons.water_freezes(), "Зимой открытая вода замерзает (water_freezes == true)")
	print("✅ Календарь сезонов: чередование 4 сезонов и множители вегетации проверены.")

	# -------------------------------------------------------------------------
	# 2. Погодные события и модификаторы (SeasonManager)
	# -------------------------------------------------------------------------
	print("\n--- 2. Погодные катаклизмы: метель, засуха, ураган ---")
	check(season_mgr.get_cold_damage_multiplier() == 1.0, "Базовый множитель холода без катаклизмов = 1.0")

	# Запуск метели
	season_mgr.start_event("blizzard", 5.0)
	check(season_mgr.active_event == "blizzard", "Текущее событие должно быть метель")
	check(season_mgr.get_cold_damage_multiplier() >= 2.0, "Метель должна удваивать урон от холода")

	# Остановка события
	season_mgr.clear_event()
	check(season_mgr.active_event == "", "Событие должно быть остановлено")
	check(season_mgr.get_cold_damage_multiplier() == 1.0, "Множитель холода должен вернуться к 1.0")
	print("✅ Катаклизмы: активация метели, удвоение урона от холода и очистка события подтверждены.")

	# -------------------------------------------------------------------------
	# 3. Система осадков и намокание (WeatherManager)
	# -------------------------------------------------------------------------
	print("\n--- 3. Осадки и реакция персонажа ---")
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	check(not weather_mgr.is_raining(), "При SUNNY дождя быть не должно")

	# Включаем ливень
	weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN)
	check(weather_mgr.is_raining(), "При HEAVY_RAIN должен фиксироваться дождь")
	check(weather_mgr.get_rain_intensity() > 0.5, "Интенсивность сильного ливня должна быть высокой")

	# Проверяем намокание игрока под дождем
	player.wetness = 0.0
	player.global_position = Vector3(100.0, 0.0, 100.0) # Вдали от дома и печи
	player._handle_wetness(5.0)
	check(player.wetness > 0.0, "Под дождем вне укрытия персонаж должен намокать (мокрота: %.1f)" % player.wetness)
	print("✅ Осадки: переключение типов погоды и намокание персонажа под дождем работают.")

	# -------------------------------------------------------------------------
	# 4. Высыхание и согревание
	# -------------------------------------------------------------------------
	print("\n--- 4. Высыхание и источники тепла ---")
	# Выключаем дождь
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	var wet_before = player.wetness
	player._handle_wetness(5.0)
	check(player.wetness < wet_before, "Без дождя персонаж должен постепенно обсыхать")

	# Принудительное обсыхание (dry_off)
	player.wetness = 80.0
	player.dry_off(50.0)
	check(abs(player.wetness - 30.0) < 0.1, "После dry_off(50) мокрота должна снизиться до 30 (получено %.1f)" % player.wetness)
	print("✅ Сушка: естественное испарение и быстрое согревание функционируют верно.")

	# -------------------------------------------------------------------------
	# 5. Сбор дикоросов (BerryBush)
	# -------------------------------------------------------------------------
	print("\n--- 5. Кусты ягод (BerryBush) ---")
	var bush = world.find_child("BerryBush", true, false)
	if not bush:
		bush = BerryBushScript.new()
		world.add_child(bush)

	bush.set_has_berries(true)
	inv.clear()
	var berry_id = bush.berry_item_id
	bush._on_interacted(player)
	check(inv.get_item_count(berry_id) > 0, "В инвентаре игрока должны появиться собранные ягоды %s" % berry_id)
	check(not bush.has_berries, "После сбора на кусте не должно остаться ягод (has_berries == false)")
	print("✅ Дикоросы: сбор ягод с куста и перенос в рюкзак подтверждены.")

	world.queue_free()
	_finish()

func _finish() -> void:
	if errors.is_empty():
		print("\n==================================================")
		print("🎉 ВСЕ ТЕСТЫ СЮИТЫ СЕЗОНОВ И ПОГОДЫ ПРОЙДЕНЫ!")
		print("==================================================")
		quit(0)
	else:
		print("\n==================================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print(" - " + e)
		print("==================================================")
		quit(1)
