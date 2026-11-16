shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D nmap : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.04, 0.16, 0.19);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.65, 0.72);
uniform float daylight = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
	VERTEX.y += sin(TIME * 1.3 + wpos.x * 0.4 + wpos.z * 0.3) * 0.03;
}

void fragment() {
	vec2 uv = wpos.xz * 0.06;
	vec3 n1 = texture(nmap, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 n2 = texture(nmap, uv * 1.9 - TIME * vec2(0.009, 0.014)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, sky_tint * daylight, fres * 0.65);
	ALPHA = mix(0.78, 0.97, fres);
	ROUGHNESS = 0.04;
	METALLIC = 0.1;
	SPECULAR = 0.9;
}
