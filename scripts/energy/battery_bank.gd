class_name BatteryBank
extends "res://scripts/interaction/interactable.gd"

## Аккумуляторный блок накопителей базы (Разделы 54, 57, 84 дизайн-документа)
## Накапливает избыток энергии ветряка и питает ночное освещение.
## [E] у батареи переключает источник питания сети: Сеть → Ветряк → Батарея.

const PowerGridScript = preload("res://scripts/energy/power_grid.gd")

@export var capacity: float = 100.0

@onready var status_light: OmniLight3D = $StatusLight

var _current_stored: float = 30.0

var stored_energy: float:
	get:
		return _current_stored
	set(val):
		_current_stored = val
		update_charge_display(_current_stored, capacity, 0.0)

func _ready() -> void:
	super._ready()
	add_to_group("power_batteries")
	object_name = "Батарейный накопитель"
	prompt_action = "Проверить заряд / Источник питания"
	if not status_light:
		status_light = get_node_or_null("StatusLight")

func _get_grid() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group("power_grid") if tree else null

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

func get_prompt() -> String:
	var pct: int = int((_current_stored / capacity) * 100.0) if capacity > 0 else 0
	var mode: String = "Сеть"
	var grid: Node = _get_grid()
	if grid and grid.has_method("get_source_mode_name"):
		mode = str(grid.get_source_mode_name())
	return "[E] Батарея: %d%% · Источник: %s (переключить)" % [pct, mode]

func _on_interacted(player: Node) -> void:
	var pct: float = (_current_stored / capacity) * 100.0 if capacity > 0 else 0.0
	var msg: String = "🔋 Батарейный накопитель: Заряд %.1f / %.1f кВт·ч (%.0f%%)." % [_current_stored, capacity, pct]
	if player and player.has_method("notify"):
		player.notify(msg)
	# Переключение источника питания: у батареи стоит рубильник сети.
	var grid: Node = _get_grid()
	if grid and grid.has_method("cycle_source_mode"):
		var mode: int = int(grid.cycle_source_mode())
		if player.has_method("notify"):
			player.notify("🔀 Источник питания: %s — %s" % [grid.get_source_mode_name(), _mode_hint(mode)])

func _mode_hint(mode: int) -> String:
	match mode:
		PowerGridScript.SourceMode.TURBINE:
			return "батарея не тратится, но мощности ветряка может не хватить — станки встанут."
		PowerGridScript.SourceMode.BATTERY:
			return "вся нагрузка на батарее (тратит заряд), ветряк подзаряжает её с КПД."
		_:
			return "ветряк питает базу, батарея покрывает пики и ночи."
