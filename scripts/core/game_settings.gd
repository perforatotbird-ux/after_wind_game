extends RefCounted

## Настройки игры: звук, экран, чувствительность камеры.
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

static func get_resolution_labels() -> Array[String]:
	var labels: Array[String] = ["Как в проекте"]
	for r in RESOLUTIONS:
		labels.append("%d × %d" % [r.x, r.y])
	return labels

# --- Применение ---

static func apply(tree: SceneTree = null) -> void:
	apply_audio()
	apply_display()
	apply_camera(tree)

static func apply_key(key: String, tree: SceneTree = null) -> void:
	match key:
		"master_volume", "sfx_volume", "ambient_volume":
			apply_audio()
		"fullscreen", "resolution_index", "vsync":
			apply_display()
		"mouse_sensitivity":
			apply_camera(tree)

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
		"fullscreen", "vsync":
			if typeof(value) == TYPE_BOOL:
				return value
		"resolution_index":
			if _is_number(value):
				return clampi(int(value), -1, RESOLUTIONS.size() - 1)
	return DEFAULTS.get(key)
