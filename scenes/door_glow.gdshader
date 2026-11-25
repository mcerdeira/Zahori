shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 rect_size;
uniform vec2 hole_half;
uniform float radius = 40.0;
uniform int steps = 4;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float strength = 0.45;

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float d = length(max(abs(p) - hole_half, vec2(0.0)));
	float t = clamp(1.0 - d / radius, 0.0, 1.0);
	t = ceil(t * float(steps)) / float(steps);
	t *= t;
	COLOR = vec4(glow_color.rgb * t * strength, 1.0);
}
