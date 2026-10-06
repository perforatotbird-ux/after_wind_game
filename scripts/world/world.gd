extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $IsometricCamera
@onready var hud: CanvasLayer = $HUD
@onready var day_night_cycle: Node = $DayNightCycle

func _ready() -> void:
	if player and hud and hud.has_method("bind_player"):
		hud.bind_player(player)
		if hud.has_method("show_notification"):
			hud.show_notification("«После бури» [Этап 6 — Водный контур и фильтрация]: Очищайте воду в фильтре, следите за шкалой жажды и пейте воду!")
	
	if camera and player and "target_node" in camera:
		camera.target_node = player
	
	if day_night_cycle and hud and hud.has_method("update_time_display"):
		day_night_cycle.time_changed.connect(hud.update_time_display)
		var h: int = int(day_night_cycle.current_hour)
		var m: int = int((day_night_cycle.current_hour - h) * 60.0)
		hud.update_time_display(day_night_cycle.current_day, h, m, day_night_cycle.get_time_string(), day_night_cycle.get_current_phase())
	
	_connect_interactive_stations()

func _connect_interactive_stations() -> void:
	if not hud:
		return
	
	# Автоматическое подключение всех производственных машин, станций и восстанавливаемых зданий к окнам HUD
	for child in find_children("*", "Area3D", true, false):
		if child.has_signal("machine_opened") and hud.has_method("open_machine_window"):
			child.machine_opened.connect(hud.open_machine_window)
		elif child.has_signal("station_opened") and hud.has_method("open_sales_window"):
			child.station_opened.connect(hud.open_sales_window)
		elif child.has_signal("building_opened") and hud.has_method("open_repair_window"):
			child.building_opened.connect(hud.open_repair_window)
