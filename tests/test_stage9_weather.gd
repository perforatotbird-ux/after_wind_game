extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const ItemDB = preload("res://scripts/inventory/item_db.gd")
const WeatherManager = preload("res://scripts/world/weather_manager.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 9...")
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
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 9: СИСТЕМА ПОГОДЫ И ОСАДКОВ")
	print("========================================")
	
	var world = root.get_node_or_null("World")
	if not world:
		_fail("Узел World не найден в сцене")
		return
	
	var player = world.get_node_or_null("Player")
	if not player:
		_fail("Player отсутствует в сцене")
		return
	
	var hud = world.get_node_or_null("HUD")
	if not hud:
		_fail("HUD отсутствует в сцене")
		return
	
	var weather_mgr = world.get_node_or_null("WeatherManager")
	if not weather_mgr:
		_fail("WeatherManager отсутствует в сцене World")
		return
	
	var plot1 = world.find_child("FarmlandPlot1", true, false)
	var reservoir = world.find_child("WaterReservoir", true, false)
	var house = world.find_child("RepairableHouse", true, false)
	var smelter = world.find_child("Smelter", true, false)
	
	if not plot1:
		_fail("FarmlandPlot1 не найден")
		return
	if not reservoir:
		_fail("WaterReservoir не найден")
		return
	if not house:
		_fail("RepairableHouse не найден")
		return
	if not smelter:
		_fail("Smelter не найден")
		return
	
	print("✅ Все ключевые узлы мира найдены (WeatherManager, Player, HUD, FarmlandPlot, Reservoir, House, Smelter).")

	# -------------------------------------------------------------
	# 1. Проверка состояний погоды и параметров
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Типы погоды и параметры WeatherManager ---")
	
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	if weather_mgr.current_weather != WeatherManager.WeatherType.SUNNY:
		_fail("set_weather(SUNNY) не установил погоду")
		return
	if weather_mgr.get_weather_name() != "Ясно" or weather_mgr.get_weather_icon() != "☀️":
		_fail("Неверное имя или иконка для SUNNY: %s, %s" % [weather_mgr.get_weather_name(), weather_mgr.get_weather_icon()])
		return
	if weather_mgr.is_raining():
		_fail("is_raining() возвращает true для солнечной погоды")
		return
	if weather_mgr.get_temperature_offset() != 0:
		_fail("Температурное смещение для солнца должно быть 0")
		return
	if weather_mgr.rain_particles and weather_mgr.rain_particles.emitting:
		_fail("Частицы дождя не должны эмиттиться при солнечной погоде")
		return
	print("  • Погода SUNNY проверена успешно.")
	
	weather_mgr.set_weather(WeatherManager.WeatherType.OVERCAST)
	if weather_mgr.get_weather_name() != "Пасмурно" or weather_mgr.get_weather_icon() != "☁️":
		_fail("Неверные параметры для OVERCAST")
		return
	if weather_mgr.is_raining():
		_fail("is_raining() возвращает true для OVERCAST")
		return
	if weather_mgr.get_temperature_offset() != -3:
		_fail("Температурное смещение для OVERCAST должно быть -3")
		return
	print("  • Погода OVERCAST проверена успешно.")
	
	weather_mgr.set_weather(WeatherManager.WeatherType.RAIN)
	if weather_mgr.get_weather_name() != "Дождь" or weather_mgr.get_weather_icon() != "🌧️":
		_fail("Неверные параметры для RAIN")
		return
	if not weather_mgr.is_raining():
		_fail("is_raining() должен возвращать true для RAIN")
		return
	if weather_mgr.get_rain_intensity() != 1.0:
		_fail("Интенсивность дождя RAIN должна быть 1.0")
		return
	if weather_mgr.get_temperature_offset() != -6:
		_fail("Температурное смещение для RAIN должно быть -6")
		return
	if weather_mgr.rain_particles and not weather_mgr.rain_particles.emitting:
		_fail("Частицы дождя должны быть включены при RAIN")
		return
	print("  • Погода RAIN проверена успешно.")
	
	weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN)
	if weather_mgr.get_weather_name() != "Сильный ливень" or weather_mgr.get_weather_icon() != "⛈️":
		_fail("Неверные параметры для HEAVY_RAIN")
		return
	if not weather_mgr.is_raining():
		_fail("is_raining() должен возвращать true для HEAVY_RAIN")
		return
	if weather_mgr.get_rain_intensity() != 2.0:
		_fail("Интенсивность дождя HEAVY_RAIN должна быть 2.0")
		return
	if weather_mgr.get_temperature_offset() != -9:
		_fail("Температурное смещение для HEAVY_RAIN должно быть -9")
		return
	if weather_mgr.rain_particles and weather_mgr.rain_particles.amount != 450:
		_fail("Для ливня должно быть увеличено количество частиц до 450")
		return
	print("  • Погода HEAVY_RAIN проверена успешно.")
	
	# -------------------------------------------------------------
	# 2. Проверка HUD отображения погоды и шкалы мокроты
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Интеграция HUD с погодой и шкалой мокроты ---")
	
	if not hud.wetness_bar or not hud.wetness_label:
		_fail("WetnessBar или WetnessLabel отсутствуют в HUD")
		return
	
	weather_mgr.set_weather(WeatherManager.WeatherType.RAIN)
	hud.update_weather_display(weather_mgr.current_weather, weather_mgr.get_weather_name(), weather_mgr.get_weather_icon())
	if not ("Дождь" in hud.weather_label.text and "🌧️" in hud.weather_label.text):
		_fail("HUD weather_label не отображает дождь: %s" % hud.weather_label.text)
		return
	print("  • HUD корректно отображает статус погоды и температуру: %s" % hud.weather_label.text)
	
	# Проверка обновления шкалы мокроты
	player.wetness = 0.0
	player.wetness_changed.emit(0.0, 100.0)
	if not ("Сухой" in hud.wetness_label.text):
		_fail("HUD wetness_label не отображает статус Сухой при 0%%: %s" % hud.wetness_label.text)
		return
	
	player.wetness = 50.0
	player.wetness_changed.emit(50.0, 100.0)
	if hud.wetness_bar.value != 50.0:
		_fail("HUD wetness_bar не установил значение 50%%")
		return
	if not ("Промок" in hud.wetness_label.text):
		_fail("HUD wetness_label не отображает статус Промок при 50%%: %s" % hud.wetness_label.text)
		return
	print("  • Шкала и статус мокроты в HUD работают корректно.")

	# -------------------------------------------------------------
	# 3. Намокание игрока под дождем и штрафы
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Намокание игрока, дебаффы скорости и усталости ---")
	
	player.wetness = 0.0
	# Позиционируем игрока далеко от дома и печи в открытом поле
	player.global_position = Vector3(30, 0, 30)
	weather_mgr.set_weather(WeatherManager.WeatherType.RAIN)
	
	# Симулируем 5 секунд дождя
	player._handle_wetness(5.0)
	if player.wetness <= 5.0:
		_fail("Игрок должен был промокнуть под дождем, текущая мокрота: %f" % player.wetness)
		return
	print("  • Намокание под дождем работает (мокрота: %.1f%%)." % player.wetness)
	
	# Проверка штрафов скорости при разной мокроте
	player.wetness = 20.0
	var speed_dry = player.get_speed_multiplier()
	player.wetness = 50.0
	var speed_wet = player.get_speed_multiplier()
	player.wetness = 90.0
	var speed_soaked = player.get_speed_multiplier()
	
	if speed_wet >= speed_dry:
		_fail("При мокроте 50%% скорость должна снижаться (было %f, стало %f)" % [speed_dry, speed_wet])
		return
	if speed_soaked >= speed_wet:
		_fail("При мокроте 90%% скорость должна быть еще ниже (было %f, стало %f)" % [speed_wet, speed_soaked])
		return
	print("  • Штрафы к скорости движения при намокании применились корректно (1.0x -> %.2fx -> %.2fx)." % [speed_wet, speed_soaked])
	
	# Проверка расхода энергии при мокрой одежде
	player.wetness = 0.0
	player.energy = 100.0
	player.consume_energy(10.0)
	var dry_energy_left = player.energy
	
	player.wetness = 85.0
	player.energy = 100.0
	player.consume_energy(10.0)
	var wet_energy_left = player.energy
	
	if wet_energy_left >= dry_energy_left:
		_fail("Мокрая одежда должна увеличивать расход энергии (сухой осталось: %f, мокрый: %f)" % [dry_energy_left, wet_energy_left])
		return
	print("  • Повышенный расход энергии при мокрой одежде подтвержден (осталось %f vs %f)." % [wet_energy_left, dry_energy_left])

	# -------------------------------------------------------------
	# 4. Сушка игрока у печи-плавильни и укрытие в отремонтированном доме
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Сушка у печи, укрытие в доме и сон ---")
	
	# Сушка у раскаленной плавильни
	player.wetness = 80.0
	player.global_position = smelter.global_position + Vector3(1.0, 0, 0.0)
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	player._handle_wetness(4.0)
	if player.wetness >= 60.0:
		_fail("Игрок у печи должен сохнуть очень быстро, текущая мокрота: %f" % player.wetness)
		return
	print("  • Быстрая сушка возле плавильной печи работает (мокрота снизилась до %.1f%%)." % player.wetness)
	
	# Укрытие в доме во время дождя
	house.current_stage = 1 # Дом отремонтирован
	player.global_position = house.global_position + Vector3(0.5, 0, 0.5)
	player.wetness = 50.0
	weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN)
	player._handle_wetness(3.0)
	if player.wetness > 50.0:
		_fail("В отремонтированном доме игрок не должен намокать во время дождя, текущая мокрота: %f" % player.wetness)
		return
	if player.wetness >= 50.0:
		_fail("В укрытии дома игрок должен постепенно сохнуть")
		return
	print("  • Укрытие в отремонтированном доме защищает от ливня и сушит персонажа (мокрота: %.1f%%)." % player.wetness)
	
	# Мгновенная просушка при отдыхе в кровати
	player.wetness = 75.0
	player.rest_in_bed(2)
	if player.wetness != 0.0:
		_fail("После сна в кровати мокрота должна сброситься до 0, текущая: %f" % player.wetness)
		return
	print("  • Сон в кровати полностью снимает мокроту (0%).")

	# -------------------------------------------------------------
	# 5. Автоматическое увлажнение грядок пашни во время дождя
	# -------------------------------------------------------------
	print("\n--- Проверка 5: Авто-полив грядок во время дождя ---")
	
	# Вспахиваем грядку
	plot1.soil_state = 1 # TILLED
	plot1.moisture = 10.0
	plot1._update_soil_material()
	
	weather_mgr.set_weather(WeatherManager.WeatherType.RAIN)
	# Симулируем 3 секунды дождя через метод _apply_rainfall_to_world
	weather_mgr._apply_rainfall_to_world(weather_mgr.get_rain_intensity(), 3.0)
	
	if plot1.moisture <= 15.0:
		_fail("Грядка должна была увлажниться дождем (было 10.0, стало: %f)" % plot1.moisture)
		return
	print("  • Дождь успешно увлажнил почву грядки (влажность выросла с 10%% до %.1f%%)." % plot1.moisture)

	# -------------------------------------------------------------
	# 6. Наполнение резервуара для воды дождевыми осадками
	# -------------------------------------------------------------
	print("\n--- Проверка 6: Наполнение резервуара осадками ---")
	
	reservoir.current_water = 5
	weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN) # интенсивность 2.0
	weather_mgr._reservoir_accumulator = 0.0
	
	# Симулируем 6 секунд сильного ливня (интенсивность 2.0 * 6.0 = 12.0 накопителя >= threshold 10.0)
	weather_mgr._apply_rainfall_to_world(weather_mgr.get_rain_intensity(), 6.0)
	
	if reservoir.current_water != 6:
		_fail("Резервуар должен был набрать +1 воды от сильного дождя (ожидалось 6, факт: %d)" % reservoir.current_water)
		return
	print("  • Резервуар успешно наполнился дождевой водой (с 5 до 6 ед).")

	# -------------------------------------------------------------
	# 7. Цикл смены погоды
	# -------------------------------------------------------------
	print("\n--- Проверка 7: Автоматическая циклическая смена погоды ---")
	
	weather_mgr._cycle_index = 0
	weather_mgr.set_weather(WeatherManager.WeatherType.SUNNY)
	weather_mgr._advance_weather_cycle()
	if weather_mgr.current_weather != WeatherManager.WeatherType.OVERCAST:
		_fail("Цикл погоды должен был переключиться на OVERCAST (факт: %d)" % weather_mgr.current_weather)
		return
	weather_mgr._advance_weather_cycle()
	if weather_mgr.current_weather != WeatherManager.WeatherType.RAIN:
		_fail("Цикл погоды должен был переключиться на RAIN (факт: %d)" % weather_mgr.current_weather)
		return
	print("  • Циклическая последовательность погоды переключается корректно.")

	print("\n========================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 9 УСПЕШНО ПРОЙДЕНЫ!")
	print("========================================")
	quit(0)
