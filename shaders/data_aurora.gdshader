// The night skies' data aurora (scripts/levels/landmark.gd, _build_aurora): a
// rippling curtain of light over the skyline, made of falling columns of data.
// UV.x runs along the ribbon, UV.y from its foot (0) to its crown (1).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.3, 1.0, 0.7, 1.0);
uniform vec4 crown : source_color = vec4(0.55, 0.4, 1.0, 1.0);
uniform float intensity = 0.55;

float hash(float n) {
	return fract(sin(n * 91.345) * 43758.5453);
}

void vertex() {
	// The curtain folds and drifts.
	VERTEX.x += sin(UV.x * 11.0 + TIME * 0.22) * 9.0;
	VERTEX.z += cos(UV.x * 7.0 + TIME * 0.17) * 12.0 * (0.4 + UV.y);
}

void fragment() {
	float foot = smoothstep(0.0, 0.12, UV.y);
	float top = 1.0 - smoothstep(0.35, 1.0, UV.y);
	float ends = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
	float sway = 0.55 + 0.45 * sin(UV.x * 23.0 + TIME * 0.4);
	// Columns of data raining down the curtain.
	float col = floor(UV.x * 160.0);
	float live = step(0.45, hash(col));
	float drops = step(0.55, fract(UV.y * 14.0 + TIME * (0.5 + hash(col + 3.0)) + hash(col) * 9.0));
	float glow = foot * top * ends * sway;
	vec3 c = mix(color.rgb, crown.rgb, UV.y);
	ALBEDO = c;
	ALPHA = clamp(glow * (0.35 + 0.65 * live * drops) * intensity, 0.0, 1.0);
}
