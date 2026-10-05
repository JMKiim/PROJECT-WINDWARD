shader_type spatial;
render_mode cull_disabled;

uniform vec4 strap_color : source_color = vec4(0.145,0.157,0.165,1.0);
uniform float strap_roughness = 0.87;
uniform float vertical_lift = 0.0;

float ramp_derivative(float low, float high, float z) {
	float t = clamp((z-low)/(high-low),0.0,1.0);
	return 6.0*t*(1.0-t)/(high-low);
}

void vertex() {
	float front = smoothstep(0.380,0.435,VERTEX.z);
	float rear = 1.0-smoothstep(0.800,0.875,VERTEX.z);
	float gradient = ramp_derivative(0.380,0.435,VERTEX.z)*rear-front*ramp_derivative(0.800,0.875,VERTEX.z);
	VERTEX.y += vertical_lift*front*rear;
	NORMAL = normalize(vec3(NORMAL.x,NORMAL.y,NORMAL.z-vertical_lift*gradient*NORMAL.y));
}

void fragment() {
	ALBEDO = strap_color.rgb;
	ROUGHNESS = strap_roughness;
}
