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

	ALBEDO = col * 0.15;
	EMISSION = col * emission_energy;
}
