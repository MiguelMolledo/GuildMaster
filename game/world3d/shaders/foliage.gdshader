shader_type spatial;
render_mode cull_disabled;

// Season controls (0..1) and wind. Vertex colour carries the painted leaf colour.
uniform float autumn = 0.0;
uniform float spring = 0.0;
uniform float blossom = 0.0; // fruit trees: share of leaves that flower in spring
uniform bool bare = false;
uniform float wind = 1.0;
uniform vec3 tint = vec3(1.0);

varying vec3 wpos;
varying float tree;

float hash(vec3 p) {
	return fract(sin(dot(floor(p * 2.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y - 1.5, 0.0);
	float sway = sin(TIME * 1.3 + w.x * 0.35 + w.z * 0.27) * 0.035 * h * wind;
	float flutter = sin(TIME * 4.1 + w.x * 2.1 + w.y * 1.7 + w.z * 1.3) * 0.012 * h * wind;
	VERTEX.x += sway + flutter;
	VERTEX.z += sway * 0.6 - flutter;
	wpos = w;
	// per tree (per MultiMesh instance too): MODEL_MATRIX only carries the instance transform in vertex()
	tree = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(3.1, 7.7, 1.3))) * 9137.1);
}

void fragment() {
	if (bare) {
		discard;
	}
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * 1.25;
	float lum = min(dot(c, vec3(0.3, 0.59, 0.11)), 0.3);
	c *= tint;
	float r = hash(wpos);
	// each tree leans to its own autumn hue (yellow / orange / red), leaves vary around it
	vec3 hue = tree < 0.35 ? vec3(0.98, 0.78, 0.16) : (tree < 0.7 ? vec3(0.96, 0.48, 0.10) : vec3(0.78, 0.17, 0.07));
	vec3 au = mix(hue, hue * vec3(0.85, 0.7, 0.6), r) * (lum * 2.6 + 0.12);
	vec3 sp = c * vec3(1.12, 1.18, 0.8) + vec3(0.025, 0.035, 0.0);
	c = mix(c, au, autumn);
	c = mix(c, sp, spring);
	if (spring > 0.5 && r < blossom) {
		c = mix(vec3(1.0, 0.78, 0.86), vec3(1.0, 0.95, 0.95), hash(wpos * 3.1)) * 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
