shader_type sky;

uniform vec3 day_top : source_color = vec3(0.24, 0.45, 0.78);
uniform vec3 day_horizon : source_color = vec3(0.70, 0.80, 0.88);
uniform vec3 night_top : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 night_horizon : source_color = vec3(0.04, 0.05, 0.09);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.15);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float daylight = 1.0;
uniform float sunset = 0.0;
uniform float cloud_cover = 0.35;
uniform float overcast = 0.0;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 top = mix(night_top, day_top, daylight);
	vec3 hor = mix(night_horizon, day_horizon, daylight);
	vec3 grey = mix(vec3(0.03), vec3(0.55, 0.57, 0.6), daylight);
	top = mix(top, grey * 0.9, overcast);
	hor = mix(hor, grey, overcast);
	vec3 col = mix(hor, top, pow(up, 0.45));
	float sd = dot(dir, normalize(sun_dir));
	col += sunset_color * pow(max(sd, 0.0), 6.0) * sunset * (1.0 - up * 0.7) * (1.0 - overcast * 0.7);
	col += sunset_color * sunset * 0.25 * (1.0 - up) * (1.0 - overcast);
	float disk = smoothstep(0.99965, 0.9999, sd);
	col += vec3(1.0, 0.95, 0.85) * disk * 12.0 * daylight * (1.0 - overcast);
	col += vec3(1.0, 0.85, 0.6) * pow(max(sd, 0.0), 300.0) * daylight * 0.8 * (1.0 - overcast);
	// moon (opposite the sun)
	float md = dot(dir, -normalize(sun_dir));
	col += vec3(0.9, 0.92, 1.0) * smoothstep(0.9993, 0.9996, md) * (1.0 - daylight) * 2.0;
	if (dir.y > 0.0) {
		vec2 suv = dir.xz / (dir.y + 0.25) * 140.0;
		vec2 cell = floor(suv);
		float s = hash(cell);
		float star = step(0.992, s) * smoothstep(0.5, 0.0, length(fract(suv) - 0.5));
		col += vec3(star) * (1.0 - daylight) * (1.0 - overcast) * (0.6 + 0.4 * sin(TIME * 3.0 + s * 50.0));
		vec2 cuv = dir.xz / (dir.y + 0.08) * 0.07 + vec2(TIME * 0.0016, TIME * 0.0009);
		float c = texture(cloud_tex, cuv).r * 0.7 + texture(cloud_tex, cuv * 2.7).r * 0.3;
		float cov = clamp(cloud_cover + overcast * 0.5, 0.0, 1.0);
		float cm = smoothstep(1.0 - cov, 1.0 - cov + 0.28, c) * smoothstep(0.0, 0.18, dir.y);
		vec3 lit = mix(vec3(0.06, 0.07, 0.1), vec3(1.0, 0.98, 0.95), daylight);
		lit = mix(lit, lit * vec3(1.0, 0.7, 0.5), sunset * 0.6);
		vec3 shade = lit * mix(0.55, 0.85, 1.0 - overcast) * (0.75 + 0.35 * texture(cloud_tex, cuv * 1.3 + 0.02).r);
		col = mix(col, shade, cm * 0.92);
	} else {
		col = mix(hor * 0.75, mix(vec3(0.02), vec3(0.22, 0.22, 0.2), daylight), smoothstep(0.0, -0.25, dir.y));
	}
	COLOR = col;
}
