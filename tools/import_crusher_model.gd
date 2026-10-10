extends SceneTree
## Импорт запечённой дробилки из Blender в текстовые ресурсы Godot.
## Сначала: python3 tools/create_crusher_model.py --bake 2048  (Blender 5.x как модуль bpy)
## Затем:   godot --headless --path . -s tools/import_crusher_model.gd -- <папка bake>
## Результат — assets/models/crusher/*.tres: меши корпуса и подвижных частей (центр — на оси
## вращения), общий материал-атлас (цвет, нормали, ORM: R — AO, G — шероховатость, B — металл)
## и материал лампы. Позиции осей печатаются — они же стоят в scenes/machines/crusher.tscn.

const OUT_DIR := "res://assets/models/crusher/"
const TEX_SIZE := 2048
const NORMAL_SIZE := 1024
const ORM_SIZE := 1024
const PARTS := {
	"CrusherBody": "crusher_body_mesh.tres",
	"CrusherFlywheel": "crusher_flywheel_mesh.tres",
	"CrusherJaw": "crusher_jaw_mesh.tres",
	"CrusherPulley": "crusher_pulley_mesh.tres",
	"CrusherStones": "crusher_stones_mesh.tres",
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://crusher_build/bake")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src.path_join("crusher_game.glb"), state) != OK:
		push_error("Не прочитан crusher_game.glb"); quit(1); return
	var scene: Node = doc.generate_scene(state)

	# --- текстуры ---
	var albedo := _load_png(src, "crusher_albedo.png", TEX_SIZE)
	var normal := _load_png(src, "crusher_normal.png", NORMAL_SIZE)
	var ao := _load_png(src, "crusher_ao.png", ORM_SIZE)
	var rough := _load_png(src, "crusher_roughness.png", ORM_SIZE)
	var metal := _load_png(src, "crusher_metallic.png", ORM_SIZE)
	var orm := Image.create(ORM_SIZE, ORM_SIZE, false, Image.FORMAT_RGB8)
	for y in ORM_SIZE:
		for x in ORM_SIZE:
			orm.set_pixel(x, y, Color(ao.get_pixel(x, y).r, rough.get_pixel(x, y).r, metal.get_pixel(x, y).r))
	var t_albedo := _save_tex(albedo, "crusher_albedo.tres", false, 0.82)
	var t_normal := _save_tex(normal, "crusher_normal.tres", true, 0.85)
	var t_orm := _save_tex(orm, "crusher_orm.tres", false, 0.8)

	# --- материалы ---
	var mat := StandardMaterial3D.new()
	mat.resource_name = "CrusherAtlas"
	mat.albedo_texture = t_albedo
	mat.normal_enabled = true
	mat.normal_texture = t_normal
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
	ResourceSaver.save(mat, OUT_DIR + "crusher_material.tres")
	var lamp := StandardMaterial3D.new()
	lamp.resource_name = "CrusherLamp"
	lamp.albedo_color = Color(0.16, 0.42, 0.2)
	lamp.roughness = 0.2
	lamp.emission_enabled = true
	lamp.emission = Color(0.36, 1.0, 0.43)
	lamp.emission_energy_multiplier = 0.0
	ResourceSaver.save(lamp, OUT_DIR + "crusher_lamp_material.tres")
	var mat_ref: Material = load(OUT_DIR + "crusher_material.tres")
	var lamp_ref: Material = load(OUT_DIR + "crusher_lamp_material.tres")

	# --- меши ---
	for node_name in PARTS.keys():
		var mi: MeshInstance3D = scene.find_child(node_name, true, false)
		if mi == null:
			push_error("В glb нет " + node_name); quit(1); return
		_save_mesh(mi.mesh, mat_ref, true, PARTS[node_name])
		print("PIVOT ", node_name, " ", mi.position)
	var lamp_src: MeshInstance3D = scene.find_child("CrusherLamp", true, false)
	_save_mesh(lamp_src.mesh, lamp_ref, false, "crusher_lamp_mesh.tres")
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
