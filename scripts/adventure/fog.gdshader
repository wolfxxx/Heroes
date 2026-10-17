shader_type canvas_item;
// Fog of war overlay: fog_map is one texel per tile, 1 = explored. The edge is a smooth field over the 4x4 tiles
// around each pixel (the compact bump kernel of terrain.gdshader), so it is round instead of stair-stepped, then made
// ragged with gradient noise (value noise showed tile-sized squares).
uniform sampler2D fog_map : filter_nearest;
uniform vec2 map_size = vec2(48.0, 48.0);
uniform float tile_px = 64.0;
varying vec2 world;
void vertex() { world = VERTEX; }

vec2 grad(vec2 p) {
	float a = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453) * 6.2831853;
	return vec2(cos(a), sin(a));
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i), f);
	float b = dot(grad(i + vec2(1, 0)), f - vec2(1, 0));
	float c = dot(grad(i + vec2(0, 1)), f - vec2(0, 1));
	float d = dot(grad(i + vec2(1, 1)), f - vec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);  // about -0.7..0.7
}
float fbm(vec2 p) {
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float s = 0.0, amp = 0.5;
	for (int i = 0; i < 3; i++) { s += amp * noise(p); p = rot * p * 2.03; amp *= 0.5; }
	return s;
}
float explored(vec2 t) {
	vec2 c = clamp(t, vec2(0.0), map_size - 1.0);
	return texture(fog_map, (c + 0.5) / map_size).r;
}
void fragment() {
	vec2 tp = world / tile_px;
	vec2 base = floor(tp - 0.5) - 1.0;
	float ws = 0.0, es = 0.0;
	for (int y = 0; y < 4; y++) {
		for (int x = 0; x < 4; x++) {
			vec2 t = base + vec2(float(x), float(y));
			float d2 = dot(tp - (t + 0.5), tp - (t + 0.5));
			float w = pow(max(0.0, 1.0 - d2 / 2.25), 4.0);
			ws += w;
			es += w * explored(t);
		}
	}
	float e = es / max(ws, 1e-4);
	float vis = smoothstep(0.38, 0.62, e + fbm(tp * 1.7) * 0.32);
	vec3 fogc = vec3(0.02, 0.02, 0.03) + vec3(0.025) * (fbm(tp * 0.9) + 0.5);
	COLOR = vec4(fogc, 1.0 - vis);
}
