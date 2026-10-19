shader_type spatial;
// One card of a gunshot's muzzle flash (scripts/fx/muzzle_flash.gd builds three):
//   shape 0  the front star, a quad across the bore: a hot core with jagged
//            petals, a different count and roll every shot;
//   shape 1  a side prong, a quad along the barrel: a flame tongue that is widest
//            at the bore (UV.y = 1) and frays to a tip (UV.y = 0).
// Additive and unshaded, so it only ever brightens what is behind it; `fade`
// runs 1 -> 0 over the flash's life and burns it out from the edges inward.
// `billboard` turns the card to face the camera (a flash with no bore to align
// to: the enemies'), keeping the node's scale.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float energy = 4.0;
uniform float petals = 5.0;
uniform float seed = 0.0;
uniform float fade = 1.0;
uniform int shape = 0;
uniform bool billboard = false;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 0.0;
	if (shape == 0) {
		float r = length(p);
		float ang = atan(p.y, p.x) + seed;
		// Petals: sharp lobes, each its own length.
		float lobe = pow(abs(cos(ang * petals * 0.5)), 3.0);
		float which = floor((ang + PI) / TAU * petals);
		float reach = mix(0.55, 1.0, hash(which + seed * 13.0));
		float star = smoothstep(lobe * reach + 0.12, 0.0, r);
		float core = smoothstep(0.5, 0.0, r);
		a = star * 0.9 + core * core * 2.2;
	} else {
		float t = 1.0 - UV.y; // 0 at the bore, 1 at the tip
		float wob = 0.8 + 0.2 * sin(t * 23.0 + seed * 5.0) * sin(t * 9.0 - seed * 3.0);
		float w = pow(1.0 - t, 0.7) * 0.6 * wob;
		float x = abs(p.x);
		a = smoothstep(w, w * 0.15, x) * smoothstep(1.0, 0.55, t) * smoothstep(0.0, 0.06, t);
		a *= 1.2;
	}
	// Burn out from the faint edges first: a fading flash shrinks, not dims.
	a = clamp(a - (1.0 - fade) * 0.7, 0.0, 2.0) * fade;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(a - 0.55, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
