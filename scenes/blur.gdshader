shader_type canvas_item;
// Desenfoque circular barato (dos anillos de muestras): para las capas
// "fuera de foco" del título.

uniform float radius = 2.0; // en texels de la textura

varying vec4 tint;

void vertex() {
	tint = COLOR; // modulate (en fragment COLOR ya viene multiplicado por la textura)
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	vec4 sum = texture(TEXTURE, UV) * 0.16;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 d = vec2(cos(a), sin(a));
		sum += texture(TEXTURE, UV + d * px * 0.5) * 0.065;
		sum += texture(TEXTURE, UV + d * px) * 0.04;
	}
	COLOR = sum * tint;
}
