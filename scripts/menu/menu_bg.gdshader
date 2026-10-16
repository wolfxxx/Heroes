shader_type canvas_item;
// Procedural fallback backdrop: dusk sky, drifting clouds, layered mountain silhouettes.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.01;
	vec3 top = vec3(0.06, 0.07, 0.16);
	vec3 mid = vec3(0.45, 0.22, 0.20);
	vec3 low = vec3(0.98, 0.62, 0.30);
	vec3 sky = mix(top, mid, smoothstep(0.0, 0.55, uv.y));
	sky = mix(sky, low, smoothstep(0.45, 0.68, uv.y));
	float c = fbm(vec2(uv.x * 3.0 + t, uv.y * 8.0));
	sky = mix(sky, sky * 1.25 + vec3(0.05, 0.02, 0.0), smoothstep(0.55, 0.8, c) * (1.0 - uv.y));
	vec3 col = sky;
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float h = 0.58 + fl * 0.09 + fbm(vec2(uv.x * (2.0 + fl * 1.7) + fl * 3.1, fl)) * (0.22 - fl * 0.04);
		vec3 mc = mix(vec3(0.20, 0.13, 0.18), vec3(0.04, 0.03, 0.05), fl / 2.0);
		col = mix(col, mc, smoothstep(h, h + 0.004, uv.y));
	}
	COLOR = vec4(col, 1.0);
}
