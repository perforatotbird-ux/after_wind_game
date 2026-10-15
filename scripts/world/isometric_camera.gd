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

@export_group("Auto Follow Rotation")
## Включено ли автоматическое вращение камеры вслед за движением персонажа.
@export var auto_rotate: bool = true
## Скорость плавного доворота камеры за игроком (рад/сек).
@export var auto_rotate_speed: float = 2.5
## Задержка (в секундах) после ручного вращения (ПКМ), перед тем как автоповорот снова включится.
@export var auto_rotate_delay: float = 0.8
## Минимальная скорость цели (м/с), при которой активируется автоповорот камеры.
@export var auto_rotate_min_speed: float = 0.3
## Порог движения относительно взгляда камеры (-1..1). При значениях выше порога
## камера доворачивается за игроком. Защищает от вращения камеры при отступлении назад (S).
@export var reverse_rotation_threshold: float = -0.3

var yaw: float = 0.0
var pitch: float = 0.832 # ~47.7 градусов (atan2(11, 10))
var current_distance: float = 14.866 # sqrt(11^2 + 10^2)

var target_yaw: float = 0.0
var target_pitch: float = 0.832
var target_distance: float = 14.866

var is_orbiting: bool = false
var _manual_orbit_timer: float = 0.0
var _last_target_pos: Vector3 = Vector3.ZERO
var _last_target_node: Node3D = null

func _ready() -> void:
	target_distance = current_distance
	target_yaw = yaw
	target_pitch = pitch
	
	if target_node:
		_last_target_node = target_node
		_last_target_pos = target_node.global_position
		_apply_camera_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_orbiting:
			is_orbiting = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_manual_orbit_timer = auto_rotate_delay

## Колесо с модификатором — зум; без него событие остаётся для смены инструмента.
func is_zoom_event(mb: InputEventMouseButton) -> bool:
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	return not zoom_requires_ctrl or mb.ctrl_pressed or mb.meta_pressed

var _player_ref: Node = null

func _unhandled_input(event: InputEvent) -> void:
	# Во время отдыха/сна камера не orbiting и не зумится.
	if get_tree().paused:
		return
	if not is_instance_valid(_player_ref) and get_tree() and get_tree().root:
		_player_ref = get_tree().root.find_child("Player", true, false)
	if _player_ref and _player_ref.get("is_resting"):
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_orbiting = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				is_orbiting = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_manual_orbit_timer = auto_rotate_delay
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
		
	if _manual_orbit_timer > 0.0:
		_manual_orbit_timer = maxf(0.0, _manual_orbit_timer - delta)
		
	_update_auto_rotation(delta)
		
	yaw = lerp_angle(yaw, target_yaw, rotation_damping * delta)
	pitch = lerpf(pitch, target_pitch, rotation_damping * delta)
	current_distance = lerpf(current_distance, target_distance, zoom_speed * delta)
	
	_apply_camera_transform(false, delta)

func _update_auto_rotation(delta: float) -> void:
	if not auto_rotate or is_orbiting or _manual_orbit_timer > 0.0:
		return
	if not is_instance_valid(target_node):
		return
		
	if target_node != _last_target_node:
		_last_target_node = target_node
		_last_target_pos = target_node.global_position
		return
		
	# 1. Вычисляем текущую горизонтальную скорость перемещения цели
	var vel_h: Vector2 = Vector2.ZERO
	if "velocity" in target_node:
		var v: Vector3 = target_node.velocity
		vel_h = Vector2(v.x, v.z)
	
	var current_pos: Vector3 = target_node.global_position
	if vel_h.length_squared() < 0.01 and delta > 0.0:
		var pos_delta: Vector3 = current_pos - _last_target_pos
		vel_h = Vector2(pos_delta.x, pos_delta.z) / delta
	_last_target_pos = current_pos
	
	var speed: float = vel_h.length()
	if speed < auto_rotate_min_speed:
		return
		
	# 2. Проверяем вектор движения относительно текущего направления камеры
	var move_dir: Vector2 = vel_h / speed
	var cam_forward_2d: Vector2 = Vector2(-sin(target_yaw), -cos(target_yaw))
	var forward_dot: float = move_dir.dot(cam_forward_2d)
	
	# Не крутим камеру в спираль при чистом отступлении назад (клавиша S)
	if forward_dot <= reverse_rotation_threshold:
		return
		
	# 3. Желаемый угол камеры позади направления движения игрока
	var desired_yaw: float = atan2(-move_dir.x, -move_dir.y)
	
	# Если у игрока есть визуальная нода с плавным разворотом тела, используем её направление
	if "visual_root" in target_node and is_instance_valid(target_node.visual_root):
		desired_yaw = target_node.visual_root.global_rotation.y
	elif target_node.has_node("Visuals"):
		var visuals: Node3D = target_node.get_node_or_null("Visuals") as Node3D
		if is_instance_valid(visuals):
			desired_yaw = visuals.global_rotation.y
			
	var angle_diff: float = abs(angle_difference(target_yaw, desired_yaw))
	if angle_diff < 0.01:
		return
		
	target_yaw = lerp_angle(target_yaw, desired_yaw, auto_rotate_speed * delta)

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
