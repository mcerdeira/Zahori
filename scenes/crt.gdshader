shader_type canvas_item;

// Efecto de monitor CRT para la terminal: brillo del fósforo (glow), scanlines,
// banda de refresco que baja, parpadeo leve y viñeta en las esquinas.

uniform float glow : hint_range(0.0, 2.0) = 0.9;
uniform float scanlines : hint_range(0.0, 1.0) = 0.2;
uniform float flicker : hint_range(0.0, 0.2) = 0.03;
uniform float vignette : hint_range(0.0, 1.0) = 0.5;
uniform float band_speed = 0.18; // pantallas por segundo
uniform vec3 phosphor : source_color = vec3(0.015, 0.035, 0.055); // el "negro" del tubo

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 base = texture(TEXTURE, UV).rgb;

	// Glow: promedio ponderado de los vecinos
	vec3 blur = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = 1.0 / (1.0 + float(x * x + y * y));
			blur += texture(TEXTURE, UV + vec2(float(x), float(y)) * px).rgb * w;
			total += w;
		}
	}
	vec3 col = base + blur / total * glow + phosphor;

	// Scanlines: una fila de píxeles de cada dos más oscura
	col *= 1.0 - scanlines * mod(floor(UV.y / px.y), 2.0);

	// Banda de refresco más clara
	float band = fract(UV.y - TIME * band_speed);
	col += vec3(0.02, 0.05, 0.07) * smoothstep(0.85, 1.0, band);

	col *= 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 53.0));

	vec2 c = UV - 0.5;
	col *= 1.0 - vignette * dot(c, c) * 2.0;

	COLOR = vec4(col, 1.0);
}
