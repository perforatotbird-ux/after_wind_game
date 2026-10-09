class_name IsometricCamera
extends Camera3D

@export var target_node: Node3D
@export var focus_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
@export var follow_speed: float = 8.0
@export var follow_offset: Vector3 = Vector3(0.0, 11.0, 10.0)

@export_group("Orbit & Zoom")
@export var min_distance: float = 3.5
@export var max_distance: float = 26.0
@export var zoom_step: float = 1.5
@export var zoom_speed: float = 8.0
@export var min_pitch: float = deg_to_rad(12.0)
@export var max_pitch: float = deg_to_rad(80.0)
@export var mouse_sensitivity: float = 0.005
@export var rotation_damping: float = 16.0
## Зум только с зажатым Ctrl (Cmd на macOS): обычное колесо листает инструменты
## на поясе (scripts/ui/gameplay_ui_controller.gd).
@export var zoom_requires_ctrl: bool = true

var yaw: float = 0.0
var pitch: float = 0.832 # ~47.7 градусов (atan2(11, 10))
var current_distance: float = 14.866 # sqrt(11^2 + 10^2)

var target_yaw: float = 0.0
var target_pitch: float = 0.832
var target_distance: float = 14.866

var is_orbiting: bool = false

func _ready() -> void:
	target_distance = current_distance
	target_yaw = yaw
	target_pitch = pitch
	
	if target_node:
		_apply_camera_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_orbiting:
			is_orbiting = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Колесо с модификатором — зум; без него событие остаётся для смены инструмента.
func is_zoom_event(mb: InputEventMouseButton) -> bool:
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	return not zoom_requires_ctrl or mb.ctrl_pressed or mb.meta_pressed

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_orbiting = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				is_orbiting = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and is_zoom_event(mb):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_distance = clampf(target_distance - zoom_step, min_distance, max_distance)
			else:
				target_distance = clampf(target_distance + zoom_step, min_distance, max_distance)
			if is_inside_tree() and get_viewport():
				get_viewport().set_input_as_handled()
			
	elif event is InputEventMouseMotion and is_orbiting:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		target_yaw -= mm.relative.x * mouse_sensitivity
		target_pitch = clampf(target_pitch - mm.relative.y * mouse_sensitivity, min_pitch, max_pitch)

func _process(delta: float) -> void:
	if not target_node:
		return
		
	yaw = lerp_angle(yaw, target_yaw, rotation_damping * delta)
	pitch = lerpf(pitch, target_pitch, rotation_damping * delta)
	current_distance = lerpf(current_distance, target_distance, zoom_speed * delta)
	
	_apply_camera_transform(false, delta)

func _apply_camera_transform(instant: bool = false, delta: float = 0.0) -> void:
	if not target_node:
		return
		
	var focus_point: Vector3 = target_node.global_position + focus_offset
	var horiz_dist: float = current_distance * cos(pitch)
	var offset: Vector3 = Vector3(
		horiz_dist * sin(yaw),
		current_distance * sin(pitch),
		horiz_dist * cos(yaw)
	)
	var desired_pos: Vector3 = focus_point + offset
	
	if instant:
		global_position = desired_pos
	else:
		global_position = global_position.lerp(desired_pos, follow_speed * delta)
		
	look_at(focus_point, Vector3.UP)
