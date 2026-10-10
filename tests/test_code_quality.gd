extends SceneTree

const WorldScene = preload("res://scenes/world/world.tscn")
const SaveManager = preload("res://scripts/core/save_manager.gd")
const SAVE_PATH = "user://test_code_quality.json"
var executed := false
var failures: Array[String] = []
var tool_events: Array[String] = []

func _initialize() -> void:
	root.add_child(WorldScene.instantiate())

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _on_tool_changed(tool_id: String, _label: String) -> void:
	tool_events.append(tool_id)

func _process(_delta: float) -> bool:
	if executed:
		return false
	executed = true
	var world = root.get_node("World")
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var player = world.get_node("Player")
	var inv = player.inventory
	var crusher = world.find_child("StoneCrusher", true, false)
	check(crusher != null, "crusher fixture exists")
	if crusher == null:
		quit(1)
		return true

	inv.items["stone_dust"] = 10
	inv.items["clay"] = 10
	inv.items["water"] = 10
	check(not crusher.start_recipe("craft_brick", player), "crusher rejects workbench recipe")
	check(inv.get_item_count("clay") == 10, "wrong machine does not consume materials")
	crusher.is_machine_running = false
	check(not crusher.start_recipe("crush_stone", null), "null player is rejected safely")

	inv.equip_tool("pickaxe")
	inv.tool_changed.connect(_on_tool_changed)
	check(SaveManager.save_game(world, SAVE_PATH), "save succeeds")
	inv.equip_tool("axe")
	tool_events.clear()
	check(SaveManager.load_game(world, SAVE_PATH), "load succeeds")
	check(inv.equipped_tool == "pickaxe", "saved equipment restored")
	check(tool_events == ["pickaxe"], "load notifies tool visuals and HUD exactly once")

	# Valid JSON with an invalid nested type must fail before ANY world mutation.
	var bad_file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	bad_file.store_string('{"player":{"energy":1},"inventory":{"items":[]}}')
	bad_file.close()
	player.energy = 77.0
	check(not SaveManager.load_game(world, SAVE_PATH), "malformed nested save rejected")
	check(is_equal_approx(player.energy, 77.0), "invalid save does not partially mutate player")

	# Validate all sections before mutation, not just inventory.items.
	for invalid in [
		{"player": {"position": []}},
		{"inventory": {"tools": [42]}},
		{"inventory": {"items": {"wood": -1}}},
		{"weather": {"current_weather": 99}},
		{"farmland": [null]},
		{"contracts": {"completed": []}},
		{"machines": [{"path": "../Player", "recipe_id": "", "timer": 0, "duration": 1}]},
		{"traders": {"Props/TraderNPC": "yes"}}
	]:
		var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid))
		file.close()
		check(not SaveManager.load_game(world, SAVE_PATH), "reject invalid section: " + str(invalid))

	var trader = world.find_child("TraderNPC", true, false)
	trader.starter_seeds_given = true
	check(SaveManager.save_game(world, SAVE_PATH), "save trader state")
	check(not FileAccess.file_exists(SAVE_PATH + ".tmp"), "successful save leaves no temporary file")
	trader.starter_seeds_given = false
	check(SaveManager.load_game(world, SAVE_PATH), "load trader state")
	check(trader.starter_seeds_given, "starter seeds cannot be claimed again after load")
	# Previous format without new optional sections remains supported.
	var legacy_file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string('{"meta":{"version":"1.0.0"},"player":{"energy":67}}')
	legacy_file.close()
	check(SaveManager.load_game(world, SAVE_PATH), "legacy save loads")
	check(is_equal_approx(player.energy, 67.0), "legacy player state restored")

	inv.items["stone"] = 10
	check(crusher.start_recipe("crush_stone", player), "correct machine recipe starts")
	crusher.process_timer = 2.0
	check(SaveManager.save_game(world, SAVE_PATH), "in-flight production save succeeds")
	crusher.is_machine_running = false
	crusher.active_recipe = {}
	crusher.process_timer = 0.0
	check(SaveManager.load_game(world, SAVE_PATH), "in-flight production loads")
	check(crusher.is_machine_running, "production resumes after load")
	check(is_equal_approx(crusher.process_timer, 2.0), "production progress restored")
	var before = inv.get_item_count("stone_dust")
	crusher._complete_process()
	check(int(crusher.pending_outputs.get("stone_dust", 0)) == 1, "restored production stores output in machine")
	crusher.collect_outputs(player)
	check(inv.get_item_count("stone_dust") == before + 1, "restored production delivers output once")

	SaveManager.delete_save(SAVE_PATH)
	SaveManager.delete_save(SAVE_PATH + ".tmp")
	if failures.is_empty():
		print("PASS: code-quality regressions")
		quit(0)
	else:
		print("FAIL: %d code-quality regressions" % failures.size())
		quit(1)
	return true
