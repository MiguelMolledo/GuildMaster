shader_type spatial;
render_mode cull_disabled;

// Stylized river on a RoadBuilder ribbon (UV.x along, UV.y across in metres, COLOR.r = half width / 10):
// deeper colour in the middle, ripples drifting downstream, broken foam along the ragged banks.
uniform vec3 shallow : source_color = vec3(0.36, 0.66, 0.66);
uniform vec3 deep : source_color = vec3(0.10, 0.32, 0.46);
uniform float speed = 0.7;
uniform float frozen = 0.0;
uniform float hw_unit = 10.0;
uniform float foam_amount = 1.0; // ponds: little foam, the water barely moves
uniform float glint = 0.0; // sun glints on the ripples (scripts/clima/fx.gd: strong when the sun is low)
uniform vec3 glint_col : source_color = vec3(1.0, 0.85, 0.6);
uniform float lluvia = 0.0; // rain: rings all over and a duller surface

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
	float hw = COLOR.r * hw_unit;
	float off = abs(UV.y);
	float nz = vnoise(wpos.xz * 0.45) * 0.6 + vnoise(wpos.xz * 1.8) * 0.4;
	float edge = hw * (0.8 + 0.3 * nz);
	if (off > edge) {
		discard;
	}
	float d = 1.0 - off / edge;
	vec3 c = mix(shallow, deep, smoothstep(0.05, 0.75, d));
	float t = TIME * speed * (1.0 - frozen);
	vec2 flow = vec2(UV.x * 0.45 - t, UV.y * 1.2);
	float rip = vnoise(flow * 1.6) * 0.6 + vnoise(flow * 4.0 + 3.0) * 0.4;
	c += vec3(0.10, 0.13, 0.12) * smoothstep(0.62, 0.8, rip) * foam_amount;
	float foam = smoothstep(0.78, 0.95, off / edge + 0.25 * (vnoise(flow * 3.0) - 0.5));
	c = mix(c, vec3(0.92, 0.96, 0.95), foam * 0.85 * foam_amount);
	c = mix(c, vec3(0.82, 0.9, 0.95), frozen * 0.85);
	vec3 em = vec3(0.0);
	if (glint > 0.01 && frozen < 0.5) {
		float g = vnoise(flow * 6.0 + vec2(TIME * 0.9, 0.0)) * vnoise(flow * 9.0 - vec2(0.0, TIME * 1.3));
		em = glint_col * smoothstep(0.42, 0.62, g) * glint * 2.2 * (1.0 - foam);
	}
	if (lluvia > 0.01) {
		vec2 cell = floor(wpos.xz / 0.5);
		vec2 ctr = (cell + vec2(hash(cell + 3.1), hash(cell + 7.7))) * 0.5;
		float ph = fract(TIME * 1.4 + hash(cell));
		float ring = 1.0 - smoothstep(0.0, 0.025, abs(length(wpos.xz - ctr) - ph * 0.3));
		c += vec3(0.12, 0.14, 0.15) * ring * (1.0 - ph) * lluvia;
		c *= 1.0 - 0.15 * lluvia;
	}
	ALBEDO = c;
	EMISSION = em;
	ROUGHNESS = mix(mix(0.08, 0.3, lluvia), 0.5, frozen);
	SPECULAR = 0.7;
}
