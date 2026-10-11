class_name AudioManager
extends Node

## Менеджер звуков (Game Feel, Разделы 83, 88 Phase F).
## Звуки — бесплатные CC0-сэмплы (Kenney, OpenGameArt) + несколько сгенерированных,
## собранные tools/build_sounds.py и сохранённые как текстовые ресурсы
## res://assets/audio/<name>.tres (см. assets/audio/CREDITS.md).
## У звука может быть несколько вариантов — при проигрывании выбирается случайный
## (без повтора подряд) с небольшим разбросом высоты, чтобы удары не звучали «машинно».

static var instance: AudioManager = null

const AUDIO_DIR := "res://assets/audio/"

## Имя звука → [базовое имя файла, число вариантов]. Варианты: <base>_0.tres … <base>_{n-1}.tres
const SOUNDS := {
	"hit_wood": ["hit_wood", 5],
	"hit_stone": ["hit_stone", 5],
	"hit_metal": ["hit_metal", 3],
	"dig": ["dig", 4],
	"till_soil": ["dig", 4],
	"swing": ["swing", 3],
	"footstep_grass": ["footstep_grass", 5],
	"footstep_dirt": ["footstep_dirt", 5],
	"pickup": ["pickup", 3],
	"drop": ["drop", 2],
	"coins": ["coins", 3],
	"harvest": ["harvest", 1],
	"berry_pick": ["berry_pick", 2],
	"plant": ["plant", 3],
	"water_splash": ["water_splash", 3],
	"water_fill": ["water_fill", 1],
	"drink": ["drink", 2],
	"eat": ["eat", 3],
	"machine_start": ["machine_start", 1],
	"machine_done": ["machine_done", 1],
	"build": ["build", 3],
	"ui_click": ["ui_click", 3],
	"ui_open": ["ui_open", 1],
	"ui_close": ["ui_close", 1],
	"ui_error": ["ui_error", 1],
	"victory_fanfare": ["victory_fanfare", 1],
}
## Зацикленные фоновые звуки (один файл, loop = true).
const AMBIENT := ["wind_ambient", "rain_ambient", "birds_ambient"]
## Звуки без случайного разброса высоты (интерфейс и музыка).
const NO_PITCH_JITTER := ["ui_click", "ui_open", "ui_close", "ui_error", "victory_fanfare", "harvest", "machine_done"]

@export var max_sfx_voices: int = 10

## name → Array[AudioStream] (для эмбиента — массив из одного потока)
var _sounds: Dictionary = {}
var _last_variant: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _ambient_wind_player: AudioStreamPlayer = null
var _ambient_rain_player: AudioStreamPlayer = null
var _ambient_birds_player: AudioStreamPlayer = null
var _is_raining: bool = false
var _rain_intensity: float = 1.0
var _ambient_tween: Tween = null

var master_volume: float = 1.0
var sfx_volume: float = 0.8
var ambient_volume: float = 0.6

func _init() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null
	for p in [_ambient_wind_player, _ambient_rain_player, _ambient_birds_player]:
		if p and is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_sounds.clear()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	_load_all_sounds()
	_start_ambient()

static func play(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if instance and is_instance_valid(instance):
		instance.play_sfx(sound_name, pitch, volume_db)

## Все имена звуков, которые можно передать в play().
static func sound_names() -> Array:
	return SOUNDS.keys()

## Список путей ресурсов для звука (варианты или единственный файл эмбиента).
static func paths_for(sound_name: String) -> Array:
	var out: Array = []
	if SOUNDS.has(sound_name):
		var base: String = SOUNDS[sound_name][0]
		for i in range(int(SOUNDS[sound_name][1])):
			out.append("%s%s_%d.tres" % [AUDIO_DIR, base, i])
	elif sound_name in AMBIENT:
		out.append("%s%s.tres" % [AUDIO_DIR, sound_name])
	return out

func get_stream(sound_name: String) -> AudioStream:
	var variants: Array = _sounds.get(sound_name, [])
	if variants.is_empty():
		return null
	if variants.size() == 1:
		return variants[0]
	var idx := randi() % variants.size()
	if idx == int(_last_variant.get(sound_name, -1)):
		idx = (idx + 1) % variants.size()
	_last_variant[sound_name] = idx
	return variants[idx]

func play_sfx(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _sounds.has(sound_name):
		return
	if DisplayServer.get_name() == "headless":
		return
	if _sfx_players.is_empty():
		return
	var vol_linear := sfx_volume * master_volume
	if vol_linear <= 0.001:
		return
	var stream := get_stream(sound_name)
	if stream == null:
		return
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	if not (sound_name in NO_PITCH_JITTER):
		pitch *= randf_range(0.93, 1.07)
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.5, 2.0)
	player.volume_db = linear_to_db(vol_linear) + volume_db
	player.play()

func set_sfx_vol(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)

func set_ambient_vol(val: float) -> void:
	ambient_volume = clampf(val, 0.0, 1.0)
	_update_ambient_volumes(0.0)

func set_weather_rain(is_raining: bool, rain_intensity: float = 1.0) -> void:
	var changed := is_raining != _is_raining or absf(rain_intensity - _rain_intensity) > 0.05
	_is_raining = is_raining
	_rain_intensity = clampf(rain_intensity, 0.3, 1.0)
	if not _ambient_rain_player or DisplayServer.get_name() == "headless":
		return
	if changed:
		_update_ambient_volumes(2.5)

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

func _setup_audio_players() -> void:
	for i in range(max_sfx_voices):
		_sfx_players.append(_make_player())
	_ambient_wind_player = _make_player()
	_ambient_rain_player = _make_player()
	_ambient_birds_player = _make_player()

func _load_all_sounds() -> void:
	var names: Array = SOUNDS.keys() + AMBIENT
	for n in names:
		var arr: Array = []
		for path in paths_for(n):
			if ResourceLoader.exists(path):
				var s := load(path) as AudioStream
				if s:
					arr.append(s)
			else:
				push_warning("AudioManager: нет файла звука " + path)
		if not arr.is_empty():
			_sounds[n] = arr

func _ambient_targets() -> Dictionary:
	var base := ambient_volume * master_volume
	return {
		_ambient_wind_player: base * (0.55 if _is_raining else 0.4),
		_ambient_rain_player: base * _rain_intensity * 0.8 if _is_raining else 0.0,
		_ambient_birds_player: 0.0 if _is_raining else base * 0.35,
	}

func _update_ambient_volumes(fade_sec: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _ambient_tween and _ambient_tween.is_valid():
		_ambient_tween.kill()
	var targets := _ambient_targets()
	if fade_sec > 0.0 and is_inside_tree():
		_ambient_tween = create_tween().set_parallel(true)
	for p: AudioStreamPlayer in targets:
		if p == null or p.stream == null:
			continue
		var target_db := linear_to_db(maxf(0.0005, targets[p]))
		if targets[p] > 0.001 and not p.playing:
			p.volume_db = -60.0 if fade_sec > 0.0 else target_db
			p.play(randf() * maxf(0.0, p.stream.get_length() - 1.0))
		if fade_sec > 0.0 and _ambient_tween:
			_ambient_tween.tween_property(p, "volume_db", target_db, fade_sec)
		else:
			p.volume_db = target_db
	if _ambient_tween:
		_ambient_tween.chain().tween_callback(_stop_silent_ambient)
	else:
		_stop_silent_ambient()

func _stop_silent_ambient() -> void:
	var targets := _ambient_targets()
	for p: AudioStreamPlayer in targets:
		if p and p.playing and targets[p] <= 0.001:
			p.stop()

func _start_ambient() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var pairs := {_ambient_wind_player: "wind_ambient", _ambient_rain_player: "rain_ambient",
		_ambient_birds_player: "birds_ambient"}
	for p: AudioStreamPlayer in pairs:
		if _sounds.has(pairs[p]):
			p.stream = _sounds[pairs[p]][0]
	_update_ambient_volumes(0.0)
