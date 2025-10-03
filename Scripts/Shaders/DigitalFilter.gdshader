shader_type canvas_item;

// Uniforms to control the effect from the Inspector
uniform float strength : hint_range(0.0, 1.0) = 0.1;
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.01;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
// NEW UNIFORM: Controls the size of the feathered edge. 0.0 = hard edge, 1.0 = softest edge.
uniform float feather_amount : hint_range(0.0, 1.0) = 0.4;

// Simple pseudo-random number generator
float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    // --- START: Feathering Logic ---
    // Calculate the distance from the center (0.0) to the edge (1.0) for a square shape.
    vec2 center_dist = abs(UV - 0.5) * 2.0;
    float edge_dist = max(center_dist.x, center_dist.y);

    // Calculate our fade-out multiplier. It will be 1.0 in the center and fade to 0.0 at the edges.
    float feather_start = 1.0 - feather_amount;
    float feather_multiplier = 1.0 - smoothstep(feather_start, 1.0, edge_dist);
    // --- END: Feathering Logic ---

    // We modify the strength of the glitch based on how close it is to the edge.
    float modified_strength = strength * feather_multiplier;

    vec4 final_color;
    float random = rand(UV + TIME);

    // Apply the glitch effect using our new feathered strength
    if (random < modified_strength) {
        // Calculate a random offset for the glitch
        vec2 offset = vec2(rand(UV * TIME) - 0.5, rand(UV - TIME) - 0.5) * 0.1;

        // Sample the screen texture with chromatic aberration
        float r = texture(TEXTURE, UV + offset - vec2(aberration_amount)).r;
        float g = texture(TEXTURE, UV + offset).g;
        float b = texture(TEXTURE, UV + offset + vec2(aberration_amount)).b;

        final_color = vec4(r, g, b, 1.0);
    } else {
        // If not glitching, just show the normal texture
        final_color = texture(TEXTURE, UV);
    }

    // Set the final color for the pixel
    COLOR = final_color;

    // Apply our opacity control at the very end
    COLOR.a *= opacity;
}