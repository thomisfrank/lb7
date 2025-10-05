shader_type canvas_item;
render_mode blend_mix, unshaded;

// --- UNIFORMS: This block must be at the top ---
// It declares all the variables for the Inspector.
uniform float pixel_size : hint_range(1.0, 16.0) = 2.0;
uniform float scanline_darkness : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_spacing : hint_range(1.0, 10.0) = 3.0;
uniform float curvature_amount : hint_range(0.0, 1.0) = 0.1;
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.01;
uniform float noise_amount : hint_range(0.0, 0.2) = 0.04;
uniform float overlay_strength : hint_range(0.0, 1.0) = 0.5;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float bloom_intensity : hint_range(0.0, 2.0) = 1.1;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.05;
uniform float flicker_speed : hint_range(0.0, 20.0) = 10.0;
// --- End of UNIFORMS ---


float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    // --- 1. Screen Curvature ---
    // This now relies on the texture sampler settings (Repeat: Disabled) in the editor.
    vec2 centered_uv = UV - vec2(0.5);
    float len = length(centered_uv);
    vec2 warped_uv = UV + centered_uv * pow(len, 2.0) * curvature_amount;

    // --- 2. Pixelation ---
    vec2 grid_uv = floor(warped_uv * TEXTURE_PIXEL_SIZE / pixel_size)
                 * pixel_size / TEXTURE_PIXEL_SIZE;

    // --- 3. Chromatic Aberration ---
    vec2 offset = centered_uv * aberration_amount;
    float r = texture(TEXTURE, grid_uv - offset).r;
    float g = texture(TEXTURE, grid_uv).g;
    float b = texture(TEXTURE, grid_uv + offset).b;
    float a = texture(TEXTURE, grid_uv).a;
    vec4 effect_color = vec4(r, g, b, a);
    
    // --- 4. Bloom Effect ---
    float brightness = dot(effect_color.rgb, vec3(0.2126, 0.7152, 0.0722));
    if (brightness > bloom_threshold) {
        vec2 px = vec2(1.0) / TEXTURE_PIXEL_SIZE;
        effect_color.rgb += texture(TEXTURE, grid_uv + vec2(px.x, 0.0)).rgb * bloom_intensity;
        effect_color.rgb += texture(TEXTURE, grid_uv - vec2(px.x, 0.0)).rgb * bloom_intensity;
        effect_color.rgb += texture(TEXTURE, grid_uv + vec2(0.0, px.y)).rgb * bloom_intensity;
        effect_color.rgb += texture(TEXTURE, grid_uv - vec2(0.0, px.y)).rgb * bloom_intensity;
    }

    // --- 5. Scanlines ---
    if (mod(FRAGCOORD.y, scanline_spacing) < 1.0) {
        effect_color.rgb *= (1.0 - scanline_darkness);
    }
    
    // --- 6. Noise ---
    float noise = (rand(UV + TIME) - 0.5) * noise_amount;
    effect_color.rgb += vec3(noise);

    // --- 7. Flicker Effect ---
    float flicker = sin(TIME * flicker_speed) * 0.5 + 0.5;
    effect_color.rgb *= (1.0 - (flicker * flicker_amount));
    
    // --- 8. Final Blending ---
    vec4 scene_color = texture(TEXTURE, warped_uv);
    vec4 blended = mix(scene_color, effect_color, overlay_strength);
    COLOR = blended;
}