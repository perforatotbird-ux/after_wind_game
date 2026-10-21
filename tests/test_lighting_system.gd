extends SceneTree

## Тестирование комплексной системы освещения и теней:
## 1. Плавный множитель погоды WeatherManager
## 2. Суточный цикл DayNightCycle: солнце, луна, тени (выкл. ночью), звёзды
## 3. LightingEnvManager: SSAO, glow, тональность ambient по времени и сезонам
## 4. FurnaceLight: подсветка печи/плавильни и реакция на machine_running_changed
## 5. LightLodManager: управление видимостью dynamic_lights по расстоянию (гистерезис)
## 6. GameSettings: пресеты качества освещения (low, medium, high, ultra)

const WorldScene = preload("res://scenes/world/world.tscn")
const WeatherManager = preload("res://scripts/world/weather_manager.gd")
const DayNightCycle = preload("res://scripts/world/day_night_cycle.gd")
const LightingEnvManager = preload("res://scripts/world/lighting_env_manager.gd")
const LightLodManager = preload("res://scripts/world/light_lod_manager.gd")
const FurnaceLight = preload("res://scripts/crafting/furnace_light.gd")
const ProductionMachine = preload("res://scripts/crafting/production_machine.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")

var errors: Array[String] = []
var world: Node = null
var frames: int = 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		errors.append(msg)
		push_error("❌ ОШИБКА: " + msg)

func _initialize() -> void:
	print("========================================")
	print("🧪 ТЕСТИРОВАНИЕ СИСТЕМЫ ОСВЕЩЕНИЯ И ТЕНЕЙ")
	print("========================================")

	# 1. Тест WeatherManager
	print("\n--- Тест 1: WeatherManager множитель освещения ---")
	var wm: WeatherManager = WeatherManager.new()
	wm.set_base_sun_energy(1.2)
	wm.set_weather(WeatherManager.WeatherType.HEAVY_RAIN, false)
	check(absf(wm._target_energy - 1.2 * 0.29) < 0.01,
		"HEAVY_RAIN должен понизить target_energy до ~0.348 (факт: %.3f)" % wm._target_energy)
	check(wm._target_weather_light_multiplier == 0.29,
		"Множитель ливня должен быть 0.29")
	wm.set_weather(WeatherManager.WeatherType.SUNNY, false)
	check(wm._target_weather_light_multiplier == 1.0,
		"Множитель солнца должен быть 1.0")
	wm.free()
	print("  • WeatherManager корректно рассчитывает множители освещения.")

	# 2. Тест LightingEnvManager
	print("\n--- Тест 2: LightingEnvManager ambient и SSAO ---")
	var lem: LightingEnvManager = LightingEnvManager.new()
	lem._day_phase = "Ночь"
	lem._season = "winter"
	lem._weather_type = WeatherManager.WeatherType.SUNNY
	var dummy_env := Environment.new()
	var dummy_we := WorldEnvironment.new()
	dummy_we.environment = dummy_env
	lem.world_environment = dummy_we
	lem._update_ambient()
	check(lem._target_ambient.b > lem._target_ambient.r,
		"Зимний ночной ambient должен иметь холодный синий оттенок (b > r)")
	check(dummy_env.ambient_light_energy < 0.45,
		"Ночью ambient energy должен быть снижен (< 0.45, факт: %.2f)" % dummy_env.ambient_light_energy)
	
	lem._day_phase = "День"
	lem._season = "summer"
	lem._update_ambient()
	check(dummy_env.ambient_light_energy > 0.55,
		"Днём ambient energy должен быть ярким (> 0.55, факт: %.2f)" % dummy_env.ambient_light_energy)
	dummy_we.free()
	lem.free()
	print("  • LightingEnvManager корректно управляет ambient light и сезонной гаммой.")

	# 3. Тест FurnaceLight
	print("\n--- Тест 3: FurnaceLight и сигнал machine_running_changed ---")
	var machine: ProductionMachine = ProductionMachine.new()
	var flight: FurnaceLight = FurnaceLight.new()
	machine.add_child(flight)
	flight._ready()
	check(flight.light_node != null, "FurnaceLight должен создать или найти light_node")
	check(not flight._running, "В простое _running должно быть false")
	
	# Симулируем запуск станка через сигнал
	machine.machine_running_changed.emit(true)
	check(flight._running == true, "FurnaceLight должен среагировать на запуск станка")
	flight._process(1.0)
	check(flight.light_node.visible == true, "При работе станка свет топки должен быть видим")
	check(flight.light_node.light_energy > 0.5, "Энергия света топки должна подняться (> 0.5)")
	check(flight.light_node.is_in_group("dynamic_lights"), "Свет топки должен входить в группу dynamic_lights")
	
	machine.machine_running_changed.emit(false)
	check(flight._running == false, "FurnaceLight должен среагировать на остановку станка")
	flight._process(1.0)
	check(flight.light_node.visible == false, "При остановке свет топки должен погаснуть")
	if flight.light_node and is_instance_valid(flight.light_node):
		flight.light_node.free()
	machine.free()
	print("  • FurnaceLight синхронизируется с работой станка и входит в dynamic_lights.")

	# 4. Тест GameSettings пресетов
	print("\n--- Тест 4: GameSettings пресеты освещения ---")
	check(GameSettings.LIGHTING_PRESET_NAMES.has("low"), "Должен быть пресет low")
	check(GameSettings.LIGHTING_PRESET_NAMES.has("ultra"), "Должен быть пресет ultra")
	check(GameSettings.LIGHTING_PRESETS["low"]["ssao"] == false, "В low SSAO выключен")
	check(GameSettings.LIGHTING_PRESETS["high"]["ssao"] == true, "В high SSAO включен")
	check(GameSettings.LIGHTING_PRESETS["ultra"]["sdfgi"] == true, "В ultra SDFGI включен")
	GameSettings.set_value("lighting_quality", "low")
	check(str(GameSettings.get_value("lighting_quality")) == "low", "Пресет low должен сохраниться")
	GameSettings.set_value("lighting_quality", "high")
	check(str(GameSettings.get_value("lighting_quality")) == "high", "Пресет high должен сохраниться")
	print("  • GameSettings пресеты графики и теней валидируются и переключаются.")

	# 5. Тест мира в сборе
	print("\n--- Тест 5: Инициализация World сцены с новыми менеджерами ---")
	world = WorldScene.instantiate()
	root.add_child(world)

func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	
	# Проверка узлов в сцене World
	var sun: DirectionalLight3D = world.get_node_or_null("DirectionalLight3D")
	check(sun != null, "В World должен быть DirectionalLight3D")
	if sun:
		check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
			"DirectionalLight3D должен использовать SHADOW_PARALLEL_4_SPLITS")
	
	var moon: DirectionalLight3D = world.get_node_or_null("MoonLight")
	check(moon != null, "В World должен быть узел MoonLight")
	
	var dnc: DayNightCycle = world.get_node_or_null("DayNightCycle")
	check(dnc != null, "В World должен быть DayNightCycle")
	if dnc and sun and moon:
		# Проверка дня: тени солнца включены, луна скрыта
		dnc.current_hour = 12.0
		dnc._update_lighting_and_sky(true)
		check(sun.shadow_enabled == true, "В полдень тени солнца должны быть активны")
		check(moon.visible == false, "В полдень луна должна быть скрыта")
		
		# Проверка ночи: тени солнца выключены, луна видна
		dnc.current_hour = 1.0
		dnc._update_lighting_and_sky(true)
		check(sun.shadow_enabled == false, "Ночью тени солнца должны отключаться для экономии GPU")
		check(moon.visible == true, "Ночью луна должна быть видна")
		check(moon.shadow_enabled == false, "Луна не должна отбрасывать тяжелые тени")
	
	var lem: LightingEnvManager = world.get_node_or_null("LightingEnvManager")
	check(lem != null, "В World должен быть LightingEnvManager")
	
	var lod_mgr: LightLodManager = world.get_node_or_null("LightLodManager")
	check(lod_mgr != null, "В World должен быть LightLodManager")
	
	# Проверка группы dynamic_lights в мире
	var dyn_lights := root.get_tree().get_nodes_in_group("dynamic_lights")
	check(dyn_lights.size() > 0, "В мире должны быть зарегистрированы dynamic_lights (фонари/окна/костры/печи)")
	
	# Проверка LightLodManager culling
	if lod_mgr and dyn_lights.size() > 0:
		var test_light: OmniLight3D = dyn_lights[0] as OmniLight3D
		if test_light:
			# Игровая логика хочет, чтобы свет горел.
			LightLodManager.set_desired_visible(test_light, true)
			test_light.visible = true
			# Создаем фиктивную камеру далеко от источника
			var cam := Camera3D.new()
			world.add_child(cam)
			cam.global_position = test_light.global_position + Vector3(100.0, 0.0, 0.0)
			lod_mgr.camera = cam
			lod_mgr._timer = lod_mgr.check_interval
			lod_mgr._process(0.1)
			check(test_light.visible == false, "На дистанции 100м свет должен быть скрыт LOD менеджером")
			check(test_light.has_meta("_lod_hidden"), "Скрытый свет должен иметь метку _lod_hidden")
			
			# Перемещаем камеру в упор
			cam.global_position = test_light.global_position + Vector3(5.0, 0.0, 0.0)
			lod_mgr._timer = lod_mgr.check_interval
			lod_mgr._process(0.1)
			check(test_light.visible == true, "Вблизи (< 24м) свет должен снова стать видимым")
			check(not test_light.has_meta("_lod_hidden"), "Метка _lod_hidden должна быть снята")
			
			# Свет, который игровая логика держит выключенным, LOD включать не должен.
			LightLodManager.set_desired_visible(test_light, false)
			cam.global_position = test_light.global_position + Vector3(100.0, 0.0, 0.0)
			lod_mgr._timer = lod_mgr.check_interval
			lod_mgr._process(0.1)
			check(test_light.visible == false, "На дистанции 100м свет должен быть скрыт LOD менеджером")
			cam.global_position = test_light.global_position + Vector3(5.0, 0.0, 0.0)
			lod_mgr._timer = lod_mgr.check_interval
			lod_mgr._process(0.1)
			check(test_light.visible == false, "LOD не должен включать свет, выключенный игровой логикой")
			cam.queue_free()

	if errors.is_empty():
		print("\n========================================")
		print("🎉 ВСЕ ТЕСТЫ СИСТЕМЫ ОСВЕЩЕНИЯ И ТЕНЕЙ УСПЕШНО ПРОЙДЕНЫ!")
		print("========================================")
		quit(0)
	else:
		print("\n========================================")
		print("❌ ОБНАРУЖЕНЫ ОШИБКИ (%d):" % errors.size())
		for e in errors:
			print("  • " + e)
		print("========================================")
		quit(1)
	return true
