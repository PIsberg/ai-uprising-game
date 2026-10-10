// The overlord's face, projected in the sky over every open-sky level
// (scripts/levels/overlord_holo.gd): a wireframe head drawn procedurally on one
// quad. Eye rings with pupils that follow you (look), a menacing brow, circuit
// traces, and a mouth that is an audio equalizer: flat while it watches, bars
// jumping while it talks (talk). Scanlines, a flicker and row tears (glitch)
// sell the hologram. Alpha-blended over a dark smoked fill rather than
// additive: additive red vanished against the bright day skies (SUBURB). Fog-free
// so it cuts through any haze.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.22, 0.16, 1.0);
uniform float energy = 2.4;
instance uniform float talk = 0.0; // 0..1 mouth activity
instance uniform vec2 look = vec2(0.0); // pupil offset, -1..1 each way (+x right, +y down)
instance uniform float blink = 0.0; // 0 open, 1 shut
instance uniform float glitch = 0.0; // 0..1 extra row tearing

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ring(float d, float r, float w) {
	return 1.0 - smoothstep(0.0, w, abs(d - r));
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(0.0, w, length(pa - ba * h));
}

void fragment() {
	vec2 uv = UV;
	float tick = floor(TIME * 9.0);
	float band = floor(uv.y * 40.0 + tick * 3.1);
	float tear = step(1.0 - (0.04 + glitch * 0.35), hash(vec2(band, tick)));
	uv.x += (hash(vec2(band, 7.0)) - 0.5) * 0.08 * tear;
	// Head space: origin mid-face, y grows DOWN (UV.y is 0 at the top).
	vec2 p = (uv - vec2(0.5)) * vec2(1.0, 1.2);

	float head_d = length(p / vec2(0.40, 0.52));
	float lines = ring(head_d, 1.0, 0.02);
	float fill = (1.0 - smoothstep(0.8, 1.0, head_d)) * 0.3;

	float open = 1.0 - blink;
	float eyes = 0.0;
	float pupils = 0.0;
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		vec2 c = vec2(s * 0.15, -0.08);
		vec2 q = p - c;
		float sq = max(open, 0.04);
		eyes += ring(length(vec2(q.x, q.y / sq)), 0.065, 0.012);
		vec2 pc = q - look * 0.03;
		pupils += (1.0 - smoothstep(0.016, 0.03, length(vec2(pc.x, pc.y / sq)))) * step(0.15, open);
		// Brow: high at the outer edge, low over the nose.
		lines += seg(p, c + vec2(s * 0.1, -0.125), c + vec2(-s * 0.06, -0.08), 0.009);
		// Cheek circuitry.
		lines += 0.6 * seg(p, vec2(s * 0.27, -0.02), vec2(s * 0.27, 0.2), 0.006);
		lines += 0.6 * seg(p, vec2(s * 0.27, 0.2), vec2(s * 0.13, 0.36), 0.006);
		lines += 0.8 * (1.0 - smoothstep(0.008, 0.016, length(p - vec2(s * 0.27, -0.02))));
	}
	// Forehead node and the bridge of the nose.
	lines += 0.6 * seg(p, vec2(0.0, -0.42), vec2(0.0, -0.24), 0.006);
	lines += 0.9 * (1.0 - smoothstep(0.012, 0.022, length(p - vec2(0.0, -0.24))));
	lines += 0.5 * seg(p, vec2(0.0, -0.05), vec2(0.0, 0.09), 0.006);

	// Mouth: an equalizer, 11 bars.
	float mouth = 0.0;
	float bx = (p.x + 0.17) / 0.34;
	if (bx > 0.0 && bx < 1.0) {
		float id = floor(bx * 11.0);
		float f = fract(bx * 11.0);
		float shape = 1.0 - abs(id - 5.0) / 7.0;
		float amp = 0.005 + talk * (0.015 + 0.06 * hash(vec2(id, floor(TIME * 14.0)))) * shape;
		mouth = step(0.18, f) * step(f, 0.82) * (1.0 - smoothstep(amp, amp + 0.006, abs(p.y - 0.21)));
	}

	float scan = 0.7 + 0.3 * step(0.5, fract(uv.y * 160.0 - TIME * 2.0));
	float flick = 0.9 + 0.1 * sin(TIME * 31.0 + hash(vec2(tick)) * 6.0);
	float lit = clamp((lines * 0.85 + eyes + pupils * 1.8 + mouth * (1.0 + talk)) * scan * flick, 0.0, 1.0);
	float a = clamp(lit + fill * (0.8 + 0.2 * scan) * (1.0 - lit), 0.0, 1.0);
	ALBEDO = mix(tint.rgb * 0.08, tint.rgb * energy, lit / max(a, 0.001));
	ALPHA = a;
}
