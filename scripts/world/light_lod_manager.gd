class_name LightLodManager
extends Node

## Оптимизация производительности динамических источников света (LOD).
## Управляет узлами OmniLight3D в группе "dynamic_lights".
## Скрывает источники света на удалении от активной камеры с гистерезисом.
## Не нарушает геймплейную логику включения/выключения через мета-флаг _lod_hidden.

@export var camera: Camera3D
@export var enable_distance: float = 24.0   ## Дистанция включения света
@export var disable_distance: float = 32.0  ## Дистанция выключения света (гистерезис)
@export var check_interval: float = 0.3     ## Интервал проверки в секундах

var _timer: float = 0.0

func _ready() -> void:
	add_to_group("light_lod_manager")
	_resolve_camera()

func _resolve_camera() -> void:
	if is_instance_valid(camera):
		return
	if get_viewport():
		camera = get_viewport().get_camera_3d()
	if not camera and get_tree():
		var cam_node = get_tree().get_first_node_in_group("cameras")
		if cam_node is Camera3D:
			camera = cam_node

func _process(delta: float) -> void:
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0
	
	if not is_instance_valid(camera):
		_resolve_camera()
	if not is_instance_valid(camera):
		return
	
	var cam_pos: Vector3 = camera.global_position
	var lights := get_tree().get_nodes_in_group("dynamic_lights")
	for node in lights:
		if not is_instance_valid(node) or not (node is Light3D):
			continue
		var light := node as Light3D
		var dist: float = cam_pos.distance_to(light.global_position)
		
		if dist > disable_distance:
			if light.visible and not light.has_meta("_lod_hidden"):
				light.set_meta("_lod_hidden", true)
				light.visible = false
		elif dist < enable_distance:
			if light.has_meta("_lod_hidden"):
				light.remove_meta("_lod_hidden")
				light.visible = true
