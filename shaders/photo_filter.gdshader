shader_type canvas_item;
// PHOTO MODE filters over the frozen frame (scripts/ui/photo_mode.gd):
// 0 none, 1 noir, 2 sepia, 3 punch (contrast + saturation), 4 vignette.
// Every mode but 0 also darkens the corners a little, like a lens.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (mode == 1) {
		float n = clamp((l - 0.5) * 1.35 + 0.5, 0.0, 1.0);
		c = vec3(n);
	} else if (mode == 2) {
		c = vec3(l * 1.07, l * 0.88, l * 0.66) + vec3(0.04, 0.02, 0.0);
	} else if (mode == 3) {
		c = mix(vec3(l), c, 1.45);
		c = clamp((c - 0.5) * 1.25 + 0.5, 0.0, 1.0);
	}
	if (mode != 0) {
		vec2 d = SCREEN_UV - vec2(0.5);
		float v = smoothstep(0.85, 0.25, length(d) * (mode == 4 ? 1.35 : 1.0));
		c *= mix(mode == 4 ? 0.25 : 0.6, 1.0, v);
	}
	COLOR = vec4(c, 1.0);
}
