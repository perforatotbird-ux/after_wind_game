shader_type spatial;
render_mode cull_disabled;
uniform sampler2D wood_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cracks_texture : filter_linear_mipmap, repeat_enable;
uniform float char_amount : hint_range(0.0,1.0) = 0.0;
uniform float ember_heat : hint_range(0.0,1.0) = 0.0;
uniform bool coal = false;
void fragment() {
 vec3 wood=texture(wood_texture,UV).rgb;
 float mask=texture(cracks_texture,UV*vec2(2.0,1.3)).r;
 float ridges=0.5+0.5*sin(UV.x*125.0+sin(UV.y*7.0)*1.5);
 float ash=max(0.0,sin(UV.x*19.0+UV.y*8.0));
 vec3 burnt=vec3(0.037,0.036,0.035)+wood*0.09+ridges*0.014+ash*0.028-mask*0.018;
 ALBEDO=mix(wood,burnt,char_amount);
 ROUGHNESS=0.93;
 float flicker=0.8+0.2*sin(TIME*3.1+UV.x*16.0+UV.y*23.0);
 EMISSION=vec3(1.0,0.18,0.018)*mask*ember_heat*flicker*(coal ? 1.8 : 0.65);
}
