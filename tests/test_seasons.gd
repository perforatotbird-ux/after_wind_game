extends SceneTree
## Система сезонов и погоды (раздел 9 мастер-плана): календарь 4×7 игровых дней,
## сезонные множители (рост, испарение, сбор), погодные события (гроза, засуха,
## метель, ураган), снег и промерзание открытой воды, холод/жара для персонажа,
## подпись сезона в HUD и секция seasons в сохранении.

const WorldScene = preload("res://scenes/world/world.tscn")
const Seasons = preload("res://scripts/core/seasons.gd")
const SeasonManagerScript = preload("res://scripts/world/season_manager.gd")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const FarmField = preload("res://scripts/farming/farm_field.gd")
const InventoryScript = preload("res://scripts/inventory/inventory.gd")
const SAVE_PATH: String = "user://test_seasons.json"

class MockPlayer extends Node:
	var inventory: Node
	var messages: Array[String] = []
	func notify(t: String) -> void:
		messages.append(t)

var errors: Array[String] = []
var world: Node
var frames: int = 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	Seasons.disable()
	_test_calendar()
	_test_factors()
	_test_disabled_is_neutral()
	_test_events()
	world = WorldScene.instantiate()
	root.add_child(world)

func _process(_d: float) -> bool:
	frames += 1
	if world == null or frames < 4:
		return false
	_run_world_tests()
	return _finish()

# --- Календарь ------------------------------------------------------------------

func _test_calendar() -> void:
	check(Seasons.DAYS_PER_SEASON == 7 and Seasons.DAYS_PER_YEAR == 28, "Год должен быть 4×7 = 28 дней")
	for day in range(1, 29):
		check(Seasons.season_for_day(day) == Seasons.ALL[(day - 1) / 7], "день %d: неверный сезон" % day)
		check(Seasons.day_in_season_for_day(day) == (day - 1) % 7 + 1, "день %d: неверный день в сезоне" % day)
	# Границы сезонов и года.
	check(Seasons.season_for_day(1) == Seasons.SPRING, "1-й день — не весна")
	check(Seasons.season_for_day(7) == Seasons.SPRING, "7-й день — не весна")
	check(Seasons.season_for_day(8) == Seasons.SUMMER, "8-й день — не лето")
	check(Seasons.season_for_day(22) == Seasons.WINTER, "22-й день — не зима")
	check(Seasons.season_for_day(21) == Seasons.AUTUMN, "21-й день — не осень")
	check(Seasons.season_for_day(29) == Seasons.SPRING, "29-й день — снова весна")
	check(Seasons.year_for_day(29) == 2, "29-й день — второй год")
	check(Seasons.day_of_year_for_day(29) == 1, "29-й день — первый день года")
	# Цикл перехода между сезонами.
	check(Seasons.next_season(Seasons.SPRING) == Seasons.SUMMER, "весна → не лето")
	check(Seasons.next_season(Seasons.WINTER) == Seasons.SPRING, "зима → не весна")
	check(Seasons.previous_season(Seasons.SPRING) == Seasons.WINTER, "перед весной не зима")
	# Календарь публикуется в статику.
	Seasons.set_calendar(20)
	check(Seasons.get_current_season() == Seasons.AUTUMN, "20-й день должен быть осенью")
	check(Seasons.get_day_in_season() == 6, "20-й день: неверный день в сезоне")
	check(Seasons.get_calendar_caption() == "🍂 осень · день 6/7", "неверная подпись календаря: %s" % Seasons.get_calendar_caption())
	check(Seasons.get_days_until_next_season() == 1, "до конца осени не 1 день")
	check(is_equal_approx(Seasons.get_season_progress(), 5.0 / 7.0), "неверный прогресс сезона")
	Seasons.activate(Seasons.WINTER, 3)
	check(Seasons.get_current_season() == Seasons.WINTER and Seasons.get_day_in_season() == 3, "activate() не выставил зиму")
	check(Seasons.get_season_caption() == "❄️ зима", "неверная иконка/имя сезона")
	check(Seasons.get_summary(Seasons.SUMMER) != "", "нет описания сезона")

func _test_factors() -> void:
	# Таблица мастер-плана: весна ×1.3 рост, лето ×2 испарение, осень ×2 сбор, зима замедление.
	Seasons.activate(Seasons.SPRING, 1)
	check(is_equal_approx(Seasons.get_growth_multiplier(), 1.3), "весна: рост не ×1.3")
	check(is_equal_approx(Seasons.get_evaporation_multiplier(), 1.0), "весна: испарение не ×1")
	check(is_equal_approx(Seasons.get_forage_multiplier(), 1.0), "весна: сбор не ×1")
	check(not Seasons.water_freezes(), "весной вода не должна замерзать")
	check(Seasons.get_rain_chance() > 0.3, "весной дожди должны быть частыми")

	Seasons.activate(Seasons.SUMMER, 1)
	check(is_equal_approx(Seasons.get_evaporation_multiplier(), 2.0), "лето: испарение не ×2 (сушь)")
	check(Seasons.get_rain_chance() < 0.2, "летом дождей должно быть мало")
	check(Seasons.get_temperature_offset() > 0, "лето должно теплее нейтрального")
	check(Seasons.get_base_temperature() > 20.0, "лето: базовая температура низкая")

	Seasons.activate(Seasons.AUTUMN, 1)
	check(is_equal_approx(Seasons.get_forage_multiplier(), 2.0), "осень: грибы/ягоды не ×2")

	Seasons.activate(Seasons.WINTER, 1)
	check(Seasons.get_growth_multiplier() < 0.5, "зима: рост не замедлен")
	check(Seasons.water_freezes(), "зимой открытая вода должна замерзать")
	check(Seasons.get_temperature_offset() < -5, "зима: температурное смещение не холодное")
	# is_in_season уважает включённую систему.
	check(Seasons.is_in_season([Seasons.WINTER]), "зима должна входить в список [зима]")
	check(not Seasons.is_in_season([Seasons.SUMMER]), "зима не должна входить в список [лето]")
	check(Seasons.describe([Seasons.SUMMER, Seasons.WINTER]) == "лето, зима", "describe() неверно")

## Обратная совместимость: без системы сезонов всё растёт круглый год.
func _test_disabled_is_neutral() -> void:
	Seasons.disable()
	check(not Seasons.is_enabled(), "disable() не выключил систему")
	check(Seasons.is_in_season([Seasons.WINTER]), "выключенные сезоны должны пропускать любой список")
	check(is_equal_approx(Seasons.get_growth_multiplier(), 1.0), "без сезонов рост не ×1")
	check(is_equal_approx(Seasons.get_evaporation_multiplier(), 1.0), "без сезонов испарение не ×1")
	check(is_equal_approx(Seasons.get_forage_multiplier(), 1.0), "без сезонов сбор не ×1")
	check(Seasons.get_temperature_offset() == 0, "без сезонов температурное смещение не 0")
	check(not Seasons.water_freezes(), "без сезонов вода не замерзать")
	check(Seasons.get_calendar_caption() == "", "без сезонов подпись календаря должна быть пустой")

# --- Погодные события -----------------------------------------------------------

func _test_events() -> void:
	check(SeasonManagerScript.EVENTS.size() == 4, "ожидались 4 погодных события")
	var sm := SeasonManagerScript.new()
	root.add_child(sm)
	sm.rng_seed = 7

	# События возможны только в своих сезонах.
	Seasons.activate(Seasons.SPRING, 1)
	check(is_equal_approx(sm.get_event_chance("storm"), 0.14), "гроза должна быть возможна весной")
	check(is_equal_approx(sm.get_event_chance("blizzard"), 0.0), "метель невозможна весной")
	Seasons.activate(Seasons.WINTER, 1)
	check(is_equal_approx(sm.get_event_chance("blizzard"), 0.22), "метель должна быть возможна зимой")
	check(is_equal_approx(sm.get_event_chance("drought"), 0.0), "засуха невозможна зимой")
	Seasons.activate(Seasons.AUTUMN, 1)
	check(is_equal_approx(sm.get_event_chance("hurricane"), 0.07), "ураган должен быть возможен осенью")
	check(is_equal_approx(sm.get_event_chance("storm"), 0.0), "гроза невозможна осенью")

	# Засуха: испарение ×3 к сезонным ×2, дождь запрещён.
	sm.events_enabled = false
	sm.clear_event()
	Seasons.activate(Seasons.SUMMER, 1)
	check(sm.start_event("drought", 96.0), "засуха не запустилась")
	check(sm.get_active_event() == "drought", "активное событие — не засуха")
	check(is_equal_approx(sm.get_evaporation_multiplier(), 6.0), "засуха: испарение не ×3 к сезонным ×2")
	check(sm.forbids_rain(), "засуха должна запрещать дождь")
	check(sm.get_event_time_left() > 0.0, "у события должен быть остаток времени")
	check(sm.get_active_event_caption().contains("Засуха"), "нет подписи события: %s" % sm.get_active_event_caption())
	check(SeasonManagerScript.is_valid_save_state(sm.get_save_state()), "состояние засухи невалидно")

	# Метель: холод ×2, замедление, снег.
	sm.clear_event()
	Seasons.activate(Seasons.WINTER, 1)
	sm.start_event("blizzard", 8.0)
	check(is_equal_approx(sm.get_cold_damage_multiplier(), 2.0), "метель: холод не ×2")
	check(sm.get_speed_multiplier() < 1.0, "метель должна замедлять")
	check(sm.has_reduced_visibility(), "метель должна снижать видимость")
	check(sm.get_forced_weather() == "snow", "метель должна навязать снег")
	check(is_equal_approx(sm.get_growth_multiplier(), Seasons.get_growth_multiplier() * 0.85), "метель: неверный множитель роста")

	# Гроза навязывает ливень, ураган — ливень и разрушения.
	sm.clear_event()
	Seasons.activate(Seasons.SPRING, 1)
	sm.start_event("storm", 4.0)
	check(sm.forces_heavy_rain(), "гроза должна навязать ливень")
	sm.clear_event()
	Seasons.activate(Seasons.AUTUMN, 1)
	sm.start_event("hurricane", 3.0)
	check(sm.get_forced_weather() == "heavy_rain", "ураган должен навязать ливень")
	check(sm.get_speed_multiplier() < 1.0, "ураган должен замедлять")

	# Событие само заканчивается по таймеру игровых часов.
	sm.clear_event()
	sm.start_event("storm", 1.0)
	var hps: float = sm.get_hours_per_second()
	sm._process(0.5 / hps)
	check(sm.get_active_event() == "storm", "событие закончилось раньше часа")
	sm._process(0.6 / hps)
	check(sm.get_active_event() == "", "событие не закончилось по таймеру")
	check(sm.get_event_time_left() == 0.0, "после события остался таймер")

	# Неизвестные и битые состояния отбрасываются.
	check(not SeasonManagerScript.is_valid_save_state({"current_season": "monsoon"}), "неизвестный сезон принят")
	check(not SeasonManagerScript.is_valid_save_state({"day_in_season": 9}), "8+ день в сезоне принят")
	check(not SeasonManagerScript.is_valid_save_state({"active_event": "tsunami"}), "неизвестное событие принято")
	check(not SeasonManagerScript.is_valid_save_state({"event_hours_left": -1.0}), "отрицательное время события принято")
	sm.apply_save_state({"enabled": true, "total_day": 23, "current_season": "winter", "day_in_season": 2, "active_event": "nope"})
	check(sm.get_active_event() == "", "битое событие не отброшено")
	check(Seasons.get_current_season() == Seasons.WINTER, "apply_save_state не восстановил сезон")
	sm.queue_free()

# --- Мир ------------------------------------------------------------------------

func _run_world_tests() -> void:
	var sm: Node = world.get_node_or_null("SeasonManager")
	check(sm != null, "В мире нет узла SeasonManager")
	if sm == null:
		return
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var hud: Node = world.get_node_or_null("HUD")
	var player: Node = world.get_node_or_null("Player")
	var weather: Node = world.get_node_or_null("WeatherManager")
	var day_cycle: Node = world.get_node_or_null("DayNightCycle")
	var house: Node = world.find_child("RepairableHouse", true, false)

	# 1. Календарь включён и живёт по дням.
	check(Seasons.is_enabled(), "Система сезонов не включена в мире")
	check(Seasons.get_current_season() == Seasons.SPRING, "Новая игра должна начинаться весной")
	check(sm.total_day == day_cycle.current_day, "Менеджер не синхронизирован с суточным циклом")
	var seen: Array[String] = []
	sm.season_changed.connect(func(s: String, _n: String, _d: int) -> void: seen.append(s))
	sm.events_enabled = false
	for day in range(1, 30):
		day_cycle.set_time(day, 8.0)
		day_cycle.day_passed.emit(day)
	check(seen.has(Seasons.SUMMER) and seen.has(Seasons.AUTUMN) and seen.has(Seasons.WINTER), "Смена сезона не объявлена: %s" % str(seen))
	check(Seasons.get_current_season() == Seasons.SPRING, "29-й день должен вернуть весну")
	check(Seasons.get_year() == 2, "После 28 дней должен идти второй год")
	check(sm.total_day == 29, "Менеджер не догнал суточный цикл: %d" % sm.total_day)

	# 2. HUD показывает сезон, а температура зависит от сезона.
	day_cycle.set_time(1, 14.0)
	weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)
	Seasons.activate(Seasons.WINTER, 1)
	hud.update_season_display()
	check(hud.season_label.visible, "Строка сезона скрыта при включённых сезонах")
	check("❄️" in hud.season_label.text and "день 1/7" in hud.season_label.text, "Нет подписи сезона в HUD: %s" % hud.season_label.text)
	hud.update_time_display(1, 14, 0, "", "День")
	var winter_temp: int = _extract_temp(hud.weather_label.text)
	Seasons.activate(Seasons.SUMMER, 1)
	hud.update_time_display(1, 14, 0, "", "День")
	var summer_temp: int = _extract_temp(hud.weather_label.text)
	check(summer_temp - winter_temp >= 15, "Лето должно быть заметно теплее зимы (%d против %d)" % [summer_temp, winter_temp])
	# Активное событие попадает в строку сезона.
	sm.events_enabled = true
	sm.start_event("blizzard", 6.0)
	hud.update_season_display()
	check("Метель" in hud.season_label.text, "Нет погодного события в HUD: %s" % hud.season_label.text)
	sm.clear_event()
	sm.events_enabled = false
	Seasons.activate(Seasons.SPRING, 1)
	hud.update_season_display()

	# 3. Снег: погода, частицы, увлажнение.
	Seasons.activate(Seasons.WINTER, 1)
	weather.set_weather(WeatherManagerScript.WeatherType.SNOW)
	check(weather.is_snowing() and weather.is_precipitating(), "Снег должен считаться осадками")
	check(not weather.is_raining(), "Снег — это не дождь")
	check(weather.get_weather_name() == "Снег" and weather.get_weather_icon() == "🌨️", "Неверные имя/иконка снега")
	check(weather.snow_particles != null and weather.snow_particles.emitting, "Снежные частицы не включены")
	check(not weather.rain_particles.emitting, "Дождь не должен идти в снег")
	check(weather.get_temperature_offset() < 0, "Снег должен снижать температуру")

	var field := FarmField.new()
	world.add_child(field)
	field.position = Vector3(90, 0, 90)
	field.size = Vector2i(2, 2)
	field.state = FarmField.State.READY
	field._reset_cells()
	field.get_cell(Vector2i(0, 0))["moisture"] = 0.0
	weather._apply_rainfall_to_world(weather.get_rain_intensity(), 2.0)
	var snow_moisture: float = float(field.get_cell(Vector2i(0, 0))["moisture"])
	field.get_cell(Vector2i(0, 0))["moisture"] = 0.0
	weather.set_weather(WeatherManagerScript.WeatherType.RAIN)
	weather._apply_rainfall_to_world(weather.get_rain_intensity(), 2.0)
	var rain_moisture: float = float(field.get_cell(Vector2i(0, 0))["moisture"])
	check(snow_moisture > 0.0, "Снег не увлажнил почву совсем")
	check(rain_moisture > snow_moisture * 3.0, "Снег должен увлажнять заметно слабее дождя (%.2f против %.2f)" % [snow_moisture, rain_moisture])
	check(float(field.get_cell(Vector2i(0, 0))["moisture"]) <= 100.0, "Влажность клетки вышла за 100")

	# 4. Сезон меняет рост и испарение делянки через узел мира.
	Seasons.activate(Seasons.SPRING, 1)
	var spring_growth: float = field.get_growth_multiplier()
	var spring_evap: float = field.get_evaporation_multiplier()
	Seasons.activate(Seasons.WINTER, 1)
	check(field.get_growth_multiplier() < spring_growth, "Зимой делянка должна расти медленнее")
	check(field.get_evaporation_multiplier() < spring_evap, "Зимой вода испаряется медленнее")
	Seasons.activate(Seasons.SUMMER, 1)
	check(is_equal_approx(field.get_evaporation_multiplier(), 2.0), "Летом испарение делянки не ×2")
	sm.start_event("drought", 72.0)
	check(is_equal_approx(field.get_evaporation_multiplier(), 6.0), "Засуха не усилила испарение делянки")
	sm.clear_event()
	Seasons.activate(Seasons.SPRING, 1)
	field.queue_free()

	# 5. Проверка промерзания воды в зависимости от типа источника.
	var well: Node = world.get_node_or_null("Resources/Lake")
	if well == null:
		well = world.get_node_or_null("Resources/WaterWell")
	check(well != null, "В мире нет источника воды (Lake или WaterWell)")
	if well:
		Seasons.activate(Seasons.SPRING, 1)
		check(not well.is_frozen(), "Весной вода не должна быть замёрзшей")
		check(well.get_prompt().contains("[E]"), "Весной с водоёма можно брать воду")
		Seasons.activate(Seasons.WINTER, 1)
		if well.get("freezes_in_winter"):
			check(well.is_frozen(), "Открытый водоём должен промерзать зимой")
		else:
			check(not well.is_frozen(), "Закрытый колодец не должен замерзать")
		var mock := MockPlayer.new()
		mock.inventory = InventoryScript.new()
		mock.add_child(mock.inventory)
		var pond = ResourceNode.new()
		pond.freezes_in_winter = true
		mock.add_child(pond)
		root.add_child(mock)
		check(pond.is_frozen(), "Открытый водоём должен промерзать зимой")
		check(pond.get_prompt().contains("замёрзла"), "Нет подсказки о промёрзшем водоёме: %s" % pond.get_prompt())
		pond.interact(mock)
		check(mock.inventory.get_item_count("water") == 0, "Из замёрзшего водоёма удалось набрать воду")
		check(mock.messages.size() > 0, "Нет сообщения о промёрзшем водоёме")
		mock.queue_free()
		Seasons.activate(Seasons.SPRING, 1)

	# 6. Холод персонажа зимой, жара летом.
	Seasons.activate(Seasons.WINTER, 1)
	day_cycle.set_time(1, 22.0)
	weather.set_weather(WeatherManagerScript.WeatherType.SNOW)
	player.global_position = Vector3(60, 0, 60)
	player.wetness = 0.0
	player.health = 100.0
	check(player.get_cold_exposure() > 0.0, "Зимой ночью на улице должно быть холодно")
	player._handle_temperature(2.0)
	check(player.health < 100.0, "Мороз на улице не снимает здоровье")
	var dry_cold: float = player.get_cold_exposure()
	player.wetness = 90.0
	check(player.get_cold_exposure() > dry_cold, "Мокрый персонаж мёрзнет сильнее сухого")
	player.wetness = 0.0
	# Дом спасает от холода.
	house.current_stage = 1
	player.global_position = house.global_position + Vector3(0.5, 0, 0.5)
	check(is_equal_approx(player.get_cold_exposure(), 0.0), "В отремонтированном доме не должно быть холодно")
	# Метель усиливает холод и замедляет.
	player.global_position = Vector3(60, 0, 60)
	sm.start_event("blizzard", 8.0)
	var blizzard_cold: float = player.get_cold_exposure()
	var blizzard_speed: float = player.get_speed_multiplier()
	sm.clear_event()
	check(blizzard_cold > dry_cold, "Метель должна усиливать холод")
	check(blizzard_speed < player.get_speed_multiplier(), "Метель должна замедлять персонажа")
	# Летняя жара в полдень.
	Seasons.activate(Seasons.SUMMER, 1)
	day_cycle.set_time(1, 14.0)
	weather.set_weather(WeatherManagerScript.WeatherType.SUNNY)
	player.thirst = 100.0
	player._handle_thirst(1.0)
	var summer_thirst_drop: float = 100.0 - player.thirst
	Seasons.activate(Seasons.WINTER, 1)
	player.thirst = 100.0
	player._handle_thirst(1.0)
	var winter_thirst_drop: float = 100.0 - player.thirst
	check(summer_thirst_drop > winter_thirst_drop * 1.3, "Летняя жара должна сушить быстрее (%.4f против %.4f)" % [summer_thirst_drop, winter_thirst_drop])
	Seasons.activate(Seasons.SPRING, 1)

	# 7. Ягоды: осенью урожай вдвое больше.
	var bush: Node = load("res://scenes/resources/berry_bush_red.tscn").instantiate()
	root.add_child(bush)
	var picker := MockPlayer.new()
	picker.inventory = InventoryScript.new()
	picker.add_child(picker.inventory)
	root.add_child(picker)
	Seasons.activate(Seasons.SPRING, 1)
	var spring_amount: int = bush.get_harvest_amount()
	Seasons.activate(Seasons.AUTUMN, 1)
	var autumn_amount: int = bush.get_harvest_amount()
	check(spring_amount > 0 and autumn_amount == spring_amount * 2, "Осенью должно быть вдвое больше ягод (%d против %d)" % [autumn_amount, spring_amount])
	Seasons.activate(Seasons.SPRING, 1)
	bush.interact(picker)
	check(picker.inventory.get_item_count("red_berry") == spring_amount, "Весной собирается обычное количество")
	bush.queue_free()
	picker.queue_free()

	# 8. Сохранение и загрузка.
	day_cycle.set_time(23, 10.0)
	sm.set_total_day(23)
	sm.events_enabled = true
	sm.start_event("storm", 5.0)
	check(SaveManager.save_game(world, SAVE_PATH), "Мир с сезонами не сохранился")
	var txt: String = FileAccess.get_file_as_string(SAVE_PATH)
	check(txt.contains("\"seasons\""), "В файле нет секции seasons")
	check(txt.contains("\"storm\""), "В файле нет активного события")
	# Портим состояние и грузим обратно.
	sm.clear_event()
	day_cycle.set_time(1, 8.0)
	sm.set_total_day(1)
	check(SaveManager.load_game(world, SAVE_PATH), "Мир с сезонами не загрузился")
	check(sm.total_day == 23, "День не восстановился: %d вместо 23" % sm.total_day)
	check(Seasons.get_current_season() == Seasons.WINTER, "Сезон не восстановился: %s" % Seasons.get_current_season())
	check(Seasons.get_day_in_season() == 2, "День в сезоне не восстановился: %d" % Seasons.get_day_in_season())
	check(sm.get_active_event() == "storm", "Событие не восстановилось: %s" % sm.get_active_event())
	# Битая секция seasons отвергается целиком, мир не меняется.
	sm.clear_event()
	var bad := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	bad.store_string(JSON.stringify({"seasons": {"current_season": "monsoon"}}))
	bad.close()
	check(not SaveManager.load_game(world, SAVE_PATH), "Битая секция seasons принята")
	check(sm.get_active_event() == "", "Битая секция seasons изменила событие")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	sm.enabled = false
	sm.apply_save_state({"enabled": false})
	Seasons.disable()

## Достаёт «+N°C» / «-N°C» из текста HUD-строки погоды.
func _extract_temp(text: String) -> int:
	var pos: int = text.rfind("°C")
	if pos < 0:
		return 0
	var digits: String = ""
	var i: int = pos - 1
	while i >= 0 and (text[i] == "-" or text[i] == "+" or text[i].is_valid_int()):
		digits = text[i] + digits
		i -= 1
	return int(digits) if digits != "" else 0

func _finish() -> bool:
	if errors.is_empty():
		print("PASS: test_seasons — календарь 4×7, сезонные множители, события (гроза/засуха/метель/ураган), снег и промерзание, холод и жара, HUD, секция seasons в сейве")
		quit(0)
	else:
		for e in errors:
			print("ПРОВАЛЕН: ", e)
		quit(1)
	return true