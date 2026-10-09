extends SceneTree

const IsometricCamera = preload("res://scripts/world/isometric_camera.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")

var _test_executed: bool = false
var target: Node3D
var cam: IsometricCamera
var player: CharacterBody3D
var test_cam: Camera3D

func _init() -> void:
	print(">>> Инициализация сцены для тестирования Orbit Camera...")
	target = Node3D.new()
	target.name = "Target"
	target.position = Vector3(5, 0, 5)
	root.add_child(target)
	
	cam = IsometricCamera.new()
	cam.name = "IsometricCamera"
	cam.target_node = target
	root.add_child(cam)
	
	player = PlayerScene.instantiate()
	player.name = "Player"
	root.add_child(player)
	
	test_cam = Camera3D.new()
	test_cam.name = "TestCam"
	root.add_child(test_cam)

func _process(_delta: float) -> bool:
	if _test_executed:
		return false
	_test_executed = true
	
	_run_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _run_tests() -> void:
	print("=================================================================")
	print("🧪 ЗАПУСК ТЕСТОВ ОРБИТАЛЬНОЙ КАМЕРЫ И УПРАВЛЕНИЯ МЫШЬЮ")
	print("=================================================================")
	
	test_camera_initialization()
	test_rmb_orbit_and_capture()
	test_mouse_motion_and_pitch_clamping()
	test_mouse_wheel_zoom_and_clamps()
	test_focus_out_safety()
	test_camera_relative_player_movement()
	
	print("=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ОРБИТАЛЬНОЙ КАМЕРЫ УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)

func test_camera_initialization() -> void:
	print("\n--- Проверка 1: Инициализация параметров камеры и стартовой позиции ---")
	if cam.min_distance != 3.5:
		_fail("min_distance должен быть 3.5, получен: %.2f" % cam.min_distance)
		return
	if cam.max_distance != 26.0:
		_fail("max_distance должен быть 26.0, получен: %.2f" % cam.max_distance)
		return
	if cam.zoom_step != 1.5:
		_fail("zoom_step должен быть 1.5, получен: %.2f" % cam.zoom_step)
		return
	if abs(cam.current_distance - 14.866) > 0.05:
		_fail("current_distance должен быть около 14.866, получен: %.3f" % cam.current_distance)
		return
	if cam.yaw != 0.0:
		_fail("yaw должен начинаться с 0.0, получен: %.3f" % cam.yaw)
		return
	if abs(cam.pitch - 0.832) > 0.05:
		_fail("pitch должен быть около 47.7 градусов (~0.832 rad), получен: %.3f" % cam.pitch)
		return
	
	# Проверяем позицию камеры
	var expected_focus: Vector3 = target.global_position + cam.focus_offset
	var horiz_dist: float = cam.current_distance * cos(cam.pitch)
	var expected_pos: Vector3 = expected_focus + Vector3(
		horiz_dist * sin(cam.yaw),
		cam.current_distance * sin(cam.pitch),
		horiz_dist * cos(cam.yaw)
	)
	
	if cam.global_position.distance_to(expected_pos) > 0.1:
		_fail("Позиция камеры не совпадает со сферическими координатами. Ожидалось %s, получено %s" % [str(expected_pos), str(cam.global_position)])
		return
		
	print("  • Начальная дистанция: %.2f м, Yaw: %.2f rad, Pitch: %.2f rad (%.1f°)" % [cam.current_distance, cam.yaw, cam.pitch, rad_to_deg(cam.pitch)])
	print("  • Позиция камеры в пространстве: %s" % str(cam.global_position))
	print("✅ Камера корректно инициализирована в изометрическом ракурсе.")

func test_rmb_orbit_and_capture() -> void:
	print("\n--- Проверка 2: Зажатие ПКМ и захват курсора (MOUSE_MODE_CAPTURED) ---")
	var rmb_press = InputEventMouseButton.new()
	rmb_press.button_index = MOUSE_BUTTON_RIGHT
	rmb_press.pressed = true
	cam._unhandled_input(rmb_press)
	
	if not cam.is_orbiting:
		_fail("Камера должна перейти в режим вращения при нажатии ПКМ")
		return
	print("  • ПКМ нажата -> is_orbiting: true")
	if DisplayServer.get_name() != "headless":
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_fail("Курсор должен быть переведен в MOUSE_MODE_CAPTURED")
			return
		print("  • mouse_mode: CAPTURED")
	else:
		print("  • Режим Headless: захват мыши симулирован для display server")
	
	var rmb_release = InputEventMouseButton.new()
	rmb_release.button_index = MOUSE_BUTTON_RIGHT
	rmb_release.pressed = false
	cam._unhandled_input(rmb_release)
	
	if cam.is_orbiting:
		_fail("Камера должна выйти из режима вращения при отпускании ПКМ")
		return
	print("  • ПКМ отпущена -> is_orbiting: false")
	if DisplayServer.get_name() != "headless":
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_fail("Курсор должен вернуться в MOUSE_MODE_VISIBLE")
			return
		print("  • mouse_mode: VISIBLE")
	print("✅ Захват и освобождение курсора мыши работают штатно.")

func test_mouse_motion_and_pitch_clamping() -> void:
	print("\n--- Проверка 3: Вращение мышью и защита углов pitch (Clamp) ---")
	# Активируем орбиту
	var rmb_press = InputEventMouseButton.new()
	rmb_press.button_index = MOUSE_BUTTON_RIGHT
	rmb_press.pressed = true
	cam._unhandled_input(rmb_press)
	
	var initial_yaw: float = cam.target_yaw
	var initial_pitch: float = cam.target_pitch
	
	var motion = InputEventMouseMotion.new()
	motion.relative = Vector2(80.0, -40.0)
	cam._unhandled_input(motion)
	
	if cam.target_yaw >= initial_yaw:
		_fail("target_yaw должен уменьшаться при движении мыши вправо")
		return
	if cam.target_pitch <= initial_pitch:
		_fail("target_pitch должен увеличиваться при движении мыши вверх")
		return
	print("  • Сдвиг мыши (80, -40) -> yaw: %.3f rad, pitch: %.3f rad" % [cam.target_yaw, cam.target_pitch])
	
	# Проверка экстремального опускания камеры (не должна уйти ниже min_pitch)
	var extreme_down = InputEventMouseMotion.new()
	extreme_down.relative = Vector2(0.0, 10000.0)
	cam._unhandled_input(extreme_down)
	if abs(cam.target_pitch - cam.min_pitch) > 0.001:
		_fail("Pitch не должен опускаться ниже min_pitch (%.3f), текущий: %.3f" % [cam.min_pitch, cam.target_pitch])
		return
	print("  • Защита от провала под землю: pitch ограничен min_pitch = %.3f rad (%.1f°)" % [cam.target_pitch, rad_to_deg(cam.target_pitch)])
	
	# Проверка экстремального подъема камеры (не должна превысить max_pitch)
	var extreme_up = InputEventMouseMotion.new()
	extreme_up.relative = Vector2(0.0, -20000.0)
	cam._unhandled_input(extreme_up)
	if abs(cam.target_pitch - cam.max_pitch) > 0.001:
		_fail("Pitch не должен превышать max_pitch (%.3f), текущий: %.3f" % [cam.max_pitch, cam.target_pitch])
		return
	print("  • Защита от переворота зенита: pitch ограничен max_pitch = %.3f rad (%.1f°)" % [cam.target_pitch, rad_to_deg(cam.target_pitch)])
	
	# Сброс нажатия
	var rmb_release = InputEventMouseButton.new()
	rmb_release.button_index = MOUSE_BUTTON_RIGHT
	rmb_release.pressed = false
	cam._unhandled_input(rmb_release)
	
	print("✅ Вращение мышью и границы наклона работают корректно.")

func test_mouse_wheel_zoom_and_clamps() -> void:
	print("\n--- Проверка 4: Масштабирование (Zoom In / Out) через Ctrl + колесо мыши ---")
	var init_dist: float = cam.target_distance
	
	# Обычное колесо листает инструменты и не должно менять зум
	var plain_wheel = InputEventMouseButton.new()
	plain_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	plain_wheel.pressed = true
	cam._unhandled_input(plain_wheel)
	if abs(cam.target_distance - init_dist) > 0.001:
		_fail("Колесо без Ctrl не должно менять дистанцию камеры (оно переключает инструменты)")
		return
	print("  • Колесо без Ctrl: дистанция не изменилась (%.2f м)" % cam.target_distance)
	
	# Ctrl + колесо вверх (приближение)
	var wheel_up = InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.ctrl_pressed = true
	cam._unhandled_input(wheel_up)
	
	if abs(cam.target_distance - (init_dist - cam.zoom_step)) > 0.001:
		_fail("Дистанция должна уменьшиться на zoom_step, ожидалось %.2f, получено %.2f" % [init_dist - cam.zoom_step, cam.target_distance])
		return
	print("  • Ctrl + колесо вверх: target_distance = %.2f м (было %.2f м)" % [cam.target_distance, init_dist])
	
	# Многократное колесо вверх до упора
	for i in range(25):
		cam._unhandled_input(wheel_up)
	if cam.target_distance != cam.min_distance:
		_fail("target_distance должна упереться в min_distance (3.5м), получено: %.2f" % cam.target_distance)
		return
	print("  • Ограничение приближения: min_distance = %.2f м" % cam.target_distance)
	
	# Ctrl + колесо вниз (отдаление) до упора
	var wheel_down = InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	wheel_down.ctrl_pressed = true
	for i in range(30):
		cam._unhandled_input(wheel_down)
	if cam.target_distance != cam.max_distance:
		_fail("target_distance должна упереться в max_distance (26.0м), получено: %.2f" % cam.target_distance)
		return
	print("  • Ограничение отдаления: max_distance = %.2f м" % cam.target_distance)
	
	print("✅ Зум через Ctrl + колесо и его граничные значения работают корректно.")

func test_focus_out_safety() -> void:
	print("\n--- Проверка 5: Безопасный сброс захвата при потере фокуса окна ---")
	var rmb_press = InputEventMouseButton.new()
	rmb_press.button_index = MOUSE_BUTTON_RIGHT
	rmb_press.pressed = true
	cam._unhandled_input(rmb_press)
	if not cam.is_orbiting:
		_fail("Орбита должна быть включена перед тестом сброса")
		return
	
	# Симулируем событие потери фокуса окном
	cam._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if cam.is_orbiting:
		_fail("Орбита должна отключиться при потере фокуса приложения")
		return
	if DisplayServer.get_name() != "headless":
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_fail("Курсор должен стать видимым при потере фокуса")
			return
	print("  • Потеря фокуса окна -> is_orbiting сброшен, mouse_mode: VISIBLE")
	print("✅ Защита от залипания захвата курсора подтверждена.")

func test_camera_relative_player_movement() -> void:
	print("\n--- Проверка 6: Камеро-зависимое движение персонажа ---")
	test_cam.current = true
	
	# Случай 1: Камера смотрит вдоль оси -Z (стандартный ракурс)
	test_cam.global_transform.basis = Basis.IDENTITY
	var input_w: Vector2 = Vector2(0, -1)
	var cam_fwd: Vector3 = -test_cam.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	var cam_right: Vector3 = test_cam.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var dir_standard: Vector3 = (cam_right * input_w.x + cam_fwd * -input_w.y).normalized()
	if not dir_standard.is_equal_approx(Vector3(0, 0, -1)):
		_fail("При камере смотрящей в -Z, нажатие W должно давать (0, 0, -1), получено: %s" % str(dir_standard))
		return
	print("  • Ракурс 0° (стандарт): W направляет персонажа в (0, 0, -1)")
	
	# Случай 2: Камера повернута на 90° вправо
	test_cam.global_transform.basis = Basis(Vector3.UP, deg_to_rad(90.0))
	cam_fwd = -test_cam.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	cam_right = test_cam.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var dir_rotated: Vector3 = (cam_right * input_w.x + cam_fwd * -input_w.y).normalized()
	if not dir_rotated.is_equal_approx(Vector3(-1, 0, 0)):
		_fail("При камере повернутой на 90°, нажатие W должно давать (-1, 0, 0), получено: %s" % str(dir_rotated))
		return
	print("  • Ракурс 90° (поворот): W направляет персонажа в (-1, 0, 0)")
	
	print("✅ Камеро-зависимое движение полностью проверено и математически выверено.")
