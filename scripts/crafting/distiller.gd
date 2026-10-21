class_name Distiller
extends ProductionMachine

## Дистиллятор для крепких напитков (самогон, спирт, настойки).
## Наследует ProductionMachine: окно станка с партиями, рецепты, топливный слот,
## износ и сохранение состояния.

const DISTILLER_FUEL_TIME: Dictionary = {"wood": 15.0, "coal": 90.0, "fuel_briquette": 120.0}

@export var fire_light: OmniLight3D

func _ready() -> void:
	machine_type = "distiller"
	machine_display_name = "Самогонный аппарат"
	power_draw = 0.0
	wear_enabled = true
	wear_per_cycle = 0.3
	has_fuel_slots = true
	fuel_slot_count = 1
	fuel_burn_times = DISTILLER_FUEL_TIME
	requires_rebuild = false
	shake_strength = 0.3
	super._ready()
	prompt_action = "Дистилляция"
	add_to_group("distillers")
	add_to_group("dynamic_lights")
	_update_fire_light()

func _process(delta: float) -> void:
	super._process(delta)
	_update_fire_light()

func _update_fire_light() -> void:
	if fire_light and is_instance_valid(fire_light):
		var lit: bool = is_machine_running and fuel_burn_left > 0.0
		LightLodManager.set_desired_visible(fire_light, lit)
		if lit:
			# Мягкое мерцание топки перегонного куба
			var t: float = Time.get_ticks_msec() / 1000.0
			fire_light.light_energy = 1.2 + sin(t * 8.0) * 0.15
