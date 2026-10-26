class_name PrimitiveBed
extends "res://scripts/interaction/interactable.gd"

## Примитивная лежанка — стартовая точка отдыха персонажа.
## Доступна сразу со старта игры (в отличие от разрушенного дома, требующего ремонта).
## Расположена возле костра, позволяет спать и восстанавливать силы,
## снимая накопившуюся бессонницу и восстанавливая здоровье и энергию.

signal rest_started(player: Node, hours: float)

func _ready() -> void:
	super._ready()
	object_name = "Примитивная лежанка"
	prompt_action = "Отдохнуть"
	add_to_group("interactables")
	add_to_group("rest_spots")

func can_sleep() -> bool:
	return true

func _on_interacted(player_node: Node) -> void:
	if not is_instance_valid(player_node):
		return
	if player_node.get("is_resting"):
		return
	_open_sleep_dialog(player_node)

func _open_sleep_dialog(player_node: Node) -> void:
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	var parent_node: Node = hud if (hud and is_instance_valid(hud)) else get_tree().root
	var dialog: Control = preload("res://scripts/ui/sleep_dialog.gd").new()
	dialog.setup(self, player_node, "😴 Примитивная лежанка")
	dialog.confirmed.connect(func(hours: float):
		sleep(player_node, hours)
	)
	parent_node.add_child(dialog)

## Основной метод сна/отдыха (совместим с интерфейсом repairable_building).
func sleep(player_node: Node, hours: float = -1.0) -> void:
	rest(player_node, hours)

func rest(player_node: Node, hours: float = -1.0) -> void:
	if not is_instance_valid(player_node):
		return

	if hours <= 0.0:
		hours = 8.0
		var dc: Node = get_tree().root.find_child("DayNightCycle", true, false)
		if dc and "current_hour" in dc:
			var cur_h: float = float(dc.current_hour)
			hours = (6.0 - cur_h) if cur_h < 6.0 else (24.0 - cur_h + 6.0)

	rest_started.emit(player_node, hours)

	if player_node.has_method("start_rest"):
		player_node.start_rest(maxf(0.5, hours), true)
		var world: Node = get_tree().root.find_child("World", true, false)
		if world:
			const SaveManagerClass = preload("res://scripts/core/save_manager.gd")
			SaveManagerClass.save_game(world)
		return

	var day_cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
	var new_day: int = -1
	if day_cycle and day_cycle.has_method("skip_to_morning"):
		day_cycle.skip_to_morning(6.0)
		new_day = day_cycle.current_day

	if player_node.has_method("rest_in_bed"):
		player_node.rest_in_bed(new_day)

	var world: Node = get_tree().root.find_child("World", true, false)
	if world:
		const SaveManagerClass = preload("res://scripts/core/save_manager.gd")
		SaveManagerClass.save_game(world)
