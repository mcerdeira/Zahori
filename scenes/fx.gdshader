shader_type canvas_item;

uniform float amount = 0.2;
uniform sampler2D offset_texture : hint_default_white;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 texture_color = texture(SCREEN_TEXTURE, SCREEN_UV);
	vec4 color = texture_color;

	float adjusted_amount = amount * texture(offset_texture, SCREEN_UV).r / 100.0;
	color.r = texture(SCREEN_TEXTURE, vec2(SCREEN_UV.x + adjusted_amount, SCREEN_UV.y)).r;
	color.g = texture(SCREEN_TEXTURE, SCREEN_UV).g;
	color.b = texture(SCREEN_TEXTURE, vec2(SCREEN_UV.x - adjusted_amount, SCREEN_UV.y)).b;

	COLOR = color;
}