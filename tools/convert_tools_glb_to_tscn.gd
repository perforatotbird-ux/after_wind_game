extends SceneTree

# Конвертер GLB -> TSCN для топора, лопаты и ведра.
# Повторяет паттерн tools/convert_glb_to_tscn.gd (GLTFDocument + generate_scene + pack).

var _executed: bool = false

const JOBS := [
	["axe", "res://assets/models/tools/axe.glb", "res://scenes/tools/axe_model.tscn", "AxeModel"],
	["shovel", "res://assets/models/tools/shovel.glb", "res://scenes/tools/shovel_model.tscn", "ShovelModel"],
	["bucket", "res://assets/models/tools/bucket.glb", "res://scenes/tools/bucket_model.tscn", "BucketModel"],
	# In-hand варианты (grip в origin): цепляются к ToolSocket.R и следуют за рукой.
	["axe_inhand", "res://assets/models/tools/axe_inhand.glb", "res://scenes/tools/axe_inhand.tscn", "AxeInHand"],
	["shovel_inhand", "res://assets/models/tools/shovel_inhand.glb", "res://scenes/tools/shovel_inhand.tscn", "ShovelInHand"],
	["bucket_inhand", "res://assets/models/tools/bucket_inhand.glb", "res://scenes/tools/bucket_inhand.tscn", "BucketInHand"],
	["bucket_full_inhand", "res://assets/models/tools/bucket_full_inhand.glb", "res://scenes/tools/bucket_full_inhand.tscn", "BucketFullInHand"],
]

func _init() -> void:
	print(">>> convert_tools_glb_to_tscn.gd _init called!")
	_convert()

func _convert() -> void:
	print("Converting axe/shovel/bucket GLB models to native Godot TSCN scenes...")
	var failed := 0
	for job in JOBS:
		var tool_id: String = job[0]
		var glb_path: String = job[1]
		var tscn_path: String = job[2]
		var node_name: String = job[3]
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(glb_path, state)
		if err != OK:
			push_error("Error reading %s: %s" % [glb_path, err])
			print("FAIL %s: cannot read %s (err %s)" % [tool_id, glb_path, err])
			failed += 1
			continue
		var node: Node = doc.generate_scene(state)
		node.name = node_name
		_set_owner_recursive(node, node)
		var packed := PackedScene.new()
		var pack_err := packed.pack(node)
		if pack_err != OK:
			push_error("Error packing %s: %s" % [tool_id, pack_err])
			print("FAIL %s: pack error %s" % [tool_id, pack_err])
			node.free()
			failed += 1
			continue
		var save_err := ResourceSaver.save(packed, tscn_path)
		if save_err != OK:
			push_error("Error saving %s: %s" % [tscn_path, save_err])
			print("FAIL %s: save error %s" % [tool_id, save_err])
			failed += 1
		else:
			print("Saved %s" % tscn_path)
		node.free()
	if failed > 0:
		print("DONE WITH %d FAILURES" % failed)
		quit(1)
	else:
		print("ALL 6 TOOL SCENES CONVERTED SUCCESSFULLY!")
		quit(0)

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
