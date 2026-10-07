class_name AudioManager
extends Node

## Процедурная аудиосистема и менеджер звуковых эффектов (Game Feel, Разделы 83, 88 Phase F)
## Генерирует процедурные звуковые эффекты в памяти без внешних зависимостей.

static var instance: AudioManager = null

@export var max_sfx_voices: int = 8

var _sounds: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _ambient_wind_player: AudioStreamPlayer = null
var _ambient_rain_player: AudioStreamPlayer = null

var master_volume: float = 1.0
var sfx_volume: float = 0.8
var ambient_volume: float = 0.6

func _init() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _ambient_wind_player and is_instance_valid(_ambient_wind_player):
		_ambient_wind_player.stop()
		_ambient_wind_player.stream = null
	if _ambient_rain_player and is_instance_valid(_ambient_rain_player):
		_ambient_rain_player.stop()
		_ambient_rain_player.stream = null
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_sounds.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	_generate_all_sounds()
	_start_ambient()

static func play(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if instance and is_instance_valid(instance):
		instance.play_sfx(sound_name, pitch, volume_db)

func play_sfx(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _sounds.has(sound_name):
		return
	if DisplayServer.get_name() == "headless":
		return
	if _sfx_players.is_empty():
		return
	
	var player = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	
	var vol_linear = sfx_volume * master_volume
	if vol_linear <= 0.001:
		return
	
	var base_db = linear_to_db(vol_linear) + volume_db
	player.stream = _sounds[sound_name]
	player.pitch_scale = clampf(pitch, 0.5, 2.0)
	player.volume_db = base_db
	player.play()

func set_sfx_vol(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)

func set_ambient_vol(val: float) -> void:
	ambient_volume = clampf(val, 0.0, 1.0)
	_update_ambient_volumes()

func set_weather_rain(is_raining: bool, rain_intensity: float = 1.0) -> void:
	if not _ambient_rain_player:
		return
	if DisplayServer.get_name() == "headless":
		return
	if is_raining:
		if not _ambient_rain_player.playing:
			_ambient_rain_player.play()
		var linear = ambient_volume * master_volume * clampf(rain_intensity, 0.3, 1.0) * 0.7
		_ambient_rain_player.volume_db = linear_to_db(maxf(0.001, linear))
	else:
		if _ambient_rain_player.playing:
			_ambient_rain_player.stop()

func _setup_audio_players() -> void:
	for i in range(max_sfx_voices):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)
	
	_ambient_wind_player = AudioStreamPlayer.new()
	_ambient_wind_player.bus = "Master"
	_ambient_wind_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient_wind_player)
	
	_ambient_rain_player = AudioStreamPlayer.new()
	_ambient_rain_player.bus = "Master"
	_ambient_rain_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient_rain_player)

func _update_ambient_volumes() -> void:
	var linear_wind = ambient_volume * master_volume * 0.4
	if _ambient_wind_player:
		_ambient_wind_player.volume_db = linear_to_db(maxf(0.001, linear_wind))

func _start_ambient() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _sounds.has("wind_ambient") and _ambient_wind_player:
		_ambient_wind_player.stream = _sounds["wind_ambient"]
		_update_ambient_volumes()
		_ambient_wind_player.play()
	
	if _sounds.has("rain_ambient") and _ambient_rain_player:
		_ambient_rain_player.stream = _sounds["rain_ambient"]

func _generate_all_sounds() -> void:
	var rate: int = 22050
	
	# 1. Удар топора по дереву (глухой упругий стук)
	_sounds["hit_wood"] = _create_wav(rate, _gen_wood_hit(rate))
	
	# 2. Удар кирки по камню/металлу (звонкий резкий щелчок с резонансом)
	_sounds["hit_stone"] = _create_wav(rate, _gen_stone_hit(rate))
	
	# 3. Вскопка земли лопатой (шорох и зачерпывание)
	_sounds["till_soil"] = _create_wav(rate, _gen_shovel_till(rate))
	
	# 4. Сбор спелого урожая (приятный восходящий перезвон)
	_sounds["harvest"] = _create_wav(rate, _gen_arpeggio(rate, [523.25, 659.25, 783.99], 0.08))
	
	# 5. Запуск технологической машины (механический урчащий разгон)
	_sounds["machine_start"] = _create_wav(rate, _gen_machine_buzz(rate))
	
	# 6. Звон монет / касса (двойной металлический дзинь)
	_sounds["coins"] = _create_wav(rate, _gen_coin_chime(rate))
	
	# 7. Зачерпывание и плеск воды
	_sounds["water_splash"] = _create_wav(rate, _gen_water_splash(rate))
	
	# 8. Клик интерфейса (короткий тактильный blip)
	_sounds["ui_click"] = _create_wav(rate, _gen_ui_blip(rate))
	
	# 9. Победный фанфарный аккорд «Base Restored»
	_sounds["victory_fanfare"] = _create_wav(rate, _gen_arpeggio(rate, [261.63, 329.63, 392.00, 523.25, 659.25], 0.18))
	
	# 10. Фоновый шелест ветра (белый шум с фильтрацией)
	_sounds["wind_ambient"] = _create_wav(rate, _gen_wind_loop(rate), true)
	
	# 11. Фоновый шум дождя
	_sounds["rain_ambient"] = _create_wav(rate, _gen_rain_loop(rate), true)

func _create_wav(mix_rate: int, data: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = data.size() / 2
	return stream

# --- Процедурные генераторы PCM-семплов (16-bit Mono, Little-Endian) ---

func _gen_wood_hit(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.14)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var freq: float = lerpf(140.0, 50.0, t)
		phase += (2.0 * PI * freq) / float(rate)
		var env: float = pow(1.0 - t, 2.5)
		var click: float = (randf_range(-0.3, 0.3)) * pow(1.0 - t, 8.0)
		var s: float = (sin(phase) * 0.7 + click) * env
		_write_sample(bytes, i, s)
	return bytes

func _gen_stone_hit(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.16)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		phase1 += (2.0 * PI * 880.0) / float(rate)
		phase2 += (2.0 * PI * 1320.0) / float(rate)
		var env: float = pow(1.0 - t, 3.2)
		var s: float = (sin(phase1) * 0.5 + sin(phase2) * 0.3) * env
		_write_sample(bytes, i, s)
	return bytes

func _gen_shovel_till(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.18)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var last: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var n: float = randf_range(-1.0, 1.0)
		last = (last + 0.15 * n) / 1.15
		var env: float = sin(t * PI) * pow(1.0 - t, 1.2)
		_write_sample(bytes, i, last * env * 1.5)
	return bytes

func _gen_arpeggio(rate: int, freqs: Array, note_sec: float) -> PackedByteArray:
	var samples_per_note: int = int(rate * note_sec)
	var total_samples: int = samples_per_note * freqs.size()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(total_samples * 2)
	for f_idx in range(freqs.size()):
		var f: float = float(freqs[f_idx])
		var phase: float = 0.0
		for i in range(samples_per_note):
			var idx: int = f_idx * samples_per_note + i
			var t: float = float(i) / float(samples_per_note)
			phase += (2.0 * PI * f) / float(rate)
			var env: float = pow(1.0 - t, 1.4)
			var s: float = (sin(phase) + 0.2 * sin(phase * 2.0)) * env * 0.75
			_write_sample(bytes, idx, s)
	return bytes

func _gen_machine_buzz(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.35)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var freq: float = lerpf(80.0, 190.0, t)
		phase += (2.0 * PI * freq) / float(rate)
		var env: float = minf(1.0, t * 5.0) * pow(1.0 - t, 1.2)
		var saw: float = fmod(phase / (2.0 * PI), 1.0) * 2.0 - 1.0
		_write_sample(bytes, i, saw * env * 0.5)
	return bytes

func _gen_coin_chime(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.22)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		p1 += (2.0 * PI * 1568.0) / float(rate) # G6
		p2 += (2.0 * PI * 2093.0) / float(rate) # C7
		var env1: float = pow(1.0 - t, 2.5)
		var env2: float = 0.0 if t < 0.3 else pow(1.0 - (t - 0.3) / 0.7, 2.5)
		var s: float = (sin(p1) * env1 + sin(p2) * env2) * 0.5
		_write_sample(bytes, i, s)
	return bytes

func _gen_water_splash(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.22)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var last: float = 0.0
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var freq: float = lerpf(400.0, 180.0, t)
		phase += (2.0 * PI * freq) / float(rate)
		var n: float = randf_range(-1.0, 1.0)
		last = (last + 0.2 * n) / 1.2
		var env: float = pow(1.0 - t, 1.6)
		var s: float = (sin(phase) * 0.4 + last * 0.6) * env * 0.8
		_write_sample(bytes, i, s)
	return bytes

func _gen_ui_blip(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 0.05)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		phase += (2.0 * PI * 920.0) / float(rate)
		var env: float = pow(1.0 - t, 2.0)
		_write_sample(bytes, i, sin(phase) * env * 0.5)
	return bytes

func _gen_wind_loop(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 1.5)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	var last: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var n: float = randf_range(-1.0, 1.0)
		last = (last + 0.04 * n) / 1.04
		# Сглаживание концов для бесшовного зацикливания
		var loop_window: float = sin(t * PI)
		_write_sample(bytes, i, last * loop_window * 0.5)
	return bytes

func _gen_rain_loop(rate: int) -> PackedByteArray:
	var samples: int = int(rate * 1.5)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / float(samples)
		var n: float = randf_range(-1.0, 1.0)
		var drop: float = 1.0 if randf() < 0.02 else 0.0
		var loop_window: float = sin(t * PI)
		var s: float = (n * 0.15 + drop * 0.4) * loop_window * 0.6
		_write_sample(bytes, i, s)
	return bytes

func _write_sample(bytes: PackedByteArray, idx: int, value: float) -> void:
	var val_i: int = clampi(int(value * 32767.0), -32768, 32767)
	var u16: int = val_i if val_i >= 0 else (val_i + 65536)
	bytes[idx * 2] = u16 & 0xFF
	bytes[idx * 2 + 1] = (u16 >> 8) & 0xFF
