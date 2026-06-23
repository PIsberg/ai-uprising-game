shader_type canvas_item;
// Spins a conic GradientTexture2D (Godot 4.7 FILL_CONIC) around the radar dish
// and masks it to the circle, for a classic sweeping-beam glow. `angle` is
// advanced by the radar each frame.
uniform float angle = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 ruv = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca) + vec2(0.5);
	vec4 tex = texture(TEXTURE, ruv);
	float mask = smoothstep(0.5, 0.46, d); // soft circular edge
	COLOR = vec4(tex.rgb, tex.a * mask);
}
