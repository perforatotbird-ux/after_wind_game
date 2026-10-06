class_name StreetLamp
extends "res://scripts/interaction/interactable.gd"

## Уличный фонарный столб базы (Разделы 54, 57, 84 дизайн-документа)
## Автоматически освещает двор в сумерках и ночью при наличии электропитания.

@export var power_demand: float = 0.4 # кВт
@export var is_on: bool = false

@onready var lamp_light: OmniLight3D = $LampLight
@onready var bulb_mesh: MeshInstance3D = $Post/Arm/Bulb

var _has_grid_power: bool = true

func _ready() -> void:
	super._ready()
	add_to_group("power_consumers")
	object_name = "Уличный фонарь"
	prompt_action = "Осмотреть"
	if not lamp_light:
		lamp_light = get_node_or_null("LampLight")
	if not bulb_mesh:
		bulb_mesh = get_node_or_null("Post/Arm/Bulb")
	
	_update_lamp_state()

func _process(_delta: float) -> void:
	_update_lamp_state()

func should_be_illuminated() -> bool:
	var day_cycle: Node = null
	if get_tree() and get_tree().root:
		day_cycle = get_tree().root.find_child("DayNightCycle", true, false)
	
	if day_cycle:
		if day_cycle.has_method("is_night") and day_cycle.is_night():
			return true
		if "current_hour" in day_cycle:
			var h: float = day_cycle.current_hour
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
	is_on = wants_on and _has_grid_power
	
	if lamp_light:
		lamp_light.visible = is_on
	
	if bulb_mesh and bulb_mesh.material_override:
		var mat = bulb_mesh.material_override as StandardMaterial3D
		if mat:
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
