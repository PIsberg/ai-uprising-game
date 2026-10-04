shader_type spatial;
// Vision-scanner beam: an additive cone from the lens out to detection range.
// Fades toward full reach and at the silhouette so it reads as a light cone,
// not a solid funnel; fog-free so distance haze never tints it dark.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float strength = 0.05;

void fragment() {
	float along = UV.y; // CylinderMesh v runs bottom->top: 1 at the lens (top), 0 at full reach
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * (0.3 + 1.7 * along * along) * edge * 2.5, 0.0, 1.0);
}
