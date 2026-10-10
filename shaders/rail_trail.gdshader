// A railgun round's ionization trail (scripts/fx/rail_trail.gd). The mesh is a
// helix band round the shot (COLOR.a 0, NORMAL pointing out from the axis) and a
// crossed-quad core (COLOR.a 1). `age` runs 0..1 over the trail's life: the
// coil swells out, wobbles and drifts up like smoke and fades; the core is
// white-hot and burns out in the first half. Additive, fog-free.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.9, 1.0, 1.0);
uniform float expand = 0.32; // metres the coil swells by the end
uniform float rise = 0.4; // metres it drifts up by the end
instance uniform float age = 0.0;

varying float core;

void vertex() {
	core = COLOR.a;
	float coil = 1.0 - core;
	VERTEX += NORMAL * (expand * sqrt(age) + sin(UV.x * 3.1 + age * 7.0) * 0.05 * age) * coil;
	VERTEX.y += rise * age * age * coil;
}

void fragment() {
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	float coil_a = pow(1.0 - age, 1.7) * (0.7 + 0.3 * sin(UV.x * 37.0 - TIME * 24.0));
	float core_a = pow(max(1.0 - age * 2.2, 0.0), 1.5) * 1.4;
	ALBEDO = mix(color.rgb * 2.6, vec3(2.6) + color.rgb, core * 0.6);
	ALPHA = clamp(mix(coil_a, core_a, core) * edge, 0.0, 1.0);
}
