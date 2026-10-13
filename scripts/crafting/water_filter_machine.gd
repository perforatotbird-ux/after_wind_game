extends "res://scripts/crafting/production_machine.gd"
## Два состояния очистителя: присланная исправная модель и руины на её основе.
## Стоимость восстановления, рецепты, уровни, энергосеть и сейвы — у ProductionMachine.

func _ready() -> void:
	super._ready()
	if wear:
		wear.condition_changed.connect(_on_condition_changed)
	_update_rebuild_visuals()

func _on_condition_changed(_condition: float, _maximum: float) -> void:
	_update_rebuild_visuals()

func _update_rebuild_visuals() -> void:
	super._update_rebuild_visuals()
	# Initial destruction and complete wear use the same broken-model variant.
	var intact := rebuilt and (not wear_enabled or wear == null or not wear.is_broken())
	if visual_node:
		visual_node.visible = intact
		if not intact:
			visual_node.position = _original_pos
	if ruined_visual:
		ruined_visual.visible = not intact
	var repaired_shape := get_node_or_null("SolidBody/RepairedTowerShape") as CollisionShape3D
	var ruined_shape := get_node_or_null("SolidBody/RuinedTowerShape") as CollisionShape3D
	if repaired_shape:
		repaired_shape.set_deferred("disabled", not intact)
	if ruined_shape:
		ruined_shape.set_deferred("disabled", intact)
