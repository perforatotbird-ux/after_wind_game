extends Node3D

const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const GameSettings = preload("res://scripts/core/game_settings.gd")
const GameSession = preload("res://scripts/core/game_session.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const PauseMenuController = preload("res://scripts/ui/pause_menu_controller.gd")

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
	
	if power_grid and hud and hud.has_method("update_power_display"):
		if not power_grid.grid_updated.is_connected(hud.update_power_display):
			power_grid.grid_updated.connect(hud.update_power_display)
		hud.update_power_display(power_grid.current_stored, power_grid.max_capacity, power_grid.current_generation, power_grid.current_consumption, power_grid.has_power)
	
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

	var request: Dictionary = GameSession.consume(get_tree())
	if not request.get("skip_menu", false):
		_show_main_menu()
		return
	var slot_id: String = str(request.get("load_slot", ""))
	if slot_id != "" and not SaveSlots.load_from_slot(self, slot_id):
		if hud and hud.has_method("show_notification"):
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

func _connect_interactive_stations() -> void:
	if not hud:
		return
	
	# Автоматическое подключение всех производственных машин, станций, зданий и NPC к окнам HUD
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

func _on_weather_changed(w_type: int, _w_name: String, _w_icon: String) -> void:
	var is_rain: bool = (w_type == 2 or w_type == 3)
	var intensity: float = 1.0 if w_type == 3 else 0.6
	if AudioManager.instance:
		AudioManager.instance.set_weather_rain(is_rain, intensity)
