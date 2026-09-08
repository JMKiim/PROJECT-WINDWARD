shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int head_bind_index = -1;
uniform bool hide_head = false;
varying float head_weight;

void vertex() {
	head_weight = 0.0;
	for (int influence = 0; influence < 4; influence++) {
		if (int(BONE_INDICES[influence]) == head_bind_index) {
			head_weight += BONE_WEIGHTS[influence];
		}
	}
}

void fragment() {
	if (hide_head && (head_bind_index < 0 || head_weight >= 0.35)) {
		discard;
	}
	ALBEDO = texture(albedo_texture, UV).rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = texture(roughness_texture, UV).r;
}
