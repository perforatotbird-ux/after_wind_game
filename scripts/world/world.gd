extends Node3D

const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const PauseMenuController = preload("res://scripts/ui/pause_menu_controller.gd")
const GameplayUIController = preload("res://scripts/ui/gameplay_ui_controller.gd")
const ContractDB = preload("res://scripts/economy/contract_db.gd")

## Интервал автосохранения в секундах реального времени (только во время игры, не в паузе и не в меню).
const AUTOSAVE_INTERVAL: float = 300.0

## Стартовое меню показывается только когда мир — главная сцена и есть окно.
## В headless-тестах (мир добавляется в root вручную) мир сразу играбелен.
@export var enable_main_menu: bool = true

var is_in_main_menu: bool = false
var _session_active: bool = false
var _autosave_timer: float = 0.0

@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $IsometricCamera
@onready var hud: CanvasLayer = $HUD
@onready var day_night_cycle: Node = $DayNightCycle
@onready var weather_manager: Node = $WeatherManager
@onready var season_manager: Node = $SeasonManager
@onready var power_grid: Node = $PowerGrid

func _ready() -> void:
	if not find_child("AudioManager", true, false):
		var am = AudioManager.new()
		am.name = "AudioManager"
		add_child(am)
	
	if player and hud and hud.has_method("bind_player"):
		hud.bind_player(player)
		if hud.has_method("show_notification"):
			hud.show_notification("«После бури» [Финал Главы 1]: Восстановите базу, станки, инструменты и ферму для завершения первого этапа!")
	
	if camera and player and "target_node" in camera:
		camera.target_node = player
	
	if day_night_cycle and hud and hud.has_method("update_time_display"):
		if not day_night_cycle.time_changed.is_connected(hud.update_time_display):
			day_night_cycle.time_changed.connect(hud.update_time_display)
		var h: int = int(day_night_cycle.current_hour)
		var m: int = int((day_night_cycle.current_hour - h) * 60.0)
		hud.update_time_display(day_night_cycle.current_day, h, m, day_night_cycle.get_time_string(), day_night_cycle.get_current_phase())
	
	if weather_manager:
		if hud and hud.has_method("update_weather_display"):
			if not weather_manager.weather_changed.is_connected(hud.update_weather_display):
				weather_manager.weather_changed.connect(hud.update_weather_display)
			hud.update_weather_display(weather_manager.current_weather, weather_manager.get_weather_name(), weather_manager.get_weather_icon())
		
		if not weather_manager.weather_changed.is_connected(_on_weather_changed):
			weather_manager.weather_changed.connect(_on_weather_changed)
		_on_weather_changed(weather_manager.current_weather, "", "")
	
	_connect_seasons()
	
	if power_grid and hud and hud.has_method("update_power_display"):
		if not power_grid.grid_updated.is_connected(_on_grid_updated):
			power_grid.grid_updated.connect(_on_grid_updated)
		call_deferred("_refresh_power_display")
	var _ws = find_child("WindSystem", true, false)
	if _ws and _ws.has_signal("wind_changed") and not _ws.wind_changed.is_connected(_on_wind_changed_refresh):
		_ws.wind_changed.connect(_on_wind_changed_refresh)
	
	_connect_interactive_stations()
	_init_session.call_deferred()

# --- Сессия: настройки, стартовое меню, загрузка слота ---

func _init_session() -> void:
	if not enable_main_menu or get_tree().current_scene != self:
		return
	if DisplayServer.get_name() == "headless":
		return
	_session_active = true
	GameSettings.load_settings()
	GameSettings.apply(get_tree())
	if hud:
		var controller = PauseMenuController.new()
		controller.name = "PauseMenuController"
		controller.setup(hud, self)
		hud.add_child(controller)
		# Клеточный рюкзак, окно станка с партиями, смена инструмента колесом.
		var gameplay_ui = GameplayUIController.new()
		gameplay_ui.name = "GameplayUIController"
		gameplay_ui.setup(hud, self, player)
		hud.add_child(gameplay_ui)

	var request: Dictionary = GameSession.consume(get_tree())
	if not request.get("skip_menu", false):
		_show_main_menu()
		return
	var slot_id: String = str(request.get("load_slot", ""))
	var loaded: bool = false
	if slot_id != "":
		loaded = SaveSlots.load_from_slot(self, slot_id)
	if not loaded:
		# Новая игра (или слот не читается): статический прогресс контрактов
		# прошлой сессии не наследуем, батарея заряжена на 100 %.
		ContractDB.reset_completed()
		if power_grid:
			power_grid.current_stored = power_grid.max_capacity
		var _bat = find_child("BatteryBank", true, false)
		if _bat:
			_bat.stored_energy = _bat.capacity
		if slot_id != "" and hud and hud.has_method("show_notification"):
			hud.show_notification("⚠️ Не удалось загрузить %s — начата новая игра" % SaveSlots.get_slot_title(slot_id))

func _show_main_menu() -> void:
	is_in_main_menu = true
	# Мир живёт (погода, сутки, звук), но игрок, камера и HUD выключены.
	for node in [player, hud, camera]:
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	if hud:
		hud.visible = false
	var menu = MainMenu.new()
	menu.name = "MainMenu"
	menu.world = self
	add_child(menu)

func _process(delta: float) -> void:
	if not _session_active or is_in_main_menu or get_tree().paused:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		SaveSlots.save_to_slot(self, SaveSlots.AUTOSAVE_ID)

# --- Подключение станций и погоды ---

## Подключает SeasonManager: календарь в HUD, погодные события и их последствия.
func _connect_seasons() -> void:
	if not season_manager:
		return
	if hud and hud.has_method("update_season_display"):
		if not season_manager.calendar_changed.is_connected(hud.update_season_display):
			season_manager.calendar_changed.connect(hud.update_season_display)
		if not season_manager.weather_event_started.is_connected(_on_season_event_started):
			season_manager.weather_event_started.connect(_on_season_event_started)
		hud.update_season_display()

## Событие началось: применяем разрушения (молния, ураган) и обновляем HUD.
func _on_season_event_started(event_id: String, _event_name: String) -> void:
	season_manager.apply_event_effects(event_id)
	if hud and hud.has_method("update_season_display"):
		hud.update_season_display()

func _connect_interactive_stations() -> void:
	if not hud:
		return
	
	# Автоматическое подключение всех производственных машин, станций, зданий и NPC к окнам HUD.
	# В игре GameplayUIController переключает machine_opened на новое окно станка.
	for child in find_children("*", "Area3D", true, false):
		if child.has_signal("machine_opened") and hud.has_method("open_machine_window"):
			if not child.machine_opened.is_connected(hud.open_machine_window):
				child.machine_opened.connect(hud.open_machine_window)
		elif child.has_signal("station_opened") and hud.has_method("open_sales_window"):
			if not child.station_opened.is_connected(hud.open_sales_window):
				child.station_opened.connect(hud.open_sales_window)
		elif child.has_signal("building_opened") and hud.has_method("open_repair_window"):
			if not child.building_opened.is_connected(hud.open_repair_window):
				child.building_opened.connect(hud.open_repair_window)
		elif child.has_signal("dialogue_opened") and hud.has_method("open_contract_window"):
			if not child.dialogue_opened.is_connected(hud.open_contract_window):
				child.dialogue_opened.connect(hud.open_contract_window)
		elif child.has_signal("board_opened") and hud.has_method("open_contract_window"):
			if not child.board_opened.is_connected(hud.open_contract_window):
				child.board_opened.connect(hud.open_contract_window)

## Мост grid_updated → HUD: добавляет к стандартным аргументам выбранный
## источник питания (Сеть / Ветряк / Батарея), чтобы он был виден в HUD.
func _on_grid_updated(stored: float, capacity: float, generation: float, consumption: float, has_power: bool) -> void:
	if hud and hud.has_method("update_power_display"):
		var mode: int = int(power_grid.get("source_mode")) if power_grid and "source_mode" in power_grid else -1
		hud.update_power_display(stored, capacity, generation, consumption, has_power, mode)

func _on_weather_changed(w_type: int, _w_name: String, _w_icon: String) -> void:
	var is_rain: bool = (w_type == 2 or w_type == 3)
	var intensity: float = 1.0 if w_type == 3 else 0.6
	if AudioManager.instance:
		AudioManager.instance.set_weather_rain(is_rain, intensity)

func _refresh_power_display() -> void:
	if power_grid and hud and hud.has_method("update_power_display"):
		_on_grid_updated(power_grid.current_stored, power_grid.max_capacity, power_grid.current_generation, power_grid.current_consumption, power_grid.has_power)

func _on_wind_changed_refresh(_speed: float, _gusting: bool) -> void:
	_refresh_power_display()
