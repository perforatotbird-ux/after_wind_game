extends SceneTree

## Вид от первого лица (V): переключение, FOV, скрытие тела, прицел,
## mouse-look без зажатых кнопок, границы наклона, игнор орбиты/зума,
## возврат в изометрию и поворот корпуса за взглядом камеры.
## Прицел вокселей по центру при захваченной мыши проверяется код-ревью
## (в headless mouse-aim отключён на стороне VoxelDeposit).

const IsometricCamera = preload("res://scripts/world/isometric_camera.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const HudScene = preload("res://scenes/ui/hud.tscn")

var _test_executed: bool = false
var _stage: int = 0
var _stage_frames: int = 0
var cam: IsometricCamera
var player: CharacterBody3D

func _init() -> void:
	print(">>> Инициализация сцены для тестирования вида от первого лица...")
	# Пол: без него игрок с гравитацией падает и позы уплывают.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	cam = IsometricCamera.new()
	cam.name = "IsometricCamera"
	cam.fov = 56.0 # как узел камеры в world.tscn
	root.add_child(cam)

	player = PlayerScene.instantiate()
	player.name = "Player"
	root.add_child(player)
	cam.target_node = player
	cam.current = true

func _process(_delta: float) -> bool:
	if _stage == 0:
		if _test_executed:
			return false
		_test_executed = true
		_run_tests()
		_stage = 1
		_stage_frames = 0
		return false
	# Стадия 1: поза мотыги — ждём приземления и работы модификатора хвата.
	_stage_frames += 1
	if _stage_frames == 1:
		player.visual_root.rotation.y = 0.0 # после проверки стрейфа корпус смотрит вбок
		var hoe: Node3D = player.equipped_tool_nodes.get("shovel")
		if hoe:
			hoe.visible = true
		return false
	if _stage_frames < 12:
		return false
	_run_hoe_tests()
	return true

func _fail(reason: String) -> void:
	push_error("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	print("❌ ТЕСТ ПРОВАЛЕН: " + reason)
	quit(1)

func _press_toggle_view() -> void:
	var event := InputEventAction.new()
	event.action = "toggle_view"
	event.pressed = true
	player._unhandled_input(event)

func _run_tests() -> void:
	print("=================================================================")
	print("🧪 ЗАПУСК ТЕСТОВ ВИДА ОТ ПЕРВОГО ЛИЦА (V)")
	print("=================================================================")

	test_action_exists()
	test_toggle_on()
	test_fp_camera_transform()
	test_mouse_look_without_buttons()
	test_pitch_clamp()
	test_orbit_and_zoom_ignored()
	test_body_follows_camera()
	test_toggle_off_restores_iso()
	test_crosshair_ui()
	test_grips_unified()
	# Проверка позы мотыги идёт отдельной стадией (нужны кадры физики и модификатора).

func _finish() -> void:
	print("=================================================================")
	print("🎉 ВСЕ ТЕСТЫ ВИДА ОТ ПЕРВОГО ЛИЦА УСПЕШНО ПРОЙДЕНЫ! (CODE 0)")
	print("=================================================================")
	quit(0)

## Топор и кирка держатся одинаково: голова инструмента в одну сторону,
## лезвие в одну сторону (единый хват в сокете ToolSocket.R).
func test_grips_unified() -> void:
	print("\n--- Проверка 10: единый хват топора и кирки ---")
	var axe: Node3D = player.equipped_tool_nodes.get("axe")
	var pickaxe: Node3D = player.equipped_tool_nodes.get("pickaxe")
	if axe == null or pickaxe == null:
		_fail("В equipped_tool_nodes должны быть axe и pickaxe")
		return
	# Меши смоделированы зеркально: у кирки голова на +Y, у топора на -Y
	# (поэтому в INHAND_GRIP у топора есть разворот на 180° вокруг X).
	# Единый хват = направления ГОЛОВ и лезвий совпадают.
	var axe_head: Vector3 = axe.transform.basis * Vector3(0.0, -1.0, 0.0)
	var pick_head: Vector3 = pickaxe.transform.basis * Vector3(0.0, 1.0, 0.0)
	var head_dot: float = axe_head.dot(pick_head)
	if head_dot < 0.999:
		_fail("Головы топора и кирки должны смотреть в одну сторону (dot=%.4f)" % head_dot)
		return
	var blade_dot: float = axe.transform.basis.x.dot(pickaxe.transform.basis.x)
	if blade_dot < 0.999:
		_fail("Оси лезвия топора и кирки должны совпадать (dot=%.4f)" % blade_dot)
		return
	# Наклон к костяшкам: голова отклонена от вертикали сокета на ~35°.
	var tilt_deg: float = rad_to_deg(acos(clampf(pickaxe.transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
	if absf(tilt_deg - player.TOOL_KNUCKLE_TILT_DEG) > 1.0:
		_fail("Наклон лезвий к костяшкам должен быть %.0f°, получено %.1f°" % [player.TOOL_KNUCKLE_TILT_DEG, tilt_deg])
		return
	print("  • Оси совпадают, наклон %.1f°" % tilt_deg)
	print("✅ Топор и кирка держатся единообразно.")

## Мотыга в покое: кисти на черенке, голова впереди-слева у земли,
## не выше уровня глаз (не пересекает лицо в виде от первого лица).
func _run_hoe_tests() -> void:
	print("\n--- Проверка 11: поза мотыги в покое ---")
	var hoe: Node3D = player.equipped_tool_nodes.get("shovel")
	if hoe == null:
		_fail("В equipped_tool_nodes должна быть мотыга (shovel)")
		return
	if not hoe.visible:
		_fail("Мотыга должна остаться видимой в тесте")
		return
	if player.hoe_grip.grip_error > 0.03:
		_fail("Кисти должны лежать на черенке (grip_error=%.4f)" % player.hoe_grip.grip_error)
		return
	var head: Vector3 = hoe.global_transform * Vector3(0, 1.42, 0)
	if head.y < 0.25 or head.y > 1.35:
		_fail("Голова мотыги в покое должна быть у земли, но не в лице (y=%.2f)" % head.y)
		return
	if head.z > -0.3:
		_fail("Голова мотыги должна быть впереди персонажа (z=%.2f)" % head.z)
		return
	var grip: Vector3 = hoe.global_transform.origin
	if grip.y < 0.8 or grip.y > 1.35:
		_fail("Хват мотыги должен быть на высоте пояса-груди (y=%.2f)" % grip.y)
		return
	print("  • Хват: %s, голова: %s, grip_error=%.4f" % [str(grip), str(head), player.hoe_grip.grip_error])
	print("✅ Поза мотыги в покое выверена.")
	_finish()

func test_action_exists() -> void:
	print("\n--- Проверка 1: действие toggle_view (V) в InputMap ---")
	var events: Array = InputMap.action_get_events("toggle_view")
	if events.is_empty():
		_fail("В InputMap нет действия toggle_view")
		return
	var has_v: bool = false
	for e in events:
		if e is InputEventKey and e.physical_keycode == KEY_V:
			has_v = true
	if not has_v:
		_fail("Действие toggle_view должно быть на клавише V (physical)")
		return
	print("✅ toggle_view назначен на V.")

func test_toggle_on() -> void:
	print("\n--- Проверка 2: V включает FP (FOV 75, тело и каска скрыты, сигнал) ---")
	var body_mesh: Node3D = player.visual_root.find_child("Miner_Body", true, false)
	var hat_mesh: Node3D = player.visual_root.find_child("Character_Helmet", true, false)
	if body_mesh == null or hat_mesh == null:
		_fail("В модели героя должны быть меши Miner_Body и Character_Helmet")
		return
	if not body_mesh.visible or not hat_mesh.visible:
		_fail("До переключения тело и каска должны быть видимы")
		return

	# Лямбда захватывает локали по значению, поэтому копим попадания в массиве.
	var signal_hits: Array = []
	cam.first_person_changed.connect(func(_enabled: bool): signal_hits.append(true))

	_press_toggle_view()

	if not cam.first_person:
		_fail("После V камера должна быть в режиме first_person")
		return
	if abs(cam.fov - cam.fp_fov) > 0.001:
		_fail("В FP FOV должен быть %.1f, получен %.1f" % [cam.fp_fov, cam.fov])
		return
	if body_mesh.visible:
		_fail("Меш Miner_Body должен быть скрыт в FP")
		return
	if hat_mesh.visible:
		_fail("Каска Character_Helmet должна быть скрыта в FP")
		return
	if not player._first_person:
		_fail("Игрок должен запомнить состояние _first_person")
		return
	if signal_hits.size() != 1:
		_fail("first_person_changed должен быть эмитнут один раз, получено %d" % signal_hits.size())
		return
	print("  • FOV: %.1f, тело и каска скрыты, сигнал эмитнут" % cam.fov)
	print("✅ V включает вид от первого лица.")

func test_fp_camera_transform() -> void:
	print("\n--- Проверка 3: камера у глаз персонажа, взгляд горизонтален ---")
	cam._process(0.016)
	var expected_eye: Vector3 = player.global_position + Vector3(0.0, cam.fp_eye_height, 0.0)
	if cam.global_position.distance_to(expected_eye) > 0.01:
		_fail("FP-камера должна стоять у глаз: ожидалось %s, получено %s" % [str(expected_eye), str(cam.global_position)])
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	var want: Vector3 = Vector3(-sin(cam.yaw), 0.0, -cos(cam.yaw))
	if fwd.distance_to(want) > 0.01:
		_fail("Взгляд должен быть горизонтальным по yaw: ожидалось %s, получено %s" % [str(want), str(fwd)])
		return
	print("  • Позиция: %s, взгляд горизонтален" % str(cam.global_position))
	print("✅ Трансформация FP-камеры верна.")

func test_mouse_look_without_buttons() -> void:
	print("\n--- Проверка 4: обзор мышью без зажатых кнопок ---")
	var yaw_before: float = cam.target_yaw
	var pitch_before: float = cam._fp_pitch
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120.0, -60.0)
	cam._unhandled_input(motion)
	if cam.target_yaw >= yaw_before:
		_fail("Мышь вправо должна уменьшать target_yaw")
		return
	if cam._fp_pitch <= pitch_before:
		_fail("Мышь вверх должна поднимать взгляд (_fp_pitch растёт)")
		return
	cam._process(0.016)
	if abs(angle_difference(cam.yaw, cam.target_yaw)) > 0.001:
		_fail("В FP yaw должен мгновенно равняться target_yaw (без сглаживания)")
		return
	var fwd: Vector3 = -cam.global_transform.basis.z
	if fwd.y <= 0.0:
		_fail("После движения мыши вверх взгляд должен быть направлен выше горизонта")
		return
	print("  • yaw: %.3f, наклон: %.1f°" % [cam.yaw, rad_to_deg(cam._fp_pitch)])
	print("✅ Mouse-look в FP работает без зажатых кнопок.")

func test_pitch_clamp() -> void:
	print("\n--- Проверка 5: границы наклона взгляда ±80° ---")
	var up := InputEventMouseMotion.new()
	up.relative = Vector2(0.0, -100000.0)
	cam._unhandled_input(up)
	if abs(cam._fp_pitch - deg_to_rad(cam.fp_max_pitch_deg)) > 0.001:
		_fail("Наклон не должен превышать %.0f°, получено %.1f°" % [cam.fp_max_pitch_deg, rad_to_deg(cam._fp_pitch)])
		return
	var down := InputEventMouseMotion.new()
	down.relative = Vector2(0.0, 100000.0)
	cam._unhandled_input(down)
	if abs(cam._fp_pitch - deg_to_rad(cam.fp_min_pitch_deg)) > 0.001:
		_fail("Наклон не должен быть ниже %.0f°, получено %.1f°" % [cam.fp_min_pitch_deg, rad_to_deg(cam._fp_pitch)])
		return
	print("✅ Наклон взгляда ограничен ±%.0f°." % cam.fp_max_pitch_deg)

func test_orbit_and_zoom_ignored() -> void:
	print("\n--- Проверка 6: в FP ПКМ-орбита и Ctrl+колесо не действуют ---")
	var dist_before: float = cam.target_distance
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	cam._unhandled_input(rmb)
	if cam.is_orbiting:
		_fail("В FP ПКМ не должен включать орбиту")
		return
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	cam._unhandled_input(wheel)
	if abs(cam.target_distance - dist_before) > 0.001:
		_fail("В FP Ctrl+колесо не должно менять дистанцию орбиты")
		return
	print("✅ Орбита и зум отключены в FP.")

func test_body_follows_camera() -> void:
	print("\n--- Проверка 7: корпус смотрит за камерой (стрейф не разворачивает) ---")
	cam.target_yaw = PI * 0.5
	cam._process(0.016)
	Input.action_press("move_forward")
	# Мелкие шаги: lerp_angle с весом > 1 перелетает цель.
	for i in range(20):
		player._handle_movement(0.05)
	Input.action_release("move_forward")
	var want_rot: float = PI * 0.5
	if abs(angle_difference(player.visual_root.rotation.y, want_rot)) > 0.05:
		_fail("В FP тело должно повернуться за взглядом камеры (%.2f rad), получено %.2f" % [want_rot, player.visual_root.rotation.y])
		return
	print("✅ Корпус в FP разворачивается по взгляду камеры.")

func test_toggle_off_restores_iso() -> void:
	print("\n--- Проверка 8: повторная V возвращает изометрию (FOV 56, тело видно) ---")
	var body_mesh: Node3D = player.visual_root.find_child("Miner_Body", true, false)
	_press_toggle_view()
	if cam.first_person:
		_fail("Повторная V должна вернуть изометрический вид")
		return
	if abs(cam.fov - 56.0) > 0.001:
		_fail("FOV изометрии должен восстановиться на 56, получен %.1f" % cam.fov)
		return
	if not body_mesh.visible:
		_fail("Меш тела должен снова стать видимым")
		return
	if player._first_person:
		_fail("Игрок должен сбросить _first_person")
		return
	# Большая delta: follow-lerp камеры (t = follow_speed * delta, clamp 1)
	# за один шаг доезжает до сферы орбиты.
	cam._process(1.0)
	var focus: Vector3 = player.global_position + cam.focus_offset
	var horiz: float = cam.current_distance * cos(cam.pitch)
	var want_pos: Vector3 = focus + Vector3(horiz * sin(cam.yaw), cam.current_distance * sin(cam.pitch), horiz * cos(cam.yaw))
	if cam.global_position.distance_to(want_pos) > 0.2:
		_fail("Камера должна вернуться на сферу орбиты: ожидалось %s, получено %s" % [str(want_pos), str(cam.global_position)])
		return
	print("✅ Возврат в изометрию корректен.")

func test_crosshair_ui() -> void:
	print("\n--- Проверка 9: прицел HUD и метод его показа ---")
	var hud := HudScene.instantiate()
	var crosshair: Control = hud.get_node_or_null("Crosshair")
	if crosshair == null:
		hud.free()
		_fail("В hud.tscn должен быть узел Crosshair")
		return
	if crosshair.visible:
		hud.free()
		_fail("Прицел должен быть скрыт по умолчанию (изометрия)")
		return
	if not hud.has_method("set_crosshair_visible"):
		hud.free()
		_fail("HUD должен иметь метод set_crosshair_visible")
		return
	hud.set_crosshair_visible(true)
	if not crosshair.visible:
		hud.free()
		_fail("set_crosshair_visible(true) должен показывать прицел")
		return
	hud.set_crosshair_visible(false)
	if crosshair.visible:
		hud.free()
		_fail("set_crosshair_visible(false) должен скрывать прицел")
		return
	hud.free()
	print("✅ Прицел HUD работает.")
