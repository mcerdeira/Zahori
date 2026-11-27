shader_type canvas_item;

uniform float amount = 0.2;
uniform sampler2D offset_texture : hint_default_white;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform bool crt = true;
uniform float curvature : hint_range(0.0, 0.3) = 0.035;
uniform float corner_radius : hint_range(0.0, 40.0) = 10.0;
uniform float scanlines : hint_range(0.0, 1.0) = 0.14;
uniform float glow : hint_range(0.0, 1.0) = 0.3;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform float brightness : hint_range(0.5, 1.5) = 1.08;

vec2 warp(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curvature * dot(c, c) * 0.5;
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = crt ? warp(SCREEN_UV) : SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	float off = amount * texture(offset_texture, uv).r / 100.0;
	vec3 col;
	col.r = texture(SCREEN_TEXTURE, vec2(uv.x + off, uv.y)).r;
	col.g = texture(SCREEN_TEXTURE, uv).g;
	col.b = texture(SCREEN_TEXTURE, vec2(uv.x - off, uv.y)).b;

	if (crt) {
		vec3 bloom = vec3(0.0);
		bloom += texture(SCREEN_TEXTURE, uv + vec2(1.5, 0.0) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv - vec2(1.5, 0.0) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv + vec2(0.0, 1.5) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv - vec2(0.0, 1.5) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv + vec2(1.5, 1.5) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv - vec2(1.5, 1.5) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv + vec2(1.5, -1.5) * px).rgb;
		bloom += texture(SCREEN_TEXTURE, uv - vec2(1.5, -1.5) * px).rgb;
		bloom /= 8.0;
		col += bloom * bloom * glow;

		col *= 1.0 - scanlines * mod(floor(uv.y / px.y), 2.0);

		vec2 c = uv - 0.5;
		col *= 1.0 - vignette * dot(c, c) * 2.0;
		col *= brightness;

		vec2 p = abs(c) / px;
		vec2 half_size = 0.5 / px;
		float dist = length(max(p - (half_size - corner_radius), 0.0)) - corner_radius;
		col *= 1.0 - smoothstep(-1.0, 0.5, dist);
	}

	COLOR = vec4(col, 1.0);
}
