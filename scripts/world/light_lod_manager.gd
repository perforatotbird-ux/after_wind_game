class_name LightLodManager
extends Node

## Оптимизация производительности динамических источников света (LOD).
## Управляет узлами OmniLight3D в группе "dynamic_lights".
## Скрывает источники света на удалении от активной камеры с гистерезисом.
## Не нарушает геймплейную логику включения/выключения: игровой код задаёт
## желаемое состояние через set_desired_visible(), а менеджер решает, показывать
## ли свет на самом деле (с учётом расстояния до камеры).

@export var camera: Camera3D
@export var enable_distance: float = 24.0   ## Дистанция включения света
@export var disable_distance: float = 32.0  ## Дистанция выключения света (гистерезис)
@export var check_interval: float = 0.3     ## Интервал проверки в секундах

var _timer: float = 0.0

## Ключ мета-данных с пожеланием игровой логики по видимости света.
const DESIRED_META: StringName = &"_gameplay_visible"
## Ключ мета-данных: свет скрыт менеджером LOD.
const LOD_META: StringName = &"_lod_hidden"

## Пожелание игровой логики по видимости света. Менеджер LOD не даёт
## «включить» свет, который игровой код держит выключенным, и наоборот.
static func set_desired_visible(light: Light3D, desired: bool) -> void:
	if light == null or not is_instance_valid(light):
		return
	light.set_meta(DESIRED_META, desired)
	light.visible = desired and not light.has_meta(LOD_META)

## Желаемое игрой состояние света (по умолчанию — свет включён).
static func get_desired_visible(light: Light3D) -> bool:
	if light == null or not is_instance_valid(light):
		return false
	return bool(light.get_meta(DESIRED_META, true))

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
			if not light.has_meta(LOD_META):
				# Запоминаем текущее состояние — его вернём, когда свет снова
				# попадёт в кадр (если игровой код не задал его явно).
				if not light.has_meta(DESIRED_META):
					light.set_meta(DESIRED_META, light.visible)
				light.set_meta(LOD_META, true)
				light.visible = false
		elif dist < enable_distance:
			if light.has_meta(LOD_META):
				light.remove_meta(LOD_META)
				# Возвращаем именно то состояние, которое просит игровой код,
				# а не «включаем свет насильно».
				light.visible = get_desired_visible(light)
