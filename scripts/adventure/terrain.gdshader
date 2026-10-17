shader_type canvas_item;
// Adventure-map ground. Each tile's terrain spreads as a soft blob (a bump reaching 1.5 tiles, summed over the 4x4
// tiles around the pixel), so borders come out rounded instead of stair-stepped; noise makes them ragged and a thin darker rim
// outlines them like painted terrain edges. Water gets a wet shore, foam and depth. Roads are cobbles drawn
// where the road distance field (in tiles, from map_view._road_field) is small.

uniform sampler2DArray terrain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D index_map : filter_nearest;
uniform sampler2D road_map : filter_linear;
uniform sampler2D road_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 map_size = vec2(48.0, 48.0);
uniform float tile_px = 64.0;
uniform float tex_tiles = 4.0;
uniform int water_index = 5;
uniform int snow_index = 3;
uniform float road_reach = 0.9;   // map_view.ROAD_REACH
uniform float road_half = 0.27;   // cobbled half-width, tiles
uniform float stone_px = 11.0;

varying vec2 world;

void vertex() { world = VERTEX; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
// gradient noise in [0, 1]: no grid-aligned blocks when it is thresholded (value noise showed tile squares)
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash2(i) * 2.0 - 1.0, f);
	float b = dot(hash2(i + vec2(1, 0)) * 2.0 - 1.0, f - vec2(1, 0));
	float c = dot(hash2(i + vec2(0, 1)) * 2.0 - 1.0, f - vec2(0, 1));
	float d = dot(hash2(i + vec2(1, 1)) * 2.0 - 1.0, f - vec2(1, 1));
	return clamp(0.5 + 0.9 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y), 0.0, 1.0);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));   // each octave turned, so no grid lines add up
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = rot * p * 2.07 + 11.3; a *= 0.5; }
	return v;
}

int tidx(vec2 c) {
	ivec2 ic = ivec2(clamp(c, vec2(0.0), map_size - 1.0));
	return int(texelFetch(index_map, ic, 0).r * 255.0 + 0.5);
}

vec3 sample_t(int i, vec2 uv) {
	if (i == water_index) {
		vec2 d = vec2(noise(uv * 9.0 + TIME * 0.25), noise(uv * 9.0 - TIME * 0.21 + 3.0)) - 0.5;
		vec3 c = texture(terrain_tex, vec3(uv + d * 0.025, float(i))).rgb;
		float glint = smoothstep(0.78, 0.95, noise(uv * 22.0 + vec2(TIME * 0.4, -TIME * 0.3)));
		return c + vec3(0.25, 0.3, 0.3) * glint * 0.5;
	}
	vec3 c = texture(terrain_tex, vec3(uv, float(i))).rgb;
	if (i == snow_index) {   // cool blue hollows and warm drifts, so snowfields aren't flat white
		float n = fbm(uv * 5.0 + 3.7);
		c *= mix(vec3(0.87, 0.91, 1.0), vec3(1.03, 1.02, 0.99), smoothstep(0.3, 0.7, n));
	}
	return c;
}

// Cobbles: x = distance to the stone's edge (cell units), yz = pixel -> stone centre, w = stone id hash.
vec4 voronoi(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x);
	vec2 mg = vec2(0.0); vec2 mr = vec2(0.0); float md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 r = g + 0.5 + 0.38 * (hash2(n + g) - 0.5) * 2.0 - f;
		float d = dot(r, r);
		if (d < md) { md = d; mr = r; mg = g; }
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
		vec2 g = mg + vec2(float(i), float(j));
		vec2 r = g + 0.5 + 0.38 * (hash2(n + g) - 0.5) * 2.0 - f;
		if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
	}
	return vec4(md, mr, hash(n + mg));
}

void fragment() {
	vec2 tp = world / tile_px;
	vec2 uv = world / (tile_px * tex_tiles);
	// low-frequency warp: borders meander instead of following the grid
	vec2 warp = vec2(fbm(tp * 0.7), fbm(tp * 0.7 + 17.3)) - 0.5;
	vec2 q = tp + warp * 1.5;

	// terrain weights: a smooth bump per tile, zero beyond 1.5 tiles so the 4x4 window never cuts one off
	float wsum[8];
	for (int k = 0; k < 8; k++) wsum[k] = 0.0;
	vec2 base = floor(q - 0.5) - 1.0;
	for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
		vec2 c = base + vec2(float(i), float(j));
		vec2 dd = q - (c + 0.5);
		float b = max(0.0, 1.0 - dot(dd, dd) / 2.25);
		wsum[tidx(c)] += b * b * b * b;
	}
	int t1 = 0; int t2 = 0; float w1 = -1.0; float w2 = -1.0;
	for (int k = 0; k < 8; k++) {
		float w = wsum[k];
		if (w > w1) { w2 = w1; t2 = t1; w1 = w; t1 = k; }
		else if (w > w2) { w2 = w; t2 = k; }
	}
	// s ~ 3.6 x distance to the border in tiles (0 on it, growing inside t1)
	float s = log(max(w1, 1e-6) / max(w2, 1e-6));
	float rag = (noise(tp * 3.7) - 0.5) * 0.85 + (noise(tp * 10.3) - 0.5) * 0.45;
	bool wet = (t1 == water_index) != (t2 == water_index);
	float sr = s + (wet ? rag * 0.6 : rag);
	float a = w2 <= 0.0 ? 1.0 : smoothstep(-0.55, 0.55, sr);   // weight of t1
	vec3 col = mix(sample_t(t2, uv), sample_t(t1, uv), a);

	if (w2 > 0.0 && !wet) {
		// thin painted rim along terrain borders
		float rim = 1.0 - smoothstep(0.0, 0.35, abs(sr));
		col *= 1.0 - 0.2 * rim;
	}
	if (wet) {
		// signed distance from the waterline: > 0 on water, < 0 on land
		float sw = (t1 == water_index ? sr : -sr);
		float land = 1.0 - smoothstep(-0.55, 0.55, sw);
		col *= mix(1.0, 0.7, (1.0 - smoothstep(0.0, 1.9, -sw)) * land);   // wet ground near the water
		float foam = smoothstep(0.12, 0.45, sw) * (1.0 - smoothstep(0.45, 1.0, sw));
		foam *= 0.55 + 0.45 * sin(TIME * 1.5 + (tp.x + tp.y) * 3.0) * noise(tp * 6.0 + TIME * 0.2);
		col = mix(col, vec3(0.85, 0.92, 0.9), clamp(foam, 0.0, 1.0) * 0.5);
	}
	if (t1 == water_index) {
		col *= mix(1.0, 0.74, smoothstep(0.6, 3.5, s));   // deeper water away from the shore
	}

	// ---- road ----
	float rd = texture(road_map, tp / map_size).r * road_reach;
	if (rd < road_half + 0.3) {
		float e = rd + (fbm(tp * 2.3) - 0.5) * 0.12 + (noise(tp * 8.7) - 0.5) * 0.06;
		vec3 dirt = texture(road_tex, world / 256.0).rgb;
		float shoulder = 1.0 - smoothstep(road_half - 0.02, road_half + 0.16, e);
		col = mix(col, dirt * 0.92, shoulder * 0.9);
		if (e < road_half + 0.02) {
			vec4 v = voronoi(world / stone_px);
			// stones thin out towards the edge, so the road frays into its gravel shoulder
			float fray = smoothstep(road_half - 0.16, road_half + 0.02, e);
			if (v.w > fray * 1.1 - 0.05) {
				float stone = smoothstep(0.04, 0.11, v.x);
				float dome = 1.0 - smoothstep(0.05, 0.32, v.x);
				float lit = dot(normalize(v.yz + 1e-4), vec2(0.7071, 0.7071)) * dome;   // light from the top left
				float grain = dot(dirt, vec3(0.333));
				vec3 sc = mix(vec3(0.50, 0.46, 0.40), vec3(0.72, 0.67, 0.57), hash(vec2(v.w, 3.1)));
				sc = mix(sc, sc * vec3(1.05, 0.98, 0.9), hash(vec2(v.w, 7.7)));
				sc *= (0.8 + 0.45 * grain) * (1.0 + 0.32 * lit);
				vec3 gap = dirt * 0.5;
				col = mix(gap, sc, stone);
			}
		}
	}

	// large-scale colour variation so tiling is not visible
	float v = fbm(tp * 0.18);
	col *= 0.86 + 0.28 * v;
	COLOR = vec4(col, 1.0);
}
