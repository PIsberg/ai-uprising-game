// ROLLBACK's rewind column (scripts/enemies/enemy_rollback.gd): an open
// cylinder over a dead robot's checkpoint, painted like a VHS tape rewinding:
// scanlines scrolling DOWN fast and a bright tracking band rolling down through
// them. Additive and fog-free so it reads at range on any level; cull disabled
// because the camera sees the inside of the far wall through the near one.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.95, 1.0, 1.0);
uniform float energy = 2.2;
instance uniform float progress = 0.0; // 0..1 through the channel: the column firms up

void fragment() {
	float y = UV.y;
	float lines = step(0.72, fract(y * 26.0 + TIME * 7.0));
	float track = 1.0 - smoothstep(0.0, 0.06, abs(fract(y + TIME * 1.6) - 0.5));
	float fade = smoothstep(0.0, 0.12, y) * smoothstep(1.0, 0.7, y);
	ALBEDO = tint.rgb * energy;
	ALPHA = clamp((lines * 0.45 + track * 0.9) * fade * (0.3 + 0.7 * progress), 0.0, 1.0);
}
