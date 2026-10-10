class_name StreetLamp
extends "res://scripts/interaction/interactable.gd"

## Уличный фонарный столб базы (Разделы 54, 57, 84 дизайн-документа)
## Автоматически освещает двор в сумерках и ночью при наличии электропитания.

@export var power_demand: float = 0.4 # кВт
@export var is_on: bool = false

@onready var lamp_light: OmniLight3D = $LampLight
@onready var bulb_mesh: MeshInstance3D = $Post/Arm/Bulb

var _has_grid_power: bool = true
var _day_cycle: Node = null
var _check_timer: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group("power_consumers")
	object_name = "Уличный фонарь"
	prompt_action = "Осмотреть"
	if not lamp_light:
		lamp_light = get_node_or_null("LampLight")
	if not bulb_mesh:
		bulb_mesh = get_node_or_null("Post/Arm/Bulb")
	
	_resolve_day_cycle()
	_update_lamp_state()

func _resolve_day_cycle() -> void:
	if is_instance_valid(_day_cycle):
		return
	if get_tree():
		_day_cycle = get_tree().get_first_node_in_group("day_night_cycle")
		if not _day_cycle and get_tree().root:
			_day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	if is_instance_valid(_day_cycle) and _day_cycle.has_signal("phase_changed"):
		if not _day_cycle.phase_changed.is_connected(_on_day_phase_changed):
			_day_cycle.phase_changed.connect(_on_day_phase_changed)

func _on_day_phase_changed(_new_phase: String) -> void:
	_update_lamp_state()

func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= 1.0:
		_check_timer = 0.0
		if not is_instance_valid(_day_cycle):
			_resolve_day_cycle()
		_update_lamp_state()

func should_be_illuminated() -> bool:
	if not is_instance_valid(_day_cycle):
		_resolve_day_cycle()
	
	if _day_cycle:
		if _day_cycle.has_method("is_night") and _day_cycle.is_night():
			return true
		if "current_hour" in _day_cycle:
			var h: float = _day_cycle.current_hour
			if h >= 18.0 or h < 6.0:
				return true
	return false

func get_power_demand() -> float:
	return power_demand if should_be_illuminated() else 0.0

func set_powered(powered: bool) -> void:
	_has_grid_power = powered
	_update_lamp_state()

func _update_lamp_state() -> void:
	var wants_on: bool = should_be_illuminated()
	var new_is_on: bool = wants_on and _has_grid_power
	if new_is_on == is_on and lamp_light and lamp_light.visible == is_on:
		return
	is_on = new_is_on
	
	if lamp_light:
		lamp_light.visible = is_on
	
	if bulb_mesh and bulb_mesh.material_override:
		var mat = bulb_mesh.material_override as StandardMaterial3D
		if mat and mat.emission_enabled != is_on:
			mat.emission_enabled = is_on

func _on_interacted(player: Node) -> void:
	var msg: String = ""
	if is_on:
		msg = "🏮 Уличный фонарь: Горит ярким теплым светом (+%.1f кВт нагрузки). Двор освещен!" % power_demand
	elif not _has_grid_power and should_be_illuminated():
		msg = "🏮 Уличный фонарь: Обесточен! Аккумуляторы разряжены или нет выработки."
	else:
		msg = "🏮 Уличный фонарь: В режиме ожидания (автоматически зажигается в сумерках)."
	
	if player and player.has_method("notify"):
		player.notify(msg)
