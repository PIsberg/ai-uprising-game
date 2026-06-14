shader_type spatial;
// A dimensional gate: a swirling energy disc with a bright event-horizon rim.
// Additive + emissive so it blooms and reads as raw energy. Drawn on a quad;
// everything outside the unit disc is discarded. Drive `intensity` 1->0 to
// fade it out as the gate collapses.

render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform vec3 color : source_color = vec3(0.35, 0.7, 1.0);
uniform vec3 rim_color : source_color = vec3(0.8, 0.95, 1.0);
uniform float swirl_speed : hint_range(0.0, 6.0) = 2.2;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
		mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(uv.y, uv.x);

	// Swirl: noise sampled in polar coords, dragged around by angle + time.
	float swirl = fbm(vec2(ang * 1.6 + r * 5.0 - TIME * swirl_speed, r * 4.0 + TIME * 0.6));
	swirl = pow(swirl, 1.6);

	// Event-horizon ring: bright band near the outer edge, dark throat at centre.
	float ring = smoothstep(0.62, 0.98, r) * smoothstep(1.0, 0.92, r);
	float throat = smoothstep(0.0, 0.55, r); // darker toward the middle

	vec3 col = color * swirl * (0.4 + 0.8 * throat) + rim_color * ring * 1.6;
	float edge = smoothstep(1.0, 0.86, r);
	float a = clamp((swirl * 0.55 * throat + ring) * intensity * edge, 0.0, 1.0);

	ALBEDO = col * intensity;
	EMISSION = col * intensity * 1.4;
	ALPHA = a;
}
