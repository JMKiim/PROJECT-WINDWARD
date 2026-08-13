shader_type spatial;
// An opaque ocean receiving the full hard mast/sail shadow made that moving
// black band read as a second water-flow direction. The hull still casts and
// receives shadows; only this effectively infinite surface omits direct shadow
// modulation so motion is carried by waves, reflections and physical foam.
render_mode cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec4 deep_color : source_color = vec4(0.018, 0.12, 0.20, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.035, 0.30, 0.42, 1.0);
uniform vec4 foam_color : source_color = vec4(0.68, 0.84, 0.88, 1.0);
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform vec2 secondary_wave_direction = vec2(0.984, 0.177);
uniform vec2 surface_flow_offset = vec2(0.0);
uniform float wave_amplitude_scale = 1.0;
uniform float simulation_time = 0.0;
uniform float sea_level = 0.0;
uniform vec3 wave_amplitudes = vec3(0.105, 0.034, 0.010);
uniform vec3 wave_numbers = vec3(0.34, 0.68, 1.48);
uniform vec3 wave_angular_speeds = vec3(1.826308, 2.582789, 3.810354);
uniform vec3 wave_phase_offsets = vec3(0.47, 2.19, 4.03);
uniform float cross_swell_strength = 0.36;

varying vec3 world_vertex;
varying vec3 world_wave_normal;
varying float combined_wave_height;


vec2 normalized_or_right(vec2 direction) {
	float magnitude_squared = dot(direction, direction);
	if (magnitude_squared < 0.000001) {
		return vec2(1.0, 0.0);
	}
	return direction * inversesqrt(magnitude_squared);
}


float random_value(vec2 position) {
	// Trigonometric hashes were evaluated twelve times per water pixel. This
	// compact polynomial hash keeps the aperiodic result while making the same
	// three-octave surface practical for Compatibility/Web renderers.
	vec3 hash_position = fract(vec3(position.xyx) * 0.1031);
	hash_position += dot(hash_position, hash_position.yzx + 33.33);
	return fract((hash_position.x + hash_position.y) * hash_position.z);
}


vec3 value_noise_with_gradient(vec2 position) {
	vec2 cell = floor(position);
	vec2 fractional = fract(position);
	vec2 blend = fractional * fractional * (3.0 - 2.0 * fractional);
	vec2 blend_derivative = 6.0 * fractional * (1.0 - fractional);
	float bottom_left = random_value(cell);
	float bottom_right = random_value(cell + vec2(1.0, 0.0));
	float top_left = random_value(cell + vec2(0.0, 1.0));
	float top_right = random_value(cell + vec2(1.0, 1.0));
	float bottom = mix(bottom_left, bottom_right, blend.x);
	float top = mix(top_left, top_right, blend.x);
	float noise_value = mix(bottom, top, blend.y);
	float derivative_x = mix(
		bottom_right - bottom_left,
		top_right - top_left,
		blend.y
	) * blend_derivative.x;
	float derivative_y = (top - bottom) * blend_derivative.y;
	return vec3(noise_value, derivative_x, derivative_y);
}


vec3 rotated_noise_sample(
	vec2 position,
	vec2 axis,
	float scale,
	vec2 offset
) {
	vec2 perpendicular = vec2(-axis.y, axis.x);
	vec2 sample_position = vec2(
		dot(position, axis),
		dot(position, perpendicular)
	) * scale + offset;
	vec3 sample_value = value_noise_with_gradient(sample_position);
	vec2 world_gradient = (
		axis * sample_value.y
		+ perpendicular * sample_value.z
	) * scale;
	return vec3(sample_value.x, world_gradient);
}


float irregular_mask(float broad_value, float detail_value) {
	return smoothstep(
		0.43,
		0.70,
		detail_value + (broad_value - 0.5) * 0.24
	);
}


void vertex() {
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 direction_a = normalized_or_right(wind_direction);
	vec2 direction_b = normalized_or_right(secondary_wave_direction);
	vec2 advected_world_position = original_world.xz - surface_flow_offset;
	float phase_a = dot(advected_world_position, direction_a) * wave_numbers.x - simulation_time * wave_angular_speeds.x + wave_phase_offsets.x;
	float phase_b = dot(advected_world_position, direction_b) * wave_numbers.y - simulation_time * wave_angular_speeds.y + wave_phase_offsets.y;
	float phase_c = dot(advected_world_position, direction_a) * wave_numbers.z - simulation_time * wave_angular_speeds.z + wave_phase_offsets.z;
	combined_wave_height = (
		sea_level
		+ sin(phase_a) * wave_amplitudes.x * wave_amplitude_scale
		+ sin(phase_b) * wave_amplitudes.y * wave_amplitude_scale * cross_swell_strength
		+ sin(phase_c) * wave_amplitudes.z
	);
	VERTEX.y += combined_wave_height;

	vec2 wave_gradient = (
		direction_a * cos(phase_a) * wave_amplitudes.x * wave_amplitude_scale * wave_numbers.x
		+ direction_b * cos(phase_b) * wave_amplitudes.y * wave_amplitude_scale * cross_swell_strength * wave_numbers.y
		+ direction_a * cos(phase_c) * wave_amplitudes.z * wave_numbers.z
	);
	NORMAL = normalize(vec3(-wave_gradient.x, 1.0, -wave_gradient.y));
	world_wave_normal = normalize(
		(MODEL_NORMAL_MATRIX * NORMAL)
	);
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// surface_flow_offset is integrated on the CPU. It remains continuous when
	// the configured current changes, unlike current_velocity * absolute time.
	// Detail has no independent time term: it belongs to the water instead of
	// reading as another wave train travelling across the macro surface.
	vec2 flow_position = world_vertex.xz - surface_flow_offset;
	vec3 broad_sample = rotated_noise_sample(
		flow_position,
		vec2(0.819152, 0.573576),
		0.075,
		vec2(7.31, -3.17)
	);
	vec3 middle_sample = rotated_noise_sample(
		flow_position,
		vec2(-0.390731, 0.920505),
		0.46,
		vec2(-11.73, 5.29)
	);
	float camera_distance = distance(CAMERA_POSITION_WORLD, world_vertex);
	float detail_lod = smoothstep(28.0, 105.0, camera_distance);
	// Unlike merely fading the result, this branch stops paying for the finest
	// octave on distant water. It materially reduces the full-screen fragment
	// cost in the Compatibility/Web path while the transition remains smooth.
	vec3 fine_sample = vec3(0.5, 0.0, 0.0);
	if (camera_distance < 105.0) {
		fine_sample = rotated_noise_sample(
			flow_position,
			vec2(0.978148, -0.207912),
			1.12,
			vec2(19.41, 13.07)
		);
	}
	float middle_weight = 0.68;
	float fine_weight = 0.32 * (1.0 - detail_lod);
	float detail_weight = middle_weight + fine_weight;
	float detail_value = (
		middle_sample.x * middle_weight
		+ fine_sample.x * fine_weight
	) / max(0.001, detail_weight);
	vec2 detail_gradient = (
		middle_sample.yz * middle_weight
		+ fine_sample.yz * fine_weight
	);
	vec2 micro_gradient = detail_gradient * 0.14;
	vec3 macro_world_normal = normalize(world_wave_normal);
	vec3 detailed_world_normal = normalize(vec3(
		macro_world_normal.x - micro_gradient.x,
		max(0.2, macro_world_normal.y),
		macro_world_normal.z - micro_gradient.y
	));
	NORMAL = normalize((VIEW_MATRIX * vec4(detailed_world_normal, 0.0)).xyz);

	float macro_slope = length(macro_world_normal.xz);
	float relative_crest_height = combined_wave_height - sea_level;
	float breakup = irregular_mask(broad_sample.x, detail_value);
	float crest = (
		smoothstep(0.025, 0.065, macro_slope)
		* smoothstep(0.025, 0.105, relative_crest_height)
		* breakup
	);
	float small_crest = (
		smoothstep(0.59, 0.78, detail_value)
		* smoothstep(0.018, 0.052, macro_slope)
		* smoothstep(-0.005, 0.065, relative_crest_height)
	);
	float fresnel = pow(
		1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0),
		5.0
	);
	float color_mix = clamp(
		0.075
		+ broad_sample.x * 0.10
		+ detail_value * 0.035
		+ crest * 0.14
		+ fresnel * 0.085,
		0.0,
		1.0
	);
	vec3 water_color = mix(deep_color.rgb, shallow_color.rgb, color_mix);
	float foam_amount = clamp(
		crest * 0.095 + small_crest * 0.050,
		0.0,
		0.16
	);
	water_color = mix(water_color, foam_color.rgb, foam_amount);

	ALBEDO = water_color;
	METALLIC = 0.0;
	float irregular_roughness = (detail_value - 0.5) * 0.045;
	ROUGHNESS = clamp(
		mix(0.21, 0.09, fresnel)
		+ irregular_roughness
		+ foam_amount * 0.24,
		0.075,
		0.40
	);
	// Godot maps dielectric F0 from SPECULAR; 0.25 is approximately water's
	// two-percent normal-incidence reflectance.
	SPECULAR = 0.25;
}
