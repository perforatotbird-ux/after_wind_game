extends Node3D
## Живой огонь поверх модели: объём из изогнутых лент, искры, мягкий дым,
## пульсирующие угли, обугливание дерева и свет. Нет анимации всей геометрии.
const FLAME_SHADER = preload("res://assets/models/campfire/flame.gdshader")
const WOOD_SHADER = preload("res://assets/models/campfire/charred_wood.gdshader")
const CRACKS = preload("res://assets/models/campfire/campfire_cracks.tres")
const SMOKE_TEX = preload("res://assets/models/campfire/campfire_smoke.tres")
var fire_light: OmniLight3D
var sparks: CPUParticles3D
var smoke: CPUParticles3D
var flames: Node3D
var flame_materials: Array[ShaderMaterial] = []
var wood_materials: Array[ShaderMaterial] = []
var coal_materials: Array[ShaderMaterial] = []
var flame_strength := 0.0
var ember_strength := 0.0
var char_amount := 0.0
var _time := 0.0
var _was_burning := false
var _smoke_tail := 0.0

func _ready() -> void:
	var cache := {}
	for mi in find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src.resource_name not in ["CampfireWood", "CampfireEndgrain", "CampfireCharcoal"]: continue
			var key := src.resource_name
			if not cache.has(key):
				var mat := ShaderMaterial.new(); mat.shader = WOOD_SHADER
				mat.set_shader_parameter("cracks_texture", CRACKS)
				mat.set_shader_parameter("wood_texture", src.albedo_texture if src.albedo_texture else load("res://assets/models/campfire/campfire_stone_texture.tres"))
				mat.set_shader_parameter("coal", key == "CampfireCharcoal")
				cache[key] = mat
				if key == "CampfireCharcoal": coal_materials.append(mat)
				else: wood_materials.append(mat)
			mi.set_surface_override_material(s, cache[key])
	flames = Node3D.new(); flames.name = "FlameRibbons"; add_child(flames)
	for i in 8:
		var ribbon := MeshInstance3D.new(); ribbon.name = "Flame%02d" % i
		ribbon.mesh = _flame_mesh(0.23 + (i % 3) * 0.055, 0.90 + (i % 4) * 0.11)
		ribbon.position = Vector3(sin(i * 2.4) * 0.13, 0.11, cos(i * 2.4) * 0.13)
		ribbon.rotation.y = i * 2.39996
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new(); mat.shader = FLAME_SHADER
		mat.set_shader_parameter("phase", i * 1.7)
		ribbon.material_override = mat; flame_materials.append(mat); flames.add_child(ribbon)
	fire_light = OmniLight3D.new(); fire_light.name = "FireLight"
	fire_light.position.y = 0.6; fire_light.light_color = Color(1, 0.47, 0.16)
	fire_light.omni_range = 5.0; fire_light.omni_attenuation = 1.35
	fire_light.light_energy = 0.0; fire_light.visible = false; add_child(fire_light)
	sparks = _particles("Sparks", 18, 1.45, false)
	smoke = _particles("Smoke", 14, 3.5, true)
	update_fire(0.0, false, false, false, true)

func _flame_mesh(width: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []; var uvs: Array[Vector2] = []
	for j in 13:
		var t := j / 12.0
		var half := width * (0.35 + sin(t * PI) * 0.8) * (1.0 - t * 0.94)
		var bend := sin(t * 4.5) * 0.06 * t
		for side in 2:
			verts.append(Vector3(bend + (-half if side == 0 else half), t * height, sin(t * PI) * 0.035))
			uvs.append(Vector2(side, t))
	for j in 12:
		for idx in [j * 2, j * 2 + 1, j * 2 + 3, j * 2, j * 2 + 3, j * 2 + 2]:
			st.set_uv(uvs[idx]); st.add_vertex(verts[idx])
	st.generate_normals()
	return st.commit()

func _particles(name_: String, count: int, seconds: float, is_smoke: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new(); p.name = name_; p.emitting = false
	p.amount = count; p.lifetime = seconds; p.position.y = 0.75 if is_smoke else 0.32
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = 0.15
	p.direction = Vector3(0.13, 1, 0.07); p.spread = 14.0
	p.gravity = Vector3(0.07, 0.14 if is_smoke else -0.25, 0.02)
	p.initial_velocity_min = 0.20 if is_smoke else 0.7
	p.initial_velocity_max = 0.45 if is_smoke else 1.0
	p.scale_amount_min = 0.25 if is_smoke else 0.65
	p.scale_amount_max = 0.65 if is_smoke else 1.2
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(0.3, 0.28, 0.25, 0), Color(0.3, 0.28, 0.25, 0.18), Color(0.42, 0.4, 0.37, 0.07), Color(0.5, 0.48, 0.45, 0)]) if is_smoke else PackedColorArray([Color(1,0.73,0.16,0), Color(1,0.84,0.35,1), Color(1,0.25,0.02,0.8), Color(1,0.1,0,0)])
	p.color_ramp = gradient
	var mat := StandardMaterial3D.new(); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = SMOKE_TEX
	if not is_smoke:
		mat.emission_enabled = true; mat.emission = Color(1,0.5,0.05); mat.emission_energy_multiplier = 0.6
	var quad := QuadMesh.new(); quad.size = Vector2(0.8,0.8) if is_smoke else Vector2(0.035,0.05)
	quad.material = mat; p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p); return p

func update_fire(delta: float, burning: bool, burned: bool, night: bool, snap: bool = false) -> void:
	_time += delta
	if _was_burning and not burning: _smoke_tail = 1.6
	_smoke_tail = maxf(0.0, _smoke_tail - delta)
	_was_burning = burning
	var target := 1.0 if burning else 0.0
	flame_strength = target if snap else move_toward(flame_strength, target, delta * 2.6)
	ember_strength = target if snap else move_toward(ember_strength, target, delta * (1.5 if burning else 0.32))
	var char_target := (0.55 if burning else 1.0) if burned else 0.0
	char_amount = char_target if snap else move_toward(char_amount, char_target, delta * 0.65)
	flames.visible = flame_strength > 0.001
	for mat in flame_materials: mat.set_shader_parameter("heat", flame_strength)
	for mat in wood_materials:
		mat.set_shader_parameter("char_amount", char_amount)
		mat.set_shader_parameter("ember_heat", ember_strength * 0.55)
	for mat in coal_materials:
		mat.set_shader_parameter("char_amount", 1.0)
		mat.set_shader_parameter("ember_heat", ember_strength)
	sparks.emitting = burning
	smoke.emitting = burning or _smoke_tail > 0.0
	var flicker := 0.90 + sin(_time * 8.1) * 0.06 + sin(_time * 13.3 + 1.4) * 0.04
	fire_light.light_energy = ((2.6 if night else 1.15) * flame_strength + ember_strength * 0.15) * flicker
	fire_light.visible = fire_light.light_energy > 0.005
