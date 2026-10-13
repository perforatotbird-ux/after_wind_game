extends SceneTree
## godot --headless --path . -s tools/import_trader_model.gd -- <build_dir>
## GLTF со скелетом из rig_trader_model.py -> текстовые ресурсы Godot без GLB/Blender.
const OUT := "res://assets/models/trader/"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Укажите папку сборки торговца"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0].path_join("trader_rigged.gltf"), state) != OK:
		push_error("Не прочитана модель торговца"); quit(1); return
	var scene := doc.generate_scene(state)
	scene.name = "WanderingTraderModel"
	var mi := scene.find_child("TraderBody", true, false) as MeshInstance3D
	var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if mi == null or ap == null:
		push_error("Нет меша или анимаций"); quit(1); return
	var mat := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	mat.resource_name = "WanderingTraderPBR"
	mat.albedo_texture = _texture(mat.albedo_texture, "trader_albedo", 1024, false, 0.88)
	mat.normal_texture = _texture(mat.normal_texture, "trader_normal", 512, true, 0.85)
	mat.roughness_texture = _texture(mat.roughness_texture, "trader_orm", 512, false, 0.85)
	mat.metallic_texture = mat.roughness_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ResourceSaver.save(mat, OUT + "trader_material.tres")
	mat = load(OUT + "trader_material.tres")
	# Меши разбиты только для хранения небольшими текстовыми файлами; один общий скелет.
	var arrays := mi.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var chunks := ceili(indices.size() / 19500.0)
	for part in chunks:
		var remap := {}
		var used: Array[int] = []
		var new_indices := PackedInt32Array()
		for i in range(part * 19500, mini((part + 1) * 19500, indices.size())):
			var old: int = indices[i]
			if not remap.has(old):
				remap[old] = used.size(); used.append(old)
			new_indices.append(remap[old])
		var clean: Array = []; clean.resize(Mesh.ARRAY_MAX)
		for attr in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
			clean[attr] = arrays[attr].slice(0, 0)
			for old in used: clean[attr].append(arrays[attr][old])
		for attr in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			if arrays[attr] == null: continue
			clean[attr] = arrays[attr].slice(0, 0)
			for old in used:
				for k in 4: clean[attr].append(arrays[attr][old * 4 + k])
		clean[Mesh.ARRAY_INDEX] = new_indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean)
		mesh.surface_set_material(0, mat)
		var file := OUT + "trader_body_%02d.tres" % part
		ResourceSaver.save(mesh, file)
		var piece := MeshInstance3D.new()
		piece.name = "TraderBody%02d" % part
		piece.mesh = load(file)
		piece.skin = mi.skin
		piece.skeleton = mi.skeleton
		piece.transform = mi.transform
		mi.get_parent().add_child(piece)
		print(file, " verts ", used.size())
	mi.get_parent().remove_child(mi); mi.free()
	var sk := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var lib := ap.get_animation_library("")
	for anim_name in lib.get_animation_list():
		var anim := lib.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in ["idle", "walk"] else Animation.LOOP_NONE
		# Constant rest channels omitted by GLTF must be restored to avoid pose leaks.
		for bone in sk.get_bone_count():
			var path := NodePath("TraderRig/Skeleton3D:" + sk.get_bone_name(bone))
			if anim.find_track(path, Animation.TYPE_ROTATION_3D) < 0:
				var track := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(track, path)
				anim.rotation_track_insert_key(track, 0.0, sk.get_bone_rest(bone).basis.get_rotation_quaternion())
		print("ANIM ", anim_name, " ", anim.length, " tracks ", anim.get_track_count())
	ResourceSaver.save(lib, OUT + "trader_animations.tres")
	ap.remove_animation_library("")
	ap.add_animation_library("", load(OUT + "trader_animations.tres"))
	ap.autoplay = "idle"
	_set_owner(scene, scene)
	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		push_error("Не упакована сцена"); quit(1); return
	ResourceSaver.save(packed, OUT + "wandering_trader.tscn")
	scene.free()
	print("TRADER IMPORT OK: ", chunks, " mesh pieces, ", indices.size() / 3, " triangles")
	quit()

func _texture(src: Texture2D, name_: String, size: int, normal: bool, quality: float) -> Texture2D:
	var image := src.get_image()
	image.convert(Image.FORMAT_RGB8)
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, normal, quality)
	ResourceSaver.save(tex, OUT + name_ + ".tres")
	return load(OUT + name_ + ".tres")

func _set_owner(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_set_owner(child, root_node)
