shader_type spatial;
// Domain-warped flow-noise lava, ported from a canvas_item shader to a spatial
// surface: maps over the bed UVs (not screen space) and drives EMISSION so the
// molten veins glow + bloom. NOT unshaded (that would drop EMISSION).
render_mode cull_disabled;

uniform float timeScaleFactor = 0.04;
// A seamless noise texture (fed by FlameMaterial.noise() from LavaHazard).
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform vec3 base_color : source_color = vec3(0.28, 0.1, 0.015);
uniform float emission_energy = 3.6;
uniform vec2 plane_size = vec2(8.0, 3.0); // bed footprint, so cell size is consistent
uniform float cell_density = 0.4;
uniform float crust_width = 1.15;   // metres of cooling margin at the bed's rim
uniform vec3 crust_color : source_color = vec3(0.048, 0.034, 0.030);

float localTime() {
	return TIME * timeScaleFactor;
}

mat2 makem2(float theta) {
	float c = cos(theta);
	float s = sin(theta);
	return mat2(vec2(c, -s), vec2(s, c));
}

float noise(vec2 x) {
	return texture(noise_texture, x * 0.01).x;
}

vec2 gradn(vec2 p) {
	float ep = 0.09;
	float gradx = noise(vec2(p.x + ep, p.y)) - noise(vec2(p.x - ep, p.y));
	float grady = noise(vec2(p.x, p.y + ep)) - noise(vec2(p.x, p.y - ep));
	return vec2(gradx, grady);
}

float flow(vec2 p) {
	float z = 2.0;
	float rz = 0.0;
	vec2 bp = p;

	for (float i = 1.0; i < 7.0; ++i) {
		p += localTime() * 0.6;
		bp += localTime() * 1.9;
		vec2 gr = gradn(i * p * 0.34 + localTime() * 1.0);
		gr *= makem2(localTime() * 6.0 - (0.05 * p.x + 0.03 * p.y) * 40.0);
		p += gr * 0.5;
		rz += (sin(noise(p) * 7.0) * 0.5 + 0.5) / z;
		p = mix(bp, p, 0.77);
		z *= 1.4;
		p *= 2.0;
		bp *= 1.9;
	}
	return rz;
}

void fragment() {
	// Map over the bed surface (scaled by its footprint so the molten cells stay a
	// consistent size on any bed), instead of the original screen-space coords.
	vec2 p = (UV - 0.5) * plane_size * cell_density;

	float rz = flow(p);
	vec3 col = base_color / rz;
	col = pow(col, vec3(1.4));

	// --- shore crust -------------------------------------------------------
	// Molten rock chills toward the bed's own border, so the edge reads as
	// crusting over rather than a plane cut off mid-flow. Together with the
	// scorched fluid_margin band just outside it, the transition runs
	// molten -> crust -> scorched rock -> clean floor instead of one hard line.
	//
	// Driven by UV distance to the border, NOT the depth buffer: this material
	// is opaque, so it writes the depth prepass and would read back its OWN
	// depth, crusting the whole bed. (The water surface can use the depth
	// buffer safely — it is transparent and never writes depth.)
	vec2 to_edge = min(UV, vec2(1.0) - UV) * plane_size;
	float crust = 1.0 - clamp(min(to_edge.x, to_edge.y) / max(crust_width, 0.001), 0.0, 1.0);
	float edge_t = min(to_edge.x, to_edge.y) / max(crust_width, 0.001);
	// Let the flow field chew the crust line up so it is not a clean inset band.
	crust = clamp(crust * (0.68 + 0.55 * (rz - 0.5)), 0.0, 1.0);
	// ...but SEAL the outermost sliver regardless of what the noise says. Lava
	// chills hardest where it meets cold rock, and leaving the noise in charge
	// right at the rim left ~32% molten colour glowing along the bed's hard
	// plane edge — a visible step against the scorched margin just outside it.
	crust = max(crust, smoothstep(0.25, 0.0, edge_t));

	// The crust never fully seals: the hottest veins keep glowing through it.
	float veins = clamp(rz - 0.6, 0.0, 1.0);
	float glow_keep = mix(1.0, 0.15 + 0.55 * veins, crust);

	ALBEDO = mix(col * 0.15, crust_color, crust);
	EMISSION = col * emission_energy * glow_keep;
}
