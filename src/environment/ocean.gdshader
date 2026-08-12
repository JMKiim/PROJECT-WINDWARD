shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.018, 0.12, 0.20, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.035, 0.30, 0.42, 1.0);
uniform vec4 foam_color : source_color = vec4(0.68, 0.84, 0.88, 1.0);
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform vec2 current_velocity = vec2(0.16, -0.05);
uniform float wind_speed = 6.0;
uniform float simulation_time = 0.0;
uniform float sea_level = 0.0;
uniform vec3 wave_amplitudes = vec3(0.105, 0.034, 0.010);
uniform vec3 wave_numbers = vec3(0.34, 0.68, 1.48);
uniform vec3 wave_angular_speeds = vec3(1.18, 1.72, 2.55);
uniform float cross_wave_direction_offset = 0.18;
uniform float cross_swell_strength = 0.36;

varying vec3 world_vertex;
varying float combined_wave_height;


float random_value(vec2 position) {
	return fract(sin(dot(position, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 position) {
	vec2 cell = floor(position);
	vec2 local = fract(position);
	local = local * local * (3.0 - 2.0 * local);
	float bottom_left = random_value(cell);
	float bottom_right = random_value(cell + vec2(1.0, 0.0));
	float top_left = random_value(cell + vec2(0.0, 1.0));
	float top_right = random_value(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, local.x),
		mix(top_left, top_right, local.x),
		local.y
	);
}


void vertex() {
	vec3 original_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 direction_a = normalize(wind_direction + vec2(0.0001));
	vec2 direction_b = normalize(
		direction_a
		+ vec2(-direction_a.y, direction_a.x) * cross_wave_direction_offset
	);
	float wind_scale = clamp(wind_speed / 6.0, 0.55, 1.8);

	// All wave trains advance with the wind. A strong cross-wave made the old
	// highlights sweep sideways even when the boat was moving straight ahead.
	float phase_a = dot(original_world.xz, direction_a) * wave_numbers.x - simulation_time * wave_angular_speeds.x * wind_scale;
	float phase_b = dot(original_world.xz, direction_b) * wave_numbers.y - simulation_time * wave_angular_speeds.y * wind_scale;
	float phase_c = dot(original_world.xz, direction_a) * wave_numbers.z - simulation_time * wave_angular_speeds.z * wind_scale;

	float height_a = sin(phase_a) * wave_amplitudes.x * wind_scale;
	float height_b = sin(phase_b) * wave_amplitudes.y * wind_scale * cross_swell_strength;
	float height_c = sin(phase_c) * wave_amplitudes.z;
	combined_wave_height = sea_level + height_a + height_b + height_c;
	VERTEX.y += combined_wave_height;

	float derivative_x = (
		cos(phase_a) * wave_amplitudes.x * wind_scale * wave_numbers.x * direction_a.x
		+ cos(phase_b) * wave_amplitudes.y * wind_scale * cross_swell_strength * wave_numbers.y * direction_b.x
		+ cos(phase_c) * wave_amplitudes.z * wave_numbers.z * direction_a.x
	);
	float derivative_z = (
		cos(phase_a) * wave_amplitudes.x * wind_scale * wave_numbers.x * direction_a.y
		+ cos(phase_b) * wave_amplitudes.y * wind_scale * cross_swell_strength * wave_numbers.y * direction_b.y
		+ cos(phase_c) * wave_amplitudes.z * wave_numbers.z * direction_a.y
	);
	NORMAL = normalize(vec3(-derivative_x, 1.0, -derivative_z));
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 flow_position = world_vertex.xz - current_velocity * simulation_time;
	vec2 direction = normalize(wind_direction + vec2(0.0001));
	vec2 cross_direction = vec2(-direction.y, direction.x);
	float broad_variation = value_noise(flow_position * 0.075);
	float phase_warp = value_noise(world_vertex.xz * 0.27) * 1.35;
	float directional_ripple = sin(
		dot(flow_position, direction) * 4.8
		+ dot(flow_position, cross_direction) * 0.035
		+ phase_warp
		- simulation_time * 3.7
	);
	float short_crest = (
		smoothstep(0.88, 0.99, directional_ripple * 0.5 + 0.5)
		* smoothstep(0.58, 0.86, broad_variation)
	);
	float crest = smoothstep(0.17, 0.29, combined_wave_height);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 water_color = mix(deep_color.rgb, shallow_color.rgb, fresnel * 0.68 + crest * 0.12);
	water_color = mix(water_color, foam_color.rgb, crest * 0.1 + short_crest * 0.075);

	ALBEDO = water_color;
	METALLIC = 0.04;
	ROUGHNESS = mix(0.38, 0.22, fresnel);
	SPECULAR = 0.48;
}
