class_name Campfire
extends ProductionMachine

## Костёр — стартовый станок Главы 2 «Первый дым» (мастер-план 2.1).
## Ручной: не берёт энергию из сети, не изнашивается, не имеет уровней.
## Один слот топлива (дрова 15 с, уголь 90 с, брикеты 120 с), рецепты базовых
## блюд, сушки и кипячения. Дополнительно: сушит промокшего персонажа рядом
## (группа heat_sources) и даёт свет ночью.
##
## Наследует ProductionMachine: переиспользует производство, партии, топливные
## слоты и окно станка, добавляя ручной режим и два эффекта.

## Топливо костра: вид → секунды горения одной единицы (мастер-план 2.1).
const CAMPFIRE_FUEL_TIME: Dictionary = {"wood": 15.0, "coal": 90.0, "fuel_briquette": 120.0}
## Группа источников тепла: персонаж сушится рядом с любым её узлом.
const HEAT_GROUP: String = "heat_sources"

## Свет костра (гасится днём, разгорается ночью).
@export var fire_light: OmniLight3D
## Частицы пламени.
@export var flame_particles: CPUParticles3D
## Яркость света ночью / днём.
@export var light_energy_night: float = 2.6
@export var light_energy_day: float = 0.5

var _day_cycle: Node = null
var _light_initialised: bool = false

func _ready() -> void:
	# Конфигурация ручного станка — до super._ready(): базовый класс создаёт
	# топливные слоты и решает, вставать ли в энергосеть, по этим полям.
	machine_type = "campfire"
	machine_display_name = "Костёр"
	prompt_action = "Готовить"
	power_draw = 0.0
	wear_enabled = false
	has_fuel_slots = true
	fuel_slot_count = 1
	fuel_burn_times = CAMPFIRE_FUEL_TIME
	requires_rebuild = false
	super._ready()
	add_to_group(HEAT_GROUP)
	add_to_group("campfires")
	if fire_light:
		fire_light.light_energy = light_energy_day
		_light_initialised = true
	set_process(true)

## Производство живёт в базовом классе; здесь только свет костра, который нужен
## всегда (ночью освещает базу и сушит персонажа), даже когда цикл не идёт.
func _process(delta: float) -> void:
	if is_machine_running:
		super._process(delta)
	_update_light()
	if _light_initialised:
		set_process(true)

## Свет костра следует за временем суток и ярче, когда в топливном слоте горит огонь.
func _update_light() -> void:
	if not fire_light:
		return
	var burning: bool = is_lit()
	var night: bool = _is_night()
	var target: float = light_energy_day
	if burning:
		target = light_energy_night if night else light_energy_day * 1.6
	fire_light.light_energy = lerpf(fire_light.light_energy, target, 0.12)
	fire_light.visible = burning or night
	if flame_particles:
		flame_particles.emitting = burning

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