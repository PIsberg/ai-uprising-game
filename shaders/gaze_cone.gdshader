// The ATTENTION HEAD's gaze (scripts/enemies/enemy_attention.gd): an additive
// cone, brightest where you look through its middle and at the eye end, with
// bands streaming away from the eye. UV.y runs 0 at the far end, 1 at the eye.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.3, 1.0);
uniform float intensity = 0.5;

void fragment() {
	float through = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float near_eye = mix(0.12, 1.0, UV.y * UV.y);
	float bands = 0.75 + 0.25 * sin(UV.y * 70.0 + TIME * 9.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(through * near_eye * bands * intensity, 0.0, 1.0);
}
