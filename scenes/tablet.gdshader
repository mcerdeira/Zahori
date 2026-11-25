shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec3 light_dir = vec3(-0.4, 0.5, 0.77);
uniform float ambient = 0.42;
uniform float highlight = 1.08;
uniform float steps = 3.0;

varying vec3 v_normal;

void vertex() {
	v_normal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV);
	float d = max(dot(normalize(v_normal), normalize(light_dir)), 0.0);
	d = floor(d * steps + 0.5) / steps;
	ALBEDO = c.rgb * mix(ambient, highlight, d);
}
