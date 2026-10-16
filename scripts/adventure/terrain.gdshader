shader_type canvas_item;
// Blended terrain: per-tile terrain index map, textures in a Texture2DArray, organic warped borders,
// animated water with shoreline foam and wet-sand darkening.

uniform sampler2DArray terrain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D index_map : filter_nearest;
uniform vec2 map_size = vec2(48.0, 48.0);
uniform float tile_px = 64.0;
uniform float tex_tiles = 4.0;
uniform int water_index = 5;
uniform int road_index = 6;

varying vec2 world;

void vertex() { world = VERTEX; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}

int tidx(vec2 c) {
	ivec2 ic = ivec2(clamp(c, vec2(0.0), map_size - 1.0));
	return int(texelFetch(index_map, ic, 0).r * 255.0 + 0.5);
}

vec3 sample_t(int i, vec2 uv) {
	vec3 c = texture(terrain_tex, vec3(uv, float(i))).rgb;
	if (i == water_index) {
		vec2 d = vec2(noise(uv * 9.0 + TIME * 0.25), noise(uv * 9.0 - TIME * 0.21 + 3.0)) - 0.5;
		c = texture(terrain_tex, vec3(uv + d * 0.025, float(i))).rgb;
		float glint = smoothstep(0.78, 0.95, noise(uv * 22.0 + vec2(TIME * 0.4, -TIME * 0.3)));
		c += vec3(0.25, 0.3, 0.3) * glint * 0.5;
	}
	return c;
}

void fragment() {
	vec2 tp = world / tile_px;
	vec2 uv = world / (tile_px * tex_tiles);
	// Warp the lookup so borders between terrains meander naturally.
	vec2 warp = vec2(fbm(tp * 0.9), fbm(tp * 0.9 + 17.3)) - 0.5;
	vec2 q = tp + warp * 1.5 - 0.5;
	vec2 i = floor(q);
	vec2 f = fract(q);
	int a = tidx(i);
	int b = tidx(i + vec2(1, 0));
	int c = tidx(i + vec2(0, 1));
	int d = tidx(i + vec2(1, 1));
	// Sharpen transitions: wide stable centres, ~40% blend zone.
	vec2 s = smoothstep(0.18, 0.82, f);
	float wa = (1.0 - s.x) * (1.0 - s.y);
	float wb = s.x * (1.0 - s.y);
	float wc = (1.0 - s.x) * s.y;
	float wd = s.x * s.y;
	// Roads are narrower than their tiles: shrink their influence.
	float rk = 2.2;
	if (a == road_index) wa = pow(wa, rk);
	if (b == road_index) wb = pow(wb, rk);
	if (c == road_index) wc = pow(wc, rk);
	if (d == road_index) wd = pow(wd, rk);
	float sum = wa + wb + wc + wd;
	wa /= sum; wb /= sum; wc /= sum; wd /= sum;

	vec3 col = sample_t(a, uv) * wa + sample_t(b, uv) * wb + sample_t(c, uv) * wc + sample_t(d, uv) * wd;

	float water = (a == water_index ? wa : 0.0) + (b == water_index ? wb : 0.0) + (c == water_index ? wc : 0.0) + (d == water_index ? wd : 0.0);
	if (water > 0.0 && water < 1.0) {
		// Shore: darken wet land, add a foam line on the water side.
		float shore = 1.0 - abs(water - 0.5) * 2.0;
		col *= mix(1.0, 0.72, smoothstep(0.0, 0.5, water) * (1.0 - smoothstep(0.5, 0.75, water)));
		float foam = smoothstep(0.55, 0.62, water) * (1.0 - smoothstep(0.62, 0.75, water));
		foam *= 0.6 + 0.4 * sin(TIME * 1.5 + (tp.x + tp.y) * 3.0);
		col = mix(col, vec3(0.85, 0.92, 0.9), foam * 0.55);
	}
	// Large-scale colour variation so tiling is not visible.
	float v = fbm(tp * 0.18);
	col *= 0.86 + 0.28 * v;
	COLOR = vec4(col, 1.0);
}
