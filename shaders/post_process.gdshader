shader_type canvas_item;
// Full-screen cinematic post: subtle sharpen, chromatic aberration toward the
// edges, vignette, and animated film grain. Tuned to read as "filmic", not loud.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float aberration : hint_range(0.0, 4.0) = 1.1;   // px offset at the corners
// 0.42 -> 0.34: the heavier ring cost ~27% brightness at bottom-centre, which
// pushed already-dark dusk ground into unreadable black (suburb playtest).
uniform float vignette_strength : hint_range(0.0, 1.5) = 0.34;
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

// Blast shockwave rings — up to three at once. Each is
// (centre.x, centre.y, progress 0..1, strength) with the centre in SCREEN UV;
// Player._handle_screen_shock projects each live blast's world position into
// UV every frame and packs them here. Unset entries are all-zero (strength 0),
// so anything reusing this shader without a player driving it stays clean.
uniform vec4 shockwaves[3];
// Digital corruption amount (EMP hit / hijack landing); 0 = clean signal.
uniform float glitch : hint_range(0.0, 1.0) = 0.0;

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

	// Blast shockwaves: expanding rings of screen-space refraction anchored to
	// each explosion's world position (the player projects every live blast
	// into screen UV each frame, so a ring stays pinned to its detonation as
	// the camera turns). The image is dragged outward at the ring's crest and
	// settles behind it, so the pressure wave becomes something you SEE, not
	// just camera shake. Aspect-corrected so rings stay circular on widescreen.
	if (advanced_post_process_enabled) {
		float aspect = px.y / px.x;
		for (int i = 0; i < 3; i++) {
			vec4 sw = shockwaves[i];
			if (sw.w <= 0.001) { continue; }
			vec2 d = (uv - sw.xy) * vec2(aspect, 1.0);
			float dist = length(d);
			if (dist < 1e-5) { continue; }
			// Crest sweeps outward with progress; band thins, amplitude decays.
			float crest = smoothstep(0.11 * (1.0 - sw.z * 0.5), 0.0,
				abs(dist - sw.z * 0.78));
			float amp = crest * sw.w * (1.0 - sw.z) * 0.045;
			uv += (d / dist) * vec2(1.0 / aspect, 1.0) * amp;
		}
	}

	// Digital corruption: banded horizontal tearing, driven when the player is
	// EMP'd or a hijack lands — the fiction's "your optics are under attack".
	if (glitch > 0.001) {
		float band = floor(uv.y * 26.0);
		float n = hash(vec2(band, floor(TIME * 16.0)));
		uv.x += (n - 0.5) * 0.07 * glitch * step(0.68, n);
	}

	center = uv - 0.5;
	r2 = dot(center, center);

	// Chromatic aberration: shift R/B outward proportional to radius. A live
	// glitch stacks a hard horizontal split on top, so corruption reads as the
	// signal tearing rather than just a lens artifact.
	vec2 dir = center * r2 * aberration;
	vec2 ca = dir * px * 2.0;
	ca.x += glitch * px.x * 16.0 * sin(TIME * 47.0 + floor(uv.y * 24.0));
	vec3 col;
	col.r = texture(screen_tex, uv + ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - ca).b;

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
