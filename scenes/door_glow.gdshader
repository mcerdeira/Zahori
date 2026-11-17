shader_type canvas_item;
render_mode blend_add, unshaded;

// Luz que sale del hueco de una puerta instant. Aditiva: en negro no aporta
// nada, así el frame negro de la animación hace de "apagado" del parpadeo.
uniform vec2 rect_size;      // px, tamaño del ColorRect
uniform vec2 hole_half;      // px, mitad del tamaño del hueco (collider)
uniform float radius = 40.0; // px que se extiende la luz
uniform int steps = 4;       // bandas de la degradación
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float strength = 0.45;

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	// distancia al borde del hueco (0 adentro)
	float d = length(max(abs(p) - hole_half, vec2(0.0)));
	float t = clamp(1.0 - d / radius, 0.0, 1.0);
	t = ceil(t * float(steps)) / float(steps); // bandas tipo pixel art
	t *= t;
	COLOR = vec4(glow_color.rgb * t * strength, 1.0);
}
