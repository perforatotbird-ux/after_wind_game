extends RefCounted

## Система сезонов и погоды (раздел 9 мастер-плана GAME_EXPANSION_MASTERPLAN).
## Подключение: const Seasons = preload("res://scripts/core/seasons.gd").
##
## Календарь: 4 сезона по 7 игровых дней, полный год = 28 игровых дней.
## Абсолютный игровой день (1-based) однозначно определяет сезон, день в сезоне,
## день года и номер года — set_calendar(day).
##
## Текущий сезон; "" — система сезонов выключена (обратная совместимость):
## тогда is_in_season() всегда true, а все множители нейтральны (1.0),
## температурное смещение 0. Так seasons-зависимый код работает круглый год.
##
## Сезон задаёт:
##   base_temp      — базовая температура воздуха, °C (к ней HUD прибавляет
##                    погодное и суточное смещение);
##   temp_offset    — поправка к температуре HUD относительно нейтральной фазы;
##   rain_chance    — вероятность дождливой погоды в сезоне (0..1);
##   growth         — множитель роста культур (весна ×1.3, зима ×0.4);
##   evaporation    — множитель испарения воды с грядок (лето ×2, засуха ×3);
##   forage         — множитель сбора ягод и грибов (осень ×2);
##   water_freeze   — замерзают ли открытые источники воды.

const SPRING: String = "spring"
const SUMMER: String = "summer"
const AUTUMN: String = "autumn"
const WINTER: String = "winter"
const ALL: Array[String] = [SPRING, SUMMER, AUTUMN, WINTER]
const NAMES: Dictionary = {SPRING: "весна", SUMMER: "лето", AUTUMN: "осень", WINTER: "зима"}
const ICONS: Dictionary = {SPRING: "🌱", SUMMER: "☀️", AUTUMN: "🍂", WINTER: "❄️"}

const DAYS_PER_SEASON: int = 7
const DAYS_PER_YEAR: int = DAYS_PER_SEASON * 4

## Базовая температура нейтрального дня: поправки seasons temp_offset считаются от неё.
const NEUTRAL_TEMPERATURE: float = 12.0

const SEASON_DATA: Dictionary = {
	SPRING: {
		"name": "весна",
		"icon": "🌱",
		"base_temp": 12.0,
		"temp_offset": 0,
		"rain_chance": 0.45,
		"growth": 1.3,
		"evaporation": 1.0,
		"forage": 1.0,
		"water_freeze": false,
		"summary": "Посадка, высокая влажность — всё растёт быстрее",
	},
	SUMMER: {
		"name": "лето",
		"icon": "☀️",
		"base_temp": 24.0,
		"temp_offset": 6,
		"rain_chance": 0.15,
		"growth": 1.0,
		"evaporation": 2.0,
		"forage": 1.0,
		"water_freeze": false,
		"summary": "Жарко и сухо — грядки сохнут вдвое быстрее",
	},
	AUTUMN: {
		"name": "осень",
		"icon": "🍂",
		"base_temp": 9.0,
		"temp_offset": -3,
		"rain_chance": 0.40,
		"growth": 1.0,
		"evaporation": 1.0,
		"forage": 2.0,
		"water_freeze": false,
		"summary": "Прохладно, часто дожди — урожай фруктов и грибов ×2",
	},
	WINTER: {
		"name": "зима",
		"icon": "❄️",
		"base_temp": -6.0,
		"temp_offset": -12,
		"rain_chance": 0.50,
		"growth": 0.4,
		"evaporation": 0.4,
		"forage": 0.5,
		"water_freeze": true,
		"summary": "Холодно, снег — рост замедлен, открытая вода замёрзла",
	},
}

## Текущий сезон; "" — система сезонов ещё не подключена.
static var current_season: String = ""
## День внутри текущего сезона, 1..DAYS_PER_SEASON.
static var day_in_season: int = 1
## День внутри года, 1..DAYS_PER_YEAR.
static var day_of_year: int = 1
## Номер года, начиная с 1.
static var year: int = 1

static func is_enabled() -> bool:
	return current_season != ""

static func get_current_season() -> String:
	return current_season

## true, если сейчас один из сезонов списка (без системы сезонов — всегда true).
static func is_in_season(seasons: Array) -> bool:
	if not is_enabled():
		return true
	return seasons.has(current_season)

static func describe(seasons: Array) -> String:
	var parts: PackedStringArray = []
	for s in seasons:
		parts.append(NAMES.get(s, str(s)))
	return ", ".join(parts)

# --- Календарь -----------------------------------------------------------------

## Сезон для абсолютного игрового дня (1-based). Дни идут весна → лето → осень → зима.
static func season_for_day(day: int) -> String:
	var index: int = (maxi(1, day) - 1) % DAYS_PER_YEAR
	return ALL[index / DAYS_PER_SEASON]

## День внутри сезона для абсолютного игрового дня, 1..DAYS_PER_SEASON.
static func day_in_season_for_day(day: int) -> int:
	var index: int = (maxi(1, day) - 1) % DAYS_PER_YEAR
	return (index % DAYS_PER_SEASON) + 1

static func day_of_year_for_day(day: int) -> int:
	return ((maxi(1, day) - 1) % DAYS_PER_YEAR) + 1

static func year_for_day(day: int) -> int:
	return ((maxi(1, day) - 1) / DAYS_PER_YEAR) + 1

## Переводит календарь на абсолютный игровой день day (1-based) и включает систему.
static func set_calendar(day: int) -> String:
	var safe_day: int = maxi(1, day)
	day_in_season = day_in_season_for_day(safe_day)
	day_of_year = day_of_year_for_day(safe_day)
	year = year_for_day(safe_day)
	current_season = season_for_day(safe_day)
	return current_season

## Включает систему сезонов на заданном сезоне и дне (1-based).
static func activate(season: String = SPRING, day: int = 1) -> void:
	var index: int = maxi(0, ALL.find(season)) if ALL.has(season) else 0
	var clamped_day: int = clampi(day, 1, DAYS_PER_SEASON)
	day_in_season = clamped_day
	day_of_year = index * DAYS_PER_SEASON + clamped_day
	year = 1
	current_season = ALL[index]

## Выключает систему сезонов (обратная совместимость: всё растёт круглый год).
static func disable() -> void:
	current_season = ""
	day_in_season = 1
	day_of_year = 1
	year = 1

static func get_day_in_season() -> int:
	return day_in_season

static func get_day_of_year() -> int:
	return day_of_year

static func get_year() -> int:
	return year

## Сколько игровых дней осталось до конца сезона (сегодняшний день не считается).
static func get_days_until_next_season() -> int:
	return DAYS_PER_SEASON - day_in_season

## Доля пройденного сезона 0..1 — для полосы прогресса в интерфейсе.
static func get_season_progress() -> float:
	if not is_enabled():
		return 0.0
	return float(day_in_season - 1) / float(DAYS_PER_SEASON)

static func get_season_name(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	return str(SEASON_DATA.get(key, {}).get("name", NAMES.get(key, key)))

static func get_season_icon(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	return str(SEASON_DATA.get(key, {}).get("icon", ICONS.get(key, "🌡️")))

## «🌱 весна» — иконка и имя текущего (или заданного) сезона.
static func get_season_caption(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	if key == "":
		return ""
	return "%s %s" % [get_season_icon(key), get_season_name(key)]

## Подпись календаря для HUD: «🌱 весна · день 3/7».
static func get_calendar_caption() -> String:
	if not is_enabled():
		return ""
	return "%s %s · день %d/%d" % [
		get_season_icon(), get_season_name(), day_in_season, DAYS_PER_SEASON
	]

static func get_summary(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	return str(SEASON_DATA.get(key, {}).get("summary", ""))

static func next_season(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	var index: int = ALL.find(key)
	if index < 0:
		return SPRING
	return ALL[(index + 1) % ALL.size()]

static func previous_season(season: String = "") -> String:
	var key: String = season if season != "" else current_season
	var index: int = ALL.find(key)
	if index < 0:
		return WINTER
	return ALL[(index - 1 + ALL.size()) % ALL.size()]

# --- Множители и погода --------------------------------------------------------

static func get_data(season: String = "") -> Dictionary:
	var key: String = season if season != "" else current_season
	return SEASON_DATA.get(key, {})

## Множитель из data по ключу key; без системы сезонов — нейтральное значение.
static func _factor(key: String, neutral: float) -> float:
	if not is_enabled():
		return neutral
	return float(SEASON_DATA.get(current_season, {}).get(key, neutral))

## Рост культур: весна ×1.3, лето/осень ×1.0, зима ×0.4.
static func get_growth_multiplier() -> float:
	return _factor("growth", 1.0)

## Испарение воды с грядок: лето ×2, зима ×0.4.
static func get_evaporation_multiplier() -> float:
	return _factor("evaporation", 1.0)

## Сбор ягод и грибов: осень ×2, зима ×0.5.
static func get_forage_multiplier() -> float:
	return _factor("forage", 1.0)

## Вероятность дождливой погоды в сезоне 0..1 (зимой — снегопада).
static func get_rain_chance() -> float:
	return _factor("rain_chance", 0.0)

## Базовая температура сезона, °C (без системы сезонов — нейтральная).
static func get_base_temperature() -> float:
	return _factor("base_temp", NEUTRAL_TEMPERATURE)

## Поправка к температуре HUD относительно нейтрального дня, °C.
static func get_temperature_offset() -> int:
	if not is_enabled():
		return 0
	return int(SEASON_DATA.get(current_season, {}).get("temp_offset", 0))

## Замерзают ли открытые источники воды в этом сезоне.
static func water_freezes() -> bool:
	if not is_enabled():
		return false
	return bool(SEASON_DATA.get(current_season, {}).get("water_freeze", false))