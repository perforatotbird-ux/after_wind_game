extends SceneTree
## Конвертирует OGG из build-папки (tools/build_sounds.py) в текстовые
## ресурсы res://assets/audio/<name>.tres (AudioStreamOggVorbis).
## Текстовый формат нужен, чтобы звуки можно было хранить/пушить как текст.
## Запуск: godot --headless --path . -s tools/import_sounds.gd -- /data/sfx_build

const LOOPED := ["wind_ambient", "rain_ambient", "birds_ambient"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else "/data/sfx_build"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/audio"))
	var count := 0
	for f in DirAccess.get_files_at(src):
		if not f.ends_with(".ogg"):
			continue
		var stream := AudioStreamOggVorbis.load_from_file(src.path_join(f))
		if stream == null:
			push_error("cannot load " + f)
			continue
		var base := f.get_basename()
		stream.loop = base in LOOPED
		var err := ResourceSaver.save(stream, "res://assets/audio/%s.tres" % base)
		if err != OK:
			push_error("save failed %s: %d" % [base, err])
		count += 1
	print("imported ", count)
	quit()
