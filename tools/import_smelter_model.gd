extends SceneTree
## Импорт запечённой плавильной печи из Blender в текстовые ресурсы Godot.
## Сначала: python3 tools/create_smelter_model.py --bake 2048  (Blender 5.x как модуль bpy)
## Затем:   godot --headless --path . -s tools/import_smelter_model.gd -- <папка bake>
## Результат — assets/models/smelter/*.tres (меш, материалы, текстуры WebP внутри .tres).

const OUT_DIR := "res://assets/models/smelter/"
const TEX_SIZE := 2048
const NORMAL_SIZE := 1024
const ORM_SIZE := 1024

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://smelter_build/bake")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src.path_join("smelter_game.glb"), state) != OK:
		push_error("Не прочитан smelter_game.glb"); quit(1); return
	var scene: Node = doc.generate_scene(state)
	var body_src: MeshInstance3D = scene.find_child("SmelterBody", true, false)
	var glow_src: MeshInstance3D = scene.find_child("SmelterGlow", true, false)
	if body_src == null or glow_src == null:
		push_error("В glb нет SmelterBody/SmelterGlow"); quit(1); return

	# --- текстуры ---
	var albedo := _load_png(src, "smelter_albedo.png", TEX_SIZE)
	var normal := _load_png(src, "smelter_normal.png", NORMAL_SIZE)
	var rough := _load_png(src, "smelter_roughness.png", ORM_SIZE)
	var metal := _load_png(src, "smelter_metallic.png", ORM_SIZE)
	var orm := Image.create(ORM_SIZE, ORM_SIZE, false, Image.FORMAT_RGB8)
	for y in ORM_SIZE:
		for x in ORM_SIZE:
			orm.set_pixel(x, y, Color(1.0, rough.get_pixel(x, y).r, metal.get_pixel(x, y).r))
	var t_albedo := _save_tex(albedo, "smelter_albedo.tres", false, 0.82)
	var t_normal := _save_tex(normal, "smelter_normal.tres", true, 0.85)
	var t_orm := _save_tex(orm, "smelter_orm.tres", false, 0.8)

	# --- материалы ---
	var mat := StandardMaterial3D.new()
	mat.resource_name = "SmelterAtlas"
	mat.albedo_texture = t_albedo
	mat.normal_enabled = true
	mat.normal_texture = t_normal
	mat.normal_scale = 1.0
	mat.roughness = 1.0
	mat.roughness_texture = t_orm
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.metallic = 0.6
	mat.metallic_texture = t_orm
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ResourceSaver.save(mat, OUT_DIR + "smelter_material.tres")
	var glow := StandardMaterial3D.new()
	glow.resource_name = "SmelterGlow"
	glow.albedo_color = Color(0.55, 0.16, 0.03)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.36, 0.06)
	glow.emission_energy_multiplier = 1.4
	glow.roughness = 0.6
	ResourceSaver.save(glow, OUT_DIR + "smelter_glow_material.tres")
	var mat_ref: Material = load(OUT_DIR + "smelter_material.tres")
	var glow_ref: Material = load(OUT_DIR + "smelter_glow_material.tres")

	# --- меши (сжатые атрибуты, касательные для карты нормалей) ---
	_save_mesh(body_src.mesh, mat_ref, true, "smelter_body_mesh.tres")
	_save_mesh(glow_src.mesh, glow_ref, false, "smelter_glow_mesh.tres")
	scene.free()
	print("IMPORT OK")
	quit(0)

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

func _save_mesh(src: Mesh, material: Material, tangents: bool, file: String) -> void:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(src, s)
		if tangents:
			st.generate_tangents()
		var arrays: Array = st.commit_to_arrays()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_material(out.get_surface_count() - 1, material)
	ResourceSaver.save(out, OUT_DIR + file)
