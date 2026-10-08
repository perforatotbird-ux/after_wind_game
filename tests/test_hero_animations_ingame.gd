extends SceneTree
## Интеграционный тест героя: игрок на полу, реальный ввод (WASD / Shift / удар).
## Проверяет, что AnimationPlayer переключает idle -> jog -> run -> mine,
## темп ходьбы подгоняется под скорость, а кости скелета действительно двигаются
## (раньше клипы двигали только IK-контроллеры и герой стоял «столбом»).
var world: Node
var player
var frames := 0
var phase := ""
func _initialize():
	world = Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(200, 1, 200)
	cs.shape = box; floor.add_child(cs); floor.position = Vector3(0, -0.5, 0)
	world.add_child(floor)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
func _snapshot() -> Dictionary:
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var d := {}
	for b in ["Thigh.l", "Forearm.r", "Hand.r", "Spine2"]:
		d[b] = sk.get_bone_pose_rotation(sk.find_bone(b))
	return d
var prev := {}
var seen := {}
var moved := {}
func _process(delta):
	frames += 1
	if frames == 5:
		phase = "idle"
	elif frames == 70:
		phase = "walk"; Input.action_press("move_forward")
	elif frames == 150:
		phase = "run"; Input.action_press("sprint")
	elif frames == 230:
		Input.action_release("sprint"); Input.action_release("move_forward")
		phase = "strike"; player.inventory.equip_tool("pickaxe"); player.trigger_tool_strike()
	elif frames == 300:
		phase = "end"
	if phase != "" and phase != "end":
		var s := _snapshot()
		if not prev.is_empty():
			var m := 0.0
			for k in s: m = maxf(m, (s[k] as Quaternion).angle_to(prev[k]))
			moved[phase] = maxf(moved.get(phase, 0.0), m)
		prev = s
		seen[String(player.anim_player.current_animation)] = true
		if frames % 20 == 0:
			print("%s f=%d anim=%s pos=%.2f speed_scale=%.2f vel=%.2f" % [phase, frames, player.anim_player.current_animation, player.anim_player.current_animation_position, player.anim_player.speed_scale, Vector2(player.velocity.x, player.velocity.z).length()])
	if phase == "end":
		print("max per-frame bone rotation change: ", moved)
		var ok: bool = moved.get("idle", 0) > 0.0005 and moved.get("walk", 0) > 0.01 and moved.get("run", 0) > 0.01 and moved.get("strike", 0) > 0.02
		ok = ok and seen.has("jog") and seen.has("run") and seen.has("mine") and seen.has("idle")
		print("Animations seen: ", seen.keys())
		print("✅ ТЕСТ ПРОЙДЕН: анимации героя работают в игре" if ok else "❌ ТЕСТ ПРОВАЛЕН: анимации героя не проигрываются")
		if not ok:
			push_error("hero animations are not playing")
		quit(0 if ok else 1)
		return true
	return false
