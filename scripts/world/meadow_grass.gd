extends RefCounted

## Стилизованная трава луга (по референсу «Dense Lush Meadow»): пучки широких
## изогнутых листьев с закруглённым сечением, градиент от тёмного корня к
## жёлто-зелёному кончику, мягкий свет на просвет, ветер. Плюс клевер у земли.
## Все меши и материалы строятся один раз и кэшируются.

## Виды пучков.
enum Kind { LUSH, LUSH_WIDE, TALL, SHORT, FAR, CLOVER }

## Вариантов меша на вид (выбор по экземпляру).
const VARIANTS: Dictionary = {Kind.LUSH: 3, Kind.LUSH_WIDE: 2, Kind.TALL: 2, Kind.SHORT: 2, Kind.FAR: 1, Kind.CLOVER: 2}

const GRASS_SHADER: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec3 root_color : source_color = vec3(0.14, 0.25, 0.07);
uniform vec3 mid_color : source_color = vec3(0.32, 0.50, 0.15);
uniform vec3 tip_color : source_color = vec3(0.56, 0.66, 0.27);
uniform float wind = 0.09;
uniform float round_normals = 0.55;
uniform float translucency = 0.25;

varying float v_h;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y;
	v_h = h;
	float gust = sin(TIME * 0.7 + wp.x * 0.11 + wp.z * 0.07) * 0.5 + 0.5;
	float s = sin(TIME * 1.7 + wp.x * 0.45 + wp.z * 0.3) * 0.65 + sin(TIME * 3.1 + wp.x * 1.3 - wp.z * 0.9) * 0.35;
	float k = wind * h * h * (0.55 + 0.9 * gust);
	VERTEX.x += s * k;
	VERTEX.z += s * k * 0.55;
	// Мягкие «скруглённые» нормали: наполовину к небу — без тёмных изнанок.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), round_normals));
}

void fragment() {
	float h = v_h;
	vec3 c = mix(root_color, mid_color, smoothstep(0.0, 0.5, h));
	c = mix(c, tip_color, smoothstep(0.45, 1.2, h));
	// Цвет экземпляра (сочный/подсохший участок) и затемнение к краю листа.
	c *= COLOR.rgb;
	float across = abs(UV.x - 0.5) * 2.0;
	c *= 1.0 - 0.16 * across * across;
	ALBEDO = c;
	AO = mix(0.45, 1.0, smoothstep(0.0, 0.45, h));
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = c * translucency * (0.4 + 0.6 * h);
}
"""

const CLOVER_SHADER: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform vec3 leaf_color : source_color = vec3(0.22, 0.46, 0.14);

void vertex() {
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.4));
}

void fragment() {
	// UV.x — расстояние от центра листика: светлее к краю, тёмная жилка в центре.
	vec3 c = leaf_color * COLOR.rgb * mix(0.8, 1.15, UV.x);
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.3;
}
"""

static var _meshes: Dictionary = {}
static var _grass_mat: ShaderMaterial = null
static var _clover_mat: ShaderMaterial = null

static func get_grass_material() -> ShaderMaterial:
	if _grass_mat == null:
		var sh := Shader.new()
		sh.code = GRASS_SHADER
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = sh
	return _grass_mat

static func get_clover_material() -> ShaderMaterial:
	if _clover_mat == null:
		var sh := Shader.new()
		sh.code = CLOVER_SHADER
		_clover_mat = ShaderMaterial.new()
		_clover_mat.shader = sh
	return _clover_mat

static func get_mesh(kind: int, variant: int) -> ArrayMesh:
	var key := "%d_%d" % [kind, variant]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (kind + 1) + 131 * variant
	var mesh: ArrayMesh
	match kind:
		Kind.LUSH:
			mesh = _build_clump(rng, 10, Vector2(0.24, 0.42), Vector2(0.055, 0.085), 0.1, Vector2(0.25, 0.6))
		Kind.LUSH_WIDE:
			mesh = _build_clump(rng, 7, Vector2(0.28, 0.5), Vector2(0.08, 0.11), 0.09, Vector2(0.3, 0.7))
		Kind.TALL:
			mesh = _build_clump(rng, 9, Vector2(0.48, 0.78), Vector2(0.03, 0.045), 0.08, Vector2(0.3, 0.75))
		Kind.SHORT:
			mesh = _build_clump(rng, 9, Vector2(0.1, 0.19), Vector2(0.04, 0.06), 0.1, Vector2(0.2, 0.5))
		Kind.FAR:
			mesh = _build_clump(rng, 5, Vector2(0.28, 0.42), Vector2(0.07, 0.095), 0.12, Vector2(0.25, 0.5), 2)
		Kind.CLOVER:
			mesh = _build_clover(rng)
	_meshes[key] = mesh
	return mesh

## Число треугольников меша (для тестов и бюджета).
static func triangle_count(mesh: Mesh) -> int:
	var n: int = 0
	for s in mesh.get_surface_count():
		var idx = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()) / 3
	return n

## Пучок: листья-«ленты» из сегментов, ширина по профилю листа (шире в нижней
## трети, закруглённый кончик), изгиб наружу от центра пучка.
static func _build_clump(rng: RandomNumberGenerator, blades: int, height: Vector2, width: Vector2, spread: float, bend: Vector2, segments: int = 4) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(blades)
		var r: float = spread * sqrt(rng.randf())
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var out := Vector3(cos(a), 0.0, sin(a))
		# Лист развёрнут поперёк направления изгиба, слегка повёрнут.
		var face_turn: float = rng.randf_range(-0.5, 0.5)
		var side := Vector3(-out.z, 0.0, out.x).rotated(Vector3.UP, face_turn)
		var h: float = rng.randf_range(height.x, height.y)
		var w: float = rng.randf_range(width.x, width.y)
		var b: float = rng.randf_range(bend.x, bend.y) * h
		var twist: float = rng.randf_range(-0.25, 0.25)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_t: float = 0.0
		var prev_n_l := Vector3.ZERO
		var prev_n_r := Vector3.ZERO
		for sgi in segments + 1:
			var t: float = float(sgi) / float(segments)
			var bf: float = b / maxf(h, 0.01)
			var center: Vector3 = root + Vector3.UP * h * t * (1.0 - 0.25 * t * bf) + out * b * t * t
			var tangent: Vector3 = (Vector3.UP * h * (1.0 - 0.5 * t * bf) + out * b * 2.0 * t).normalized()
			var sd: Vector3 = side.rotated(tangent, twist * t).normalized()
			var face_n: Vector3 = sd.cross(tangent).normalized()
			if face_n.dot(out) < 0.0:
				face_n = -face_n
						# Закруглённый кончик: ширина почти постоянна и резко сходится только у самого конца.
			var prof: float = lerpf(0.75, 1.0, clampf(t / 0.2, 0.0, 1.0)) * pow(maxf(0.0, 1.0 - pow(t, 1.8)), 0.75)
			var half: float = w * 0.5 * prof
			var lft: Vector3 = center - sd * half
			var rgt: Vector3 = center + sd * half
			var n_l: Vector3 = (face_n - sd * 0.75).normalized()
			var n_r: Vector3 = (face_n + sd * 0.75).normalized()
			if sgi > 0:
				if sgi < segments:
					_quad(st, prev_l, prev_r, rgt, lft, prev_n_l, prev_n_r, n_r, n_l, prev_t, t)
				else:
					# Закруглённый кончик: полукруг-веер от середины последнего сечения.
					var pc: Vector3 = (prev_l + prev_r) * 0.5
					var ph: float = (prev_r - prev_l).length() * 0.5
					var psd: Vector3 = (prev_r - prev_l).normalized()
					var ptan: Vector3 = (center - pc).normalized()
					var pn: Vector3 = (prev_n_l + prev_n_r).normalized()
					var last := prev_l
					var last_n := prev_n_l
					var last_uv := Vector2(0.0, prev_t)
					for k in range(1, 5):
						var ang: float = PI * float(k) / 4.0
						var q: Vector3 = pc - psd * cos(ang) * ph + ptan * sin(ang) * maxf(ph * 1.8, (center - pc).length() * 0.7)
						var qn: Vector3 = (pn - psd * cos(ang) * 0.75 * (1.0 - sin(ang))).normalized()
						var quv := Vector2(0.5 - 0.5 * cos(ang), lerpf(prev_t, 1.0, sin(ang)))
						_tri(st, pc, last, q, pn, last_n, qn, Vector2(0.5, prev_t), last_uv, quv)
						last = q
						last_n = qn
						last_uv = quv
			prev_l = lft
			prev_r = rgt
			prev_n_l = n_l
			prev_n_r = n_r
			prev_t = t
	st.index()
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, t0: float, t1: float) -> void:
	_tri(st, a, b, c, na, nb, nc, Vector2(0.0, t0), Vector2(1.0, t0), Vector2(1.0, t1))
	_tri(st, a, c, d, na, nc, nd, Vector2(0.0, t0), Vector2(1.0, t1), Vector2(0.0, t1))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	for v in [[a, na, ua], [b, nb, ub], [c, nc, uc]]:
		st.set_normal(v[1])
		st.set_uv(v[2])
		st.set_color(Color.WHITE)
		st.add_vertex(v[0])

## Кустик клевера: 3–5 стебельков с тройными листиками-сердечками у земли.
static func _build_clover(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sprigs: int = rng.randi_range(3, 5)
	for i in sprigs:
		var a: float = rng.randf() * TAU
		var c := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.1) + Vector3.UP * rng.randf_range(0.04, 0.09)
		var rot: float = rng.randf() * TAU
		var size: float = rng.randf_range(0.028, 0.04)
		for k in 3:
			var la: float = rot + TAU * k / 3.0
			var dir := Vector3(cos(la), 0.0, sin(la))
			var tilt: float = rng.randf_range(0.05, 0.25)
			# Листик — веер из 6 треугольников: круг, сдвинутый от центра.
			var lc: Vector3 = c + dir * size * 0.95 + Vector3.UP * size * tilt
			var n := (Vector3.UP - dir * tilt).normalized()
			var prev := Vector3.ZERO
			for s in 7:
				var ang: float = la + PI + TAU * s / 6.0
				var heart: float = 1.0 - 0.35 * pow(absf(cos((ang - la) * 0.5)), 8.0)
				var p: Vector3 = lc + Vector3(cos(ang), 0.0, sin(ang)) * size * heart
				if s > 0:
					_tri(st, lc, prev, p, n, n, n, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0))
				prev = p
	st.index()
	return st.commit()
