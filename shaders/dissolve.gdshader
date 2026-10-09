shader_type spatial;
render_mode cull_disabled;

// Disintegration death (KillFx.DISINTEGRATE). Replaces a robot's surface
// materials for the last second of its life: a noisy burn front sweeps
// top-down, discarding the chassis behind a glowing edge and scorching the
// metal just ahead of it. Albedo/metal/rough are copied from the material it
// replaces, so the robot looks unchanged at dissolve = 0.
//
// Per-robot values are instance uniforms (set_instance_shader_parameter), so a
// whole chassis animates through one call per mesh, whatever its materials.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform vec3 edge_color : source_color = vec3(0.45, 0.9, 1.0);
uniform float edge_width = 0.09;
uniform float noise_scale = 3.4;
uniform float height_bias : hint_range(0.0, 1.0) = 0.55; // 0 = pure noise, 1 = a clean top-down wipe

instance uniform float dissolve = 0.0;
instance uniform float y_lo = 0.0;
instance uniform float y_hi = 2.0;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_pos * noise_scale;
	float n = 0.6 * vnoise(p) + 0.3 * vnoise(p * 2.1) + 0.1 * vnoise(p * 4.3);
	float h = clamp((world_pos.y - y_lo) / max(y_hi - y_lo, 0.01), 0.0, 1.0);
	float v = mix(n, h, height_bias);
	// cut runs from above 1 (nothing gone) to below 0 (everything gone).
	float cut = 1.0 + edge_width - dissolve * (1.0 + 2.0 * edge_width);
	if (v > cut) {
		discard;
	}
	float edge = smoothstep(cut - edge_width, cut, v);
	float scorch = smoothstep(cut - 0.18, cut, v);
	vec4 base = albedo_color;
	if (has_tex) {
		base *= texture(albedo_tex, UV);
	}
	ALBEDO = base.rgb * mix(1.0, 0.25, scorch);
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.9, scorch);
	// The whole chassis heats as it goes, so the effect reads at range too.
	EMISSION = edge_color * (edge * 7.0 + scorch * 0.8 + dissolve * 0.35);
}
