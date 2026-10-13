class_name Campfire
extends ProductionMachine

## Костёр — стартовый станок Главы 2 «Первый дым» (мастер-план 2.1).
## Ручной: не берёт энергию из сети, не изнашивается, не имеет уровней.
## Один слот топлива (дрова 15 с, уголь 90 с, брикеты 120 с), рецепты базовых
## блюд, сушки и кипячения. Дополнительно: сушит промокшего персонажа рядом
## (группа heat_sources) и даёт свет ночью.
##
## Наследует ProductionMachine: переиспользует производство, партии, топливные
## слоты и окно станка, добавляя независимое горение и живую модель.

## Топливо костра: вид → секунды горения одной единицы (мастер-план 2.1).
const CAMPFIRE_FUEL_TIME: Dictionary = {"wood": 15.0, "coal": 90.0, "fuel_briquette": 120.0}
## Группа источников тепла: персонаж сушится рядом с любым её узлом.
const HEAT_GROUP: String = "heat_sources"

## Свет и модель костра управляются фактическим горением, а не готовкой.
@export var fire_light: OmniLight3D
var has_burned: bool = false
var _day_cycle: Node = null
var _fire_model: Node3D

func _ready() -> void:
	machine_type = "campfire"
	machine_display_name = "Костёр"
	power_draw = 0.0
	wear_enabled = false
	has_fuel_slots = true
	fuel_slot_count = 1
	fuel_burn_times = CAMPFIRE_FUEL_TIME
	requires_rebuild = false
	shake_strength = 0.0
	super._ready()
	prompt_action = "Готовить"
	add_to_group(HEAT_GROUP)
	add_to_group("campfires")
	_fire_model = get_node_or_null("Visual/CampfireModel")
	if _fire_model: fire_light = _fire_model.fire_light
	refresh_fire_visuals(true)
	set_process(true)

## Костёр расходует топливо даже без рецепта. Готовка и огонь используют одни
## секунды, не списывая их дважды; большой delta корректно пересекает поленья.
func _process(delta: float) -> void:
	var remaining := maxf(0.0, delta)
	while remaining > 0.000001:
		if fuel_burn_left <= 0.000001 and not _light_next_fuel(): break
		var step := minf(remaining, fuel_burn_left)
		if is_machine_running and power_ok:
			step = minf(step, maxf(0.0, process_duration - process_timer))
			if step <= 0.000001:
				super._process(0.0)
				continue
			super._process(step)
		else:
			fuel_burn_left = maxf(0.0, fuel_burn_left - step)
		remaining -= step
	if fuel_burn_left <= 0.000001: _light_next_fuel()
	if is_lit(): has_burned = true
	_update_light(delta)
	set_process(true)

func _light_next_fuel() -> bool:
	var lit := super._light_next_fuel()
	if lit and fuel_burn_left > 0.0: has_burned = true
	return lit

func add_fuel_from_inventory(inv: Node, item_id: String, amount: int = -1) -> int:
	var added := super.add_fuel_from_inventory(inv, item_id, amount)
	_update_light(0.0)
	set_process(true)
	return added

func take_fuel_from_slot(slot_index: int, inv: Node) -> int:
	# Возвращаются только ещё не сгоревшие единицы; уже горящее полено догорает.
	var active_seconds := fuel_burn_left
	var taken := super.take_fuel_from_slot(slot_index, inv)
	if active_seconds > 0.0:
		fuel_burn_left = active_seconds
		active_fuel_slot = -1 if int(fuel_slots[0]["count"]) <= 0 else 0
	_update_light(0.0)
	set_process(true)
	return taken

func cancel_batch() -> bool:
	var cancelled := super.cancel_batch()
	set_process(true)
	return cancelled

func _finish_run() -> void:
	super._finish_run()
	set_process(true)

func _update_rebuild_visuals() -> void:
	super._update_rebuild_visuals()
	set_process(true)

func refresh_fire_visuals(snap: bool = true) -> void:
	if is_lit(): has_burned = true
	if _fire_model:
		_fire_model.update_fire(0.0, is_lit(), has_burned, _is_night(), snap)
	set_process(true)

func _update_light(delta: float = 0.0) -> void:
	if _fire_model:
		_fire_model.update_fire(delta, is_lit(), has_burned, _is_night())
	elif fire_light:
		fire_light.visible = is_lit()

func _is_night() -> bool:
	if not is_instance_valid(_day_cycle) and get_tree():
		_day_cycle = get_tree().get_first_node_in_group(DayNightCycle.GROUP)
	if _day_cycle and _day_cycle.has_method("is_night"):
		return bool(_day_cycle.is_night())
	return false

## Горит ли сейчас костёр (для подсказок и звука).
func is_lit() -> bool:
	return fuel_burn_left > 0.0

func get_prompt() -> String:
	if not rebuilt:
		return super.get_prompt()
	if is_lit():
		return "[E] %s (горит, топлива на %d с)" % [object_name, int(get_fuel_time_total())]
	return "[E] %s (нет огня — заложите дрова в окне станка)" % object_name

## Блюда костра засчитываются в вехи Главы 2 с обычным качеством.
func _on_outputs_produced(outputs: Dictionary) -> void:
	for item_id in outputs.keys():
		CookingProgress.register_dish(str(item_id), int(outputs[item_id]), CookingProgress.QUALITY_PLAIN)