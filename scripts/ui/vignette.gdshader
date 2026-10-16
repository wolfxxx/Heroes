shader_type canvas_item;
uniform float strength = 0.75;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.0, 1.2)));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
