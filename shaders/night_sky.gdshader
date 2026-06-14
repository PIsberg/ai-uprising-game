shader_type sky;
// A stylized night "heaven" for open-sky levels: a tinted zenith→horizon
// gradient, a procedural twinkling starfield (three octaves of varying size),
// a faint tilted Milky-Way haze band, and a soft glowing moon. Everything is
// themeable per level so each faction's sky keeps its colour identity
// (Grok runs red, the Hollow runs green, etc.). Drives IBL too, but the night
// palette is dark by design so it won't wash out the in-scene lighting.

uniform vec3 zenith_color : source_color = vec3(0.015, 0.02, 0.06);
uniform vec3 horizon_color : source_color = vec3(0.10, 0.08, 0.16);
uniform vec3 ground_color : source_color = vec3(0.01, 0.01, 0.02);
uniform float horizon_falloff : hint_range(0.5, 8.0) = 3.0;

uniform float star_density : hint_range(0.0, 0.3) = 0.08;
uniform float star_brightness : hint_range(0.0, 6.0) = 2.0;
uniform vec3 star_tint : source_color = vec3(0.85, 0.92, 1.0);
uniform float twinkle_speed : hint_range(0.0, 8.0) = 2.5;

uniform float milkyway_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec3 milkyway_tint : source_color = vec3(0.5, 0.55, 0.85);

uniform vec3 moon_dir = vec3(0.45, 0.55, -0.7);
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
uniform float moon_size : hint_range(0.0, 0.3) = 0.05;
uniform float moon_glow : hint_range(0.0, 4.0) = 1.4;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(i + vec3(0,0,0)), hash31(i + vec3(1,0,0)), f.x),
			mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
			mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

// One grid of stars: a single candidate per cell, twinkling, random brightness.
float star_layer(vec3 dir, float scale, float density, float tw) {
	vec3 p = dir * scale;
	vec3 id = floor(p);
	float rnd = hash31(id);
	if (rnd < 1.0 - density) {
		return 0.0;
	}
	vec3 sp = vec3(hash31(id + 1.7), hash31(id + 3.3), hash31(id + 5.9));
	float d = length(fract(p) - sp);
	// A bright pinpoint core plus a faint halo so small stars survive bloom.
	float core = smoothstep(0.14, 0.0, d) + 0.4 * smoothstep(0.32, 0.0, d);
	float tk = 0.7 + 0.3 * sin(tw + rnd * 40.0); // never fully blinks out
	return core * tk * (0.55 + 0.6 * hash31(id + 9.1));
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	// Base gradient: tight band of horizon colour, opening to the zenith tint.
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 1.0 / horizon_falloff));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 3.0, 0.0, 1.0));
	}

	// Stars + haze fade in just above the horizon (none below it).
	float horizonfade = smoothstep(0.0, 0.16, up);

	if (horizonfade > 0.0) {
		// Milky-Way: an fbm haze concentrated on a tilted great circle.
		if (milkyway_strength > 0.0) {
			float b = dot(normalize(dir), normalize(vec3(0.55, 0.25, -0.8)));
			float bandmask = exp(-b * b * 6.0);
			float haze = fbm(dir * 3.0 + vec3(11.3, 0.0, 7.7));
			haze = max(haze - 0.45, 0.0);
			col += milkyway_tint * haze * bandmask * milkyway_strength * horizonfade;
		}

		// Starfield: four octaves so sizes/spacing vary; brighter near the band.
		float tw = TIME * twinkle_speed;
		float bandboost = 1.0 + 1.5 * exp(-pow(dot(normalize(dir), normalize(vec3(0.55, 0.25, -0.8))), 2.0) * 6.0);
		float s = star_layer(dir, 120.0, star_density, tw)
			+ star_layer(dir, 200.0, star_density * 0.9, tw * 0.7) * 0.9
			+ star_layer(dir, 300.0, star_density * 0.7, tw * 1.3) * 0.7
			+ star_layer(dir, 460.0, star_density * 0.5, tw * 1.7) * 0.5;
		col += star_tint * s * star_brightness * bandboost * horizonfade;
	}

	// Moon: a crisp bright disc with a tight halo (kept from dominating the sky).
	vec3 md = normalize(moon_dir);
	float md_d = distance(dir, md);
	float disc = smoothstep(moon_size, moon_size * 0.55, md_d);
	float glow = pow(clamp(1.0 - md_d * 2.6, 0.0, 1.0), 5.0) * moon_glow;
	col += moon_color * (disc * 4.0 + glow);

	COLOR = col;
}
