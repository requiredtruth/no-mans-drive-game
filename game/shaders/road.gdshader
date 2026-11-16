shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_asphalt : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness = 0.0;

void vertex() {
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec2 tuv = vec2(u * 3.4, v * 2.6);
	vec3 asphalt = texture(tex_asphalt, tuv).rgb;
	float wear = clamp(texture(tex_asphalt, vec2(u * 0.37, v * 0.05)).r * 2.6, 0.0, 1.0);
	// lane markings
	float center = step(abs(u - 0.5), 0.011) * step(0.45, fract(v * 0.5));
	float edge = step(abs(abs(u - 0.5) - 0.405), 0.008);
	float paint = max(center, edge) * smoothstep(0.25, 0.45, wear);
	vec3 col = mix(asphalt, center > 0.5 ? vec3(0.85, 0.68, 0.22) : vec3(0.82), paint * 0.85);
	// crumbling shoulder
	float shoulder = smoothstep(0.43, 0.5, abs(u - 0.5) + (wear - 0.5) * 0.08);
	col = mix(col, texture(tex_dirt, tuv * 0.8).rgb * 0.9, shoulder);
	ALBEDO = col * mix(1.0, 0.55, wetness);
	ROUGHNESS = mix(0.88, 0.18, wetness * (1.0 - shoulder));
	NORMAL_MAP = texture(n_asphalt, tuv).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	SPECULAR = mix(0.4, 0.8, wetness);
}
