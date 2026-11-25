shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5) {
		COLOR = vec4(c.rgb, 1.0);
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float a = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
				+ texture(TEXTURE, UV - vec2(px.x, 0.0)).a
				+ texture(TEXTURE, UV + vec2(0.0, px.y)).a
				+ texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		COLOR = a > 0.5 ? outline_color : vec4(0.0);
	}
}
