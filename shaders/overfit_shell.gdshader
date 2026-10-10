// OVERFITTER's fitted shell: a fresnel rim over a scrolling grid, added on top
// of the scene. `color` is the gun it has overfit to; `flash` spikes on a
// resisted hit. scripts/enemies/enemy_overfitter.gd.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform vec4 color : source_color = vec4(0.3, 1.0, 0.6, 1.0);
uniform float strength = 1.0;
uniform float flash = 0.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	vec2 cell = UV * vec2(28.0, 14.0) + vec2(0.0, TIME * 0.35);
	vec2 g = abs(fract(cell) - 0.5);
	float grid = smoothstep(0.43, 0.5, max(g.x, g.y));
	float a = (rim * 1.3 + grid * (0.18 + rim * 0.6)) * strength + flash * (0.25 + rim);
	ALBEDO = color.rgb * 2.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
