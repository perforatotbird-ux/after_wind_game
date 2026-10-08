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
	# Резолвер замаха: старая модель ("mine" 0.42 c) и новая из пакета
	# ("Track_Pickaxe_Swing" 1.5 c, играется ускоренно до ~1.0 c).
	var swing_name: String = "mine"
	if not ap.has_animation(swing_name):
		for c in ["Track_Pickaxe_Swing", "Track_Pickaxe_Swing_Heavy"]:
			if ap.has_animation(c):
				swing_name = c
				break
	var mine: Animation = ap.get_animation(swing_name)
	var is_long_swing: bool = mine.length >= 0.8
	if is_long_swing:
		check(mine.length >= 0.9 and mine.length <= 1.7, "Long swing cycle must be 0.9-1.7s")
	else:
		check(mine.length >= 0.35 and mine.length <= 0.45, "Strike cycle must be 350-450ms")
	for bone_name in ["Spine", "Chest", "UpperArm"]:
		var found: bool = false
		for track in range(mine.get_track_count()):
			if bone_name in str(mine.track_get_path(track)):
				found = true
		check(found, "Missing authored upper-body track: " + bone_name)
	# Ожидаемые параметры замаха зеркалят логику player._play_interaction_swing.
	var DUR: float = mine.length / 1.5 if is_long_swing else mine.length
	var CONTACT: float = DUR * (0.55 if is_long_swing else 0.38)
	var visuals: Node3D = player.visual_root
	var hand_bone_name: String = "Hand.R"
	if skeleton.find_bone(hand_bone_name) == -1:
		hand_bone_name = "Hand_R"
	var hand: int = skeleton.find_bone(hand_bone_name)
	var bind: Transform3D = skeleton.get_bone_global_rest(hand).affine_inverse()
	var tool_data := MeshDataTool.new()
	tool_data.create_from_surface(pickaxe.mesh, 0)
	var tip := Vector3.ZERO
	var tip_z: float = -INF
	for i in range(tool_data.get_vertex_count()):
		var v: Vector3 = tool_data.get_vertex(i)
		if v.z > tip_z:
			tip_z = v.z
			tip = v
	ap.play(swing_name, 0.0)
	ap.seek(0.0, true)
	skeleton.force_update_all_bone_transforms()
	var feet: Dictionary = {}
	var foot_names: Array[String] = ["Foot.L", "Foot.R"]
	if skeleton.find_bone("Foot.L") == -1:
		foot_names = ["Foot_L", "Foot_R"]
	for name in foot_names:
		feet[name] = skeleton.get_bone_global_pose(skeleton.find_bone(name))
	var max_drift: float = 0.0
	var max_tip_z: float = -INF
	var high_tip_y: float = -INF
	var impact_tip := Vector3.ZERO
	# 121 samples, including between authored keys (catches quaternion flips).
	for i in range(121):
		var t: float = mine.length * i / 120.0
		ap.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		for name in feet:
			var pose: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone(name))
			max_drift = maxf(max_drift, pose.origin.distance_to(feet[name].origin))
			if not is_long_swing:
				check(pose.basis.is_equal_approx(feet[name].basis), "Foot rotation changed during planted strike")
		var p: Vector3 = visuals.to_local(skeleton.global_transform * (skeleton.get_bone_global_pose(hand) * bind * tip))
		max_tip_z = maxf(max_tip_z, p.z)
		high_tip_y = maxf(high_tip_y, p.y)
	ap.seek(CONTACT, true)
	skeleton.force_update_all_bone_transforms()
	impact_tip = visuals.to_local(skeleton.global_transform * (skeleton.get_bone_global_pose(hand) * bind * tip))
	# Длинный замах новой модели допускает больший дрейф/дугу, чем короткий авторский.
	var drift_limit: float = 0.05 if is_long_swing else 0.002
	check(max_drift < drift_limit, "Planted feet drifted too much")
	check(max_tip_z <= 0.05 if is_long_swing else 0.02, "Tool swung behind the hero")
	check(impact_tip.z <= (-0.30 if is_long_swing else -0.50), "Impact must be in front")
	check(high_tip_y - impact_tip.y > (0.30 if is_long_swing else 0.70), "Missing readable high-to-low arc")
	# Verify geometry weights: no foot vertices connected to hands/arms.
	var body: MeshInstance3D = player.find_child("Farmer_Character", true, false)
	if body == null:
		body = player.find_child("Character_Boots", true, false)
	if body == null:
		body = player.find_child("Character_Jacket", true, false)
	var foot_vertices: int = 0
	for surface in range(body.mesh.get_surface_count()):
		var md := MeshDataTool.new()
		md.create_from_surface(body.mesh, surface)
		for i in range(md.get_vertex_count()):
			if md.get_vertex(i).y > 0.13:
				continue
			foot_vertices += 1
			var bones: PackedInt32Array = md.get_vertex_bones(i)
			var weights: PackedFloat32Array = md.get_vertex_weights(i)
			for j in range(bones.size()):
				if weights[j] > 0.001:
					var bname: String = skeleton.get_bone_name(body.skin.get_bind_bone(bones[j]))
					check(bname.begins_with("Foot.") or bname.begins_with("Shin.") or bname.begins_with("Foot_") or bname.begins_with("Shin_") or bname.begins_with("LowerLeg"), "Boot geometry weighted outside lower limb: " + bname)
	check(foot_vertices > 0, "No boot vertices tested")

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
