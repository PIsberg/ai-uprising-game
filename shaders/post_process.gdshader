shader_type canvas_item;
// Full-screen cinematic post: subtle sharpen, chromatic aberration toward the
// edges, vignette, and animated film grain. Tuned to read as "filmic", not loud.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float aberration : hint_range(0.0, 4.0) = 1.1;   // px offset at the corners
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.42;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float sharpen : hint_range(0.0, 1.5) = 0.35;
uniform float speed_warp : hint_range(0.0, 1.0) = 0.0; // sprint: radial streak + tunnel

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 center = uv - 0.5;
	float r2 = dot(center, center);

	// Chromatic aberration: shift R/B outward proportional to radius.
	vec2 dir = center * r2 * aberration;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * px * 2.0).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * px * 2.0).b;

	// Sprint speed-warp: a few radial samples streaked toward the edges, blended
	// in proportional to how hard the player is running.
	if (speed_warp > 0.001) {
		vec3 streak = vec3(0.0);
		for (int i = 1; i <= 4; i++) {
			float t = float(i) / 4.0;
			streak += texture(screen_tex, uv - center * t * 0.06 * speed_warp).rgb;
		}
		streak *= 0.25;
		col = mix(col, streak, clamp(r2 * 2.2 * speed_warp, 0.0, 0.8));
	}

	// Unsharp mask using a 4-tap cross.
	vec3 blur = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb
		+ texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
	blur *= 0.25;
	col += (col - blur) * sharpen;

	// Vignette.
	float vig = smoothstep(vignette_softness, vignette_softness - 0.5, r2 * 1.4);
	col *= mix(1.0 - vignette_strength, 1.0, vig);

	// Animated film grain (luminance-only so it stays neutral).
	float g = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 91.7) - 0.5;
	col += g * grain_amount;

	COLOR = vec4(col, 1.0);
}
