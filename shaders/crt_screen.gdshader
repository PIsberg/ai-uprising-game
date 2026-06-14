shader_type spatial;
// A live computer/CRT screen. Procedural scrolling "terminal text", moving
// scanlines, a slow phosphor refresh sweep, mains-hum flicker and a curvature
// vignette. Unshaded + emissive so it reads as a light source the way a real
// monitor does — glows in the dark, bleeds into Godot's bloom. Theme it per
// faction with `screen_color`; flip `amber` for old-CRT terminals.

render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 screen_color : source_color = vec3(0.25, 1.0, 0.45);
uniform vec3 bg_color : source_color = vec3(0.02, 0.07, 0.04);
uniform float brightness : hint_range(0.2, 4.0) = 1.7;
uniform float glow : hint_range(0.0, 4.0) = 1.6;        // emission multiplier
uniform float scanline_count : hint_range(20.0, 400.0) = 140.0;
uniform float scanline_depth : hint_range(0.0, 1.0) = 0.35;
uniform float flicker : hint_range(0.0, 0.3) = 0.05;
uniform float content_density : hint_range(0.0, 1.0) = 0.62; // share of lit rows
uniform float scroll_speed : hint_range(0.0, 6.0) = 1.1;
uniform float rows : hint_range(6.0, 60.0) = 24.0;
uniform float cols : hint_range(8.0, 96.0) = 38.0;
uniform float curvature : hint_range(0.0, 0.6) = 0.22;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;

	// --- barrel-ish curvature: push UVs out from centre, vignette the corners.
	vec2 c = uv * 2.0 - 1.0;
	vec2 cuv = uv + c * dot(c, c) * curvature * 0.06;
	float vig = clamp(1.0 - dot(c, c) * (0.35 + curvature), 0.0, 1.0);
	// hard edge so the dark bezel reads even before the mesh frame.
	float frame = step(0.0, cuv.x) * step(cuv.x, 1.0) * step(0.0, cuv.y) * step(cuv.y, 1.0);

	// --- scrolling terminal text: a grid of blocky glyphs, whole rows scroll up.
	float scroll = TIME * scroll_speed;
	float row = floor(cuv.y * rows + scroll);
	float col = floor(cuv.x * cols);
	// per-row "is this a line of text" + indent so rows have ragged left edges.
	float row_on = step(1.0 - content_density, hash(vec2(row, 7.0)));
	float indent = floor(hash(vec2(row, 19.0)) * 4.0);
	float line_len = cols * (0.45 + 0.5 * hash(vec2(row, 31.0)));
	float in_text = step(indent, col) * step(col, indent + line_len);
	// per-glyph on/off + gaps between "words".
	float glyph = step(0.35, hash(vec2(col, row)));
	float gap = step(0.12, hash(vec2(floor(col / 4.0), row)));
	// fill the cell partially (a glyph isn't a solid block).
	vec2 cell = fract(vec2(cuv.x * cols, cuv.y * rows + scroll));
	float ink = step(0.12, cell.x) * step(cell.x, 0.88) * step(0.18, cell.y) * step(cell.y, 0.82);
	float lit = row_on * in_text * glyph * gap * ink;

	// blinking cursor parked at the end of the newest (bottom) line.
	float cursor_row = floor(rows + scroll) - 1.0;
	float cursor = step(cursor_row - 0.5, row) * step(row, cursor_row + 0.5)
		* step(indent + line_len, col) * step(col, indent + line_len + 1.0)
		* step(0.5, fract(TIME * 1.4));

	// --- phosphor refresh sweep travelling down the screen.
	float sweep = fract(cuv.y * 0.5 - TIME * 0.12);
	float sweep_glow = smoothstep(0.97, 1.0, sweep) * 0.5;

	// --- scanlines + mains-hum flicker.
	float scan = 1.0 - scanline_depth * (0.5 + 0.5 * sin(cuv.y * scanline_count * 6.28318));
	float flick = 1.0 - flicker * hash(vec2(floor(TIME * 24.0), 3.0));

	vec3 base = mix(bg_color, screen_color, clamp(lit + cursor, 0.0, 1.0));
	base += screen_color * sweep_glow;
	base *= scan * flick * vig * brightness * frame;

	ALBEDO = base;
	EMISSION = base * glow;
}
