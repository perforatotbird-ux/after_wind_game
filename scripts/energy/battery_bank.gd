class_name BatteryBank
extends "res://scripts/interaction/interactable.gd"

## Аккумуляторный блок накопителей базы (Разделы 54, 57, 84 дизайн-документа)
## Накапливает избыток энергии ветряка и питает ночное освещение.

@export var capacity: float = 100.0

@onready var status_light: OmniLight3D = $StatusLight

var _current_stored: float = 30.0

func _ready() -> void:
	super._ready()
	add_to_group("power_batteries")
	object_name = "Батарейный накопитель"
	prompt_action = "Проверить заряд"
	if not status_light:
		status_light = get_node_or_null("StatusLight")

func update_charge_display(stored: float, cap: float, _net: float) -> void:
	_current_stored = stored
	capacity = cap
	if not status_light:
		return
	
	var pct: float = (stored / cap) * 100.0 if cap > 0 else 0.0
	if pct >= 50.0:
		status_light.light_color = Color(0.2, 0.9, 0.35, 1) # Зеленый
		status_light.light_energy = 1.0
	elif pct >= 20.0:
		status_light.light_color = Color(0.95, 0.85, 0.2, 1) # Желтый
		status_light.light_energy = 0.8
	else:
		status_light.light_color = Color(0.95, 0.25, 0.25, 1) # Красный
		status_light.light_energy = 0.6

func _on_interacted(player: Node) -> void:
	var pct: float = (_current_stored / capacity) * 100.0 if capacity > 0 else 0.0
	var msg: String = "🔋 Батарейный накопитель: Заряд %.1f / %.1f кВт·ч (%.0f%%)." % [_current_stored, capacity, pct]
	if player and player.has_method("notify"):
		player.notify(msg)
