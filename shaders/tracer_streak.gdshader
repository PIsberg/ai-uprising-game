shader_type spatial;
// A shot's tracer streak (scripts/fx/tracer.gd): a flat card along the line of
// fire that the script turns to face the camera. Across it, a white-hot core
// inside a soft halo in the shot's colour; along it, brightest at the nose and
// fading out to nothing at the tail. Additive and unshaded: it only ever brightens.
// The card is a unit PlaneMesh (local z in -0.5..0.5, the nose at -z), scaled
// to the streak's length by its node.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float energy = 5.0;
uniform float fade = 1.0;

varying float along; // 0 at the tail, 1 at the nose

void vertex() {
	along = 0.5 - VERTEX.z;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float core = exp(-pow(x / 0.16, 2.0));
	float halo = exp(-pow(x / 0.5, 2.0)) * 0.35;
	// Zero at the tail: the instant streak's tail is at the muzzle, close to the
	// eye where the card is widest, and any brightness left there ends in a cut.
	float taper = pow(clamp(along, 0.0, 1.0), 1.6) * smoothstep(1.0, 0.93, along);
	float a = (core * 1.3 + halo) * taper * fade;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core * taper * 0.75, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
