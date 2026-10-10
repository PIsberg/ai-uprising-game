// The gun's RAMPAGE charge (scripts/weapons/weapon.gd, _on_rampage_changed): a
// pulsing fresnel rim over the viewmodel in the streak tier's colour, worn as
// a material_overlay so the gun's own look stays underneath.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float strength = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.65 + 0.35 * sin(TIME * 9.0);
	ALBEDO = color.rgb * 2.5;
	ALPHA = clamp(rim * pulse * strength, 0.0, 1.0);
}
