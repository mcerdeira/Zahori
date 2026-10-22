shader_type canvas_item;

// 0 = colores normales, 1 = silueta 100% negra (respeta la transparencia)
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), amount);
}
