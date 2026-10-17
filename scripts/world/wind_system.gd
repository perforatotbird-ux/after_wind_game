class_name WindSystem
extends Node

## Динамическая система ветра (Разделы 54, 57, 84 дизайн-документа).
##
## Ветер — отдельная величина мира (м/с), из которой ветряк считает выработку.
## Скорость складывается из четырёх слоёв и пересчитывается каждый кадр:
##   * база погоды (ясно 2, пасмурно 5, дождь 9, ливень 15, снег 10 м/с);
##   * множитель сезона (осень ×1.3, зима ×1.2, весна ×1.0, лето ×0.7);
##   * множитель погодного события (ураган ×2.0, гроза ×1.35, метель ×1.25,
##     засуха ×0.3);
##   * суточный множитель (днём ×1.1, ночью ×0.85 — дневной бриз).
## К цели ветер идёт плавно (approach_seconds), а поверх базы накладываются
## порывы (шум FastNoiseLite, ±30 %), поэтому стрелка «дышит», а не скачет.
##
## Ветряк берёт силу ветра отсюда через группу `wind_system`. Тесты и отладка
## могут форсировать точное значение методом set_wind_speed (порывы при этом
## выключаются до смены погоды).

const Seasons = preload("res://scripts/core/seasons.gd")
const WeatherManagerScript = preload("res://scripts/world/weather_manager.gd")

const GROUP: String = "wind_system"

signal wind_changed(speed: float, gusting: bool)

## Базовая скорость ветра по типу погоды, м/с.
const WEATHER_BASE_WIND: Dictionary = {
	WeatherManagerScript.WeatherType.SUNNY: 2.0,
	WeatherManagerScript.WeatherType.OVERCAST: 5.0,
	WeatherManagerScript.WeatherType.RAIN: 9.0,
	WeatherManagerScript.WeatherType.HEAVY_RAIN: 15.0,
	WeatherManagerScript.WeatherType.SNOW: 10.0,
}

## Множитель сезона: осенью и зимой ветрено, летом затишье.
const SEASON_WIND_MULT: Dictionary = {
	Seasons.SPRING: 1.0,
	Seasons.SUMMER: 0.7,
	Seasons.AUTUMN: 1.3,
	Seasons.WINTER: 1.2,
}

## Множитель погодного события (гроза/засуха/метель/ураган).
const EVENT_WIND_MULT: Dictionary = {
	"storm": 1.35,
	"drought": 0.3,
	"blizzard": 1.25,
	"hurricane": 2.0,
}

const DAY_MULT: float = 1.1
const NIGHT_MULT: float = 0.85
const DAY_START_HOUR: int = 7
const DAY_END_HOUR: int = 19

## Размах порывов вокруг базовой скорости (доля) и его границы.
const GUST_STRENGTH: float = 0.3
const GUST_MIN_FACTOR: float = 0.7
const GUST_MAX_FACTOR: float = 1.3

## Границы Бофорта в м/с и названия степеней для интерфейса.
const BEAUFORT_LIMITS: Array[float] = [0.5, 2.0, 4.0, 6.0, 8.0, 11.0, 14.0, 17.0, 21.0, 25.0, 29.0, 33.0]
const BEAUFORT_NAMES: Array[String] = [
	"Штиль", "Тихий", "Лёгкий", "Слабый", "Умеренный", "Свежий",
	"Сильный", "Крепкий", "Очень крепкий", "Штормовой", "Сильный шторм",
	"Жестокий шторм", "Ураган",
]

@export var enabled: bool = true
@export var max_wind: float = 30.0
## За сколько реальных секунд ветер выходит на новую погоду.
@export var approach_seconds: float = 45.0
@export var gusts_enabled: bool = true

## Базовая (сглаженная) скорость ветра без порывов, м/с.
var wind_speed: float = 0.0
var _target_wind: float = 0.0
## Форсированное значение (тесты/отладка): погода и порывы не влияют.
var _override: bool = false
var _elapsed: float = 0.0
var _noise: FastNoiseLite
var _last_emitted_speed: float = -1.0
var _last_emitted_gusting: bool = false
var _weather_mgr: Node = null
var _season_mgr: Node = null
var _day_cycle: Node = null

func _ready() -> void:
	add_to_group(GROUP)
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.05
	_noise.fractal_octaves = 2
	_bind_nodes()
	# На старте ветер уже соответствует погоде — без разгона от нуля.
	_target_wind = _compute_target()
	wind_speed = _target_wind

func _bind_nodes() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_weather_mgr = tree.get_first_node_in_group("weather_manager")
	_season_mgr = tree.get_first_node_in_group("season_manager")
	_day_cycle = tree.get_first_node_in_group("day_night_cycle")
	if _weather_mgr and _weather_mgr.has_signal("weather_changed"):
		if not _weather_mgr.weather_changed.is_connected(_on_weather_changed):
			_weather_mgr.weather_changed.connect(_on_weather_changed)

## Смена погоды снимает форсированное значение: ветер снова живой.
func _on_weather_changed(_weather: int, _name: String, _icon: String) -> void:
	_override = false
	_target_wind = _compute_target()

func _process(delta: float) -> void:
	if not enabled:
		return
	if _weather_mgr == null:
		_bind_nodes()
	if not _override:
		_target_wind = _compute_target()
		var step: float = clampf(delta / maxf(1.0, approach_seconds), 0.0, 1.0)
		wind_speed = clampf(lerpf(wind_speed, _target_wind, step), 0.0, max_wind)
	_elapsed += delta
	_emit_if_changed()

# --- Публичный API --------------------------------------------------------------

## Текущая скорость ветра с порывами, м/с.
func get_wind_speed() -> float:
	return clampf(wind_speed * _gust_factor(), 0.0, max_wind)

## Доля от максимальной скорости ветра 0..1 (для полос и порогов).
func get_wind_ratio() -> float:
	return get_wind_speed() / maxf(0.01, max_wind)

## Степень по шкале Бофорта 0..12.
func get_beaufort() -> int:
	var speed: float = get_wind_speed()
	for i in BEAUFORT_LIMITS.size():
		if speed < BEAUFORT_LIMITS[i]:
			return i
	return BEAUFORT_NAMES.size() - 1

func get_wind_name() -> String:
	return BEAUFORT_NAMES[clampi(get_beaufort(), 0, BEAUFORT_NAMES.size() - 1)]

## Идёт ли сейчас порыв (отклонение от базы больше 8 %).
func is_gusting() -> bool:
	return gusts_enabled and not _override and absf(_gust_factor() - 1.0) > 0.08

## Слабее порога wind — ветряк простаивает (затишье).
func is_calm(threshold: float = 3.0) -> bool:
	return get_wind_speed() < threshold

## «💨 Ветер: 8.4 м/с (свежий)» — строка для HUD и подсказок.
func get_status_text() -> String:
	return "💨 Ветер: %.1f м/с (%s)" % [get_wind_speed(), get_wind_name().to_lower()]

## Форсирует точное значение ветра (тесты/отладка). Порывы и погода выключены
## до первой смены погоды или clear_override().
func set_wind_speed(value: float) -> void:
	_override = true
	wind_speed = clampf(value, 0.0, max_wind)
	_target_wind = wind_speed
	_emit_if_changed(true)

func clear_override() -> void:
	_override = false
	_target_wind = _compute_target()

func is_forced() -> bool:
	return _override

# --- Слои скорости -------------------------------------------------------------

## Базовая скорость текущей погоды (без сезона/событий/суток), м/с.
func get_weather_base_wind() -> float:
	var weather: int = int(WeatherManagerScript.WeatherType.SUNNY)
	if _weather_mgr and "current_weather" in _weather_mgr:
		weather = int(_weather_mgr.current_weather)
	return float(WEATHER_BASE_WIND.get(weather, 2.0))

func get_season_multiplier() -> float:
	if not Seasons.is_enabled():
		return 1.0
	return float(SEASON_WIND_MULT.get(Seasons.get_current_season(), 1.0))

func get_event_multiplier() -> float:
	if _season_mgr == null or not _season_mgr.has_method("get_active_event"):
		return 1.0
	return float(EVENT_WIND_MULT.get(str(_season_mgr.get_active_event()), 1.0))

func get_day_multiplier() -> float:
	if _day_cycle == null or not ("current_hour" in _day_cycle):
		return 1.0
	var hour: int = int(_day_cycle.current_hour)
	if hour >= DAY_START_HOUR and hour <= DAY_END_HOUR:
		return DAY_MULT
	return NIGHT_MULT

func _compute_target() -> float:
	var base: float = get_weather_base_wind()
	var mult: float = get_season_multiplier() * get_event_multiplier() * get_day_multiplier()
	return clampf(base * mult, 0.0, max_wind)

func _gust_factor() -> float:
	if not gusts_enabled or _override or _noise == null:
		return 1.0
	return clampf(1.0 + _noise.get_noise_1d(_elapsed) * GUST_STRENGTH, GUST_MIN_FACTOR, GUST_MAX_FACTOR)

# --- Уведомления и сохранение --------------------------------------------------

func _emit_if_changed(force: bool = false) -> void:
	var speed: float = get_wind_speed()
	var gusting: bool = is_gusting()
	if force or absf(speed - _last_emitted_speed) >= 0.1 or gusting != _last_emitted_gusting:
		_last_emitted_speed = speed
		_last_emitted_gusting = gusting
		wind_changed.emit(speed, gusting)

func get_save_state() -> Dictionary:
	return {"wind_speed": wind_speed}

## Сейв восстанавливает уже установившуюся скорость; дальше ветер снова живой.
func apply_save_state(state: Dictionary) -> void:
	wind_speed = clampf(float(state.get("wind_speed", 0.0)), 0.0, max_wind)
	_target_wind = _compute_target()
	_override = false
