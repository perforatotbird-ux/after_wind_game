extends Node3D
## Два склада, четыре стадии: руины → каркас с тентом → амбар → оснащённый амбар.
const Hoist = preload('res://scripts/buildings/storage_hoist_animator.gd')
@export_range(0,3) var storage_stage:=0
var lantern_lights: Array[OmniLight3D]=[]
var glow_material: StandardMaterial3D
var hoist: Node3D
var _day_cycle: Node
var _timer:=0.0
func _ready() -> void:
	refresh_geometry()
	var glow:=get_node_or_null('Glow') as MeshInstance3D
	if glow:
		glow_material=glow.mesh.surface_get_material(0).duplicate()
		glow_material.emission_enabled=true
		glow_material.emission=Color(1,.53,.16)
		glow.set_surface_override_material(0,glow_material)
		for x in [-2.13,2.13]:
			var light:=OmniLight3D.new();light.position=Vector3(x,2.03,2.04)
			light.name='LanternLight';light.light_color=Color(1,.53,.23);light.light_energy=.5;light.omni_range=2.7
			add_child(light);lantern_lights.append(light)
	if storage_stage==3:
		hoist=Hoist.new();hoist.name='HoistAnimator';add_child(hoist)
	update_environment()
func refresh_geometry() -> void:
	for name_ in ['Shell','Roof','Doors','Hardware','Goods','Gear','Crank','Chain','Hook','Lanterns','Glow']:
		var part:=get_node_or_null(name_) as Node3D
		if part: part.visible=storage_stage!=1
	var debris:=get_node_or_null('Debris') as Node3D
	if debris: debris.visible=storage_stage==0
	var tarp:=get_node_or_null('Tarp') as Node3D
	if tarp: tarp.visible=storage_stage==1
func update_environment() -> void:
	if not is_instance_valid(_day_cycle): _day_cycle=get_tree().get_first_node_in_group(DayNightCycle.GROUP)
	var night: bool=is_instance_valid(_day_cycle) and _day_cycle.has_method('is_night') and _day_cycle.is_night()
	var lit:=is_visible_in_tree() and storage_stage>=2 and night
	for light in lantern_lights: light.visible=lit
	if glow_material: glow_material.emission_energy_multiplier=.8 if lit else .08
func _process(delta: float) -> void:
	_timer+=delta
	if _timer<.25:return
	_timer=0
	update_environment()
