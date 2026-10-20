shader_type canvas_item;
// The mountains of the map's border stand on the rocky ridge, not in a meadow: the grass at their feet turns to the
// ridge's ochre stone (a green pixel keeps its light, loses its hue).
void fragment() {
	vec4 c = COLOR;  // (the texture, already sampled and modulated)
	float green = clamp((c.g - max(c.r * 0.92, c.b)) * 7.0, 0.0, 1.0);
	float l = dot(c.rgb, vec3(0.3, 0.55, 0.15));
	vec3 rock = vec3(0.62, 0.5, 0.35) * (0.3 + 1.15 * l);
	COLOR = vec4(mix(c.rgb, rock, green), c.a);
}
