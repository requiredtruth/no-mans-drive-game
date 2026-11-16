shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_grass : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_rock : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_sand : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float snow_cover = 0.0;
uniform float wetness = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

vec3 two_scale(sampler2D t, vec2 uv) {
	return mix(texture(t, uv * 0.22).rgb, texture(t, uv * 0.047).rgb, 0.4);
}

void fragment() {
	vec2 uv = wpos.xz;
	float desert = COLOR.r;
	float forest = COLOR.g;
	float tundra = COLOR.b;
	float plains = max(0.0, 1.0 - desert - forest - tundra);
	vec3 grass = two_scale(tex_grass, uv);
	vec3 dirt = two_scale(tex_dirt, uv);
	vec3 forest_floor = mix(grass * vec3(0.78, 0.86, 0.66), dirt, 0.42);
	vec3 sand = two_scale(tex_sand, uv) * vec3(0.7, 0.6, 0.47);
	vec3 snow = two_scale(tex_snow, uv);
	vec3 alb = grass * plains + forest_floor * forest + sand * desert + snow * tundra;
	float macro = texture(tex_grass, uv * 0.0045).g;
	alb *= 0.82 + 0.36 * macro;
	alb = mix(alb, dirt, clamp(COLOR.a, 0.0, 1.0) * 0.85);
	vec3 n = normalize(wnorm);
	float rockm = smoothstep(0.22, 0.38, 1.0 - n.y);
	vec3 rx = texture(tex_rock, wpos.zy * 0.14).rgb;
	vec3 rz = texture(tex_rock, wpos.xy * 0.14).rgb;
	vec3 ry = texture(tex_rock, wpos.xz * 0.14).rgb;
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 rock = rx * bw.x + ry * bw.y + rz * bw.z;
	alb = mix(alb, rock * mix(vec3(1.0), vec3(1.05, 0.9, 0.75), desert), rockm);
	alb = mix(alb, snow, snow_cover * smoothstep(0.55, 0.9, n.y));
	ALBEDO = alb * mix(1.0, 0.62, wetness);
	ROUGHNESS = mix(0.96, 0.35, wetness);
	vec3 ng = texture(n_grass, uv * 0.22).rgb;
	vec3 ns = texture(n_sand, uv * 0.22).rgb;
	vec3 nr = texture(n_rock, wpos.xz * 0.14).rgb;
	vec3 nm = mix(mix(ng, ns, desert), nr, rockm);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.9;
}
