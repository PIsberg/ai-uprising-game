shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

// A security firewall: a sheet of hex cells with scan bands climbing it and
// columns of streaming packet glyphs, brightest at the edges where the emitter
// pylons feed it. `collapse` (0..1) drains it top-down when the firewall drops.

uniform vec3 wall_color : source_color = vec3(1.0, 0.18, 0.12);
uniform vec2 wall_size = vec2(8.0, 3.2);      // metres; keeps cells square on any span
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float collapse : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

// 1 on the thin edges of a hex lattice, 0 inside the cells.
float hex_edge(vec2 p) {
	const vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	float to_centre = max(dot(g, normalize(r)), g.x);
	return smoothstep(0.40, 0.47, to_centre);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 m = UV * wall_size;                  // metres across / down the sheet (UV.y = 0 at top)
	float up = 1.0 - UV.y;                    // 0 floor .. 1 top

	float grid = hex_edge(m * 3.2 + vec2(0.0, TIME * 0.35));

	// Scan bands climbing the sheet.
	float band = pow(0.5 + 0.5 * sin((up * wall_size.y - TIME * 1.6) * 3.2), 12.0);

	// Streaming packet glyphs: narrow columns of blocks sliding down the sheet.
	float col = floor(m.x * 5.0);
	vec2 cell = floor(vec2(m.x * 5.0, m.y * 7.0 - TIME * (2.0 + hash(vec2(col, 3.0)) * 3.0)));
	float glyph = step(0.82, hash(cell)) * step(0.55, hash(vec2(col, 9.0)));

	// Bright feed rails at both ends and along the top/bottom edges.
	float ex = min(UV.x, 1.0 - UV.x) * wall_size.x;
	float ey = min(UV.y, 1.0 - UV.y) * wall_size.y;
	float rails = exp(-ex * 5.0) + 0.6 * exp(-ey * 6.0);

	float flicker = 0.9 + 0.1 * sin(TIME * 23.0 + m.x * 1.7);
	float body = grid * 0.9 + band * 0.7 + glyph * 0.45 + rails * 1.2 + 0.12;
	body *= flicker * intensity;
	body += hit_flash * 1.5;

	// Collapse drains from the top: everything above the falling line goes dark,
	// with a hot seam riding the line so the drop reads as the power cutting out.
	float line = 1.0 - collapse;
	float alive = step(up, line);
	float seam = exp(-abs(up - line) * 30.0) * step(0.001, collapse) * (1.0 - collapse);
	body = body * alive + seam * 3.0;

	ALBEDO = wall_color * body;
	ALPHA = clamp(body * 0.6, 0.0, 1.0);
}