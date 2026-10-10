// The interior wall screen's face (scripts/levels/landmark.gd, kind "screen"):
// the AI's eye on a dark, scanlined panel. `look` (-1..1 each way) shifts the
// pupil toward the player; `blink` closes the lids (0 open, 1 shut).
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 accent : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec2 look = vec2(0.0);
uniform float blink = 0.0;
uniform float aspect = 1.6; // width / height
uniform float energy = 2.2;

void fragment() {
	vec2 uv = UV;
	// Centred, in units of screen height; +y up.
	vec2 p = (uv - vec2(0.5, 0.47)) * vec2(aspect, 1.0);
	p.y = -p.y;
	float half_w = 0.62;
	float open = 0.3 * (1.0 - blink);
	float xs = clamp(abs(p.x) / half_w, 0.0, 1.0);
	float lid = open * (1.0 - xs * xs);
	float inside = step(abs(p.y), lid) * step(abs(p.x), half_w);
	vec2 pc = p - look * vec2(0.24, 0.12);
	float d = length(pc);
	float iris = smoothstep(0.205, 0.19, d);
	float pupil = smoothstep(0.078, 0.066, d);
	float ang = atan(pc.y, pc.x);
	float stri = 0.55 + 0.45 * sin(ang * 46.0 + d * 40.0 - TIME * 0.6);
	float hot = smoothstep(0.2, 0.07, d);
	vec3 col = accent.rgb * 0.07 * inside;
	col += accent.rgb * iris * stri * (0.5 + 1.2 * hot) * inside;
	col = mix(col, vec3(0.0), pupil * inside);
	col += vec3(1.0) * smoothstep(0.022, 0.0, length(pc - vec2(-0.035, 0.035))) * inside;
	float edge = smoothstep(0.012, 0.0, abs(abs(p.y) - lid)) * step(abs(p.x), half_w);
	col += accent.rgb * edge * 1.6;
	// Panel: faint grid, rolling scanlines, a vignette.
	vec2 g = abs(fract(uv * vec2(aspect * 10.0, 10.0)) - 0.5);
	col += accent.rgb * smoothstep(0.46, 0.5, max(g.x, g.y)) * 0.07;
	col *= 0.82 + 0.18 * sin(uv.y * 360.0 - TIME * 5.0);
	col *= smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(aspect, 1.0)));
	ALBEDO = col * energy;
}
