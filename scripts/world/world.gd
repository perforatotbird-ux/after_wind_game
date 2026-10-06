extends Node3D

const AudioManager = preload("res://scripts/audio/audio_manager.gd")

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
		day_night_cycle.time_changed.connect(hud.update_time_display)
		var h: int = int(day_night_cycle.current_hour)
		var m: int = int((day_night_cycle.current_hour - h) * 60.0)
		hud.update_time_display(day_night_cycle.current_day, h, m, day_night_cycle.get_time_string(), day_night_cycle.get_current_phase())
	
	if weather_manager:
		if hud and hud.has_method("update_weather_display"):
			weather_manager.weather_changed.connect(hud.update_weather_display)
			hud.update_weather_display(weather_manager.current_weather, weather_manager.get_weather_name(), weather_manager.get_weather_icon())
		
		var rain_callback = func(w_type, _w_name, _w_icon):
			var is_rain: bool = (w_type == 2 or w_type == 3)
			var intensity: float = 1.0 if w_type == 3 else 0.6
			if AudioManager.instance:
				AudioManager.instance.set_weather_rain(is_rain, intensity)
		weather_manager.weather_changed.connect(rain_callback)
		rain_callback.call(weather_manager.current_weather, "", "")
	
	if power_grid and hud and hud.has_method("update_power_display"):
		power_grid.grid_updated.connect(hud.update_power_display)
		hud.update_power_display(power_grid.current_stored, power_grid.max_capacity, power_grid.current_generation, power_grid.current_consumption, power_grid.has_power)
	
	_connect_interactive_stations()

func _connect_interactive_stations() -> void:
	if not hud:
		return
	
	# Автоматическое подключение всех производственных машин, станций, зданий и NPC к окнам HUD
	for child in find_children("*", "Area3D", true, false):
		if child.has_signal("machine_opened") and hud.has_method("open_machine_window"):
			child.machine_opened.connect(hud.open_machine_window)
		elif child.has_signal("station_opened") and hud.has_method("open_sales_window"):
			child.station_opened.connect(hud.open_sales_window)
		elif child.has_signal("building_opened") and hud.has_method("open_repair_window"):
			child.building_opened.connect(hud.open_repair_window)
		elif child.has_signal("dialogue_opened") and hud.has_method("open_contract_window"):
			child.dialogue_opened.connect(hud.open_contract_window)
		elif child.has_signal("board_opened") and hud.has_method("open_contract_window"):
			child.board_opened.connect(hud.open_contract_window)
