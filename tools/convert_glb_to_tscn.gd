extends SceneTree

var _executed: bool = false

func _init() -> void:
	print(">>> convert_glb_to_tscn.gd _init called!")
	_convert()

func _convert() -> void:
	print("Converting GLB models to native Godot TSCN scenes...")
	
	# 1. Convert Miner
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file("res://assets/models/character/miner.glb", state)
	if err == OK:
		var node = doc.generate_scene(state)
		node.name = "MinerModel"
		_set_owner_recursive(node, node)
		
		var packed = PackedScene.new()
		var pack_err = packed.pack(node)
		if pack_err == OK:
			var save_err = ResourceSaver.save(packed, "res://scenes/player/miner_model.tscn")
			if save_err == OK:
				print("✅ Saved res://scenes/player/miner_model.tscn")
			else:
				print("❌ Error saving miner_model.tscn: ", save_err)
		else:
			print("❌ Error packing miner node: ", pack_err)
		node.free()
	else:
		print("❌ Error reading miner.glb: ", err)

	# 2. Convert Pickaxe
	var doc_p = GLTFDocument.new()
	var state_p = GLTFState.new()
	var err_p = doc_p.append_from_file("res://assets/models/tools/pickaxe.glb", state_p)
	if err_p == OK:
		var node_p = doc_p.generate_scene(state_p)
		node_p.name = "PickaxeModel"
		_set_owner_recursive(node_p, node_p)
		
		var packed_p = PackedScene.new()
		var pack_err_p = packed_p.pack(node_p)
		if pack_err_p == OK:
			var save_err_p = ResourceSaver.save(packed_p, "res://scenes/tools/pickaxe_model.tscn")
			if save_err_p == OK:
				print("✅ Saved res://scenes/tools/pickaxe_model.tscn")
			else:
				print("❌ Error saving pickaxe_model.tscn: ", save_err_p)
		node_p.free()

	quit(0)

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
