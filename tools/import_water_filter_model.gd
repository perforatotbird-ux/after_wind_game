extends SceneTree
## godot --headless --path . -s tools/import_water_filter_model.gd -- <build_dir>
## Два состояния присланного очистителя -> компактные текстовые ресурсы Godot.
const OUT := "res://assets/models/water_filter/"
var materials := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Укажите папку сборки очистителя"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	for state_name in ["repaired", "ruined"]:
		if not _import_state(args[0], state_name): quit(1); return
	print("WATER FILTER IMPORT OK")
	quit()

func _import_state(dir: String, state_name: String) -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(dir.path_join("filter_" + state_name + ".gltf"), state) != OK:
		push_error("Не прочитана модель " + state_name); return false
	var src := doc.generate_scene(state)
	var out := Node3D.new()
	out.name = "WaterFilterRepaired" if state_name == "repaired" else "WaterFilterRuined"
	var triangles := 0
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		for surface in mi.mesh.get_surface_count():
			var mat := _material(mi.mesh.surface_get_material(surface), state_name)
			var arrays: Array = mi.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			for chunk in ceili(indices.size() / 24000.0):
				var used: Array[int] = []; var remap := {}; var new_indices := PackedInt32Array()
				for i in range(chunk * 24000, mini((chunk + 1) * 24000, indices.size())):
					var old: int = indices[i]
					if not remap.has(old): remap[old] = used.size(); used.append(old)
					new_indices.append(remap[old])
				var clean: Array = []; clean.resize(Mesh.ARRAY_MAX)
				for attr in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
					if arrays[attr] == null: continue
					clean[attr] = arrays[attr].slice(0, 0)
					for old in used: clean[attr].append(arrays[attr][old])
				if arrays[Mesh.ARRAY_TANGENT] != null:
					clean[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
					for old in used:
						for k in 4: clean[Mesh.ARRAY_TANGENT].append(arrays[Mesh.ARRAY_TANGENT][old * 4 + k])
				clean[Mesh.ARRAY_INDEX] = new_indices
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
				mesh.surface_set_material(0, mat)
				var file := OUT + "filter_%s_%s_%02d_%02d.tres" % [state_name, mi.name.to_snake_case(), surface, chunk]
				ResourceSaver.save(mesh, file)
				var piece := MeshInstance3D.new()
				piece.name = "%s_%02d_%02d" % [mi.name, surface, chunk]
				piece.mesh = load(file)
				piece.transform = _transform_to_root(mi, src)
				out.add_child(piece); piece.owner = out
				print(file, " verts ", used.size())
	var scene := PackedScene.new()
	if scene.pack(out) != OK: return false
	ResourceSaver.save(scene, OUT + "water_filter_" + state_name + ".tscn")
	print(state_name, " triangles ", triangles, " parts ", out.get_child_count())
	out.free(); src.free()
	return true

func _transform_to_root(node: Node3D, root_node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent is Node3D and parent != root_node:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

func _material(src: StandardMaterial3D, state_name: String) -> Material:
	var key := src.resource_name.to_snake_case()
	if materials.has(key): return materials[key]
	var mat := src.duplicate() as StandardMaterial3D
	if src.albedo_texture:
		# Ruins use the original atlas plus vertex patina, not a second copy of the textures.
		if not materials.has("atlas"):
			materials["atlas"] = {
				"albedo": _texture(src.albedo_texture, "filter_albedo", 1024, false, 0.88),
				"normal": _texture(src.normal_texture, "filter_normal", 512, true, 0.85),
				"orm": _texture(src.roughness_texture, "filter_orm", 512, false, 0.85)
			}
		mat.albedo_texture = materials["atlas"]["albedo"]
		mat.normal_texture = materials["atlas"]["normal"]
		mat.roughness_texture = materials["atlas"]["orm"]
		mat.metallic_texture = mat.roughness_texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.vertex_color_use_as_albedo = state_name == "ruined"
		if state_name == "ruined":
			mat.albedo_color = Color(0.85, 0.79, 0.70)
			mat.metallic = 0.35
			mat.roughness = 1.0
		# Model is opaque, repaired or broken; no artificial water glow.
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ResourceSaver.save(mat, OUT + key + "_material.tres")
	materials[key] = load(OUT + key + "_material.tres")
	return materials[key]

func _texture(src: Texture2D, name_: String, size: int, normal: bool, quality: float) -> Texture2D:
	var image := src.get_image()
	image.convert(Image.FORMAT_RGB8)
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, normal, quality)
	ResourceSaver.save(tex, OUT + name_ + ".tres")
	return load(OUT + name_ + ".tres")
