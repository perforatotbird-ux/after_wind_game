class_name DayNightCycle
extends Node

## Система суточного цикла, динамического освещения и времени суток
## Соответствует разделам 7, 12, 13, 72 дизайн-документа

signal time_changed(day: int, hour: int, minute: int, formatted: String, phase: String)
signal day_passed(new_day: int)
signal phase_changed(new_phase: String)

@export_group("Time Settings")
## Длительность полных суток в секундах реального времени (480 сек = 8 мин)
@export var day_duration_seconds: float = 480.0
@export var current_day: int = 1
@export var current_hour: float = 8.0
@export var time_scale: float = 1.0

@export_group("Scene References")
@export var sun_light: DirectionalLight3D
@export var world_environment: WorldEnvironment

var current_phase: String = "Утро"
var _sky_material: ProceduralSkyMaterial = null
var _last_reported_minute: int = -1

func _ready() -> void:
	if not sun_light:
		sun_light = get_parent().get_node_or_null("DirectionalLight3D")
	
	if not world_environment:
		world_environment = get_parent().get_node_or_null("WorldEnvironment")
	
	if world_environment and world_environment.environment and world_environment.environment.sky:
		_sky_material = world_environment.environment.sky.sky_material as ProceduralSkyMaterial
	
	_update_lighting_and_sky(true)

func _process(delta: float) -> void:
	# Скорость изменения времени (24 игровых часа за day_duration_seconds)
	var hours_per_second: float = (24.0 / max(1.0, day_duration_seconds)) * time_scale
	current_hour += hours_per_second * delta
	
	if current_hour >= 24.0:
		current_hour -= 24.0
		current_day += 1
		day_passed.emit(current_day)
	
	_update_lighting_and_sky(false)
	_check_minute_update()

func _check_minute_update() -> void:
	var hour_int: int = int(current_hour)
	var minute_int: int = int((current_hour - hour_int) * 60.0)
	
	if minute_int != _last_reported_minute:
		_last_reported_minute = minute_int
		var new_phase: String = get_current_phase()
		if new_phase != current_phase:
			current_phase = new_phase
			phase_changed.emit(current_phase)
		
		var fmt: String = get_time_string()
		time_changed.emit(current_day, hour_int, minute_int, fmt, current_phase)

func get_current_phase() -> String:
	if current_hour >= 5.0 and current_hour < 11.0:
		return "Утро"
	elif current_hour >= 11.0 and current_hour < 17.0:
		return "День"
	elif current_hour >= 17.0 and current_hour < 21.0:
		return "Вечер"
	else:
		return "Ночь"

func get_phase_icon() -> String:
	match get_current_phase():
		"Утро": return "🌅"
		"День": return "☀️"
		"Вечер": return "🌇"
		_: return "🌙"

func is_night() -> bool:
	return current_hour >= 21.0 or current_hour < 5.0

func get_time_string() -> String:
	var hour_int: int = int(current_hour)
	var minute_int: int = int((current_hour - hour_int) * 60.0)
	var icon: String = get_phase_icon()
	return "%s День %d | %02d:%02d (%s)" % [icon, current_day, hour_int, minute_int, get_current_phase()]

func get_ambient_temperature() -> int:
	# Температура в зависимости от времени суток
	if is_night():
		return 11
	match get_current_phase():
		"Утро": return 16
		"День": return 22
		"Вечер": return 18
		_: return 14

func skip_to_morning(target_hour: float = 6.0) -> void:
	current_day += 1
	current_hour = target_hour
	_last_reported_minute = -1
	current_phase = get_current_phase()
	_update_lighting_and_sky(true)
	day_passed.emit(current_day)
	var hour_int: int = int(current_hour)
	var minute_int: int = int((current_hour - hour_int) * 60.0)
	time_changed.emit(current_day, hour_int, minute_int, get_time_string(), current_phase)

func _update_lighting_and_sky(force: bool) -> void:
	if not sun_light and not _sky_material and not force:
		return
	
	# Нормализованный суточный прогресс: 0.0 в 00:00, 0.5 в 12:00
	var day_progress: float = current_hour / 24.0
	
	# Вращение солнца:
	# На рассвете (06:00 -> 0.25) солнце всходит под малым углом.
	# В полдень (12:00 -> 0.50) солнце в высшей точке (~65° над горизонтом).
	# На закате (18:00 -> 0.75) солнце садится.
	# Ночью (21:00-05:00) слабый лунный свет с противоположной стороны.
	var sun_pitch_deg: float
	var sun_yaw_deg: float = day_progress * 360.0
	var light_energy: float
	var light_color: Color
	
	var sky_top: Color
	var sky_horiz: Color
	var ground_horiz: Color
	
	if current_hour >= 5.0 and current_hour < 11.0:
		# Утро
		var factor: float = (current_hour - 5.0) / 6.0
		sun_pitch_deg = lerpf(15.0, 60.0, factor)
		light_energy = lerpf(0.6, 1.2, factor)
		light_color = Color(1.0, 0.88, 0.75).lerp(Color(1.0, 0.96, 0.90), factor)
		sky_top = Color(0.25, 0.35, 0.55).lerp(Color(0.36, 0.54, 0.78), factor)
		sky_horiz = Color(0.92, 0.70, 0.50).lerp(Color(0.65, 0.72, 0.78), factor)
		ground_horiz = Color(0.40, 0.35, 0.30).lerp(Color(0.50, 0.48, 0.45), factor)
		
	elif current_hour >= 11.0 and current_hour < 17.0:
		# День
		sun_pitch_deg = 65.0
		light_energy = 1.25
		light_color = Color(1.0, 0.97, 0.92)
		sky_top = Color(0.36, 0.54, 0.78)
		sky_horiz = Color(0.65, 0.72, 0.78)
		ground_horiz = Color(0.50, 0.48, 0.45)
		
	elif current_hour >= 17.0 and current_hour < 21.0:
		# Вечер / Закат
		var factor: float = (current_hour - 17.0) / 4.0
		sun_pitch_deg = lerpf(60.0, 10.0, factor)
		light_energy = lerpf(1.2, 0.4, factor)
		light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.30), factor)
		sky_top = Color(0.36, 0.54, 0.78).lerp(Color(0.20, 0.22, 0.45), factor)
		sky_horiz = Color(0.65, 0.72, 0.78).lerp(Color(0.95, 0.45, 0.25), factor)
		ground_horiz = Color(0.50, 0.48, 0.45).lerp(Color(0.35, 0.28, 0.25), factor)
		
	else:
		# Ночь
		var night_t: float
		if current_hour >= 21.0:
			night_t = (current_hour - 21.0) / 8.0
		else:
			night_t = (current_hour + 3.0) / 8.0
		sun_pitch_deg = 35.0 # Луна над горизонтом
		light_energy = 0.20
		light_color = Color(0.35, 0.45, 0.70) # Холодный лунный свет
		sky_top = Color(0.04, 0.05, 0.12)
		sky_horiz = Color(0.08, 0.10, 0.18)
		ground_horiz = Color(0.12, 0.12, 0.15)
	
	if sun_light:
		sun_light.rotation_degrees = Vector3(-sun_pitch_deg, sun_yaw_deg, 0.0)
		sun_light.light_energy = light_energy
		sun_light.light_color = light_color
	
	if _sky_material:
		_sky_material.sky_top_color = sky_top
		_sky_material.sky_horizon_color = sky_horiz
		_sky_material.ground_horizon_color = ground_horiz
