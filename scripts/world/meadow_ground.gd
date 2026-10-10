extends RefCounted

## Материал земли-луга: гладкий мох под пучками травы (meadow_grass.gd)
## плюс крупные пятна в мировых координатах — сочная и подсохшая трава,
## проплешины, тени от кочек — и вытоптанный двор базы с рваным краем.
## Шейдер собирается из строки один раз и кэшируется.

## Двор базы (x, z, ширина, глубина) — утоптанная земля вместо травы.
const DEFAULT_YARD: Rect2 = Rect2(-11.0, -9.0, 22.0, 16.0)

const SHADER_CODE: String = """
shader_type spatial;
render_mode diffuse_burley;

uniform vec4 yard_rect = vec4(-11.0, -9.0, 11.0, 7.0);

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Мох и подшёрсток под пучками травы — гладкий, без пикселей (как в референсе).
	float fine = vnoise(p * 7.0) * 0.5 + vnoise(p * 17.0) * 0.5;
	vec3 grass = mix(vec3(0.09, 0.17, 0.045), vec3(0.17, 0.29, 0.075), clamp(fbm(p * 1.1) * 0.7 + fine * 0.45, 0.0, 1.0));
	// Утоптанная земля с мелкими камешками.
	vec3 soil = mix(vec3(0.25, 0.17, 0.10), vec3(0.38, 0.28, 0.18), fbm(p * 1.6 + vec2(9.0, 3.0)));
	soil = mix(soil, vec3(0.5, 0.45, 0.38), step(0.86, vnoise(p * 13.0)) * 0.5);
	soil *= 0.9 + 0.2 * vnoise(p * 30.0);

	// Крупные пятна: сочная зелень / подсохшая трава / тень от кочек.
	float lush = fbm(p * 0.07);
	float dry = smoothstep(0.55, 0.78, fbm(p * 0.12 + vec2(31.0, 7.0)));
	float clump = fbm(p * 0.45 + vec2(3.0, 11.0));
	vec3 tint = mix(vec3(0.82, 0.92, 0.78), vec3(1.08, 1.12, 0.9), lush);
	tint = mix(tint, vec3(1.32, 1.22, 0.78), dry * 0.75);
	tint *= 0.86 + 0.28 * clump;
	vec3 col = grass * tint;

	// Редкие проплешины земли на лугу.
	float bald = smoothstep(0.74, 0.82, fbm(p * 0.22 + vec2(71.0, 2.0)));
	col = mix(col, soil * vec3(1.05, 1.0, 0.95), bald * 0.85);

	// Вытоптанный двор базы с рваным краем.
	vec2 c = (yard_rect.xy + yard_rect.zw) * 0.5;
	vec2 h = (yard_rect.zw - yard_rect.xy) * 0.5;
	vec2 d = abs(p - c) - h;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	sd += (fbm(p * 0.55) - 0.5) * 2.2;
	float yard = 1.0 - smoothstep(-0.6, 0.5, sd);
	vec3 trodden = soil * (0.9 + 0.2 * fbm(p * 0.9 + vec2(5.0, 5.0)));
	// По краю двора — примятая трава вперемешку с землёй.
	float edge = (1.0 - smoothstep(0.0, 1.6, abs(sd))) * 0.35;
	col = mix(col, mix(col, trodden, 0.55), edge);
	col = mix(col, trodden, yard);

	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.2;
}
"""

static var _material: ShaderMaterial = null

static func get_material(yard: Rect2 = DEFAULT_YARD) -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		var m := ShaderMaterial.new()
		m.shader = shader
		_material = m
	_material.set_shader_parameter("yard_rect", Vector4(yard.position.x, yard.position.y, yard.end.x, yard.end.y))
	return _material

## CPU-копия края двора (без шума) — для раскладки травы и мусора.
static func yard_signed_distance(p: Vector2, yard: Rect2 = DEFAULT_YARD) -> float:
	var c: Vector2 = yard.get_center()
	var h: Vector2 = yard.size * 0.5
	var d := Vector2(absf(p.x - c.x) - h.x, absf(p.y - c.y) - h.y)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)
