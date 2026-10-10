// QUANTIZER's chassis (scripts/enemies/enemy_quantizer.gd) as it loses
// precision. The material copies the look it replaces (same albedo/metallic/
// roughness uniforms as the dissolve shader, so KillFx.swap_to_dissolve can
// swap it in), then:
//  - vertices snap to a world-space grid `grid` metres wide: the chassis goes
//    blocky, and because the grid is fixed in the world, the blocks jump as it
//    moves (low-bit motion for free);
//  - colours posterize to `levels` steps per channel;
//  - faint scanning bit-rows in edge_color come up as precision drops.
// `grid` 0 and `levels` 256 is the untouched FP32 look.
shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform bool has_tex = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform vec3 edge_color : source_color = vec3(0.35, 1.0, 0.6);
instance uniform float grid = 0.0;
instance uniform float levels = 256.0;

void vertex() {
	if (grid > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		w = round(w / grid) * grid;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	}
}

void fragment() {
	vec4 base = albedo_color;
	if (has_tex) {
		base *= texture(albedo_tex, UV);
	}
	ALBEDO = floor(base.rgb * levels + 0.5) / levels;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	float lowbit = clamp(grid * 6.0, 0.0, 1.0);
	float row = step(0.9, fract(FRAGCOORD.y * 0.05 + TIME * 3.0));
	EMISSION = edge_color * row * lowbit * 0.9;
}
