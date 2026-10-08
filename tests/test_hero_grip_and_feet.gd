extends SceneTree
## Регрессия по визуальным багам героя:
##  1. стопы не вывернуты носком вверх (Foot->Toe смотрит вниз-вперёд, как в rest);
##  2. топор в руке головой вверх (голова над кулаком со стороны большого пальца);
##  3. кирка/инструмент в кулаке: пальцы правой кисти сжаты во всех клипах удара,
##     центр сокета — внутри кулака (рядом с суставами пальцев).
var player
var frames := 0
var shots := [["idle", 0.5], ["walk", 0.3], ["mine", 0.2], ["mine", 0.43], ["chop", 0.5], ["dig", 0.8]]
var errors: Array[String] = []

func _initialize():
	var world := Node3D.new()
	root.add_child(world)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)

func _angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))

func _process(_d):
	frames += 1
	if frames < 5:
		return false
	var ap: AnimationPlayer = player.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = player.find_child("Skeleton3D", true, false)
	player.set_process(false)
	player.set_physics_process(false)
	var i := (frames - 5) / 2
	if i >= shots.size():
		_finish()
		return true
	var sh: Array = shots[i]
	if (frames - 5) % 2 == 0:
		ap.play(sh[0]); ap.seek(sh[1], true); ap.pause()
		return false
	var gp := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin
	var gr := func(n: String) -> Vector3: return sk.global_transform * sk.get_bone_global_rest(sk.find_bone(n)).origin
	var tag := "%s@%.2f" % sh
	# 1. Стопа: наклон Foot->Toe к горизонту близок к rest (не задрана носком вверх).
	for s in ["l", "r"]:
		var d: Vector3 = gp.call("Toe." + s) - gp.call("Foot." + s)
		var r: Vector3 = gr.call("Toe." + s) - gr.call("Foot." + s)
		var pitch := rad_to_deg(asin(d.normalized().y))
		var rest_pitch := rad_to_deg(asin(r.normalized().y))
		# В ходьбе стопа на ударе пяткой естественно приподнимает носок — допуск шире.
		var tol := 45.0 if sh[0] == "walk" else 20.0
		if pitch > rest_pitch + tol:
			errors.append("%s: стопа %s задрана (наклон %.0f°, rest %.0f°)" % [tag, s, pitch, rest_pitch])
	# 3. Кулак правой кисти в клипах инструмента.
	if sh[0] in ["mine", "chop", "dig"]:
		var h: Vector3 = gp.call("Hand.r")
		var m1: Vector3 = gp.call("Middle1.r")
		var m2: Vector3 = gp.call("Middle2.r")
		var m3: Vector3 = gp.call("Middle3.r")
		var curl := _angle(m1 - h, m2 - m1) + _angle(m2 - m1, m3 - m2)
		if curl < 100.0:
			errors.append("%s: кисть раскрыта (изгиб пальцев %.0f°)" % [tag, curl])
		var sock: Vector3 = player.tool_socket.global_position
		var dist := sock.distance_to((m1 + m2 + m3) / 3.0)
		if dist > 0.12:
			errors.append("%s: сокет вне кулака (%.2f м от пальцев)" % [tag, dist])
	# 2. Топор: голова над кулаком со стороны большого пальца (+Y сокета).
	if sh[0] == "chop":
		var axe: Node3D = player.equipped_tool_nodes.get("axe")
		if axe == null:
			errors.append("нет in-hand топора")
		else:
			var head_local := axe.transform * Vector3(0.0, -0.40, 0.0) # голова в меше axe_inhand
			if head_local.y < 0.3:
				errors.append("топор перевёрнут: голова на %.2f по оси рукояти" % head_local.y)
			var pinky_to_index: Vector3 = gp.call("Index1.r") - gp.call("Pinky1.r")
			var y_axis: Vector3 = player.tool_socket.global_transform.basis.y.normalized()
			if y_axis.dot(pinky_to_index.normalized()) < 0.7:
				errors.append("ось рукояти не направлена к большому пальцу")
	print("  • %s проверен" % tag)
	return false

func _finish():
	if errors.is_empty():
		print("ТЕСТ ПРОЙДЕН: стопы, хват топора/кирки в норме")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("ТЕСТ ПРОВАЛЕН")
		quit(1)
