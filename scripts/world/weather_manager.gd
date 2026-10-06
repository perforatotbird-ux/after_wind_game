class_name WeatherManager
extends Node

## Система погоды и атмосферных явлений (Разделы 11, 13, 72 дизайн-документа)
## Управляет 4 типами погоды: Солнечно, Пасмурно, Дождь, Сильный ливень.
## Координирует выпадение осадков, авто-полив грядок, наполнение резервуаров и мокроту игрока.

enum WeatherType {
	SUNNY,      # Солнечно
	OVERCAST,   # Пасмурно
	RAIN,       # Дождь
	HEAVY_RAIN  # Сильный ливень
}

signal weather_changed(new_weather: WeatherType, weather_name: String, icon: String)
signal rain_tick(intensity: float, delta: float)

@export_group("Weather Settings")
@export var current_weather: WeatherType = WeatherType.SUNNY
@export var auto_cycle: bool = true
## Интервал автоматической смены погоды в секундах (120 сек = 2 мин)
@export var weather_change_interval: float = 120.0

@export_group("Visual References")
@export var rain_particles: CPUParticles3D
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

func _ready() -> void:
	if not rain_particles:
		rain_particles = get_node_or_null("RainParticles")
	if not sun_light and get_parent():
		sun_light = get_parent().get_node_or_null("DirectionalLight3D")
	if not world_environment and get_parent():
		world_environment = get_parent().get_node_or_null("WorldEnvironment")
	
	set_weather(current_weather)

func _process(delta: float) -> void:
	if auto_cycle:
		_timer += delta
		if _timer >= weather_change_interval:
			_timer = 0.0
			_advance_weather_cycle()
	
	if is_raining():
		var intensity: float = get_rain_intensity()
		rain_tick.emit(intensity, delta)
		_apply_rainfall_to_world(intensity, delta)

func _advance_weather_cycle() -> void:
	_cycle_index = (_cycle_index + 1) % _cycle_sequence.size()
	set_weather(_cycle_sequence[_cycle_index])

func set_weather(new_type: WeatherType) -> void:
	current_weather = new_type
	_update_visuals()
	weather_changed.emit(current_weather, get_weather_name(), get_weather_icon())
	
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

func _update_visuals() -> void:
	var raining: bool = is_raining()
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

func _apply_rainfall_to_world(intensity: float, delta: float) -> void:
	var world = get_parent()
	if not world:
		return
	
	# 1. Автоматическое увлажнение грядок пашни
	for plot in world.find_children("*", "Area3D", true, false):
		if plot.has_method("water_plot") and "soil_state" in plot and "moisture" in plot:
			if plot.soil_state == 1: # SoilState.TILLED
				var hydration: float = 3.5 * intensity * delta
				plot.moisture = min(plot.max_moisture, plot.moisture + hydration)
				if plot.has_method("_update_soil_material"):
					plot._update_soil_material()
	
	# 2. Наполнение водного резервуара дождевой водой
	_reservoir_accumulator += delta * intensity
	var threshold: float = 10.0 # каждые 10 сек в обычный дождь, 5 сек в ливень
	if _reservoir_accumulator >= threshold:
		_reservoir_accumulator = 0.0
		for reservoir in world.find_children("*", "Area3D", true, false):
			if "current_water" in reservoir and "max_capacity" in reservoir:
				if reservoir.current_water < reservoir.max_capacity:
					reservoir.current_water = min(reservoir.max_capacity, reservoir.current_water + 1)
					if reservoir.has_signal("water_level_changed"):
						reservoir.water_level_changed.emit(reservoir.current_water, reservoir.max_capacity)

func is_raining() -> bool:
	return current_weather == WeatherType.RAIN or current_weather == WeatherType.HEAVY_RAIN

func get_rain_intensity() -> float:
	match current_weather:
		WeatherType.RAIN: return 1.0
		WeatherType.HEAVY_RAIN: return 2.0
		_: return 0.0

func get_weather_name() -> String:
	match current_weather:
		WeatherType.SUNNY: return "Ясно"
		WeatherType.OVERCAST: return "Пасмурно"
		WeatherType.RAIN: return "Дождь"
		WeatherType.HEAVY_RAIN: return "Сильный ливень"
		_: return "Ясно"

func get_weather_icon() -> String:
	match current_weather:
		WeatherType.SUNNY: return "☀️"
		WeatherType.OVERCAST: return "☁️"
		WeatherType.RAIN: return "🌧️"
		WeatherType.HEAVY_RAIN: return "⛈️"
		_: return "☀️"

func get_temperature_offset() -> int:
	match current_weather:
		WeatherType.SUNNY: return 0
		WeatherType.OVERCAST: return -3
		WeatherType.RAIN: return -6
		WeatherType.HEAVY_RAIN: return -9
		_: return 0
