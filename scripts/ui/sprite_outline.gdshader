shader_type canvas_item;
// Ink outline + warm top-left rim light for 3D-rendered sprites. The outline width is in SCREEN pixels:
// px = texture pixels per screen pixel (1 / draw scale), so it stays visible on scaled-down sprites.
uniform float px = 2.0;
uniform float width = 2.0;
uniform vec4 ink : source_color = vec4(0.09, 0.06, 0.03, 0.95);
uniform vec4 rim : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float rim_strength = 0.35;
uniform float saturation = 1.15;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;  // modulate (hit flashes, fades)
}

void fragment() {
	vec2 t = TEXTURE_PIXEL_SIZE * px * width;
	vec4 c = texture(TEXTURE, UV);
	float a = c.a;
	float m = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		m = max(m, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * t).a);
	}
	float ul = texture(TEXTURE, UV + vec2(-1.0, -1.0) * t * 0.8).a;
	float rimf = clamp(a - ul, 0.0, 1.0) * rim_strength;
	vec3 col = c.rgb;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	col = mix(col, rim.rgb, rimf);
	float oa = ink.a * clamp(m - a, 0.0, 1.0);
	float alpha = a + oa * (1.0 - a);
	vec3 rgb = (col * a + ink.rgb * oa * (1.0 - a)) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha) * vcol;
}
