shader_type canvas_item;
render_mode blend_add, unshaded;
// Camera lens flare from the sun (or the night sky's moon), drawn additively
// under the player's post pass so it takes the grade, grain and vignette.
// LensFlare (scripts/fx/lens_flare.gd) feeds the light's screen position and an
// occlusion-faded strength every frame; at strength 0 the node is hidden.
//   - bloom: a soft core and wide glow round the light
//   - starburst: thin aperture spikes that turn slowly with the view
//   - anamorphic streak: a long horizontal blue-white line through it
//   - ghosts: tinted aperture reflections along the axis from the light
//     through the screen centre, mirrored to the far side as it nears an edge
//   - halo: a faint prismatic ring centred on the screen
//   - lens dirt: smudges and specks on the glass (a texture baked once at
//     load), invisible until the light is near them

uniform vec2 light_uv = vec2(0.5, 0.5);
uniform float strength : hint_range(0.0, 1.5) = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.8);
uniform float aspect = 1.7777;
uniform float spin = 0.0; // starburst rotation (radians), follows the view yaw
uniform float dirt_amount : hint_range(0.0, 2.0) = 1.0;
uniform float ghost_amount : hint_range(0.0, 2.0) = 1.0;
// Smudges and specks on the glass, baked once by LensFlare.dirt_texture().
uniform sampler2D dirt_tex : filter_linear, repeat_disable;

float ghost(vec2 p, vec2 c, float r, float soft) {
	float d = length(p - c);
	return smoothstep(r, r * (1.0 - soft), d);
}

void fragment() {
	if (strength <= 0.0005) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = SCREEN_UV;
		vec2 asp = vec2(aspect, 1.0);
		vec2 d = (uv - light_uv) * asp;
		float dist = length(d);
		vec3 col = vec3(0.0);

		// Bloom: tight hot core plus a broad, low glow.
		col += tint * (exp(-dist * 70.0) * 1.1 + exp(-dist * 9.0) * 0.2);

		// Starburst: six short aperture spikes (a hexagonal iris), fading fast.
		float ang = atan(d.y, d.x) + spin;
		float spikes = pow(abs(cos(ang * 3.0)), 220.0);
		col += tint * spikes * exp(-dist * 11.0) * 0.45;

		// Anamorphic streak: long and thin, cooler than the light.
		float streak = exp(-abs(d.y) * 260.0) * exp(-abs(d.x) * 1.6);
		col += mix(tint, vec3(0.55, 0.75, 1.0), 0.6) * streak * 0.42;

		// Ghosts along the lens axis (light -> centre -> beyond). Each is a
		// soft aperture disc tinted a little differently, larger the further
		// it sits from the light; one hollow ring for the classic look.
		vec2 axis = vec2(0.5) - light_uv;
		vec2 p = uv * asp;
		float edge = clamp(length(axis) * 1.6, 0.0, 1.0); // ghosts swell off-centre
		vec3 g = vec3(0.0);
		g += vec3(1.0, 0.55, 0.25) * ghost(p, (light_uv + axis * 0.55) * asp, 0.030, 0.7) * 0.35;
		g += vec3(0.35, 1.0, 0.55) * ghost(p, (light_uv + axis * 1.25) * asp, 0.060, 0.5) * 0.16;
		g += vec3(0.45, 0.6, 1.0) * ghost(p, (light_uv + axis * 1.6) * asp, 0.11, 0.35) * 0.10;
		g += vec3(1.0, 0.4, 0.75) * ghost(p, (light_uv + axis * 2.05) * asp, 0.045, 0.6) * 0.20;
		g += vec3(0.8, 0.9, 1.0) * ghost(p, (light_uv + axis * 0.25) * asp, 0.018, 0.8) * 0.40;
		float ring_d = length(p - (light_uv + axis * 1.85) * asp);
		g += vec3(0.6, 0.85, 1.0) * smoothstep(0.012, 0.0, abs(ring_d - 0.16)) * 0.10;
		col += g * tint * ghost_amount * mix(0.6, 1.0, edge);

		// Halo: a faint prismatic ring around the screen centre, brightest on
		// the side facing the light.
		vec2 hc = (uv - 0.5) * asp;
		float hr = length(hc);
		float facing = clamp(dot(normalize(hc + 1e-5), normalize(-axis * asp + 1e-5)) * 0.5 + 0.5, 0.0, 1.0);
		float ring = smoothstep(0.035, 0.0, abs(hr - 0.42));
		vec3 prism = vec3(smoothstep(0.035, 0.0, abs(hr - 0.43)),
				smoothstep(0.035, 0.0, abs(hr - 0.42)),
				smoothstep(0.035, 0.0, abs(hr - 0.41)));
		col += prism * ring * facing * facing * 0.07 * tint;

		// Lens dirt: big faint smudges plus small specks, lit only near the light.
		float dirt = texture(dirt_tex, uv).r;
		float lit = exp(-dist * 2.6);
		col += tint * dirt * lit * 0.32 * dirt_amount;

		COLOR = vec4(col * strength, 1.0);
	}
}
