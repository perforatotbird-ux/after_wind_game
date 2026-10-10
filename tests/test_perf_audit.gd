extends SceneTree
## Автоматический бенчмарк производительности и памяти (Godot 4.7 SceneTree)
## Измеряет тесты A-G и сохраняет результаты в outputs/perf_audit_results.json

const WorldScene = preload("res://scenes/world/world.tscn")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

var frame: int = 0
var stage: int = 0
var stage_frame: int = 0
var world: Node = null
var player: Node = null
var report: Dictionary = {}

var acc_fps: float = 0.0
var min_fps: float = 999999.0
var max_fps: float = 0.0
var acc_process_ms: float = 0.0
var acc_physics_ms: float = 0.0
var acc_draw_calls: float = 0.0
var acc_objects: float = 0.0
var acc_primitives: float = 0.0

var spawned_nodes: Array = []
var reload_results: Array = []
var long_start_mem: float = 0.0

func _initialize() -> void:
	world = WorldScene.instantiate()
	root.add_child(world)
	player = world.get_node_or_null("Player")
	print("=== STARTING PERFORMANCE AUDIT BENCHMARK ===")

func _reset_acc() -> void:
	acc_fps = 0.0
	min_fps = 999999.0
	max_fps = 0.0
	acc_process_ms = 0.0
	acc_physics_ms = 0.0
	acc_draw_calls = 0.0
	acc_objects = 0.0
	acc_primitives = 0.0

func _sample() -> void:
	var fps := float(Engine.get_frames_per_second())
	if fps > 0.0:
		min_fps = minf(min_fps, fps)
		max_fps = maxf(max_fps, fps)
		acc_fps += fps
	acc_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	acc_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	acc_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	acc_objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	acc_primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

func _finish_metrics(count: int) -> Dictionary:
	var f := float(maxi(1, count))
	return {
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"memory_static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / (1024.0 * 1024.0),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0),
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / (1024.0 * 1024.0),
		"physics_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_islands": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		"avg_fps": acc_fps / f,
		"min_fps": min_fps if min_fps < 999999.0 else 0.0,
		"max_fps": max_fps,
		"avg_process_time_ms": acc_process_ms / f,
		"avg_physics_time_ms": acc_physics_ms / f,
		"avg_draw_calls": acc_draw_calls / f,
		"avg_objects_drawn": acc_objects / f,
		"avg_primitives": acc_primitives / f,
	}

func _capture_instant() -> Dictionary:
	return {
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}

func _process(_delta: float) -> bool:
	frame += 1
	stage_frame += 1

	match stage:
		0:
			# Прогрев (15 кадров)
			if stage_frame >= 15:
				print("Starting TEST A: IDLE...")
				stage = 1
				stage_frame = 0
				_reset_acc()
		1:
			# TEST A: IDLE (60 кадров)
			_sample()
			if stage_frame >= 60:
				report["TEST_A_IDLE"] = _finish_metrics(60)
				print("Starting TEST B: NORMAL GAMEPLAY...")
				stage = 2
				stage_frame = 0
				_reset_acc()
		2:
			# TEST B: NORMAL GAMEPLAY (движение персонажа, 60 кадров)
			if is_instance_valid(player) and "velocity" in player:
				player.velocity = Vector3(2.8, 0.0, 1.4)
			_sample()
			if stage_frame >= 60:
				report["TEST_B_GAMEPLAY"] = _finish_metrics(60)
				print("Starting TEST C: DENSE ENVIRONMENT...")
				stage = 3
				stage_frame = 0
				if is_instance_valid(player):
					player.global_position = Vector3(-24.0, 0.0, 24.0)
				_reset_acc()
		3:
			# TEST C: DENSE ENVIRONMENT (60 кадров в лесу)
			_sample()
			if stage_frame >= 60:
				report["TEST_C_DENSE"] = _finish_metrics(60)
				print("Starting TEST D: MACHINERY...")
				stage = 4
				stage_frame = 0
				if is_instance_valid(player):
					player.global_position = Vector3(0.0, 0.0, 0.0)
				var crusher = world.find_child("StoneCrusher", true, false)
				var smelter = world.find_child("Smelter", true, false)
				if crusher and crusher.has_method("start_batch"):
					crusher.start_batch("crush_stone", 5, player)
				if smelter and smelter.has_method("start_batch"):
					smelter.start_batch("smelt_iron", 5, player)
				_reset_acc()
		4:
			# TEST D: MACHINERY (60 кадров с работающими машинами)
			_sample()
			if stage_frame >= 60:
				report["TEST_D_MACHINERY"] = _finish_metrics(60)
				print("Starting TEST E: MASS SPAWN...")
				stage = 5
				stage_frame = 0
				report["TEST_E_MASS_SPAWN"] = {}
		5:
			# TEST E: MASS SPAWN (100 -> 250 -> 500 -> 1000)
			var target_count := 0
			if stage_frame == 5: target_count = 100
			elif stage_frame == 10: target_count = 250
			elif stage_frame == 15: target_count = 500
			elif stage_frame == 20: target_count = 1000
			
			if target_count > 0:
				var need := target_count - spawned_nodes.size()
				for i in need:
					var it: Node = DroppedItemScript.spawn(world, "stone", 1, Vector3(randf_range(-15, 15), 1.0, randf_range(-15, 15)))
					if is_instance_valid(it):
						spawned_nodes.append(it)
				report["TEST_E_MASS_SPAWN"][str(target_count)] = _capture_instant()
			
			if stage_frame >= 25:
				for n in spawned_nodes:
					if is_instance_valid(n):
						n.queue_free()
				spawned_nodes.clear()
				print("Starting TEST F: SCENE RELOAD...")
				stage = 6
				stage_frame = 0
		6:
			# TEST F: SCENE RELOAD (5 циклов смены сцены)
			var cycle := stage_frame / 4
			var sub_frame := stage_frame % 4
			if sub_frame == 0 and cycle < 5:
				var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
				var obj_before := Performance.get_monitor(Performance.OBJECT_COUNT)
				var node_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
				world.queue_free()
				world = WorldScene.instantiate()
				root.add_child(world)
				player = world.get_node_or_null("Player")
				var mem_after := Performance.get_monitor(Performance.MEMORY_STATIC)
				var obj_after := Performance.get_monitor(Performance.OBJECT_COUNT)
				var node_after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
				reload_results.append({
					"cycle": cycle + 1,
					"mem_static_mb": mem_after / (1024.0 * 1024.0),
					"objects": obj_after,
					"nodes": node_after,
					"delta_mem_kb": (mem_after - mem_before) / 1024.0,
					"delta_nodes": node_after - node_before
				})
			if stage_frame >= 20:
				report["TEST_F_SCENE_RELOAD"] = reload_results
				print("Starting TEST G: LONG SESSION...")
				stage = 7
				stage_frame = 0
				long_start_mem = Performance.get_monitor(Performance.MEMORY_STATIC)
				_reset_acc()
		7:
			# TEST G: LONG SESSION (120 кадров)
			_sample()
			if stage_frame >= 120:
				var long_metrics := _finish_metrics(120)
				var long_end_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
				long_metrics["net_memory_growth_kb"] = (long_end_mem - long_start_mem) / 1024.0
				report["TEST_G_LONG_SESSION"] = long_metrics
				_save_and_quit()
				return true

	return false

func _save_and_quit() -> void:
	var json_str := JSON.stringify(report, "\t")
	print("--- BENCHMARK COMPLETED ---")
	print("METRICS_JSON_START")
	print(json_str)
	print("METRICS_JSON_END")
