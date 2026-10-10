extends SceneTree
## Импорт запечённого склада из Blender (три состояния) в текстовые ресурсы Godot.
## Сначала: STORAGE_STATE=<ruins|barn|complex> python3 tools/create_storage_model.py --bake 2048
## Затем:   godot --headless --path . -s tools/import_storage_model.gd -- <STORAGE_OUT> [состояние…]
## Результат — assets/models/storage/*.tres: у каждого состояния свой атлас (цвет 2048, нормали 1024,
## ORM 1024: R — AO, G — шероховатость, B — металл), материал и меши частей. У подвижных частей
## подъёмника центр меша — на оси; позиции печатаются, они же стоят в repairable_storage.tscn.

const OUT_DIR := "res://assets/models/storage/"
const TEX_SIZE := 2048
const NORMAL_SIZE := 1024
const ORM_SIZE := 1024
const STATES := {
	"ruins": {"StorageRuins": "storage_ruins_mesh.tres"},
	"barn": {"StorageBarnFrame": "storage_barn_frame_mesh.tres", "StorageBarnShell": "storage_barn_shell_mesh.tres",
		"StorageBarnTarp": "storage_barn_tarp_mesh.tres"},
	"complex": {"StorageComplex": "storage_complex_mesh.tres", "StorageComplexYard": "storage_complex_yard_mesh.tres",
		"StorageGear": "storage_complex_gear_mesh.tres",
		"StorageCrank": "storage_complex_crank_mesh.tres", "StorageChain": "storage_complex_chain_mesh.tres",
		"StorageHook": "storage_complex_hook_mesh.tres"},
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var root_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://storage_build")
	var which: Array = args.slice(1) if args.size() > 1 else STATES.keys()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	for state in which:
		if not _import_state(root_dir.path_join("bake_" + state), state):
			quit(1); return
	print("IMPORT OK")
	quit(0)

func _import_state(src: String, state: String) -> bool:
	var pre := "storage_" + state
	var doc := GLTFDocument.new()
	var gstate := GLTFState.new()
	if doc.append_from_file(src.path_join(pre + "_game.glb"), gstate) != OK:
		push_error("Не прочитан %s_game.glb" % pre); return false
	var scene: Node = doc.generate_scene(gstate)
	var albedo := _load_png(src, pre + "_albedo.png", TEX_SIZE)
	var normal := _load_png(src, pre + "_normal.png", NORMAL_SIZE)
	var ao := _load_png(src, pre + "_ao.png", ORM_SIZE)
	var rough := _load_png(src, pre + "_roughness.png", ORM_SIZE)
	var metal := _load_png(src, pre + "_metallic.png", ORM_SIZE)
	var orm := Image.create(ORM_SIZE, ORM_SIZE, false, Image.FORMAT_RGB8)
	for y in ORM_SIZE:
		for x in ORM_SIZE:
			orm.set_pixel(x, y, Color(ao.get_pixel(x, y).r, rough.get_pixel(x, y).r, metal.get_pixel(x, y).r))
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Storage_%s_Atlas" % state
	mat.albedo_texture = _save_tex(albedo, pre + "_albedo.tres", false, 0.8)
	mat.normal_enabled = true
	mat.normal_texture = _save_tex(normal, pre + "_normal.tres", true, 0.82)
	var t_orm := _save_tex(orm, pre + "_orm.tres", false, 0.78)
	mat.ao_enabled = true
	mat.ao_texture = t_orm
	mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.ao_light_affect = 0.35
	mat.roughness = 1.0
	mat.roughness_texture = t_orm
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.metallic = 1.0
	mat.metallic_texture = t_orm
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Тент и тонкие листы видны с обеих сторон — у них есть толщина, отсечение граней оставляем.
	ResourceSaver.save(mat, OUT_DIR + pre + "_material.tres")
	var mat_ref: Material = load(OUT_DIR + pre + "_material.tres")
	var parts: Dictionary = STATES[state]
	for node_name in parts.keys():
		var mi: MeshInstance3D = scene.find_child(node_name, true, false)
		if mi == null:
			push_error("В glb нет " + node_name); return false
		_save_mesh(mi.mesh, mat_ref, parts[node_name])
		print("PIVOT ", node_name, " ", mi.position)
	scene.free()
	return true

func _load_png(dir: String, file: String, size: int) -> Image:
	var img := Image.load_from_file(dir.path_join(file))
	img.convert(Image.FORMAT_RGB8)
	if img.get_width() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img

func _save_tex(img: Image, file: String, is_normal: bool, quality: float) -> Texture2D:
	var t := PortableCompressedTexture2D.new()
	t.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, is_normal, quality)
	ResourceSaver.save(t, OUT_DIR + file)
	return load(OUT_DIR + file)

func _save_mesh(src: Mesh, material: Material, file: String) -> void:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(src, s)
		st.generate_tangents()
		var arrays: Array = st.commit_to_arrays()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_material(out.get_surface_count() - 1, material)
	ResourceSaver.save(out, OUT_DIR + file)
