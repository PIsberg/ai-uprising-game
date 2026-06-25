shader_type spatial;
// NOT unshaded: an unshaded spatial shader outputs ALBEDO and ignores EMISSION,
// which would leave this black. We want EMISSION (so it glows + blooms) with a
// black ALBEDO, so keep lighting on but contribute nothing diffuse.
render_mode cull_disabled;
// Matrix "digital rain" for a 3D screen — ported from a canvas_item shader to
// drive EMISSION on a mesh (so it glows + blooms). Falling snapped columns of
// glyphs sampled from a char strip, selected/distorted by a low-res noise tex.

uniform sampler2D chars : filter_nearest, repeat_enable;
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform vec3 rain_color : source_color = vec3(0.1, 1.0, 0.2);
uniform float emission_energy = 3.0;

void fragment() {
	// Random character cell (noise resolution is 32x32, so loop the UV 32x).
	vec2 uv = fract(UV * 32.0);
	float noise = texture(noise_tex, UV).g;
	noise = round(noise * 10.0) / 10.0;            // snap to 0.1 steps
	uv.x = (uv.x / 10.0) - 0.005;                  // pick one of 10 glyph columns
	uv.x += noise;                                 // offset per column by noise
	uv.x += round(TIME * 0.5 * 10.0) / 10.0;       // animate, snapped so it ticks

	// Vertical falling "rain" gradient, distorted per column and pixelated.
	float rain = UV.y;
	float distortion = texture(noise_tex, UV / vec2(1.0, 32.0)).g;
	distortion = round(distortion * 10.0) / 10.0;
	rain -= round(TIME * 0.2 * 32.0) / 32.0;       // fall in steps, not smoothly
	rain += distortion;
	rain = fract(rain);
	rain = round(rain * 16.0) / 16.0;              // pixelate
	rain = pow(rain, 1.8);                         // sharpen the head of each drop

	// Always-visible faint code (floor) that flares bright at each drop head, so
	// a small screen reads as full matrix rain rather than mostly-black.
	float lit = rain * 1.7 + 0.18;
	vec3 glyph = texture(chars, uv).rgb * lit * rain_color;
	ALBEDO = vec3(0.0);
	EMISSION = glyph * emission_energy;
	ALPHA = 1.0;
}
