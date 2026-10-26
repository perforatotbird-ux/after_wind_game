extends SceneTree

func _init() -> void:
	print("TEST_MODELS_START")
	
	# 1. Test generator scene
	var gen_scene: PackedScene = load("res://scenes/energy/solid_generator.tscn")
	assert(gen_scene != null, "cannot load solid_generator.tscn")
	var gen_node = gen_scene.instantiate()
	assert(gen_node != null, "cannot instantiate solid_generator.tscn")
	var gen_model = gen_node.get_node_or_null("GeneratorModel")
	assert(gen_model != null, "GeneratorModel node vanished or not present")
	print("GeneratorModel child count: ", gen_model.get_child_count())
	assert(gen_model.get_child_count() > 0, "GeneratorModel has no children meshes")
	gen_node.free()
	
	# 2. Test primitive bed scene
	var bed_scene: PackedScene = load("res://scenes/buildings/primitive_bed.tscn")
	assert(bed_scene != null, "cannot load primitive_bed.tscn")
	var bed_node = bed_scene.instantiate()
	assert(bed_node != null, "cannot instantiate primitive_bed.tscn")
	var bed_model = bed_node.get_node_or_null("BedModel")
	assert(bed_model != null, "BedModel node vanished or not present")
	print("BedModel child count: ", bed_model.get_child_count())
	assert(bed_model.get_child_count() > 0, "BedModel has no children meshes")
	bed_node.free()
	
	# 3. Test world scene
	var world_scene: PackedScene = load("res://scenes/world/world.tscn")
	assert(world_scene != null, "cannot load world.tscn")
	var world_node = world_scene.instantiate()
	assert(world_node != null, "cannot instantiate world.tscn")
	
	var world_gen = world_node.get_node_or_null("Props/SolidGenerator")
	assert(world_gen != null, "Props/SolidGenerator not found in world.tscn")
	var world_gen_model = world_gen.get_node_or_null("GeneratorModel")
	assert(world_gen_model != null, "GeneratorModel missing from world_gen")
	print("World SolidGenerator position: ", world_gen.position)
	print("World GeneratorModel child count: ", world_gen_model.get_child_count())
	assert(world_gen_model.get_child_count() > 0, "world_gen_model has no children")
	
	var world_bed = world_node.get_node_or_null("Props/PrimitiveBed")
	assert(world_bed != null, "Props/PrimitiveBed not found in world.tscn")
	var world_bed_model = world_bed.get_node_or_null("BedModel")
	assert(world_bed_model != null, "BedModel missing from world_bed")
	print("World PrimitiveBed position: ", world_bed.position)
	print("World BedModel child count: ", world_bed_model.get_child_count())
	assert(world_bed_model.get_child_count() > 0, "world_bed_model has no children")
	
	world_node.free()
	
	print("ALL_MODELS_VERIFIED_SUCCESSFULLY")
	quit(0)
