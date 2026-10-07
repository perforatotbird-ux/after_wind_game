extends SceneTree

func _init() -> void:
	print(">>> Converting stardew_farmer.glb to native Godot scenes/player/character_model.tscn...")
	_convert()

func _convert() -> void:
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var err = doc.append_from_file("res://assets/models/character/stardew_farmer.glb", state)
	if err == OK:
		var node = doc.generate_scene(state)
		node.name = "CharacterModel"
		_reset_constant_mining_channels(node)
		_set_owner_recursive(node, node)
		
		var packed = PackedScene.new()
		var pack_err = packed.pack(node)
		if pack_err == OK:
			var save_err = ResourceSaver.save(packed, "res://scenes/player/character_model.tscn")
			if save_err == OK:
				print("✅ Successfully saved res://scenes/player/character_model.tscn")
			else:
				print("❌ Error saving character_model.tscn: ", save_err)
		else:
			print("❌ Error packing character node: ", pack_err)
		node.free()
	else:
		print("❌ Error reading stardew_farmer.glb: ", err)
	
	quit(0)

func _reset_constant_mining_channels(node: Node) -> void:
	# glTF optimizes invariant channels away. Reset all bones explicitly so a
	# swing started during walk/run cannot retain the previous leg pose.
	var ap: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = node.find_child("Skeleton3D", true, false)
	if not ap or not skeleton or not ap.has_animation("mine"):
		return
	var mine: Animation = ap.get_animation("mine")
	# glTF's inclusive end-frame export adds one frame; trim to authored span.
	mine.length = 25.0 / 60.0
	for bone in range(skeleton.get_bone_count()):
		var path := NodePath(str(node.get_path_to(skeleton)) + ":" + skeleton.get_bone_name(bone))
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			if mine.find_track(path, type) != -1:
				continue
			var track: int = mine.add_track(type)
			mine.track_set_path(track, path)
			var value: Variant = rest.origin if type == Animation.TYPE_POSITION_3D else rest.basis.get_rotation_quaternion() if type == Animation.TYPE_ROTATION_3D else rest.basis.get_scale()
			mine.track_insert_key(track, 0.0, value)
			mine.track_insert_key(track, mine.length, value)

func _set_owner_recursive(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner_recursive(child, root_node)
