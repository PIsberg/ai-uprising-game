shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Standard PBR textures/colors
uniform vec4 albedo_color : source_color = vec4(0.24, 0.26, 0.3, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float metallic : hint_range(0.0, 1.0) = 0.85;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform bool use_normal_map = false; // only sample normal_tex when the model actually has one

// Dynamic damage parameters
uniform float health_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float menace_blink : hint_range(0.0, 10.0) = 0.0;
uniform vec3 menace_color : source_color = vec3(1.0, 0.16, 0.1);
uniform vec3 core_color : source_color = vec3(1.0, 0.4, 0.0);

// World-ish position used only to drive the procedural damage pattern.
varying vec3 triplanar_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Simple procedural noise for electrical crackles
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Mesh tangents (imported) drive any normal mapping; we don't override them.
	triplanar_pos = VERTEX * 1.5;
}

void fragment() {
	// Sample textures using standard UV coordinates to preserve hand-authored texture mapping
	vec4 tex_albedo = texture(albedo_tex, UV);
	vec4 final_albedo = albedo_color * tex_albedo;

	// PBR
	ALBEDO = final_albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	// Only apply a normal map when the model actually ships one — sampling an
	// unbound normal_tex yields garbage normals that read as seam lines.
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	
	// Dynamic Damage Effect (exposed core)
	// Ramps up as health drops below 75%
	float damage_intensity = clamp((0.75 - health_ratio) / 0.75, 0.0, 1.0);
	
	// Procedural electrical grid lines
	vec2 damage_uv = triplanar_pos.xy + triplanar_pos.zy;
	float elect_line1 = noise(damage_uv * 12.0 + vec2(TIME * 0.8, -TIME * 0.3));
	float elect_line2 = noise(damage_uv * 18.0 - vec2(TIME * 0.5, TIME * 0.7));
	float electrical_crackle = step(0.72 + 0.15 * sin(TIME * 25.0), elect_line1 * elect_line2);
	
	// Exposed core regions (rust/melted metal mask)
	float core_mask = step(0.55, noise(damage_uv * 4.0)) * damage_intensity;
	
	// Mix damaged core into Albedo
	vec3 core_glow = core_color * (1.5 + 2.0 * sin(TIME * 12.0 + damage_uv.x));
	vec3 elect_glow = core_color * 5.0 * electrical_crackle;
	
	// If damaged, darken the metal albedo and add burn marks
	ALBEDO = mix(ALBEDO, vec3(0.08, 0.08, 0.09), core_mask * 0.85);
	ROUGHNESS = mix(ROUGHNESS, 0.95, core_mask);
	METALLIC = mix(METALLIC, 0.1, core_mask);
	
	// Emission: Blend menace blink/glow + electrical sparks + exposed melting core
	vec3 emission_glow = menace_color * menace_blink;
	emission_glow += mix(vec3(0.0), core_glow, core_mask);
	emission_glow += mix(vec3(0.0), elect_glow, damage_intensity);
	
	EMISSION = emission_glow;
	
	// Fresnel rim glow when hit or highly damaged
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += menace_color * fresnel * (menace_blink * 0.5 + damage_intensity * 0.3);
}
