class_name WindTurbine
extends "res://scripts/interaction/interactable.gd"

## Ветроэлектрогенератор базы (Разделы 54, 57, 84 дизайн-документа)
## Преобразует энергию ветра в электричество для освещения и зарядки аккумуляторов.

@export var base_output: float = 2.0
@export var is_operational: bool = true

@onready var rotor_node: Node3D = $Rotor
@onready var status_light: OmniLight3D = $StatusLight

var _current_rotation_speed: float = 3.0
var _weather_mgr: Node = null

func _ready() -> void:
	super._ready()
	add_to_group("power_generators")
	object_name = "Ветрогенератор"
	prompt_action = "Осмотреть"
	if not rotor_node:
		rotor_node = get_node_or_null("Rotor")
	if not status_light:
		status_light = get_node_or_null("StatusLight")

func _process(delta: float) -> void:
	if not is_operational:
		return
	
	_update_generation_parameters()
	if rotor_node:
		rotor_node.rotate_z(_current_rotation_speed * delta)

func _get_weather_manager() -> Node:
	if not is_instance_valid(_weather_mgr) and get_tree() and get_tree().root:
		_weather_mgr = get_tree().root.find_child("WeatherManager", true, false)
	return _weather_mgr

func _update_generation_parameters() -> void:
	var weather_mgr = _get_weather_manager()
	var weather_type: int = 0
	if weather_mgr and "current_weather" in weather_mgr:
		weather_type = weather_mgr.current_weather
	
	match weather_type:
		0: # SUNNY
			_current_rotation_speed = 2.2
		1: # OVERCAST
			_current_rotation_speed = 3.8
		2: # RAIN
			_current_rotation_speed = 6.2
		3: # HEAVY_RAIN
			_current_rotation_speed = 9.5
		_:
			_current_rotation_speed = 3.0

func get_current_output() -> float:
	if not is_operational:
		return 0.0
	
	var weather_mgr = _get_weather_manager()
	var weather_type: int = 0
	if weather_mgr and "current_weather" in weather_mgr:
		weather_type = weather_mgr.current_weather
	
	match weather_type:
		0: return 2.0 # Ясно (слабый бриз)
		1: return 3.5 # Пасмурно (умеренный ветер)
		2: return 5.5 # Дождь (свежий шквалистый ветер)
		3: return 8.5 # Ливень (штормовой ветер)
		_: return base_output

func _on_interacted(player: Node) -> void:
	var output: float = get_current_output()
	var msg: String = "⚡ Ветрогенератор: Выработка %.1f кВт. Ротор стабильно генерирует ток." % output
	if player and player.has_method("notify"):
		player.notify(msg)
