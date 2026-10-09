extends SceneTree

## Тест стартового меню: слоты сохранений, «Продолжить», настройки, сессия.
## Запуск: godot --headless --script res://tests/test_main_menu_and_slots.gd

const WorldScene = preload("res://scenes/world/world.tscn")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const SavesPanel = preload("res://scripts/ui/saves_panel.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

const TEST_DIR: String = "user://test_menu_slots"
const TEST_AUTOSAVE: String = "user://test_menu_slots/autosave.json"
const TEST_SETTINGS: String = "user://test_menu_settings.cfg"

var world: Node
var _done: bool = false
var _frames: int = 0

func _init() -> void:
	SaveSlots.save_dir = TEST_DIR
	SaveSlots.autosave_path = TEST_AUTOSAVE
	GameSettings.settings_path = TEST_SETTINGS
	world = WorldScene.instantiate()
	root.add_child(world)

func _process(_delta: float) -> bool:
	if _done:
		return false
	_frames += 1
	if _frames < 3:
		return false
	_done = true
	_run()
	return false

func _fail(msg: String) -> void:
	print("❌ ТЕСТ ПРОВАЛЕН: " + msg)
	_cleanup()
	quit(1)

func _cleanup() -> void:
	for slot_id in SaveSlots.get_all_slot_ids():
		var path: String = SaveSlots.get_slot_path(slot_id)
		for p in [path, path + ".tmp"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)

func _run() -> void:
	_cleanup()

	# 1. В headless-тесте мир не показывает стартовое меню
	if world.get("is_in_main_menu") != false:
		_fail("в тестовом запуске мир не должен открывать стартовое меню")
		return
	if world.find_child("MainMenu", false, false) != null:
		_fail("MainMenu не должен создаваться в headless")
		return

	# 2. Пустые слоты
	if SaveSlots.get_all_slot_ids().size() != 1 + SaveSlots.MANUAL_SLOT_COUNT:
		_fail("ожидалось автосохранение + %d ручных слота" % SaveSlots.MANUAL_SLOT_COUNT)
		return
	if SaveSlots.get_latest_slot() != "":
		_fail("без сохранений «Продолжить» должно быть недоступно")
		return
	if SaveSlots.get_slot_info("slot_1").get("exists", true):
		_fail("slot_1 должен быть пуст")
		return

	# 3. Сохранение в слот 2
	if not SaveSlots.save_to_slot(world, "slot_2"):
		_fail("save_to_slot(slot_2) вернул false")
		return
	var info: Dictionary = SaveSlots.get_slot_info("slot_2")
	if not info.get("exists", false) or not info.get("valid", false):
		_fail("slot_2 должен существовать и быть корректным")
		return
	if SaveSlots.get_latest_slot() != "slot_2":
		_fail("последним сохранением должен быть slot_2")
		return
	if SaveSlots.format_slot_details(info) == "Пусто":
		_fail("описание заполненного слота не должно быть «Пусто»")
		return

	# 4. Недопустимый идентификатор слота
	if SaveSlots.get_slot_path("../evil") != "" or SaveSlots.save_to_slot(world, "slot_9"):
		_fail("неизвестный слот должен отклоняться")
		return

	# 5. Повреждённый слот не выбирается для «Продолжить»
	var f = FileAccess.open(SaveSlots.get_slot_path("slot_3"), FileAccess.WRITE)
	f.store_string("{ это не json")
	f.close()
	var bad: Dictionary = SaveSlots.get_slot_info("slot_3")
	if not bad.get("exists", false) or bad.get("valid", true):
		_fail("повреждённый slot_3 должен быть exists=true, valid=false")
		return
	if SaveSlots.get_latest_slot() != "slot_2":
		_fail("повреждённый слот не должен становиться последним")
		return

	# 6. Загрузка из слота
	if not SaveSlots.load_from_slot(world, "slot_2"):
		_fail("load_from_slot(slot_2) вернул false")
		return
	if SaveSlots.load_from_slot(world, "slot_1"):
		_fail("загрузка пустого слота должна возвращать false")
		return

	# 7. Стартовое меню: «Продолжить» доступно, окна создаются
	var menu = MainMenu.new()
	menu.world = world
	root.add_child(menu)
	if menu._continue_button == null or menu._continue_button.disabled:
		_fail("при наличии сохранения «Продолжить» должно быть доступно")
		return
	var saves_panel = SavesPanel.new()
	saves_panel.setup("load", world)
	menu.add_child(saves_panel)
	var settings_panel = SettingsPanel.new()
	menu.add_child(settings_panel)
	saves_panel.queue_free()
	settings_panel.queue_free()

	# 8. Удаление слотов
	SaveSlots.delete_slot("slot_2")
	SaveSlots.delete_slot("slot_3")
	if SaveSlots.has_slot("slot_2") or SaveSlots.has_slot("slot_3"):
		_fail("слоты должны удаляться")
		return
	menu.refresh_continue()
	if not menu._continue_button.disabled:
		_fail("без сохранений «Продолжить» должно блокироваться")
		return
	menu.queue_free()

	# 9. Настройки: проверка диапазонов, сохранение, сброс
	GameSettings.load_settings()
	GameSettings.set_value("master_volume", 5.0)
	GameSettings.set_value("mouse_sensitivity", 0.0)
	GameSettings.set_value("resolution_index", 99)
	GameSettings.set_value("fullscreen", "да")
	GameSettings.set_value("sfx_volume", 0.3)
	if not is_equal_approx(float(GameSettings.get_value("master_volume")), 1.0):
		_fail("громкость должна ограничиваться 1.0")
		return
	if not is_equal_approx(float(GameSettings.get_value("mouse_sensitivity")), GameSettings.MOUSE_SENSITIVITY_MIN):
		_fail("чувствительность должна ограничиваться минимумом")
		return
	if int(GameSettings.get_value("resolution_index")) != GameSettings.RESOLUTIONS.size() - 1:
		_fail("индекс разрешения должен ограничиваться списком")
		return
	if GameSettings.get_value("fullscreen") != false:
		_fail("некорректный fullscreen должен сбрасываться на значение по умолчанию")
		return
	GameSettings.load_settings()
	if not is_equal_approx(float(GameSettings.get_value("sfx_volume")), 0.3):
		_fail("настройки должны сохраняться в файл")
		return
	GameSettings.reset_to_defaults()
	if not is_equal_approx(float(GameSettings.get_value("sfx_volume")), float(GameSettings.DEFAULTS["sfx_volume"])):
		_fail("сброс должен возвращать значения по умолчанию")
		return

	# 10. Сессия: запрос читается ровно один раз
	GameSession.request_load(self, "slot_1")
	var req: Dictionary = GameSession.consume(self)
	if not req.get("skip_menu", false) or req.get("load_slot", "") != "slot_1":
		_fail("GameSession должен вернуть запрос загрузки slot_1")
		return
	if not GameSession.consume(self).is_empty():
		_fail("повторный consume должен возвращать пустой словарь")
		return
	GameSession.request_new_game(self)
	GameSession.request_main_menu(self)
	if not GameSession.consume(self).is_empty():
		_fail("request_main_menu должен сбрасывать запрос")
		return

	_cleanup()
	print("✅ test_main_menu_and_slots: все проверки пройдены")
	quit(0)
