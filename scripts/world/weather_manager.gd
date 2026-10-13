class_name WeatherManager
extends Node

## Система погоды и атмосферных явлений (Разделы 11, 13, 72 дизайн-документа)
## Управляет 5 типами погоды: Солнечно, Пасмурно, Дождь, Сильный ливень, Снег.
## Координирует выпадение осадков, авто-полив грядок, наполнение резервуаров и мокроту игрока.
## Сезон (Seasons) задаёт частоту дождей, а погодные события (SeasonManager —
## гроза, засуха, метель, ураган) могут навязать погоду принудительно.

const Seasons = preload("res://scripts/core/seasons.gd")

enum WeatherType {
	SUNNY,      # Солнечно
	OVERCAST,   # Пасмурно
	RAIN,       # Дождь
	HEAVY_RAIN, # Сильный ливень
	SNOW        # Снег
}

signal weather_changed(new_weather: WeatherType, weather_name: String, icon: String)
signal rain_tick(intensity: float, delta: float)

## Насколько снег увлажняет почву по сравнению с дождём той же силы.
const SNOW_HYDRATION: float = 0.25
## Снег не наполняет цистерны: тает он позже, весной.
const SNOW_RESERVOIR_FACTOR: float = 0.0

@export_group("Weather Settings")
@export var current_weather: WeatherType = WeatherType.SUNNY
@export var auto_cycle: bool = true
## Интервал автоматической смены погоды в секундах (120 сек = 2 мин)
@export var weather_change_interval: float = 120.0

@export_group("Visual References")
@export var rain_particles: CPUParticles3D
@export var snow_particles: CPUParticles3D
@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment

var _timer: float = 0.0
var _reservoir_accumulator: float = 0.0
var _cycle_sequence: Array[WeatherType] = [
	WeatherType.SUNNY,
	WeatherType.OVERCAST,
	WeatherType.RAIN,
	WeatherType.HEAVY_RAIN,
	WeatherType.RAIN,
	WeatherType.OVERCAST,
	WeatherType.SUNNY
]
var _cycle_index: int = 0
var _season_mgr: Node = null

func _ready() -> void:
	if not rain_particles:
		rain_particles = get_node_or_null("RainParticles")
	if not snow_particles:
		snow_particles = get_node_or_null("SnowParticles")
	if not sun_light and get_parent():
		sun_light = get_parent().get_node_or_null("DirectionalLight3D")
	if not world_environment and get_parent():
		world_environment = get_parent().get_node_or_null("WorldEnvironment")
	if not is_instance_valid(_season_mgr) and get_parent():
		_season_mgr = get_parent().get_node_or_null("SeasonManager")
	
	set_weather(current_weather)

func _process(delta: float) -> void:
	if auto_cycle:
		_timer += delta
		if _timer >= weather_change_interval:
			_timer = 0.0
			_advance_weather_cycle()
	
	if is_precipitating():
		var intensity: float = get_precipitation_intensity()
		rain_tick.emit(intensity, delta)
		_apply_rainfall_to_world(intensity, delta)

## Следующая погода по циклу. Цикл сезонный: в засушливом сезоне дождей меньше,
## а зимой вместо дождя идёт снег. Событие (гроза/метель/ураган) важнее цикла.
func _advance_weather_cycle() -> void:
	if not is_instance_valid(_season_mgr) and get_parent():
		_season_mgr = get_parent().get_node_or_null("SeasonManager")
	if _season_mgr and _season_mgr.has_method("get_forced_weather"):
		match str(_season_mgr.get_forced_weather()):
			"heavy_rain":
				set_weather(WeatherType.HEAVY_RAIN)
				return
			"snow":
				set_weather(WeatherType.SNOW)
				return
	if _season_mgr and _season_mgr.has_method("forbids_rain") and _season_mgr.forbids_rain():
		# Засуха: дождя не будет — солнце или пасмурность.
		_cycle_index = (_cycle_index + 1) % _cycle_sequence.size()
		set_weather(_cycle_sequence[_cycle_index] if not _is_rainy(_cycle_sequence[_cycle_index]) else WeatherType.SUNNY)
		return
	_cycle_index = (_cycle_index + 1) % _cycle_sequence.size()
	var next: WeatherType = _seasonal_weather(_cycle_sequence[_cycle_index])
	set_weather(next)

## Переводит дождь в снег, если на дворе зима.
func _seasonal_weather(weather: WeatherType) -> WeatherType:
	if _is_rainy(weather) and Seasons.get_current_season() == Seasons.WINTER:
		return WeatherType.SNOW
	return weather

func _is_rainy(weather: WeatherType) -> bool:
	return weather == WeatherType.RAIN or weather == WeatherType.HEAVY_RAIN

## Тип WeatherType по имени погодного события ("snow" / "heavy_rain" / "").
func weather_type_for_event(event_weather: String) -> WeatherType:
	match event_weather:
		"heavy_rain": return WeatherType.HEAVY_RAIN
		"rain": return WeatherType.RAIN
		"snow": return WeatherType.SNOW
		"overcast": return WeatherType.OVERCAST
		_: return WeatherType.SUNNY

func set_weather(new_type: WeatherType, notify_player: bool = true) -> void:
	current_weather = new_type
	_update_visuals()
	weather_changed.emit(current_weather, get_weather_name(), get_weather_icon())
	if not notify_player:
		return

	var world = get_parent()
	if world:
		var hud = world.get_node_or_null("HUD")
		if hud and hud.has_method("show_notification"):
			match current_weather:
				WeatherType.SUNNY:
					hud.show_notification("☀️ Небо прояснилось, светит теплое солнце.")
				WeatherType.OVERCAST:
					hud.show_notification("☁️ Небо затянуло плотными серыми тучами.")
				WeatherType.RAIN:
					hud.show_notification("🌧️ Начался моросящий дождь! Вода наполняет грядки и цистерны.")
				WeatherType.HEAVY_RAIN:
					hud.show_notification("⛈️ Начался сильный ливень! Найдите укрытие от холодной воды.")
				WeatherType.SNOW:
					hud.show_notification("🌨️ Пошёл снег. Вода в открытых источниках замёрзла — нужна печь или колодец.")

func _update_visuals() -> void:
	var raining: bool = is_raining()
	var snowing: bool = is_snowing()
	if rain_particles:
		rain_particles.emitting = raining
		if current_weather == WeatherType.HEAVY_RAIN:
			rain_particles.amount = 450
			rain_particles.initial_velocity_min = 22.0
			rain_particles.initial_velocity_max = 28.0
		elif current_weather == WeatherType.RAIN:
			rain_particles.amount = 200
			rain_particles.initial_velocity_min = 15.0
			rain_particles.initial_velocity_max = 20.0
	if snow_particles:
		snow_particles.emitting = snowing
	
	# Корректировка освещения при пасмурной или дождливой погоде
	if sun_light:
		match current_weather:
			WeatherType.SUNNY:
				sun_light.light_energy = 1.2
			WeatherType.OVERCAST:
				sun_light.light_energy = 0.8
			WeatherType.RAIN:
				sun_light.light_energy = 0.55
			WeatherType.HEAVY_RAIN:
				sun_light.light_energy = 0.35
			WeatherType.SNOW:
				sun_light.light_energy = 0.7

func _apply_rainfall_to_world(intensity: float, delta: float) -> void:
	if not get_tree():
		return
	var snowing: bool = is_snowing()
	var hydration_rate: float = 3.5 * intensity * (SNOW_HYDRATION if snowing else 1.0)
	
	# 1. Автоматическое увлажнение грядок пашни через группу (O(1) поиск)
	var plots = get_tree().get_nodes_in_group("farmland_plots")
	for plot in plots:
		if is_instance_valid(plot) and "soil_state" in plot and "moisture" in plot:
			if plot.soil_state == 1: # SoilState.TILLED
				var hydration: float = hydration_rate * delta
				var old_wet: bool = (plot.moisture > 10.0)
				plot.moisture = min(plot.max_moisture, plot.moisture + hydration)
				if (plot.moisture > 10.0) != old_wet and plot.has_method("_update_soil_material"):
					plot._update_soil_material()
	
	# 1б. Делянки: осадки поливают все клетки.
	for field in get_tree().get_nodes_in_group("farm_fields"):
		if is_instance_valid(field) and field.has_method("apply_rain"):
			field.apply_rain(hydration_rate * delta)
	
	# 2. Наполнение водного резервуара дождевой водой
	_reservoir_accumulator += delta * intensity * (SNOW_RESERVOIR_FACTOR if snowing else 1.0)
	var threshold: float = 10.0 # каждые 10 сек в обычный дождь, 5 сек в ливень
	if _reservoir_accumulator >= threshold:
		_reservoir_accumulator = 0.0
		var reservoirs = get_tree().get_nodes_in_group("water_reservoirs")
		if reservoirs.is_empty() and get_parent():
			reservoirs = get_parent().find_children("*", "Area3D", true, false)
		for reservoir in reservoirs:
			if is_instance_valid(reservoir) and "current_water" in reservoir and "max_capacity" in reservoir:
				if reservoir.current_water < reservoir.max_capacity:
					reservoir.current_water = min(reservoir.max_capacity, reservoir.current_water + 1)
					if reservoir.has_signal("water_level_changed"):
						reservoir.water_level_changed.emit(reservoir.current_water, reservoir.max_capacity)

func is_raining() -> bool:
	return _is_rainy(current_weather)

func is_snowing() -> bool:
	return current_weather == WeatherType.SNOW

## Идёт ли хоть какие-то осадки (дождь, ливень или снег).
func is_precipitating() -> bool:
	return is_raining() or is_snowing()

func get_rain_intensity() -> float:
	match current_weather:
		WeatherType.RAIN: return 1.0
		WeatherType.HEAVY_RAIN: return 2.0
		WeatherType.SNOW: return 0.5
		_: return 0.0

## Сила осадков для почвы и резервуара: дождь 1.0/2.0, снег 0.5.
func get_precipitation_intensity() -> float:
	return get_rain_intensity()

func get_weather_name() -> String:
	match current_weather:
		WeatherType.SUNNY: return "Ясно"
		WeatherType.OVERCAST: return "Пасмурно"
		WeatherType.RAIN: return "Дождь"
		WeatherType.HEAVY_RAIN: return "Сильный ливень"
		WeatherType.SNOW: return "Снег"
		_: return "Ясно"

func get_weather_icon() -> String:
	match current_weather:
		WeatherType.SUNNY: return "☀️"
		WeatherType.OVERCAST: return "☁️"
		WeatherType.RAIN: return "🌧️"
		WeatherType.HEAVY_RAIN: return "⛈️"
		WeatherType.SNOW: return "🌨️"
		_: return "☀️"

## Погодное смещение температуры (не зависит от сезона).
func get_temperature_offset() -> int:
	match current_weather:
		WeatherType.SUNNY: return 0
		WeatherType.OVERCAST: return -3
		WeatherType.RAIN: return -6
		WeatherType.HEAVY_RAIN: return -9
		WeatherType.SNOW: return -5
		_: return 0

## Сезонное смещение температуры (лето теплее, зима холоднее).
func get_season_temperature_offset() -> int:
	return Seasons.get_temperature_offset()
