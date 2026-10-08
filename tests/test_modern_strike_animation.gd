extends SceneTree

const PlayerScene = preload("res://scenes/player/player.tscn")
const RockScene = preload("res://scenes/resources/rock_node.tscn")

class ModalStub extends Node:
	func is_gameplay_input_blocked() -> bool:
		return true

var player
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	player = PlayerScene.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var ap: AnimationPlayer = player.anim_player
	var skeleton: Skeleton3D = player.find_child("Skeleton3D", true, false)
	var pickaxe: MeshInstance3D = player.equipped_pickaxe_mesh
	check(ap != null and skeleton != null and pickaxe != null, "Missing hero rig")
	if failed:
		quit(1)
		return
	# Удар киркой текущей модели: клип "mine" (UAL OverhandThrow, ретаргет
	# tools/retarget_ual_to_miner.gd). Темп и момент контакта — в metadata клипа.
	var swing_name: String = "mine"
	check(ap.has_animation(swing_name), "Missing 'mine' strike clip")
	if failed:
		quit(1)
		return
	var mine: Animation = ap.get_animation(swing_name)
	check(mine.length >= 0.8 and mine.length <= 1.6, "Strike clip must be 0.8-1.6s")
	check(mine.has_meta("contact_time") and mine.has_meta("play_speed"), "Strike clip must carry contact_time/play_speed metadata")
	var speed: float = float(mine.get_meta("play_speed", 1.0))
	var DUR: float = mine.length / speed
	var CONTACT: float = float(mine.get_meta("contact_time", mine.length * 0.5)) / speed
	check(DUR >= 0.6 and DUR <= 1.2, "Strike must feel snappy (0.6-1.2s)")
	for bone_name in ["Spine1", "Spine2", "Forearm.r", "Hand.r", "Thigh.l"]:
		var found: bool = false
		for track in range(mine.get_track_count()):
			if str(mine.track_get_path(track)).ends_with(":" + bone_name):
				found = true
		check(found, "Missing retargeted body track: " + bone_name)
	var visuals: Node3D = player.visual_root
	var socket: int = skeleton.find_bone("ToolSocket.R")
	check(socket != -1, "Missing ToolSocket.R bone")
	# Навершие кирки: вершина, дальше всех по оси рукояти (+Y сокета).
	var tool_data := MeshDataTool.new()
	tool_data.create_from_surface(pickaxe.mesh, 0)
	var tip := Vector3.ZERO
	for i in range(tool_data.get_vertex_count()):
		var v: Vector3 = tool_data.get_vertex(i)
		if v.y > tip.y:
			tip = v
	tip = pickaxe.transform * tip
	var tip_at := func(t: float) -> Vector3:
		ap.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		return visuals.to_local(skeleton.global_transform * (skeleton.get_bone_global_pose(socket) * tip))
	ap.play(swing_name, 0.0)
	ap.seek(0.0, true)
	skeleton.force_update_all_bone_transforms()
	var feet: Dictionary = {}
	for name in ["Foot.l", "Foot.r"]:
		feet[name] = skeleton.get_bone_global_pose(skeleton.find_bone(name))
	var max_drift: float = 0.0
	var high_tip_y: float = -INF
	# 121 samples, including between keys (catches quaternion flips).
	var prev_tip: Vector3 = tip_at.call(0.0)
	var max_jump: float = 0.0
	for i in range(121):
		var t: float = mine.length * i / 120.0
		var p: Vector3 = tip_at.call(t)
		for name in feet:
			var pose: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone(name))
			max_drift = maxf(max_drift, (skeleton.global_transform.basis * (pose.origin - feet[name].origin)).length())
		if t <= mine.get_meta("contact_time", mine.length):
			high_tip_y = maxf(high_tip_y, p.y)
		max_jump = maxf(max_jump, p.distance_to(prev_tip))
		prev_tip = p
	var impact_tip: Vector3 = tip_at.call(float(mine.get_meta("contact_time", 0.0)))
	check(max_drift < 0.35, "Feet drifted too much during the strike")
	check(max_jump < 0.6, "Tool teleports between samples (quaternion flip)")
	check(impact_tip.z <= -0.30, "Impact must be in front of the hero")
	check(high_tip_y - impact_tip.y > 0.60, "Missing readable high-to-low arc")
	check(impact_tip.y < 0.9, "Pickaxe must come down low at contact")
	# Тело и каска — skinned меши на скелете героя.
	var body: MeshInstance3D = player.find_child("Miner_Body", true, false)
	check(body != null and body.skin != null, "Missing skinned Miner_Body")
	var helmet: MeshInstance3D = player.find_child("Character_Helmet", true, false)
	check(helmet != null and helmet.skin != null, "Missing skinned Character_Helmet")
	var foot_vertices: int = body.mesh.surface_get_array_len(0) if body else 0

	# A real ResourceNode, not a prop that only changes an animation boolean.
	var rock = RockScene.instantiate()
	root.add_child(rock)
	rock.position = Vector3(0, 0, -1)
	player.inventory.equip_tool("pickaxe")
	player.current_interactable = rock
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var before: int = rock.current_hits
	player.is_mining = false
	player.current_anim = ""
	player.play_animation("walk")
	ap.advance(0.15)
	player.velocity = Vector3(4, 0, 0)
	player._unhandled_input(click)
	check(player.is_mining and player.current_anim == swing_name, "Input did not start strike immediately")
	check(ap.current_animation == swing_name and is_zero_approx(ap.current_animation_position), "Animation not applied in input callback")
	check(player.velocity.x == 0 and player.velocity.z == 0, "Player slides while planting feet")
	check(rock.current_hits == before, "Resource hit happened before visual contact")
	check(Engine.time_scale == 1.0, "Global time scale changed at windup")
	# Динамический контакт/цикл из player (старая модель 0.15/0.42, новая ~0.55/1.0).
	var C: float = player._strike_contact_time
	var D: float = player._strike_duration
	check(absf(C - CONTACT) < 0.05 and absf(D - DUR) < 0.05, "Strike timing mismatch")
	player._update_strike(maxf(0.01, C - 0.01))
	check(rock.current_hits == before, "Hit before contact")
	player._update_strike(0.02)
	check(rock.current_hits == before - 1, "Contact must apply exactly one hit")
	check(ap.speed_scale == 0.0 and Engine.time_scale == 1.0, "Hit pause must be local to animation")
	player._update_strike(0.03)
	check(ap.speed_scale == 1.0, "Hit pause did not clear")
	player._update_strike(0.03)
	check(rock.current_hits == before - 1, "Duplicate resource hit within one swing")
	# Recovery click buffering, then release: one extra swing, not a backlog.
	var to_recovery: float = D - player._strike_elapsed - 0.05
	player._update_strike(maxf(0.01, to_recovery))
	player._unhandled_input(click)
	check(player._strike_buffered, "Recovery click lost")
	click.pressed = false
	player._input(click)
	player.nearby_interactables.assign([rock])
	player._update_strike(D - player._strike_elapsed + 0.05)
	check(player.is_mining and player._strike_elapsed == 0.0, "Buffered strike did not start")
	player._update_strike(C + 0.01)
	check(rock.current_hits == before - 2, "Buffered strike did not hit exactly once")
	player._update_strike(0.03)
	player._update_strike(D)
	check(not player.is_mining, "Release failed to stop repetition")
	if player._pickaxe_is_builtin:
		check(pickaxe.visible and ap.speed_scale == 1.0, "Strike state did not reset")
	else:
		check(not pickaxe.visible and ap.speed_scale == 1.0, "Strike state did not reset")

	# UI/modal blocks input and clears hold without mutating world time.
	var hud := ModalStub.new()
	hud.name = "HUD"
	root.add_child(hud)
	player._hud = hud
	click.pressed = true
	player._unhandled_input(click)
	check(not player.is_mining, "Modal allowed a gameplay click")
	print("STRIKE: cycle=%.3fs, contact=%.3fs, foot drift=%.6fm, arc height=%.3fm, tested boot vertices=%d" % [mine.length, C, max_drift, high_tip_y-impact_tip.y, foot_vertices])
	print("Input callback pose, exactly-once contact, local hit pause, buffering/release and UI block checked.")
	quit(1 if failed else 0)
