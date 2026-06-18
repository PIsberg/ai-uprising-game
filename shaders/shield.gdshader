shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec3 shield_color : source_color = vec3(0.3, 0.7, 1.0);
uniform float pattern_scale : hint_range(1.0, 50.0) = 15.0;
uniform float fresnel_power : hint_range(0.1, 10.0) = 3.5;
uniform float grid_intensity : hint_range(0.0, 1.0) = 0.45;

// Hit ripple uniforms (supports up to 3 simultaneous ripples)
uniform vec3 hit_pos_0;
uniform float hit_time_0 = -10.0;
uniform vec3 hit_pos_1;
uniform float hit_time_1 = -10.0;
uniform vec3 hit_pos_2;
uniform float hit_time_2 = -10.0;

varying vec3 local_vertex;

// Hexagonal grid calculation
float hex_grid(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508); // sqrt(3)
	vec4 hC = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + vec4(0.5, 0.5, 0.5, 0.5);
	vec2 a = p - hC.xy * s;
	vec2 b = p - (hC.zw + 0.5) * s;
	return step(0.03, min(dot(a, a), dot(b, b)) * 14.0);
}

void vertex() {
	local_vertex = VERTEX;
}

void fragment() {
	// Fresnel effect for edge glow
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	
	// Hexagonal grid based on local vertex coordinates to wrap around geometry cleanly
	vec2 hex_uv = local_vertex.xy + local_vertex.zy;
	float grid = 1.0 - hex_grid(hex_uv * pattern_scale + vec2(0.0, TIME * 0.1));
	
	// Calculate hit ripples
	float ripple_effect = 0.0;
	vec3 hit_positions[3] = vec3[](hit_pos_0, hit_pos_1, hit_pos_2);
	float hit_times[3] = float[](hit_time_0, hit_time_1, hit_time_2);
	
	for (int i = 0; i < 3; i++) {
		float elapsed = TIME - hit_times[i];
		if (elapsed >= 0.0 && elapsed < 1.5) {
			float dist = distance(local_vertex, hit_positions[i]);
			// Ripple speed and width
			float ripple_speed = 3.8;
			float wave_front = elapsed * ripple_speed;
			float d = abs(dist - wave_front);
			
			// Exponential fade out over distance and time
			float wave = exp(-d * 8.0) * (1.0 - elapsed / 1.5);
			
			// Pulsing sine wave inside the ripple envelope
			wave *= 0.5 + 0.5 * sin(dist * 20.0 - TIME * 35.0);
			ripple_effect += wave;
		}
	}
	
	// Combine layers
	vec3 glow = shield_color * (fresnel * 1.5 + grid * grid_intensity);
	glow += vec3(1.0) * ripple_effect * 1.8; // bright white impact waves
	
	ALBEDO = glow;
	ALPHA = clamp(fresnel * 0.75 + grid * grid_intensity * 0.5 + ripple_effect, 0.0, 1.0);
}
