shader_type spatial;
// Inverted-hull outline drawn as a material overlay on whatever the player aims at.
// The hull grows with distance so the line keeps a steady width on screen.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float width = 0.0036;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = clamp(-view_pos.z, 0.3, 30.0);
	vec3 n = normalize(NORMAL);
	// undo the model scale so thin, scaled-up items get the same line as big ones
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += n * width * d / max(s, 0.001);
}

void fragment() {
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
