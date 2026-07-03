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

// Noise/FBM generator functions for lightning path distortion
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	// Signed gradients in [-1, 1] — an unsigned hash biases every dot product
	// positive and pushes the bolt permanently off one edge of the shield.
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = smoothstep(0.0, 1.0, f);
	
	float a = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) + 0.5;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
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
	
	// Blue lightning effect crackling across the shield surface:
	vec2 lightning_uv = local_vertex.xy * 2.2;
	lightning_uv.y += TIME * 1.6;
	float val = fbm(lightning_uv);
	float lightning_line = abs(local_vertex.x * 2.2 + val * 0.5);
	float lightning = 0.05 / (lightning_line + 0.01);
	
	vec2 lightning_uv2 = local_vertex.yx * 2.0;
	lightning_uv2.x += TIME * -1.8;
	float val2 = fbm(lightning_uv2);
	float lightning_line2 = abs(local_vertex.y * 1.8 + val2 * 0.4);
	float lightning2 = 0.04 / (lightning_line2 + 0.01);
	
	float total_lightning = clamp(lightning + lightning2, 0.0, 2.5);
	
	// Combine layers
	vec3 glow = shield_color * (fresnel * 1.5 + grid * grid_intensity);
	glow += shield_color * total_lightning * 1.4; // crackling blue lightning glow
	glow += vec3(1.0) * ripple_effect * 1.8; // bright white impact waves
	
	ALBEDO = glow;
	ALPHA = clamp(fresnel * 0.75 + grid * grid_intensity * 0.5 + total_lightning * 0.55 + ripple_effect, 0.0, 1.0);
}
