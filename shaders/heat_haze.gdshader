shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Rising heat shimmer: a vertical "curtain" quad that re-samples the screen
// slightly offset by scrolling waves — the air above lava visibly wobbles.
// Strongest at the base of the curtain and dissolving to nothing at the top
// and at the side edges (so the quad's rectangle never reads as a cut-out).
// Pure screen-space refraction: no lighting, no depth write, cheap per pixel.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.05) = 0.011;
uniform float speed : hint_range(0.0, 6.0) = 1.6;

void fragment() {
	float base = UV.y; // QuadMesh UV: 1.0 at the bottom edge — the hottest air
	float edge = smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.85, UV.x);
	float t = TIME * speed;
	// Two crossed waves drifting upward (phase moves against UV.y over time).
	float w1 = sin(UV.x * 34.0 + UV.y * 46.0 + t * 3.1);
	float w2 = sin(UV.x * 61.0 - UV.y * 38.0 + t * 4.7 + 1.7);
	vec2 off = vec2(w1 + w2 * 0.6, w2 * 0.4) * strength * base * base * edge;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = clamp(base * 1.4, 0.0, 1.0) * edge;
}
