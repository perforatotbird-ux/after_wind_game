extends SceneTree
## Импорт ягодного куста (berry_bush.glb из Blender) в текстовые ресурсы Godot.
##   godot --headless --path . -s tools/import_berry_bush.gd -- <путь к berry_bush.glb>
## Результат — assets/models/berry_bush/: меши веток, листвы (по мешу на слой листвы, чтобы
## каждый файл был < 1 МБ) и ягод, материалы. Синие ягоды — та же модель, только другой
## материал ягод. Куст «без ягод» — те же ветки и листва без меша Berries.

const OUT_DIR := "res://assets/models/berry_bush/"
## Слои листвы: материал glb -> имя файла.
const LEAF_LAYERS := {
	"MAT_Leaves_Dark": "leaves_dark",
	"MAT_Leaves": "leaves",
	"MAT_Leaves_Light": "leaves_light",
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Укажите путь к berry_bush.glb"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		push_error("Не прочитан " + args[0]); quit(1); return
	var scene: Node = doc.generate_scene(state)
	var mats := {
		"branches": _material("BerryBush_Branches", Color(0.195, 0.087, 0.030), 0.8, false),
		"leaves_dark": _material("BerryBush_LeavesDark", Color(0.0168, 0.125, 0.0103), 0.68, true),
		"leaves": _material("BerryBush_Leaves", Color(0.0497, 0.254, 0.0232), 0.62, true),
		"leaves_light": _material("BerryBush_LeavesLight", Color(0.175, 0.503, 0.0595), 0.55, true),
		"berry_red": _material("BerryBush_BerryRed", Color(0.503, 0.0048, 0.025), 0.4, false),
		"berry_blue": _material("BerryBush_BerryBlue", Color(0.03, 0.07, 0.42), 0.38, false),
	}
	for key in mats:
		ResourceSaver.save(mats[key], OUT_DIR + "berry_bush_%s_material.tres" % key)
		mats[key] = load(OUT_DIR + "berry_bush_%s_material.tres" % key)
	var branches: MeshInstance3D = scene.find_child("Branches", true, false)
	var berries: MeshInstance3D = scene.find_child("Berries", true, false)
	var leaves: MeshInstance3D = scene.find_child("Leaves", true, false)
	if branches == null or berries == null or leaves == null:
		push_error("В glb нет Branches/Berries/Leaves"); quit(1); return
	_save_surfaces(branches.mesh, [0], mats["branches"], "berry_bush_branches_mesh.tres")
	# Ягоды без материала: цвет задаёт сцена куста (красный или синий).
	_save_surfaces(berries.mesh, [0], null, "berry_bush_berries_mesh.tres")
	for s in leaves.mesh.get_surface_count():
		var mat: Material = leaves.mesh.surface_get_material(s)
		var key: String = LEAF_LAYERS.get(mat.resource_name if mat else "", "")
		if key == "":
			push_error("Неизвестный слой листвы %d" % s); quit(1); return
		_save_surfaces(leaves.mesh, [s], mats[key], "berry_bush_%s_mesh.tres" % key)
	print("AABB ", leaves.mesh.get_aabb().merge(branches.mesh.get_aabb()))
	scene.free()
	print("IMPORT OK")
	quit(0)

func _material(name_: String, color: Color, rough: float, two_sided: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name_
	m.albedo_color = color
	m.roughness = rough
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Сохраняет поверхности меша без UV (текстур у куста нет) со сжатием атрибутов.
func _save_surfaces(src: Mesh, surfaces: Array, material: Material, file: String) -> void:
	var out := ArrayMesh.new()
	for s in surfaces:
		var arrays: Array = src.surface_get_arrays(s)
		var clean: Array = []
		clean.resize(Mesh.ARRAY_MAX)
		clean[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		clean[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		clean[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		if material:
			out.surface_set_material(out.get_surface_count() - 1, material)
	ResourceSaver.save(out, OUT_DIR + file)
