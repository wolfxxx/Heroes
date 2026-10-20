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
void fragment() {
	vec2 mpx = map_size * tile_px;
	vec2 out_v = max(-world, world - mpx);  // >0 past an edge
	float inside = min(min(world.x, world.y), min(mpx.x - world.x, mpx.y - world.y));
	if (inside < 0.0) {
		float d = length(max(out_v, vec2(0.0)));
		vec2 q = world / tile_px * 1.3;
		// the void: a dark slate, bluer and lighter than the shroud, with a faint grain
		vec3 c = vec3(0.07, 0.075, 0.095) + vec3(0.03, 0.03, 0.035) * (fbm(q) + 0.5);
		float band = 48.0 + 26.0 * fbm(world / tile_px * 0.6);  // a ragged band of rocks along the edge
		if (d < band) {
			// boulders: voronoi cells shaded as domes lit from the upper left, dark cracks between them
			vec2 rp = world / 30.0;
			vec2 ri = floor(rp);
			float d1 = 9.0, d2 = 9.0; vec2 cc = vec2(0.0); vec2 cid = vec2(0.0);
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec2 g = ri + vec2(float(x), float(y));
					vec2 o = vec2(fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453),
						fract(sin(dot(g, vec2(39.3468, 11.135))) * 24634.6345));
					vec2 r = g + o - rp;
					float dd = dot(r, r);
					if (dd < d1) { d2 = d1; d1 = dd; cc = r; cid = g; }
					else if (dd < d2) { d2 = dd; }
				}
			}
			float gap = sqrt(d2) - sqrt(d1);
			float crack = smoothstep(0.0, 0.08, gap);
			float rim = smoothstep(0.0, 0.35, gap);  // rounded shoulders darken toward the cracks
			float lit = clamp(0.5 + dot(normalize(-cc + vec2(0.0001)), vec2(-0.6, -0.7)) * 0.6 * min(1.0, sqrt(d1) * 2.2), 0.0, 1.0);
			float tone = fract(sin(dot(cid, vec2(7.13, 3.71))) * 9137.1);
			vec3 rock = mix(vec3(0.30, 0.27, 0.23), vec3(0.46, 0.41, 0.34), tone) * (0.45 + 0.95 * lit) * mix(0.6, 1.0, rim);
			rock *= 0.85 + 0.3 * (fbm(world / 9.0) + 0.5) * 0.5;
			rock = mix(vec3(0.05, 0.04, 0.035), rock, crack);
			float fade = smoothstep(band, band - 10.0, d);  // the outer rocks sink into the void
			rock *= mix(0.35, 1.0, smoothstep(band, 4.0, d));
			c = mix(c, rock, fade);
			c = mix(c, vec3(0.04, 0.03, 0.02), smoothstep(3.0, 0.0, d) * 0.8);  // a dark seam at the map's edge
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
		float edge = pow(max(0.0, 1.0 - inside / 22.0), 2.0) * 0.6;  // a soft shadow in along the edge
		COLOR = vec4(fogc, 1.0 - vis * (1.0 - edge));
	}
}
