class_name SeasonManager
extends Node

## Менеджер сезонов и погодных событий (раздел 9 мастер-плана, разделы 12.3 и 13.4).
## Следит за календарём (4 сезона × 7 игровых дней = 28 дней в году), публикует
## текущий сезон в Seasons и запускает погодные события: гроза, засуха, метель, ураган.
## Отдельный узел нужен, потому что Seasons — статический класс: сам календарь
## ведёт узел, а статика хранит только текущее значения для быстрых проверок.
##
## Узел в мире: world.tscn → «SeasonManager». Многие системы берут множители
## не от узла, а от Seasons (им не нужен узел) — см. Seasons.get_growth_multiplier().
## Множители событий (засуха ×3 испарения, метель ×2 урона от холода) доступны
## только через узел, потому что событие — состояние мира.

const Seasons = preload("res://scripts/core/seasons.gd")
const AudioManager = preload("res://scripts/audio/audio_manager.gd")
const DroppedItemScript = preload("res://scripts/inventory/dropped_item.gd")

## Погодные события. Длительность в игровых часах (дни — для засухи).
## chance — вероятность старта события в игровой день (0..1), только для своего сезона.
const EVENTS: Dictionary = {
	"storm": {
		"name": "Гроза",
		"icon": "⛈️",
		"seasons": [Seasons.SPRING, Seasons.SUMMER],
		"chance": 0.14,
		"min_hours": 2.0,
		"max_hours": 6.0,
		"message": "⛈️ Гроза: ливень с громом. Следите за деревьями — молния бьёт по ним!",
	},
	"drought": {
		"name": "Засуха",
		"icon": "🥵",
		"seasons": [Seasons.SUMMER],
		"chance": 0.20,
		"min_hours": 72.0, # 3 дня
		"max_hours": 120.0, # 5 дней
		"message": "🥵 Засуха: дождя не будет несколько дней. Грядки сохнут втрое быстрее!",
	},
	"blizzard": {
		"name": "Метель",
		"icon": "🌨️",
		"seasons": [Seasons.WINTER],
		"chance": 0.22,
		"min_hours": 4.0,
		"max_hours": 12.0,
		"message": "🌨️ Метель: холод ×2, видимость падает. К печи или в дом!",
	},
	"hurricane": {
		"name": "Ураган",
		"icon": "🌀",
		"seasons": [Seasons.AUTUMN],
		"chance": 0.07,
		"min_hours": 2.0,
		"max_hours": 4.0,
		"message": "🌀 Ураган! Крыша и забор повреждены, ресурсы разбросаны.",
	},
}
const ALL_EVENTS: Array[String] = ["storm", "drought", "blizzard", "hurricane"]

signal season_changed(season: String, season_name: String, day_in_season: int)
signal day_started(day_in_season: int, total_day: int)
signal weather_event_started(event_id: String, event_name: String)
signal weather_event_ended(event_id: String)
signal calendar_changed()

const GROUP: String = "season_manager"
## Запасная скорость игрового времени (1 игровой час = 60 с), если нет DayNightCycle.
const FALLBACK_HOURS_PER_SECOND: float = 1.0 / 60.0
## Множители событий.
const DROUGHT_EVAPORATION: float = 3.0
const BLIZZARD_COLD: float = 2.0
const BLIZZARD_SPEED: float = 0.85
const HURRICANE_EVAPORATION: float = 2.0
const HURRICANE_SPEED: float = 0.9
## Доля запасов, разбрасываемых ураганом.
const HURRICANE_SCATTER: float = 0.15
## Вероятность, что молния подожжёт одно дерево за грозу.
const LIGHTNING_CHANCE: float = 0.35
## Вспышки молний посреди грозы: интервал в игровых часах (0.12–0.3 ч —
## каждые ~7–18 реальных секунд). Каждая вспышка видна (HUD), каждая третья
## в среднем бьёт по дереву — гроза ощущается, а не только числится.
const STORM_FLASH_MIN_HOURS: float = 0.12
const STORM_FLASH_MAX_HOURS: float = 0.3

@export_group("Calendar")
## Сезоны включены с начала игры (Глава 3 мастер-плана).
@export var enabled: bool = true
## Абсолютный игровой день, с которого начинается календарь (1 = весна, 1-й день).
@export var start_day: int = 1

@export_group("Weather Events")
@export var events_enabled: bool = true
## 0 — случайный сид, иначе фиксированный (для тестов и воспроизводимости).
@export var rng_seed: int = 0

var total_day: int = 1
## Идентификатор активного события ("" — событий нет).
var active_event: String = ""
## Сколько игровых часов осталось активному событию.
var event_hours_left: float = 0.0
## Сколько вспышек молний уже было за текущую грозу (телеметрия/тесты).
var storm_flashes: int = 0
var _storm_next_flash: float = 0.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _day_cycle: Node = null
var _weather_mgr: Node = null
var _applied_season: String = ""

func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = rng_seed if rng_seed != 0 else randi()
	_bind_nodes()
	_apply_calendar(true)

## Ищет DayNightCycle/WeatherManager рядом и подписывается на смену суток.
func _bind_nodes() -> void:
	if not is_instance_valid(_day_cycle) and get_parent():
		_day_cycle = get_parent().get_node_or_null("DayNightCycle")
	if not is_instance_valid(_weather_mgr) and get_parent():
		_weather_mgr = get_parent().get_node_or_null("WeatherManager")
	if _day_cycle and not _day_cycle.day_passed.is_connected(_on_day_passed):
		_day_cycle.day_passed.connect(_on_day_passed)

func _process(delta: float) -> void:
	if active_event == "":
		return
	var hours: float = delta * get_hours_per_second()
	event_hours_left -= hours
	if active_event == "storm":
		_storm_next_flash -= hours
		if _storm_next_flash <= 0.0:
			_storm_next_flash = _rng.randf_range(STORM_FLASH_MIN_HOURS, STORM_FLASH_MAX_HOURS)
			_storm_flash()
	if event_hours_left <= 0.0:
		_finish_event()

func get_hours_per_second() -> float:
	if not is_instance_valid(_day_cycle):
		_bind_nodes()
	if _day_cycle and _day_cycle.has_method("get_hours_per_second"):
		return float(_day_cycle.get_hours_per_second())
	return FALLBACK_HOURS_PER_SECOND

# --- Календарь -----------------------------------------------------------------

## Переводит календарь на игровой день day (1-based) и обновляет мир.
func set_total_day(day: int, force: bool = false) -> bool:
	var safe_day: int = maxi(1, day)
	var changed: bool = safe_day != total_day
	total_day = safe_day
	if enabled:
		_apply_calendar(force)
	elif not force:
		clear_calendar()
	return changed

func _on_day_passed(new_day: int) -> void:
	var changed: bool = set_total_day(new_day, false)
	if changed and enabled:
		day_started.emit(Seasons.get_day_in_season(), total_day)
		_roll_weather_event()
	_push_to_world()

## Пересчитывает Seasons по текущему дню; season_changed — только при смене сезона.
func _apply_calendar(force: bool) -> void:
	if not enabled:
		clear_calendar()
		return
	var season: String = Seasons.season_for_day(total_day)
	Seasons.set_calendar(total_day)
	var is_new_season: bool = season != _applied_season
	_applied_season = season
	if is_new_season or force:
		_apply_season_visuals(season)
		season_changed.emit(season, Seasons.get_season_name(season), Seasons.get_day_in_season())
	calendar_changed.emit()

func clear_calendar() -> void:
	if _applied_season != "":
		_applied_season = ""
		_apply_season_visuals("")
	Seasons.disable()
	calendar_changed.emit()

## Подкрашивает небо и солнце под сезон (суточный цикл продолжает считать своё).
func _apply_season_visuals(season: String) -> void:
	if not is_instance_valid(_day_cycle):
		_bind_nodes()
	if _day_cycle and _day_cycle.has_method("set_season_tint"):
		_day_cycle.set_season_tint(season)

## День начала сезона (новый год / новая смена сезона) — для уведомлений.
func _push_to_world() -> void:
	var hud: Node = get_parent().get_node_or_null("HUD") if get_parent() else null
	if hud and hud.has_method("update_season_display"):
		hud.update_season_display()

# --- Погодные события ----------------------------------------------------------

## Шанс старта события в текущем сезоне (для тестов и отладки).
func get_event_chance(event_id: String) -> float:
	if not events_enabled or not Seasons.is_enabled():
		return 0.0
	var data: Dictionary = EVENTS.get(event_id, {})
	var seasons: Array = data.get("seasons", [])
	if not Seasons.is_in_season(seasons):
		return 0.0
	return float(data.get("chance", 0.0))

func _roll_weather_event() -> void:
	if active_event != "":
		return
	for event_id in ALL_EVENTS:
		if _rng.randf() < get_event_chance(event_id):
			start_event(event_id)
			return

## Запускает погодное событие (id из EVENTS). Возвращает false, если нельзя.
func start_event(event_id: String, duration_hours: float = -1.0) -> bool:
	if not EVENTS.has(event_id):
		return false
	var data: Dictionary = EVENTS[event_id]
	if active_event == event_id:
		return false
	if active_event != "":
		_finish_event(true)
	active_event = event_id
	event_hours_left = duration_hours if duration_hours > 0.0 else _roll_duration(data)
	if event_id == "storm":
		storm_flashes = 0
		_storm_next_flash = 0.05 # первая молния почти сразу — гроза видна с начала
	var message: String = str(data.get("message", ""))
	if message != "":
		_notify("%s (%s)" % [message, get_event_time_left_text()])
	_apply_event_to_world()
	weather_event_started.emit(event_id, str(data.get("name", event_id)))
	return true

func _roll_duration(data: Dictionary) -> float:
	var low: float = float(data.get("min_hours", 2.0))
	var high: float = maxf(low, float(data.get("max_hours", low)))
	return _rng.randf_range(low, high)

func _finish_event(silent: bool = false) -> void:
	var finished: String = active_event
	active_event = ""
	event_hours_left = 0.0
	_apply_event_to_world()
	if finished != "":
		if not silent:
			_notify("%s %s закончилось." % [str(EVENTS.get(finished, {}).get("icon", "")), str(EVENTS.get(finished, {}).get("name", finished))])
		weather_event_ended.emit(finished)

func clear_event() -> void:
	if active_event != "":
		_finish_event(true)

func get_active_event() -> String:
	return active_event

func get_active_event_name() -> String:
	return str(EVENTS.get(active_event, {}).get("name", ""))

## Подпись активного события для HUD: «⛈️ Гроза (ещё 3 ч)». Пусто, если событий нет.
func get_active_event_caption() -> String:
	if active_event == "":
		return ""
	var data: Dictionary = EVENTS.get(active_event, {})
	return "%s %s (%s)" % [str(data.get("icon", "")), get_active_event_name(), get_event_time_left_text()]

func get_event_time_left() -> float:
	return maxf(0.0, event_hours_left)

func get_event_time_left_text() -> String:
	var hours: float = get_event_time_left()
	if hours >= 24.0:
		return "ещё %d дн." % int(ceil(hours / 24.0))
	return "ещё %d ч" % int(ceil(hours))

# --- Множители событий ---------------------------------------------------------

## Испарение с грядок: сезон × событие (засуха ×3).
func get_evaporation_multiplier() -> float:
	var mult: float = Seasons.get_evaporation_multiplier()
	if active_event == "drought":
		mult *= DROUGHT_EVAPORATION
	elif active_event == "hurricane":
		mult *= HURRICANE_EVAPORATION
	return mult

## Рост культур: сезон × событие (метель и ураган тормозят).
func get_growth_multiplier() -> float:
	var mult: float = Seasons.get_growth_multiplier()
	if active_event == "blizzard" or active_event == "hurricane":
		mult *= BLIZZARD_SPEED
	return mult

## Урон от холода: метель ×2.
func get_cold_damage_multiplier() -> float:
	return BLIZZARD_COLD if active_event == "blizzard" else 1.0

## Замедление персонажа в непогоду.
func get_speed_multiplier() -> float:
	if active_event == "blizzard":
		return BLIZZARD_SPEED
	if active_event == "hurricane":
		return HURRICANE_SPEED
	return 1.0

## Падает ли видимость (метель, ураган).
func has_reduced_visibility() -> bool:
	return active_event == "blizzard" or active_event == "hurricane"

## Гроза: ливень независимо отSeasonal распределения погоды.
func forces_heavy_rain() -> bool:
	return active_event == "storm"

## Засуха: осадков не будет.
func forbids_rain() -> bool:
	return active_event == "drought"

## Погода, которую событие требует ("" — не навязывает).
func get_forced_weather() -> String:
	if active_event == "storm":
		return "heavy_rain"
	if active_event == "blizzard":
		return "snow"
	if active_event == "hurricane":
		return "heavy_rain"
	return ""

## Применение события к WeatherManager (ливень/снег и его прекращение).
func _apply_event_to_world() -> void:
	if not is_instance_valid(_weather_mgr):
		_bind_nodes()
	if not _weather_mgr:
		return
	if not _weather_mgr.has_method("set_weather"):
		return
	var forced: String = get_forced_weather()
	match forced:
		"heavy_rain":
			_weather_mgr.set_weather(WeatherManager.WeatherType.HEAVY_RAIN)
		"snow":
			_weather_mgr.set_weather(WeatherManager.WeatherType.SNOW)

# --- Последствия событий --------------------------------------------------------

## Разрушения и разбросанные ресурсы при урагане.
func apply_event_effects(event_id: String) -> void:
	match event_id:
		"storm":
			_lightning_strike()
		"hurricane":
			_damage_roof()
			_scatter_resources()

## Вспышка молнии посреди грозы: видна всегда (вспышка экрана), бьёт по
## дереву с обычным шансом. Гроза ощущается, даже если молния ушла в поле.
func _storm_flash() -> void:
	storm_flashes += 1
	var hud: Node = get_parent().get_node_or_null("HUD") if get_parent() else null
	if hud and hud.has_method("flash_lightning"):
		hud.flash_lightning()
	_lightning_strike()

## Молния поджигает одно дерево рядом с базой.
func _lightning_strike() -> void:
	if _rng.randf() >= LIGHTNING_CHANCE:
		return
	var trees: Array = get_tree().get_nodes_in_group("trees") if is_inside_tree() else []
	var targets: Array = []
	for t in trees:
		if is_instance_valid(t) and t.has_method("respawn") and "is_depleted" in t and not t.is_depleted:
			targets.append(t)
	if targets.is_empty():
		return
	var tree: Node = targets[_rng.randi_range(0, targets.size() - 1)]
	tree.is_depleted = true
	if tree.has_method("_set_depleted"):
		tree._set_depleted(true)
	_notify("⚡ Молния ударила в дерево «%s» — оно сгорело. Нужен саженец." % str(tree.get("resource_display_name") if "resource_display_name" in tree else tree.name))
	AudioManager.play("hit_wood")

## Ураган сносит крышу дома на одну стадию.
func _damage_roof() -> void:
	var house: Node = get_parent().find_child("RepairableHouse", true, false) if get_parent() else null
	if not house or not ("current_stage" in house):
		return
	if int(house.current_stage) <= 0:
		_notify("🌀 Ураган сорвал часть крыши, но дом и так был в руинах.")
		return
	house.current_stage -= 1
	if house.has_method("_update_visuals"):
		house._update_visuals()
	_notify("🌀 Ураган повредил дом: стадия %d." % int(house.current_stage))

## Часть древесины и камня разлетается вокруг персонажа.
func _scatter_resources() -> void:
	var player: Node = get_parent().find_child("Player", true, false) if get_parent() else null
	if not player:
		return
	var inv = player.get("inventory") if "inventory" in player else null
	if not inv or not inv.has_method("get_item_count") or not inv.has_method("remove_item"):
		return
	var scattered: int = 0
	for item_id in ["wood", "stone"]:
		var amount: int = int(inv.get_item_count(item_id))
		if amount <= 0:
			continue
		var lost: int = maxi(1, int(floor(amount * HURRICANE_SCATTER)))
		if inv.remove_item(item_id, lost):
			DroppedItemScript.drop_from_player(player, item_id, lost)
			scattered += lost
	if scattered > 0:
		_notify("🌀 Ветер раскидал %d ед. запасов — их нужно собрать." % scattered)

# --- Сохранения ----------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"enabled": enabled,
		"total_day": total_day,
		"current_season": Seasons.get_current_season(),
		"day_in_season": Seasons.get_day_in_season(),
		"year": Seasons.get_year(),
		"active_event": active_event,
		"event_hours_left": maxf(0.0, event_hours_left),
	}

func apply_save_state(state: Dictionary) -> void:
	enabled = bool(state.get("enabled", enabled))
	total_day = maxi(1, int(state.get("total_day", total_day)))
	var saved_season: String = str(state.get("current_season", ""))
	if enabled and saved_season != "" and Seasons.ALL.has(saved_season):
		var day: int = clampi(int(state.get("day_in_season", 1)), 1, Seasons.DAYS_PER_SEASON)
		# Год из сейва важнее дня: восстанавливаем абсолютный день, если он не сходится.
		var absolute: int = total_day
		if Seasons.season_for_day(absolute) != saved_season:
			absolute = (maxi(1, int(state.get("year", 1)) - 1) * Seasons.DAYS_PER_YEAR) \
				+ Seasons.ALL.find(saved_season) * Seasons.DAYS_PER_SEASON + day
			total_day = absolute
		Seasons.set_calendar(total_day)
	_applied_season = Seasons.get_current_season()
	if enabled:
		_apply_calendar(false)
		_push_to_world()
	active_event = str(state.get("active_event", ""))
	event_hours_left = maxf(0.0, float(state.get("event_hours_left", 0.0)))
	if active_event != "" and not EVENTS.has(active_event):
		active_event = ""
		event_hours_left = 0.0
	_apply_event_to_world()

static func is_valid_save_state(state: Dictionary) -> bool:
	if not state is Dictionary:
		return false
	if state.has("enabled") and not (state["enabled"] is bool):
		return false
	if state.has("total_day") and float(state.get("total_day", 1)) < 1.0:
		return false
	var season: String = str(state.get("current_season", ""))
	if season != "" and not Seasons.ALL.has(season):
		return false
	if state.has("day_in_season"):
		var day: float = float(state["day_in_season"])
		if day < 1.0 or day > float(Seasons.DAYS_PER_SEASON):
			return false
	if state.has("year") and float(state.get("year", 1)) < 1.0:
		return false
	var event: String = str(state.get("active_event", ""))
	if event != "" and not EVENTS.has(event):
		return false
	if state.has("event_hours_left") and float(state.get("event_hours_left", 0.0)) < 0.0:
		return false
	return true

func _notify(text: String) -> void:
	var hud: Node = get_parent().get_node_or_null("HUD") if get_parent() else null
	if hud and hud.has_method("show_notification"):
		hud.show_notification(text)