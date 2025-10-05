shader_type canvas_item;

// --- Uniforms ---
// color_a: Inner color for radial gradient
uniform vec4 color_a : source_color = vec4(0.149, 0.682, 0.373, 1.0); // Inner color (#26ae5f)
// color_b: Outer color for radial gradient
uniform vec4 color_b : source_color = vec4(0.161, 0.686, 0.380, 1.0); // Outer color (#29AF61)

// speed: How fast the blob wanders
uniform float speed = 0.3;
// intensity: How far the blob's center moves from the card's center
uniform float intensity = 0.3;
// sharpness: How soft or sharp the gradient's edge is
uniform float sharpness = 1.5;

// random_seed: A unique number for each instance to randomize its movement
uniform float random_seed : hint_range(0.0, 100.0) = 0.0;


void fragment() {
	// 1. Create varied properties using the random seed.
	// This makes each instance feel slightly different.
	// We use sin/cos on the seed to get values between -1 and 1, creating small variations.
	float varied_speed = speed * (1.0 + sin(random_seed) * 0.2); // Varies speed by +/- 20%
	float varied_intensity = intensity * (1.0 + cos(random_seed) * 0.2); // Varies intensity by +/- 20%

	// 2. Create a moving center point.
	// We add the random_seed to TIME to offset the animation start point for each instance.
	vec2 moving_center = vec2(
		0.5 + sin((TIME * varied_speed) + random_seed) * varied_intensity,
		0.5 + cos((TIME * varied_speed * 0.7) + random_seed) * varied_intensity
	);

	// 3. Calculate the distance from the current pixel (UV) to the moving center.
	float dist = distance(UV, moving_center);

	// 4. Apply sharpness and clamp the result.
	float gradient_factor = clamp(dist * sharpness, 0.0, 1.0);
	
	// 5. Mix the two colors based on the final gradient factor.
	COLOR = mix(color_a, color_b, gradient_factor);
}