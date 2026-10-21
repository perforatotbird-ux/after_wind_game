class_name FurnaceLight
extends Node

## Управляет OmniLight3D тёплого огненного свечения работающей печи / плавильни.
## Реагирует на сигнал machine_running_changed станка и создаёт атмосферное мерцание.

@export var light_node: OmniLight3D
@export var base_energy: float = 1.4
@export var idle_energy: float = 0.0
@export var flicker_speed: float = 7.5
@export var flicker_amp: float = 0.12

var _running: bool = false
var _time: float = 0.0
var _current_energy: float = 0.0

func _ready() -> void:
	if not light_node and get_parent():
		light_node = get_parent().get_node_or_null("FurnaceLight")
	if not light_node and get_parent():
		light_node = OmniLight3D.new()
		light_node.name = "FurnaceLight"
		light_node.light_color = Color(1.0, 0.42, 0.12)
		light_node.omni_range = 4.5
		light_node.omni_attenuation = 1.6
		light_node.shadow_enabled = false
		LightLodManager.set_desired_visible(light_node, false)
		light_node.position = Vector3(0.0, 0.6, 0.4)
		get_parent().add_child.call_deferred(light_node)
	
	if light_node:
		light_node.add_to_group("dynamic_lights")
	
	var machine: Node = get_parent()
	if machine:
		if machine.has_signal("machine_running_changed") and not machine.machine_running_changed.is_connected(_on_running_changed):
			machine.machine_running_changed.connect(_on_running_changed)
		if "is_machine_running" in machine:
			_running = bool(machine.is_machine_running)
			_current_energy = base_energy if _running else idle_energy

func _process(delta: float) -> void:
	_time += delta
	var target: float = base_energy if _running else idle_energy
	if abs(_current_energy - target) > 0.001:
		_current_energy = move_toward(_current_energy, target, delta * 3.0)
	
	if light_node and is_instance_valid(light_node):
		if not light_node.is_in_group("dynamic_lights"):
			light_node.add_to_group("dynamic_lights")
		if _current_energy > 0.01:
			var flicker: float = 1.0 + sin(_time * flicker_speed) * flicker_amp + sin(_time * 13.0) * (flicker_amp * 0.5)
			light_node.light_energy = _current_energy * flicker
			LightLodManager.set_desired_visible(light_node, true)
		else:
			light_node.light_energy = 0.0
			LightLodManager.set_desired_visible(light_node, false)

func _on_running_changed(running: bool) -> void:
	_running = running
