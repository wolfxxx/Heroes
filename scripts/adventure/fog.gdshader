shader_type canvas_item;
// Fog of war overlay: fog_map is one texel per tile, 1 = explored.
uniform sampler2D fog_map : filter_linear;
uniform vec2 map_size = vec2(48.0, 48.0);
uniform float tile_px = 64.0;
varying vec2 world;
void vertex() { world = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec2 tp = world / tile_px;
	float e = texture(fog_map, tp / map_size).r;
	float n = noise(tp * 2.3) * 0.5 + noise(tp * 5.1) * 0.25;
	float vis = smoothstep(0.35, 0.75, e + (n - 0.375) * 0.5);
	vec3 fogc = vec3(0.02, 0.02, 0.03) + vec3(0.03) * noise(tp * 1.3);
	COLOR = vec4(fogc, 1.0 - vis);
}
