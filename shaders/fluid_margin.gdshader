shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Flush shoreline margin: the band of ground immediately around a fluid bed,
// blended INTO the floor instead of framing it.
//
// This replaces the raised rim box the lava/water beds used to sit inside. That
// box stood ~12 cm proud of the floor with hard vertical sides, which is a large
// part of why a bed read as an object placed ON the ground rather than a pool
// filling it. This lies flat against the floor and fades out over `band` metres,
// so the transition floor -> shore -> fluid has no silhouette at all.
//
// Water uses it as a damp, darkened, slightly glossy margin; lava as scorched
// rock with heat still glowing out of it.

uniform vec2 inner_size = vec2(8.0, 3.0); // the fluid footprint it wraps
uniform vec2 plane_size = vec2(11.0, 6.0); // this quad's own footprint
uniform float band = 1.4;                  // metres the margin reaches outward
uniform vec4 tint : source_color = vec4(0.05, 0.04, 0.04, 1.0);
uniform vec3 glow : source_color = vec3(0.5, 0.12, 0.02);
uniform float glow_energy = 0.0;  // >0 for lava (heat bleeding into the rock)
uniform float roughness_val = 1.0; // ~0.15 for a wet water margin
uniform float edge_noise = 0.35;   // breaks the rectangle into an uneven shore
uniform sampler2D noise_tex : repeat_enable, filter_linear;

void fragment() {
	// Metres from this fragment to the fluid's rectangular border: negative
	// inside the fluid footprint, positive out on the dry floor.
	vec2 p = abs(UV - 0.5) * plane_size;
	vec2 outside = p - inner_size * 0.5;
	float d = length(max(outside, vec2(0.0))) + min(max(outside.x, outside.y), 0.0);

	// Wobble the shore so it never reads as a drawn rectangle.
	float n = texture(noise_tex, UV * 3.0).r - 0.5;
	d += n * edge_noise;

	// Solid across the fluid's own footprint, fading to nothing `band` metres
	// out. For water this plane doubles as the BED — the dark ground the pool
	// is seen down into — which is why it stays opaque inside rather than being
	// a hollow ring. A separate opaque bed plane does not work: once the water
	// surface correctly fades to clear at the rim, that bed's own edge is left
	// exposed as a hard silhouette against the floor, which is the very problem
	// this is here to remove (measured: it made the rim step 2.6x WORSE).
	float a = 1.0 - smoothstep(0.0, max(band, 0.001), d);

	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * tint.a;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	if (glow_energy > 0.0) {
		// Heat is strongest right at the fluid and dies out into cold rock.
		EMISSION = glow * glow_energy * pow(clamp(a, 0.0, 1.0), 2.0);
	}
}
