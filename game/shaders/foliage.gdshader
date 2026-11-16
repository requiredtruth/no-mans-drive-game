shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wind_strength = 0.12;
uniform float sway_height = 1.0;
uniform float fade_start = 400.0;

varying vec3 inst;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0) / sway_height;
	float t = TIME * 1.7 + wp.x * 0.13 + wp.z * 0.09;
	float gust = 0.7 + 0.3 * sin(TIME * 0.31 + wp.x * 0.01);
	VERTEX.x += sin(t) * wind_strength * h * h * gust;
	VERTEX.z += cos(t * 0.83) * wind_strength * h * h * 0.6 * gust;
	inst = COLOR.rgb;
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * tint * inst;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
