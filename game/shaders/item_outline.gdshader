shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

void vertex() {
	// Expand in view space so component scaling doesn't change the stroke width.
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 normal_view = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	float width = max(0.0015, -view_position.z * 0.0025);
	view_position.xyz += normal_view * width;
	POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
	ALBEDO = vec3(1.0);
}
