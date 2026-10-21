class_name LightingEnvManager
extends Node

## Управляет WorldEnvironment: SSAO, ambient color, glow и сезонной гаммой.
## Подписывается на сигналы DayNightCycle, WeatherManager и SeasonManager.
## Не трогает DirectionalLight3D (зона ответственности DayNightCycle).

const Seasons = preload("res://scripts/core/seasons.gd")

@export var world_environment: WorldEnvironment
@export var enable_ssao: bool = true
@export var enable_sdfgi: bool = false
@export var enable_glow: bool = true
@export var lake_material: ShaderMaterial

# Плавный переход ambient color
var _target_ambient: Color = Color(0.3, 0.3, 0.4)
var _ambient_lerp_speed: float = 0.6

# Сезонные базовые оттенки окружения
const SEASON_AMBIENT: Dictionary = {
	"spring": Color(0.28, 0.32, 0.36),
	"summer": Color(0.35, 0.33, 0.28),
	"autumn": Color(0.32, 0.28, 0.24),
	"winter": Color(0.22, 0.27, 0.42),
	"":       Color(0.30, 0.30, 0.36),
}

# Погодные коэффициенты яркости рассеянного света (по типу погоды).
const WEATHER_AMBIENT_MULT: Dictionary = {
	0: 1.0,   # SUNNY
	1: 0.75,  # OVERCAST
	2: 0.60,  # RAIN
	3: 0.45,  # HEAVY_RAIN
	4: 0.85,  # SNOW
}

var _season: String = ""
var _weather_type: int = 0
var _day_phase: String = "День"
## Озеро ищется один раз: полный обход мира каждый кадр стоил слишком дорого.
var _lake_lookup_done: bool = false

func _ready() -> void:
	add_to_group("lighting_env_manager")
	if not world_environment and get_parent():
		world_environment = get_parent().get_node_or_null("WorldEnvironment")
	
	_bind_signals()
	_apply_environment_settings()
	_update_ambient()

func _bind_signals() -> void:
	var dnc: Node = null
	if get_tree():
		dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if not dnc and get_parent():
		dnc = get_parent().get_node_or_null("DayNightCycle")
	
	if dnc:
		if dnc.has_signal("phase_changed") and not dnc.phase_changed.is_connected(_on_phase_changed):
			dnc.phase_changed.connect(_on_phase_changed)
		if dnc.has_signal("time_changed") and not dnc.time_changed.is_connected(_on_time_changed):
			dnc.time_changed.connect(_on_time_changed)
		if dnc.has_method("get_current_phase"):
			_day_phase = dnc.get_current_phase()
	
	var wm: Node = null
	if get_parent():
		wm = get_parent().get_node_or_null("WeatherManager")
	if not wm and get_tree():
		wm = get_tree().get_first_node_in_group("weather_manager")
	if wm and wm.has_signal("weather_changed") and not wm.weather_changed.is_connected(_on_weather_changed):
		wm.weather_changed.connect(_on_weather_changed)
		if "current_weather" in wm:
			_weather_type = int(wm.current_weather)
	
	var sm: Node = null
	if get_parent():
		sm = get_parent().get_node_or_null("SeasonManager")
	if sm and sm.has_signal("season_changed") and not sm.season_changed.is_connected(_on_season_changed):
		sm.season_changed.connect(_on_season_changed)
	# Текущий сезон живёт в статическом календаре Seasons, а не в SeasonManager,
	# поэтому берём его оттуда — иначе первый сезон остался бы нейтральным.
	_season = Seasons.get_current_season()

func _apply_environment_settings() -> void:
	if not world_environment or not world_environment.environment:
		return
	var env: Environment = world_environment.environment
	# SSAO
	env.ssao_enabled = enable_ssao
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	
	# SDFGI (по умолчанию выключен, включается для Ultra)
	env.sdfgi_enabled = enable_sdfgi
	
	# Tone mapping — Film-grade ACES
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	
	# Glow
	env.glow_enabled = enable_glow
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2

func _process(delta: float) -> void:
	if not world_environment or not world_environment.environment:
		return
	var env: Environment = world_environment.environment
	var cur: Color = env.ambient_light_color
	if cur != _target_ambient:
		env.ambient_light_color = cur.lerp(_target_ambient, clampf(_ambient_lerp_speed * delta * 5.0, 0.0, 1.0))
	
	_update_water_tint()

func _on_phase_changed(phase: String) -> void:
	_day_phase = phase
	_update_ambient()

func _on_time_changed(_day: int, _hour: int, _min: int, _fmt: String, phase: String) -> void:
	if _day_phase != phase:
		_day_phase = phase
		_update_ambient()

func _on_weather_changed(w_type, _w_name: String, _icon: String) -> void:
	# Ключ таблицы — тип погоды (WeatherType), а не название: названия русские.
	_weather_type = int(w_type)
	_update_ambient()

func _on_season_changed(season: String, _season_name: String = "", _day_in_season: int = 1) -> void:
	_season = season
	_update_ambient()

func _update_ambient() -> void:
	if not world_environment or not world_environment.environment:
		return
	var base: Color = SEASON_AMBIENT.get(_season, SEASON_AMBIENT[""])
	match _day_phase:
		"Ночь":
			base = base.lerp(Color(0.04, 0.05, 0.12), 0.85)
		"Утро":
			base = base.lerp(Color(0.55, 0.45, 0.35), 0.25)
		"Вечер":
			base = base.lerp(Color(0.45, 0.30, 0.20), 0.30)
		_:
			pass
	
	var mult: float = WEATHER_AMBIENT_MULT.get(_weather_type, 1.0)
	_target_ambient = Color(base.r * mult, base.g * mult, base.b * mult)
	
	var env: Environment = world_environment.environment
	env.ambient_light_energy = 0.65 if _day_phase == "День" else (0.10 if _day_phase == "Ночь" else 0.50)

func _update_water_tint() -> void:
	if not lake_material and not _lake_lookup_done:
		# Озеро ищем один раз: обход мира каждый кадр стоил слишком дорого.
		_lake_lookup_done = true
		var lake: Node = get_tree().get_first_node_in_group("lakes") if get_tree() else null
		if not lake and get_parent():
			lake = get_parent().find_child("Lake", true, false)
		if lake:
			var mesh_inst := lake.find_child("WaterMesh", true, false) as MeshInstance3D
			if not mesh_inst:
				mesh_inst = lake.find_child("LakeWater", true, false) as MeshInstance3D
			if not mesh_inst:
				# Надпись воды в модели озера: ищем любой узел с материалом-шейдером.
				for cand in lake.find_children("*", "MeshInstance3D", true, false):
					var mi := cand as MeshInstance3D
					if mi and mi.material_override is ShaderMaterial:
						mesh_inst = mi
						break
			if mesh_inst and mesh_inst.material_override is ShaderMaterial:
				lake_material = mesh_inst.material_override
			elif mesh_inst and mesh_inst.get_surface_override_material(0) is ShaderMaterial:
				lake_material = mesh_inst.get_surface_override_material(0)
	
	if lake_material:
		var sky_color: Color = _target_ambient
		lake_material.set_shader_parameter("sky_tint", Vector3(sky_color.r, sky_color.g, sky_color.b))
		var energy: float = 1.0 if _day_phase == "День" else 0.45
		lake_material.set_shader_parameter("reflection_energy", energy)
