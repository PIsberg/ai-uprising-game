shader_type spatial;
// Floating holographic projection panel: travelling scanlines, a bright refresh
// band sweeping up, soft projector-edge falloff and mains flicker. Additive +
// unshaded so it glows in the dark and bleeds into bloom like a real hologram.

render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;

uniform vec3 holo_color : source_color = vec3(0.4, 0.85, 1.0);
uniform float scan_count : hint_range(10.0, 240.0) = 90.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.5;
uniform float scroll : hint_range(0.0, 4.0) = 0.15;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	// Travelling horizontal scanlines.
	float scan = 0.5 + 0.5 * sin(uv.y * scan_count * 6.28318 - TIME * 4.0);
	// Bright refresh band sweeping upward.
	float band = smoothstep(0.9, 1.0, fract(uv.y - TIME * scroll));
	// Soft elliptical edge falloff so it reads as a projection, not a decal.
	vec2 c = uv * 2.0 - 1.0;
	float edge = clamp(1.0 - dot(c, c) * 0.8, 0.0, 1.0);
	// Mains-hum flicker + occasional dropout line.
	float flick = 1.0 - 0.22 * hash(vec2(floor(TIME * 18.0), 1.0));
	float drop = step(0.995, hash(vec2(floor(uv.y * 40.0), floor(TIME * 9.0))));
	float a = (0.22 + 0.5 * scan + band) * edge * flick * alpha * (1.0 - drop * 0.8);
	ALBEDO = holo_color;
	EMISSION = holo_color * (0.6 + scan * 0.8 + band * 1.6);
	ALPHA = clamp(a, 0.0, 1.0);
}
