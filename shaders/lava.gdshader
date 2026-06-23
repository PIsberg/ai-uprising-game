shader_type spatial;
// Flowing molten lava: a dark basalt crust broken by cracks of glowing molten
// rock that scroll and churn. Emissive so it lights itself and reads as a hot
// hazard you don't want to cross. Used by scripts/systems/lava_hazard.gd on the
// recessed lava beds the level builder lays down to force detours.
render_mode cull_back, diffuse_burley, specular_disabled;

uniform vec3 hot_color : source_color = vec3(1.6, 0.55, 0.08);
uniform vec3 cool_color : source_color = vec3(0.85, 0.10, 0.02);
uniform vec3 crust_color : source_color = vec3(0.05, 0.03, 0.03);
uniform float flow_speed = 0.06;
uniform float emission_strength = 4.6; // HDR-hot molten glow (sears on HDR output)
uniform float crust_amount = 0.55; // higher = more dark crust, thinner veins

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// Two noise fields scrolling in opposite directions churn the surface.
	vec2 uv = UV * 5.0;
	float t = TIME * flow_speed;
	float n1 = fbm(uv + vec2(t, t * 0.6));
	float n2 = fbm(uv * 1.7 - vec2(t * 0.8, t));
	float molten = clamp((n1 * 0.6 + n2 * 0.4), 0.0, 1.0);
	// Cracks: thin bright veins where the crust splits.
	float veins = smoothstep(crust_amount, crust_amount + 0.18, molten);
	vec3 lava = mix(cool_color, hot_color, smoothstep(0.4, 1.0, molten));
	vec3 col = mix(crust_color, lava, veins);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.5, veins);
	METALLIC = 0.0;
	// Crust stays dark, veins glow hot — pulses subtly so it looks alive.
	float pulse = 0.85 + 0.15 * sin(TIME * 1.3 + molten * 6.2831);
	EMISSION = mix(crust_color * 0.2, lava, veins) * emission_strength * pulse;
}
