shader_type canvas_item;
// Colourblind correction: one full-screen pass on top of everything the game
// draws (world, HUD, cutscenes, menus). GraphicsSettings owns the overlay and
// uploads colorblind_matrix(mode); the overlay is hidden when the mode is Off.
// Greys are fixed points of the matrix, so neutral text keeps its colour.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform mat3 cb_matrix = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(max(cb_matrix * col, vec3(0.0)), 1.0);
}
