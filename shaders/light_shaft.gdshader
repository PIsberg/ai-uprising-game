shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 0.35;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.25;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.6;
uniform float edge_falloff : hint_range(0.1, 4.0) = 1.8;
uniform bool noise_enabled = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	
	// Fade at vertical borders (top/bottom of cylinder mesh) to prevent hard clipping
	float vertical_fade = smoothstep(0.0, 0.22, uv.y) * smoothstep(1.0, 0.78, uv.y);
	
	// Circular side-edge falloff (fade near center/edges)
	float lateral_fade = pow(1.0 - abs(uv.x - 0.5) * 2.0, edge_falloff);
	
	float final_alpha = vertical_fade * lateral_fade;
	
	if (noise_enabled) {
		// Scrolling noise to simulate swirling dust particles in the shaft
		vec2 scroll1 = vec2(TIME * noise_speed * 0.4, TIME * noise_speed * 0.9);
		vec2 scroll2 = vec2(-TIME * noise_speed * 0.6, TIME * noise_speed * 1.3);
		
		float n1 = noise(uv * noise_scale * 4.0 + scroll1);
		float n2 = noise(uv * noise_scale * 6.5 + scroll2);
		
		// Combine noise layers for complexity
		float swirl = mix(n1, n2, 0.5);
		final_alpha *= (0.35 + 0.65 * swirl);
	}
	
	ALBEDO = color;
	EMISSION = color * intensity;
	ALPHA = clamp(final_alpha * intensity * 0.15, 0.0, 1.0);
}
