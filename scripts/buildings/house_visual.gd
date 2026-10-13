extends Node3D
## Два архитектурных состояния и четыре совместимые стадии восстановления.
const SMOKE_TEXTURE = preload('res://assets/models/campfire/campfire_smoke.tres')
@export_range(0, 3) var house_stage := 0
var window_material: StandardMaterial3D
var smoke: CPUParticles3D
var window_lights: Array[OmniLight3D] = []
var _day_cycle: Node
var _timer := 0.0

func _ready() -> void:
	refresh_geometry()
	var glass := find_child('Glass', true, false) as MeshInstance3D
	if glass and glass.mesh.get_surface_count() > 0:
		# Keep the shared geometry, but never modify another stage's material.
		window_material = glass.mesh.surface_get_material(0).duplicate()
		glass.set_surface_override_material(0, window_material)
		window_material.emission_enabled = true
		window_material.emission = Color(1.0, 0.54, 0.18)
		_create_effects()
	update_environment()

func refresh_geometry() -> void:
	var roof := find_child('Roof', true, false) as Node3D
	var debris := find_child('Debris', true, false) as Node3D
	var tarp := find_child('Tarp', true, false) as Node3D
	if roof: roof.visible = house_stage != 1
	if debris: debris.visible = house_stage == 0
	if tarp: tarp.visible = house_stage == 1

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.25: return
	_timer = 0.0
	update_environment()

func update_environment() -> void:
	var active_house := is_visible_in_tree() and house_stage == 3
	var night := false
	if not is_instance_valid(_day_cycle):
		_day_cycle = get_tree().get_first_node_in_group(DayNightCycle.GROUP)
	if is_instance_valid(_day_cycle) and _day_cycle.has_method('is_night'):
		night = _day_cycle.is_night()
	if window_material:
		window_material.albedo_color = Color(0.93, 0.665, 0.35) if active_house else Color(0.26, 0.32, 0.37)
		window_material.emission_energy_multiplier = (0.8 if night else 0.20) if active_house else 0.0
	for light in window_lights: light.visible = active_house and night
	if smoke: smoke.emitting = active_house

func _create_effects() -> void:
	smoke = CPUParticles3D.new()
	smoke.name = 'ChimneySmoke'
	smoke.position = Vector3(2.52, 4.62, -0.62)
	smoke.emitting = false
	smoke.amount = 12
	smoke.lifetime = 4.8
	smoke.preprocess = 1.5
	smoke.direction = Vector3(0.12, 1, 0.08)
	smoke.spread = 14
	smoke.gravity = Vector3(0.025, 0.02, 0.015)
	smoke.initial_velocity_min = 0.32
	smoke.initial_velocity_max = 0.48
	smoke.scale_amount_min = 0.4
	smoke.scale_amount_max = 0.75
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.2)); curve.add_point(Vector2(0.6, 0.9)); curve.add_point(Vector2(0.85, 1.1)); curve.add_point(Vector2(1, 0.0))
	smoke.scale_amount_curve = curve
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.62, 0.62)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Constant low opacity avoids dark initial particle buffers in Compatibility.
	# Size curve fades both ends; texture gives each cloud a soft edge.
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = Color(0.62, 0.63, 0.64, 0.07)
	mat.albedo_texture = SMOKE_TEXTURE
	mesh.material = mat
	smoke.mesh = mesh
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	for p in [Vector3(-1.48, 1.6, 2.22), Vector3(1.48, 1.6, 2.22)]:
		var light := OmniLight3D.new()
		light.name = 'WarmWindowLight'
		light.position = p
		light.light_color = Color(1, 0.49, 0.20)
		light.light_energy = 0.42
		light.omni_range = 2.8
		light.visible = false
		add_child(light)
		window_lights.append(light)
