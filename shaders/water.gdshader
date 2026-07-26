shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Deep pool surface that MEETS the world instead of floating on it.
//
// The old water was a flat alpha-blended plane: a hard-cut rectangle sitting a
// few centimetres above the arena floor, which read as a blue slab laid on the
// ground rather than liquid filling a basin. Fixed by three things:
//
//   * SHORELINE — the pool dissolves toward its own rim, so there is no cut
//     edge anywhere, plus surf where solid geometry breaks the surface.
//   * REFRACTION — the bed is re-sampled through the ripple normal, so the
//     pool has visible volume instead of being a tinted sheet.
//   * DEPTH GRADING — shallow and translucent at the margins, dark toward the
//     middle.
//
// WHY THE BODY GRADIENT IS UV-BASED, NOT DEPTH-BASED. The bed cannot actually
// be sunk: the arena floor is one solid slab, and cutting a hole through it
// would turn wading into falling — a gameplay change, not a visual one. So the
// pool stands only ~10 cm above its bed, and a depth-buffer fade would drive
// the WHOLE surface transparent when viewed from above, not just the shore.
// Distance-to-rim in UV is therefore the honest source for the body gradient.
//
// The depth buffer is still used, but only for what it can discriminate here:
// something standing IN the pool (a robot's legs, a prop, a wall) reads a
// contact depth near zero, while the bed reads at least `bed_gap`. Surf is
// keyed off that gap, which is why `foam_width` must stay well under it.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D ripple_tex : repeat_enable, filter_linear; // seamless noise

uniform vec3 shallow_color : source_color = vec3(0.18, 0.50, 0.55);
uniform vec3 deep_color : source_color = vec3(0.012, 0.055, 0.13);
uniform vec3 foam_color : source_color = vec3(0.78, 0.91, 0.98);

uniform vec2 plane_size = vec2(8.0, 8.0); // bed footprint in metres
uniform float shelf_width = 1.6;  // metres from the rim over which it deepens
uniform float foam_width = 0.05;  // contact depth counted as "breaks the surface"
uniform float refraction = 0.045;
uniform float ripple_speed = 0.05;
uniform float ripple_scale = 0.55;
uniform float ripple_strength = 1.0;
uniform float max_alpha = 0.95;

float linear_depth(vec2 uv, mat4 inv_proj) {
	// Reverse-Z depth buffer: the raw sample is used directly as NDC z.
	float d = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, d), 1.0);
	return -(view.z / view.w);
}

// Two noise fields scrolling against each other — a cheap ripple height whose
// gradient becomes the surface normal (and the refraction offset).
float ripple_h(vec2 p) {
	float t = TIME * ripple_speed;
	float a = texture(ripple_tex, p * 0.5 + vec2(t, t * 0.63)).r;
	float b = texture(ripple_tex, p * 0.87 - vec2(t * 0.71, t * 1.13)).r;
	return (a + b) * 0.5;
}

void fragment() {
	vec2 wp = UV * plane_size * ripple_scale;
	float e = 0.03;
	float h = ripple_h(wp);
	vec2 grad = vec2(ripple_h(wp + vec2(e, 0.0)) - h,
					 ripple_h(wp + vec2(0.0, e)) - h) / e;

	vec3 n = normalize(vec3(-grad.x * ripple_strength * 0.05, 1.0,
							-grad.y * ripple_strength * 0.05));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Body depth: metres to the nearest rim, ramped over the shelf, wobbled by
	// the ripple field so the shoreline is not a clean inset rectangle.
	vec2 to_edge = min(UV, vec2(1.0) - UV) * plane_size;
	float edge_m = min(to_edge.x, to_edge.y) + (h - 0.5) * 0.35;
	float body = clamp(edge_m / max(shelf_width, 0.001), 0.0, 1.0);

	float here = -VERTEX.z;
	float contact = max(linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - here, 0.0);

	// Refraction grows with body depth so the margins never smear dry floor
	// inward, and is rejected outright if the offset would pull in something
	// standing IN FRONT of the surface (that bleeds foreground into the pool).
	vec2 refr_uv = SCREEN_UV + grad * refraction * body;
	if (linear_depth(refr_uv, INV_PROJECTION_MATRIX) < here) {
		refr_uv = SCREEN_UV;
	}
	vec3 below = texture(screen_tex, refr_uv).rgb;

	vec3 tint = mix(shallow_color, deep_color, body);
	vec3 col = mix(below * mix(vec3(1.0), tint, 0.6), tint, body * 0.82);

	// Surf where something breaks the surface — see the header note on why this
	// keys off a contact depth well under the surface-to-bed gap.
	float foam = 1.0 - smoothstep(0.0, foam_width, contact);
	foam *= 0.5 + 0.5 * ripple_h(wp * 2.6 + vec2(TIME * 0.04, 0.0));
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.7);

	ALBEDO = col;
	// The rim dissolves rather than ending on a cut line — this is what stops
	// the pool reading as a slab laid on the floor.
	ALPHA = clamp(body, 0.0, 1.0) * max_alpha;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
