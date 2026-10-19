shader_type spatial;
// An explosion's fireball (ExplosionFX._fireball): a boiling ball of fire, not a
// white dome. The surface churns (fbm noise pushes the vertices in and out and
// scrolls upward through the colour), it is white-hot where it faces you and
// cools through the blast colour to a charred red at the rim, and `burn`
// (0 fresh .. 1 spent, tweened by the script) cools the whole ball and eats it
// away from its thin, cool parts first, so it breaks up into tongues instead of
// fading as one shell.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 hot : source_color = vec4(1.0, 0.96, 0.8, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.25, 1.0);
uniform vec4 char_col : source_color = vec4(0.22, 0.05, 0.02, 1.0);
uniform float burn = 0.0;
uniform float seed = 0.0;
uniform float energy = 3.5;

varying vec3 obj;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	float d = fbm(VERTEX * 3.0 + vec3(seed) + vec3(0.0, TIME * 1.5, 0.0));
	VERTEX += NORMAL * (d - 0.5) * 0.35;
	obj = VERTEX;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0); // 1 at the centre, 0 at the rim
	float t = fbm(obj * 4.0 + vec3(seed) + vec3(0.0, -TIME * 2.0, 0.0));
	float heat = facing * 0.75 + t * 0.6 - burn * 1.1;
	vec3 col = mix(char_col.rgb, tint.rgb, smoothstep(0.0, 0.45, heat));
	col = mix(col, hot.rgb, smoothstep(0.6, 1.0, heat));
	float body = t + facing * 0.35;
	float a = smoothstep(burn * 0.95, burn * 0.95 + 0.22, body);
	ALBEDO = col * mix(1.0, energy, smoothstep(0.35, 1.0, heat));
	ALPHA = a * (1.0 - smoothstep(0.85, 1.0, burn));
}
