shader_type canvas_item;
// Night-vision goggles (Player.toggle_night_vision): an image-intensifier pass
// over the finished frame. Auto-gain lifts the dark hard and compresses the
// bright (1 - exp(-l * gain)), a blurred tap adds the phosphor bloom round
// lights and robot eyes, then green phosphor, grain, faint scanlines and the
// round goggle mask. `boot` ramps 0 -> 1 as the tube powers up (a white flash
// that settles).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float gain = 10.0;
uniform float boot = 1.0;
uniform vec3 phosphor = vec3(0.30, 1.0, 0.42);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 glow = textureLod(screen_tex, uv, 3.5).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float lg = dot(glow, vec3(0.299, 0.587, 0.114));
	float amp = 1.0 - exp(-(l + lg * 0.35) * gain);
	// Grain that changes every frame, and the tube's faint scanlines.
	float n = hash(floor(FRAGCOORD.xy * 0.5) + vec2(TIME * 61.0, TIME * 17.0));
	amp += (n - 0.5) * 0.09;
	amp *= 0.93 + 0.07 * sin(FRAGCOORD.y * 1.7);
	// Power-up: starts as a white flash, settles to the gain.
	float flash = (1.0 - boot) * 1.4;
	vec3 col = phosphor * clamp(amp, 0.0, 1.2) + vec3(flash);
	// Round goggle mask, corrected for the aspect ratio, with a soft rim.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length((uv - 0.5) * vec2(aspect, 1.0));
	float mask = smoothstep(0.66, 0.5, d);
	COLOR = vec4(col * mask, 1.0);
}
