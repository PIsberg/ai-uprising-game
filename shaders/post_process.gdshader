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
uniform float low_health : hint_range(0.0, 1.0) = 0.0; // critical: pulsing red rim + drained color
uniform bool advanced_post_process_enabled = true;

// Color grade: a lift/gamma/gain style tint + contrast + saturation trim, picked
// from a named preset in GraphicsSettings so the whole game can shift mood
// (cold sci-fi steel, warm amber war-film, punchy high-contrast) without
// touching per-level environments.
uniform vec3 grade_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float grade_contrast : hint_range(0.5, 1.5) = 1.0;
uniform float grade_saturation : hint_range(0.0, 1.5) = 1.0;

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

	// Sprint speed-warp barrel distortion (fisheye warp)
	if (advanced_post_process_enabled && speed_warp > 0.001) {
		float dist = 0.15 * speed_warp;
		uv = center * (1.0 + dist * r2) + 0.5;
		// Re-evaluate center/r2 based on distorted uv
		center = uv - 0.5;
		r2 = dot(center, center);
	}

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

	// Screen-space horizontal bloom lens flares (anamorphic streak on bright elements)
	if (advanced_post_process_enabled) {
		vec3 flare = vec3(0.0);
		float flare_threshold = 0.82;
		float streak_width = 0.04;
		int samples = 8;
		for (int i = -samples; i <= samples; i++) {
			if (i == 0) continue;
			float offset = float(i) / float(samples);
			vec2 sample_uv = uv + vec2(offset * streak_width, 0.0);
			sample_uv = clamp(sample_uv, vec2(0.001), vec2(0.999));
			vec3 c = texture(screen_tex, sample_uv).rgb;
			float brightness = dot(c, vec3(0.299, 0.587, 0.114));
			if (brightness > flare_threshold) {
				float weight = (1.0 - abs(offset)) * (brightness - flare_threshold) * 0.15;
				flare += c * vec3(0.35, 0.65, 1.0) * weight; // Cinematic cyan/blue flare tint
			}
		}
		col += flare;
	}

	// Color grade: contrast pivots around mid-grey, saturation blends toward
	// luminance, tint multiplies the result — cheap but reads as a real LUT pass.
	col = (col - 0.5) * grade_contrast + 0.5;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, grade_saturation);
	col *= grade_tint;

	// Vignette.
	float vig = smoothstep(vignette_softness, vignette_softness - 0.5, r2 * 1.4);
	col *= mix(1.0 - vignette_strength, 1.0, vig);

	// Critical health: blood-red rim that throbs with a slow pulse, plus a
	// touch of drained saturation — the world greys out as you fade.
	if (low_health > 0.001) {
		float pulse = 0.7 + 0.3 * sin(TIME * 5.2);
		float rim = smoothstep(0.06, 0.75, r2 * 2.1) * low_health * pulse;
		col = mix(col, vec3(0.42, 0.015, 0.015), clamp(rim, 0.0, 0.78));
		float grey = dot(col, vec3(0.333));
		col = mix(col, vec3(grey), low_health * 0.22);
	}

	// Animated film grain (luminance-only so it stays neutral).
	float g = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 91.7) - 0.5;
	col += g * grain_amount;

	COLOR = vec4(col, 1.0);
}
