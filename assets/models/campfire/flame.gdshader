shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 float y=UV.y; float t=TIME*3.0+phase;
 VERTEX.x += (sin(t-y*5.0)*0.08+sin(t*1.7+y*11.0)*0.035)*y*y;
 VERTEX.z += sin(t*0.8+y*7.0+phase)*0.045*y;
 VERTEX.y *= (0.90+0.10*sin(t*1.3+phase))*mix(0.35,1.0,heat);
}
void fragment() {
 float y=UV.y; float t=TIME*2.4+phase;
 float n=noise(vec2(UV.x*6.0,y*6.0-t))+0.4*noise(vec2(UV.x*14.0,y*13.0-t*1.7));
 float dist=abs(UV.x-0.5)*2.0;
 float alpha=(1.0-smoothstep(0.35,1.0,dist+0.17*(n-0.5))) * (1.0-smoothstep(0.72,1.0,y)) * smoothstep(0.0,0.09,y);
 float core=(1.0-smoothstep(0.13,0.70,dist))*(1.0-smoothstep(0.28,0.86,y));
 vec3 orange=vec3(1.0,0.22+0.12*n,0.025);
 vec3 yellow=vec3(1.0,0.91,0.25);
 ALBEDO=mix(orange,yellow,core);
 EMISSION=ALBEDO*1.25;
 ALPHA=alpha*heat*0.85;
}
