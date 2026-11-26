shader_type spatial;

// Still water of fountains, troughs and wash houses (LandmarkBuilder gives it to the surfaces named MI_Water):
// the river's colours, slow ripples drifting in world space and small glints; it does not flow.
uniform vec3 shallow : source_color = vec3(0.40, 0.70, 0.72);
uniform vec3 deep : source_color = vec3(0.13, 0.38, 0.52);
uniform float speed = 0.3;
uniform float scale = 4.5;
uniform float glint = 1.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = wpos.xz * scale;
	float n = vnoise(p + vec2(t, t * 0.6)) * 0.6 + vnoise(p * 2.3 - vec2(t * 0.8, t * 1.1)) * 0.4;
	vec3 c = mix(deep, shallow, smoothstep(0.2, 0.85, n));
	c += vec3(0.45, 0.5, 0.5) * smoothstep(0.74, 0.8, n) * glint;
	ALBEDO = c;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
