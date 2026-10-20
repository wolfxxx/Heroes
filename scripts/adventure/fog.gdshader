shader_type canvas_item;
// Fog of war overlay: fog_map is one texel per tile, 1 = explored. The edge is a smooth field over the 4x4 tiles
// around each pixel (the compact bump kernel of terrain.gdshader), so it is round instead of stair-stepped, then made
// ragged with gradient noise (value noise showed tile-sized squares). Past the map's edge: a ragged band of boulders
// (the classic map's rocky edge) and a dark slate void beyond it, told apart from the black shroud (the view may run
// a little past the edge), never the bare background with stray tree shadows; a soft shadow falls inward along the edge.
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
// The rocky ridge along the map's edge: boulders of varied size (a power diagram: each cell has its own weight), their
// height a rounded shoulder from the cracks with fine crags on it, lit from the upper left by the slope of that height.
// `s` is the depth past the edge (<0: on the map).
vec2 rock_h(vec2 w) {  // (height, the cell's tone)
	vec2 rp = w / 34.0;
	vec2 ri = floor(rp);
	float d1 = 9.0, d2 = 9.0; vec2 cid = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = ri + vec2(float(x), float(y));
			vec2 o = vec2(fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453),
				fract(sin(dot(g, vec2(39.3468, 11.135))) * 24634.6345));
			float wt = fract(sin(dot(g, vec2(5.17, 91.3))) * 3758.31) * 0.45;  // big and small boulders
			vec2 r = g + o - rp;
			float dd = dot(r, r) - wt;
			if (dd < d1) { d2 = d1; d1 = dd; cid = g; }
			else if (dd < d2) { d2 = dd; }
		}
	}
	float gap = d2 - d1;
	float h = sqrt(smoothstep(0.0, 0.6, gap)) * 20.0 + fbm(w / 7.0) * 3.0 + fbm(w / 19.0) * 6.0;
	return vec2(h, fract(sin(dot(cid, vec2(7.13, 3.71))) * 9137.1));
}
vec3 ridge(vec2 w, float s, float band) {
	vec2 h0 = rock_h(w);
	float hx = rock_h(w + vec2(1.5, 0.0)).x;
	float hy = rock_h(w + vec2(0.0, 1.5)).x;
	vec3 n = normalize(vec3(-(hx - h0.x) / 1.5, -(hy - h0.x) / 1.5, 0.9));
	float lit = clamp(dot(n, normalize(vec3(-0.6, -0.7, 0.75))), 0.0, 1.0);
	vec3 rock = mix(vec3(0.34, 0.30, 0.25), vec3(0.50, 0.45, 0.37), h0.y) * (0.38 + 0.9 * lit);
	rock *= mix(0.45, 1.0, smoothstep(0.0, 10.0, h0.x));  // dark in the cracks
	rock *= mix(0.3, 1.0, smoothstep(band, 6.0, s));  // the outer rocks sink into the void
	return rock;
}

void fragment() {
	vec2 mpx = map_size * tile_px;
	vec2 out_v = max(-world, world - mpx);  // >0 past an edge
	float inside = min(min(world.x, world.y), min(mpx.x - world.x, mpx.y - world.y));
	float band = 48.0 + 26.0 * fbm(world / tile_px * 0.6);  // how far the ridge runs out past the edge
	float enc = 8.0 + 14.0 * (fbm(world / 40.0) + 0.5);  // and how far its boulders reach in onto the map (ragged)
	if (inside < 0.0) {
		float d = length(max(out_v, vec2(0.0)));
		// the void: a dark slate, bluer and lighter than the shroud, with a faint grain
		vec3 c = vec3(0.07, 0.075, 0.095) + vec3(0.03, 0.03, 0.035) * (fbm(world / tile_px * 1.3) + 0.5);
		if (d < band) {
			c = mix(c, ridge(world, d, band), smoothstep(band, band - 10.0, d));
		}
		COLOR = vec4(c, 1.0);
	} else {
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
		float edge = pow(max(0.0, 1.0 - (inside - enc) / 26.0), 2.0) * 0.65;  // the ridge's shadow on the map
		float a = 1.0 - vis * (1.0 - min(edge, 0.65));
		float cov = smoothstep(enc + 1.5, enc - 1.5, inside);  // the boulders lying on the map's rim
		vec3 rc = ridge(world, -inside, band);
		float ao = a * (1.0 - cov) + cov;
		COLOR = vec4((fogc * a * (1.0 - cov) + rc * cov) / max(ao, 1e-4), ao);
	}
}
