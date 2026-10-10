shader_type spatial;

// Skyline towers (scripts/levels/skyline.gd): every box of the megacity ring
// in one MultiMesh, unit cubes scaled per instance. Walls get a grid of lit
// and dark windows measured in metres, so a 100 m tower and a 20 m one share a
// floor height; roofs, tier caps and spires stay plain.
//
// INSTANCE_CUSTOM: r = per-box seed, g = fraction of windows lit,
// b = 1 for walls that carry windows (0: spires, caps).

uniform vec3 body_color : source_color = vec3(0.07, 0.075, 0.09);
uniform vec3 window_color : source_color = vec3(0.6, 0.8, 1.0);
uniform vec3 warm_color : source_color = vec3(1.0, 0.78, 0.45);
uniform float window_energy = 2.2;
uniform vec2 cell = vec2(2.4, 3.4); // metres per window across, per floor up

varying vec3 lp;
varying vec3 ln;
varying vec3 box;
varying vec4 custom;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	box = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = body_color;
	METALLIC = 0.25;
	ROUGHNESS = 0.8;
	if (abs(ln.y) < 0.5 && custom.b > 0.5) {
		vec2 m;
		float face;
		if (abs(ln.x) > 0.5) {
			m = vec2(lp.z * box.z, (lp.y + 0.5) * box.y);
			face = sign(ln.x);
		} else {
			m = vec2(lp.x * box.x, (lp.y + 0.5) * box.y);
			face = 2.0 + sign(ln.z);
		}
		vec2 id = floor(m / cell);
		vec2 f = fract(m / cell);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.78);
		float seed = custom.r * 97.0 + face * 17.0;
		float lit = step(1.0 - custom.g, hash(id + vec2(seed, seed * 0.37)));
		// Whole floors go dark together, the way an office tower empties.
		lit *= step(0.22, hash(vec2(id.y * 1.3, seed)));
		// A few windows on a slow blink.
		float fl = hash(id * 1.7 + vec2(seed));
		if (fl > 0.985) {
			lit *= step(0.5, fract(TIME * 0.11 + fl * 13.0));
		}
		vec3 wc = mix(window_color, warm_color, step(0.62, hash(id + vec2(3.1, seed))));
		ALBEDO = mix(body_color, body_color * 0.35, win);
		ROUGHNESS = mix(0.8, 0.15, win);
		EMISSION = wc * window_energy * win * lit;
	}
}
