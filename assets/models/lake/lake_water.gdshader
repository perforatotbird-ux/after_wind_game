shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Standalone material: no autoloads, gameplay nodes or world assumptions.
// Local coordinates keep the wind stable when the model is moved in a level.
uniform float wind_strength : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float wind_speed : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float preview_time = -1.0; // -1: realtime; nonnegative: deterministic capture.
uniform vec3 deep_color : source_color = vec3(0.17, 0.31, 0.28);
uniform vec3 shallow_color : source_color = vec3(0.40, 0.51, 0.38);
uniform float water_opacity : hint_range(0.0, 1.0, 0.01) = 0.88;
varying vec2 water_position;
varying float shore_depth;

float noise_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float smooth_noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise_hash(i), noise_hash(i + vec2(1.0, 0.0)), f.x),
               mix(noise_hash(i + vec2(0.0, 1.0)), noise_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    float t = (preview_time < 0.0 ? TIME : preview_time) * wind_speed;
    vec2 p = VERTEX.xz;
    water_position = p;
    // The imported colour gradient encodes depth. Dampen waves at the bank.
    float shallow = clamp((COLOR.r - 0.06) / 0.13, 0.0, 1.0);
    shore_depth = 1.0 - shallow;
    float edge = 1.0 - pow(shallow, 1.3333);
    float a = dot(p, vec2(1.9, -0.8)) - t * 0.785398;
    float b = dot(p, vec2(-1.2, -2.4)) - t * 1.570796;
    float amplitude = 0.023 * wind_strength * edge;
    VERTEX.y += amplitude * (sin(a) + 0.47826 * sin(b));
    float dx = amplitude * (1.9 * cos(a) - 0.573912 * cos(b));
    float dz = amplitude * (-0.8 * cos(a) - 1.147824 * cos(b));
    NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
    float t = (preview_time < 0.0 ? TIME : preview_time) * wind_speed;
    vec2 p = water_position;
    // Two crossing, low-contrast capillary ripple fields rather than noisy foam.
    float a = dot(p, vec2(15.0, 7.0)) - t * 1.570796;
    float b = dot(p, vec2(-9.0, 19.0)) - t * 2.356194;
    vec3 local_normal = normalize(vec3(
        -(0.048 * cos(a) - 0.026 * cos(b)) * wind_strength,
        1.0,
        -(0.022 * cos(a) + 0.055 * cos(b)) * wind_strength));
    NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(local_normal, 0.0)).xyz + NORMAL * 0.7);
    ALBEDO = mix(shallow_color, deep_color, shore_depth);
    float breakup = 0.45 + 0.55 * pow(sin(dot(p, vec2(-1.5, 2.0)) + t * 0.785398), 2.0);
    float irregular_phase = a + smooth_noise(p * 2.3) * 3.7;
    float wavelet_mask = smoothstep(0.34, 0.69, smooth_noise(p * vec2(3.3, 1.8) + vec2(4.0, -1.0)));
    float capillary_sheen = pow(max(0.0, sin(irregular_phase)), 12.0) * breakup * wavelet_mask;
    ALBEDO += vec3(0.024, 0.032, 0.030) * capillary_sheen * (0.25 + 0.75 * shore_depth) * wind_strength;
    ROUGHNESS = 0.27 + 0.025 * sin(a) * sin(b);
    SPECULAR = 0.42;
    METALLIC = 0.0;
    ALPHA = water_opacity;
}
