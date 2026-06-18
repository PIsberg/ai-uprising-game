shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.015, 0.022, 0.032, 0.92);
uniform float metallic : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.03;
uniform float wave_scale : hint_range(0.5, 50.0) = 16.0;
uniform float ripple_speed : hint_range(0.1, 5.0) = 1.3;
uniform bool ripples_enabled = true;

// Sine wave normal calculation for wind ripples and rain drips
vec3 get_wave_normal(vec2 uv, float time) {
	if (!ripples_enabled) {
		return vec3(0.0, 1.0, 0.0);
	}
	
	// Wind waves: sum of multiple scrolling sine waves at different angles
	float wave1 = sin(uv.x * wave_scale * 0.8 + time * ripple_speed * 1.5) * 0.5 + 0.5;
	float wave2 = cos(uv.y * wave_scale * 1.2 - time * ripple_speed * 1.1) * 0.5 + 0.5;
	float wave3 = sin((uv.x + uv.y) * wave_scale * 1.5 + time * ripple_speed * 2.0) * 0.5 + 0.5;
	float wave4 = cos((uv.x - uv.y) * wave_scale * 2.2 - time * ripple_speed * 0.8) * 0.5 + 0.5;
	
	// High-frequency circular rain drips at scattered points
	float rain1 = sin(distance(uv, vec2(0.2, 0.3)) * 60.0 - time * 15.0) * 0.2;
	float rain2 = sin(distance(uv, vec2(-0.4, 0.7)) * 45.0 - time * 12.0) * 0.2;
	float rain3 = sin(distance(uv, vec2(0.8, -0.2)) * 75.0 - time * 18.0) * 0.2;
	float rain4 = sin(distance(uv, vec2(-0.6, -0.5)) * 55.0 - time * 14.0) * 0.2;
	
	// Modulate drip amplitudes over time to look organic
	rain1 *= sin(time * 2.0) * 0.5 + 0.5;
	rain2 *= cos(time * 1.7) * 0.5 + 0.5;
	rain3 *= sin(time * 3.1) * 0.5 + 0.5;
	rain4 *= cos(time * 2.4) * 0.5 + 0.5;

	// Calculate derivatives for wind waves
	float dx = (
		cos(uv.x * wave_scale * 0.8 + time * ripple_speed * 1.5) * wave_scale * 0.8 * 0.5 +
		cos((uv.x + uv.y) * wave_scale * 1.5 + time * ripple_speed * 2.0) * wave_scale * 1.5 * 0.5 -
		sin((uv.x - uv.y) * wave_scale * 2.2 - time * ripple_speed * 0.8) * wave_scale * 2.2 * 0.5
	) * 0.25;
	
	float dy = (
		-sin(uv.y * wave_scale * 1.2 - time * ripple_speed * 1.1) * wave_scale * 1.2 * 0.5 +
		cos((uv.x + uv.y) * wave_scale * 1.5 + time * ripple_speed * 2.0) * wave_scale * 1.5 * 0.5 +
		sin((uv.x - uv.y) * wave_scale * 2.2 - time * ripple_speed * 0.8) * wave_scale * 2.2 * 0.5
	) * 0.25;

	// Calculate derivatives for rain drips
	vec2 diff1 = uv - vec2(0.2, 0.3); float d1 = max(0.01, length(diff1));
	vec2 diff2 = uv - vec2(-0.4, 0.7); float d2 = max(0.01, length(diff2));
	vec2 diff3 = uv - vec2(0.8, -0.2); float d3 = max(0.01, length(diff3));
	vec2 diff4 = uv - vec2(-0.6, -0.5); float d4 = max(0.01, length(diff4));
	
	float r_dx = (
		60.0 * cos(d1 * 60.0 - time * 15.0) * (diff1.x / d1) * 0.2 * (sin(time * 2.0) * 0.5 + 0.5) +
		45.0 * cos(d2 * 45.0 - time * 12.0) * (diff2.x / d2) * 0.2 * (cos(time * 1.7) * 0.5 + 0.5) +
		75.0 * cos(d3 * 75.0 - time * 18.0) * (diff3.x / d3) * 0.2 * (sin(time * 3.1) * 0.5 + 0.5) +
		55.0 * cos(d4 * 55.0 - time * 14.0) * (diff4.x / d4) * 0.2 * (cos(time * 2.4) * 0.5 + 0.5)
	) * 0.15;
	
	float r_dy = (
		60.0 * cos(d1 * 60.0 - time * 15.0) * (diff1.y / d1) * 0.2 * (sin(time * 2.0) * 0.5 + 0.5) +
		45.0 * cos(d2 * 45.0 - time * 12.0) * (diff2.y / d2) * 0.2 * (cos(time * 1.7) * 0.5 + 0.5) +
		75.0 * cos(d3 * 75.0 - time * 18.0) * (diff3.y / d3) * 0.2 * (sin(time * 3.1) * 0.5 + 0.5) +
		55.0 * cos(d4 * 55.0 - time * 14.0) * (diff4.y / d4) * 0.2 * (cos(time * 2.4) * 0.5 + 0.5)
	) * 0.15;

	// Return normal vector in tangent space (where normal is Y-up in Godot spatial shaders)
	return normalize(vec3(-(dx + r_dx) * 0.025, 1.0, -(dy + r_dy) * 0.025));
}

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	ALBEDO = water_color.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness_wet;
	ALPHA = water_color.a;
	
	// Sample dynamic normals in tangent space based on local vertex coordinates
	NORMAL = get_wave_normal(local_pos.xz, TIME);
}
