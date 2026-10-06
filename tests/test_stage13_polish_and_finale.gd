extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const VictoryManager = preload("res://scripts/core/victory_manager.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")
const ItemDB = preload("res://scripts/inventory/item_db.gd")

var _test_executed: bool = false

func _init() -> void:
	print("Инициализация сцены для тестирования Этапа 13...")
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
	print("=================================================================")
	print("🧪 ЗАПУСК ТЕСТОВ ЭТАПА 13: GAME FEEL, АУДИО, ПАУЗА И BASE RESTORED")
	print("=================================================================")
	
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
		_fail("HUD не найден")
		return
	
	var inv = player.get("inventory")
	if not inv:
		_fail("Инвентарь игрока не найден")
		return

	# -------------------------------------------------------------
	# 1. Проверка процедурного AudioManager
	# -------------------------------------------------------------
	print("\n--- Проверка 1: Процедурный AudioManager и генерация звуков ---")
	var audio_mgr = world.find_child("AudioManager", true, false)
	if not audio_mgr:
		_fail("AudioManager не найден среди дочерних узлов World")
		return
	
	if not AudioManager.instance:
		_fail("Статический экземпляр AudioManager.instance равен null")
		return
	
	var expected_sounds: Array[String] = [
		"hit_wood", "hit_stone", "till_soil", "harvest",
		"machine_start", "coins", "water_splash", "ui_click",
		"victory_fanfare", "wind_ambient", "rain_ambient"
	]
	
	for s_name in expected_sounds:
		if not audio_mgr._sounds.has(s_name):
			_fail("Звуковой эффект '%s' отсутствует в реестре AudioManager" % s_name)
			return
		var stream: AudioStreamWAV = audio_mgr._sounds[s_name]
		if not stream or stream.data.is_empty():
			_fail("Аудиопоток '%s' пуст или не сгенерирован" % s_name)
			return
		print("  • Звук '%s': %d байт PCM, mix_rate: %d Гц" % [s_name, stream.data.size(), stream.mix_rate])
	
	# Проверка вызова воспроизведения и регулировки громкости
	AudioManager.play("hit_wood", 1.05)
	AudioManager.play("coins", 1.0)
	AudioManager.play("ui_click")
	
	audio_mgr.set_sfx_vol(0.5)
	if abs(audio_mgr.sfx_volume - 0.5) > 0.01:
		_fail("Регулировка sfx_volume не сработала")
		return
	
	audio_mgr.set_ambient_vol(0.7)
	if abs(audio_mgr.ambient_volume - 0.7) > 0.01:
		_fail("Регулировка ambient_volume не сработала")
		return
	
	audio_mgr.set_weather_rain(true, 0.8)
	audio_mgr.set_weather_rain(false)
	print("✅ Все 11 процедурных звуковых эффектов сгенерированы и воспроизводятся.")

	# -------------------------------------------------------------
	# 2. Проверка Меню Паузы (PauseWindow) и PauseButton
	# -------------------------------------------------------------
	print("\n--- Проверка 2: Меню паузы PauseWindow и управление по ESC ---")
	if not hud.pause_window:
		_fail("PauseWindow отсутствует в HUD")
		return
	if not hud.pause_button:
		_fail("PauseButton отсутствует в HUD")
		return
	
	# Открытие меню паузы
	hud.toggle_pause_menu()
	if not hud.pause_window.visible:
		_fail("PauseWindow должно быть видимым после toggle_pause_menu()")
		return
	if not paused:
		_fail("Дерево сцены SceneTree должно встать на паузу при открытии PauseWindow")
		return
	if not hud.base_progress_label or hud.base_progress_label.text.is_empty():
		_fail("BaseProgressLabel в меню паузы не обновлен")
		return
	print("  • Индикатор прогресса в меню паузы: '%s'" % hud.base_progress_label.text)
	
	if not hud.pause_tasks_list or hud.pause_tasks_list.get_child_count() != 8:
		_fail("Чек-лист вех восстановления базы должен содержать 8 пунктов, факт: %d" % (hud.pause_tasks_list.get_child_count() if hud.pause_tasks_list else 0))
		return
	print("  • Чек-лист вех в меню паузы успешно отрисован (8 задач).")
	
	# Проверка слайдеров
	if hud.sfx_slider:
		hud.sfx_slider.value = 0.65
		if abs(audio_mgr.sfx_volume - 0.65) > 0.01:
			_fail("Слайдер sfx_slider не синхронизировался с AudioManager")
			return
	
	# Закрытие меню паузы
	hud.close_pause_menu()
	if hud.pause_window.visible:
		_fail("PauseWindow должно закрыться после close_pause_menu()")
		return
	if paused:
		_fail("Пауза должна быть снята после закрытия PauseWindow")
		return
	print("✅ Меню паузы и чек-лист восстановления базы функционируют штатно.")

	# -------------------------------------------------------------
	# 3. Проверка логики VictoryManager
	# -------------------------------------------------------------
	print("\n--- Проверка 3: Менеджер оценки условий финала VictoryManager ---")
	ContractDB.reset_completed()
	
	# Сброс стадий зданий для проверки неполного состояния
	var house = world.find_child("RepairableHouse", true, false)
	var storage = world.find_child("RepairableStorage", true, false)
	if house: house.current_stage = 0
	if storage: storage.current_stage = 0
	
	var initial_eval = VictoryManager.evaluate_base_restored(world)
	print("  • Начальное состояние базы: выполнено %d/%d вех (%d%%), финал: %s" % [
		initial_eval.completed_count, initial_eval.total_count, initial_eval.progress_pct, str(initial_eval.is_victory)
	])
	if initial_eval.is_victory:
		_fail("База не должна считаться восстановленной на нулевых стадиях")
		return
	
	# Приводим мир к 100% выполнению всех 8 условий Первого этапа:
	# 1. Дом 2/2
	if house: house.current_stage = 2
	# 2. Склад 2/2
	if storage: storage.current_stage = 2
	# 3. Дробилка в наличии (уже в сцене)
	# 4. Верстак в наличии (уже в сцене)
	# 5. Печь-плавильня в наличии (уже в сцене)
	# 6. Грядка вскопана
	var plot1 = world.find_child("FarmlandPlot1", true, false)
	if plot1:
		plot1.soil_state = 1
	# 7. Сдано 2 контракта
	ContractDB.completed_contracts["contract_wood"] = true
	ContractDB.completed_contracts["contract_bricks"] = true
	# 8. Инструмент мастера Lv.2 экипирован
	inv.upgrade_tool("iron_axe")
	
	var complete_eval = VictoryManager.evaluate_base_restored(world)
	print("  • Состояние после завершения всех работ: выполнено %d/%d вех (%d%%), финал: %s" % [
		complete_eval.completed_count, complete_eval.total_count, complete_eval.progress_pct, str(complete_eval.is_victory)
	])
	if not complete_eval.is_victory:
		_fail("Все 8 условий выполнены, но evaluate_base_restored вернул is_victory == false")
		return
	if complete_eval.progress_pct != 100 or complete_eval.completed_count != 8:
		_fail("Прогресс должен быть 100%% (8/8 вех)")
		return
	print("✅ VictoryManager корректно верифицировал все 8 критериев Раздела 85 дизайн-документа.")

	# -------------------------------------------------------------
	# 4. Проверка победного окна VictoryWindow («BASE RESTORED»)
	# -------------------------------------------------------------
	print("\n--- Проверка 4: Окно триумфа VictoryWindow (BASE RESTORED) ---")
	if not hud.victory_window:
		_fail("VictoryWindow отсутствует в HUD")
		return
	
	hud._victory_shown = false
	var triggered = hud.check_and_show_victory_if_earned()
	if not triggered:
		_fail("check_and_show_victory_if_earned() должно вернуть true при 100% готовности")
		return
	if not hud.victory_window.visible:
		_fail("VictoryWindow должно стать видимым")
		return
	if not paused:
		_fail("Игра должна быть на паузе во время победного экрана")
		return
	print("  • Победное окно «BASE RESTORED» успешно активировано.")
	
	hud.close_victory_window()
	if hud.victory_window.visible:
		_fail("VictoryWindow должно закрыться после close_victory_window()")
		return
	if paused:
		_fail("Пауза должна быть снята для перехода в режим свободной песочницы")
		return
	print("✅ Переход в свободный режим песочницы после победного окна работает безупречно.")

	print("\n=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ЭТАПА 13 УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("🎉 ПЕРВАЯ ГЛАВА «ПОСЛЕ БУРИ» (BASE RESTORED) ПОЛНОСТЬЮ ЗАВЕРШЕНА!")
	print("=================================================================")
	quit(0)
