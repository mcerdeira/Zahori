shader_type canvas_item;

// Disolución pixel a pixel de la copia del agua: cada pixel tiene un umbral
// al azar y desaparece cuando progress lo pasa. Antes de irse se blanquea.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

varying vec2 world_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_px = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = floor(world_px);
	// los pixels de arriba se van un poco antes (el vapor sube)
	float th = hash(px) * 0.8 + fract(px.y / 16.0) * 0.2;
	if (progress > th) {
		discard;
	}
	float heat = smoothstep(0.0, 0.6, progress);
	c.rgb = mix(c.rgb, vec3(0.9, 0.97, 1.0), heat);
	COLOR = c;
}
