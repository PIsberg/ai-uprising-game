// The data conduits feeding an interior AI (scripts/levels/landmark.gd,
// _build_cables): a faint additive line with bright packets streaming along
// it into the AI. Each instance's length (m) rides INSTANCE_CUSTOM.x so the
// packet spacing is the same on every cable.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back;

uniform vec4 color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float spacing = 3.0; // metres between packets
uniform float speed = 0.9; // packets per second

varying float len;

void vertex() {
	len = INSTANCE_CUSTOM.x;
}

void fragment() {
	float along = UV.y * len;
	float p = fract(along / spacing + TIME * speed);
	float packet = smoothstep(0.8, 0.96, p) * (1.0 - smoothstep(0.96, 1.0, p));
	ALBEDO = color.rgb * (1.0 + packet * 3.0);
	ALPHA = clamp(0.22 + packet * 0.9, 0.0, 1.0);
}
