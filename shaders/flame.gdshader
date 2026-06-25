shader_type spatial;
render_mode blend_add, cull_disabled;

// Using blend_add for glowing VFX and cull_disabled to show inner surfaces
// But you can also change rendermode to what you want


// *-*-*-*-*-* ^^^^^ COLORS *-*-*-*-*-* ^^^^^
uniform vec4 core_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);

// *-*-*-*-*-* ^^^^^ MOVEMENT & SCALE *-*-*-*-*-* ^^^^^
uniform sampler2D noise_texture : repeat_enable;
// Direction and Speed (X, Y)
uniform vec2 uv_pan = vec2(0.0, -10.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);

// *-*-*-*-*-* ^^^^^ ALPHA CUTOFF / EROSION *-*-*-*-*-* ^^^^^
// 0.0: Fully transparent | 1.0: Fully solid
uniform float noise_density : hint_range(0.0, 1.0) = 0.5;
// 0.001: Sharp edges | 0.5: Soft/Blurry edges
uniform float cut_sharpness : hint_range(0.001, 1.0) = 0.1;
// Multiplier for the noise glow brightness
uniform float noise_intensity = 1.0;

// *-*-*-*-*-* ^^^^^ SHAPE & VIEW ANGLE *-*-*-*-*-* ^^^^^
uniform float length_fade_power = 2.0;
uniform float edge_fade_power = 1.5;
// Prevents the shader from going dark when looking directly down the axis (0.0 to 1.0)
uniform float top_down_brightness : hint_range(0.0, 1.0) = 0.3;

// *-*-*-*-*-* ^^^^^ GLOBAL SETTINGS *-*-*-*-*-* ^^^^^
uniform float emission_energy = 3.0;

void fragment() {
    vec2 scaled_uv = UV * uv_scale;
    vec2 scrolling_uv = scaled_uv + (uv_pan * TIME);

    float base_noise = texture(noise_texture, scrolling_uv).r;
    // Gamma correction to deepen noise contrast
    base_noise = pow(base_noise, 2.2);

    // Invert density so 1.0 = solid, 0.0 = empty
    float threshold = 1.0 - noise_density;
    // Remaps noise based on threshold to create the erosion/cut effect
    float cut_noise = smoothstep(threshold, threshold + cut_sharpness, base_noise);

    // Ensures the mesh remains visible at steep angles (like top-down view)
    float fresnel = max(abs(dot(NORMAL, VIEW)), top_down_brightness);
    float edge_fade = pow(fresnel, edge_fade_power);

    float vertical_fade = 1.0 - UV.y;
    vertical_fade = pow(clamp(vertical_fade, 0.0, 1.0), length_fade_power);

    // Mixing is purely noise-based to keep the hot "core" visible from any direction
    float color_mix = smoothstep(0.1, 0.7, base_noise);
    vec3 base_color = mix(edge_color.rgb, core_color.rgb, color_mix);


    // Combine shape mask, vertical fade, and fresnel for transparency
    float final_alpha = cut_noise * vertical_fade * edge_fade;
    // Combine alpha with intensity and energy for emission strength
    float final_emission_strength = final_alpha * noise_intensity * emission_energy;


    ALBEDO = vec3(0.0);
    EMISSION = base_color * final_emission_strength;
    ALPHA = clamp(final_alpha, 0.0, 1.0);
}
