shader_type canvas_item;
// Ink outline + warm top-left rim light for 3D-rendered sprites. The outline width is in SCREEN pixels:
// px = texture pixels per screen pixel (1 / draw scale), so it stays visible on scaled-down sprites.
uniform float px = 2.0;
uniform float width = 2.0;
uniform vec4 ink : source_color = vec4(0.09, 0.06, 0.03, 0.95);
uniform vec4 rim : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float rim_strength = 0.35;
uniform float saturation = 1.15;
// optional owner-colour ring outside the ink (heroes on the map): alpha 0 = off
uniform vec4 team : source_color = vec4(0.0);

// see-through windows (battle): ellipses in canvas space (centre x, y, radius x, y) where the figure fades to
// hole_alpha, so a stack standing behind it stays readable
uniform vec4 holes[4];
uniform int hole_count = 0;
uniform float hole_alpha = 0.4;
// the whole figure faded evenly (battle: it stands in front of the stack in play)
uniform float body_alpha = 1.0;

varying vec4 vcol;
varying vec2 world;

void vertex() {
	vcol = COLOR;  // modulate (hit flashes, fades)
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
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
	if (team.a > 0.0) {
		float m2 = 0.0;
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.523599;
			m2 = max(m2, smoothstep(0.55, 0.85, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * t * 1.8).a));  // solid figure only, not its soft shadow
		}
		float ta = team.a * clamp(m2 - smoothstep(0.55, 0.85, alpha), 0.0, 1.0);
		float a2 = alpha + ta * (1.0 - alpha);
		rgb = (rgb * alpha + team.rgb * ta * (1.0 - alpha)) / max(a2, 0.0001);
		alpha = a2;
	}
	float keep = 1.0;
	for (int i = 0; i < hole_count; i++) {
		vec2 d = (world - holes[i].xy) / holes[i].zw;
		keep = min(keep, mix(hole_alpha, 1.0, smoothstep(0.5, 1.0, length(d))));
	}
	COLOR = vec4(rgb, alpha * keep * body_alpha) * vcol;
}
