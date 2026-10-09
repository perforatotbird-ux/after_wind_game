extends RefCounted

## Настройки игры: звук, экран, интерфейс, чувствительность камеры и скорость времени.
## Хранятся в user://settings.cfg (ConfigFile, секция [settings]) и применяются
## при запуске мира (world.gd) и при каждом изменении в окне настроек.
## В headless-режиме параметры окна не трогаются.

const AudioManager = preload("res://scripts/audio/audio_manager.gd")

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
## Базовая чувствительность IsometricCamera; в настройках хранится множитель.
const BASE_MOUSE_SENSITIVITY: float = 0.005
const MOUSE_SENSITIVITY_MIN: float = 0.25
const MOUSE_SENSITIVITY_MAX: float = 3.0
## Скорость игрового времени: сколько реальных секунд длится 1 игровой час.
## По умолчанию 60 с (1 игровой час = 1 минута, сутки = 24 мин).
const GAME_HOUR_PRESETS: Array = [20.0, 30.0, 45.0, 60.0, 90.0, 120.0, 180.0]
const GAME_HOUR_MIN: float = 10.0
const GAME_HOUR_MAX: float = 600.0
## Масштаб интерфейса поверх автоматического (окно растягивается от базы 1600×900).
const UI_SCALE_MIN: float = 0.75
const UI_SCALE_MAX: float = 1.5
const RESOLUTIONS: Array = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

## resolution_index = -1 — не менять размер окна (как в project.godot).
const DEFAULTS: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 0.8,
	"ambient_volume": 0.6,
	"fullscreen": false,
	"resolution_index": -1,
	"vsync": true,
	"mouse_sensitivity": 1.0,
	"seconds_per_game_hour": 60.0,
	"ui_scale": 1.0,
}

## Путь можно подменить в тестах.
static var settings_path: String = SETTINGS_PATH
static var _values: Dictionary = {}
static var _loaded: bool = false

static func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, key):
			_values[key] = _sanitize(key, cfg.get_value(SECTION, key))

static func save_settings() -> bool:
	_ensure_loaded()
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	return cfg.save(settings_path) == OK

static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))

## Устанавливает значение (с проверкой диапазона), сохраняет файл и применяет его.
static func set_value(key: String, value: Variant, tree: SceneTree = null) -> void:
	if not DEFAULTS.has(key):
		return
	_ensure_loaded()
	_values[key] = _sanitize(key, value)
	save_settings()
	apply_key(key, tree)

static func reset_to_defaults(tree: SceneTree = null) -> void:
	_values = DEFAULTS.duplicate(true)
	_loaded = true
	save_settings()
	apply(tree)

static func get_mouse_sensitivity() -> float:
	return BASE_MOUSE_SENSITIVITY * float(get_value("mouse_sensitivity"))

static func get_seconds_per_game_hour() -> float:
	return float(get_value("seconds_per_game_hour"))

## Подписи пресетов скорости времени для выпадающего списка настроек.
static func get_game_hour_labels() -> Array[String]:
	var labels: Array[String] = []
	for sec in GAME_HOUR_PRESETS:
		labels.append(format_game_hour(float(sec)))
	return labels

## «1 мин — сутки 24 мин»: длительность часа и суток в реальном времени.
static func format_game_hour(sec: float) -> String:
	var hour_text: String = ("%d с" % int(sec)) if sec < 60.0 else (("%d мин" % int(sec / 60.0)) if is_equal_approx(fmod(sec, 60.0), 0.0) else ("%.1f мин" % (sec / 60.0)))
	var day_min: float = sec * 24.0 / 60.0
	var day_text: String = ("%d мин" % int(round(day_min))) if day_min < 60.0 else ("%.1f ч" % (day_min / 60.0)).replace(".0 ч", " ч")
	var suffix: String = " (по умолчанию)" if is_equal_approx(sec, float(DEFAULTS["seconds_per_game_hour"])) else ""
	return "%s — сутки %s%s" % [hour_text, day_text, suffix]

## Индекс ближайшего пресета к текущему значению.
static func get_game_hour_preset_index() -> int:
	var cur: float = get_seconds_per_game_hour()
	var best: int = 0
	for i in GAME_HOUR_PRESETS.size():
		if absf(float(GAME_HOUR_PRESETS[i]) - cur) < absf(float(GAME_HOUR_PRESETS[best]) - cur):
			best = i
	return best

static func get_resolution_labels() -> Array[String]:
	var labels: Array[String] = ["Как в проекте"]
	for r in RESOLUTIONS:
		labels.append("%d × %d" % [r.x, r.y])
	return labels

# --- Применение ---

static func apply(tree: SceneTree = null) -> void:
	apply_audio()
	apply_display()
	apply_ui_scale(tree)
	apply_camera(tree)
	apply_time(tree)

static func apply_key(key: String, tree: SceneTree = null) -> void:
	match key:
		"master_volume", "sfx_volume", "ambient_volume":
			apply_audio()
		"fullscreen", "resolution_index", "vsync":
			apply_display()
		"mouse_sensitivity":
			apply_camera(tree)
		"seconds_per_game_hour":
			apply_time(tree)
		"ui_scale":
			apply_ui_scale(tree)

## Длительность игрового часа -> DayNightCycle (группа "day_night_cycle").
static func apply_time(tree: SceneTree = null) -> void:
	if tree == null:
		return
	var sec: float = get_seconds_per_game_hour()
	for cycle in tree.get_nodes_in_group("day_night_cycle"):
		if cycle.has_method("set_seconds_per_game_hour"):
			cycle.set_seconds_per_game_hour(sec)

## Дополнительный множитель масштаба интерфейса (база растяжения — project.godot).
static func apply_ui_scale(tree: SceneTree = null) -> void:
	if tree == null or tree.root == null:
		return
	tree.root.content_scale_factor = float(get_value("ui_scale"))

static func apply_audio() -> void:
	var am = AudioManager.instance
	if not is_instance_valid(am):
		return
	am.master_volume = float(get_value("master_volume"))
	am.set_sfx_vol(float(get_value("sfx_volume")))
	# set_ambient_vol пересчитывает громкость фона с учётом master_volume.
	am.set_ambient_vol(float(get_value("ambient_volume")))

static func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("vsync")) else DisplayServer.VSYNC_DISABLED)
	if bool(get_value("fullscreen")):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var idx: int = int(get_value("resolution_index"))
	if idx >= 0 and idx < RESOLUTIONS.size():
		var size: Vector2i = RESOLUTIONS[idx]
		DisplayServer.window_set_size(size)
		var screen_rect := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen_rect.position + (screen_rect.size - size) / 2)

static func apply_camera(tree: SceneTree = null) -> void:
	if tree == null or tree.current_scene == null:
		return
	var cam = tree.current_scene.get_node_or_null("IsometricCamera")
	if cam != null and "mouse_sensitivity" in cam:
		cam.mouse_sensitivity = get_mouse_sensitivity()

# --- Вспомогательное ---

static func _ensure_loaded() -> void:
	if not _loaded:
		load_settings()

static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _sanitize(key: String, value: Variant) -> Variant:
	match key:
		"master_volume", "sfx_volume", "ambient_volume":
			if _is_number(value):
				return clampf(float(value), 0.0, 1.0)
		"mouse_sensitivity":
			if _is_number(value):
				return clampf(float(value), MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
		"seconds_per_game_hour":
			if _is_number(value):
				return clampf(float(value), GAME_HOUR_MIN, GAME_HOUR_MAX)
		"ui_scale":
			if _is_number(value):
				return clampf(float(value), UI_SCALE_MIN, UI_SCALE_MAX)
		"fullscreen", "vsync":
			if typeof(value) == TYPE_BOOL:
				return value
		"resolution_index":
			if _is_number(value):
				return clampi(int(value), -1, RESOLUTIONS.size() - 1)
	return DEFAULTS.get(key)
