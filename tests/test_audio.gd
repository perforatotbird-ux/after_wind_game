extends SceneTree
## Звуки: все звуки из таблицы AudioManager существуют как ресурсы assets/audio/*.tres,
## загружаются, не пустые и разумной длины; фоновые петли зациклены; у ударов есть
## варианты; в коде вызываются только существующие имена звуков; громкости/дождь
## переключаются без ошибок; финальный размер звуков небольшой.

const AudioManager = preload("res://scripts/audio/audio_manager.gd")

var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func _initialize() -> void:
	var total_bytes := 0
	for n in AudioManager.SOUNDS.keys() + AudioManager.AMBIENT:
		var paths: Array = AudioManager.paths_for(n)
		check(not paths.is_empty(), "Нет путей для звука %s" % n)
		for p in paths:
			check(ResourceLoader.exists(p), "Нет файла %s" % p)
			var s := load(p) as AudioStreamOggVorbis
			check(s != null, "Не загружается %s" % p)
			if s == null:
				continue
			var length := s.get_length()
			total_bytes += FileAccess.get_file_as_bytes(p).size()
			if n in AudioManager.AMBIENT:
				check(s.loop, "Фоновый звук %s не зациклен" % n)
				check(length >= 15.0, "Фоновый звук %s слишком короткий: %.1f с" % [n, length])
			else:
				check(not s.loop, "Эффект %s не должен быть зациклен" % p)
				check(length > 0.02 and length < 3.0, "Странная длина %s: %.2f с" % [p, length])
	check(total_bytes < 3 * 1024 * 1024, "Звуки слишком тяжёлые: %d байт" % total_bytes)
	for n in ["hit_wood", "hit_stone", "footstep_grass", "swing", "eat"]:
		check(int(AudioManager.SOUNDS[n][1]) >= 3, "Мало вариантов у %s" % n)
	# Все AudioManager.play("...") в коде ссылаются на существующие звуки.
	var re := RegEx.new()
	re.compile("AudioManager\\.play\\(\"([a-z_]+)\"")
	var used := {}
	_scan_dir("res://scripts", re, used)
	for n in used:
		check(AudioManager.SOUNDS.has(n), "В коде используется неизвестный звук '%s' (%s)" % [n, used[n]])
	for n in ["swing", "footstep_grass", "eat", "drink", "berry_pick", "plant", "drop", "build", "hit_metal", "dig", "ui_open", "ui_close"]:
		check(used.has(n), "Звук %s нигде не используется" % n)
	# Менеджер: загрузка, выбор вариантов без повтора подряд, громкости, дождь.
	var am = AudioManager.new()
	root.add_child(am)
	await process_frame
	check(AudioManager.instance == am, "AudioManager.instance не установлен")
	check(am._sounds.size() == AudioManager.SOUNDS.size() + AudioManager.AMBIENT.size(), "Загружено звуков: %d" % am._sounds.size())
	var prev: AudioStream = null
	for i in 20:
		var st: AudioStream = am.get_stream("hit_stone")
		check(st != null and st != prev, "Вариант удара повторился подряд")
		prev = st
	AudioManager.play("hit_wood")
	AudioManager.play("unknown_sound")
	am.set_sfx_vol(0.4)
	am.set_ambient_vol(0.5)
	am.set_weather_rain(true, 0.9)
	check(am._is_raining, "Флаг дождя не выставлен")
	am.set_weather_rain(false)
	check(absf(am.sfx_volume - 0.4) < 0.001 and absf(am.ambient_volume - 0.5) < 0.001, "Громкости не применились")
	am.queue_free()
	if errors.is_empty():
		print("Звуков: %d (+%d фоновых), используется в коде: %d, размер %.0f КиБ" % [AudioManager.SOUNDS.size(), AudioManager.AMBIENT.size(), used.size(), total_bytes / 1024.0])
		print("TEST PASSED")
		quit(0)
	else:
		for e in errors:
			print("FAIL: " + e)
		quit(1)

func _scan_dir(dir: String, re: RegEx, used: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			for m in re.search_all(src):
				used[m.get_string(1)] = f
	for d in DirAccess.get_directories_at(dir):
		_scan_dir(dir.path_join(d), re, used)
