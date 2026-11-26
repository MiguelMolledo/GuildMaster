shader_type spatial;
render_mode cull_disabled;

// Organic road ribbon. UV.x = metres along the road, UV.y = signed metres across,
// COLOR.r = half width / 10. The edge is cut by noise (no straight borders); an optional
// cobbled core (fraction of the half width) fades into packed dirt, which darkens at the rim.
uniform sampler2D dirt : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D cobble : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D cobble_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float cobble_core = 0.0;
uniform float snow = 0.0;
uniform float hw_unit = 10.0;
uniform float edge_base = 0.62;
uniform float edge_var = 0.62;
uniform vec3 tint = vec3(1.0);

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
	float off = abs(UV.y);
	float hw = COLOR.r * hw_unit;
	float nz = vnoise(wpos.xz * 0.35) * 0.5 + vnoise(wpos.xz * 1.3) * 0.3 + vnoise(wpos.xz * 4.0) * 0.2;
	float edge = hw * (edge_base + edge_var * nz);
	if (off > edge) {
		discard;
	}
	vec3 c = texture(dirt, wpos.xz * 0.16).rgb;
	c *= mix(1.0, 0.82, smoothstep(edge * 0.6, edge, off));
	vec3 nm = vec3(0.5, 0.5, 1.0);
	if (cobble_core > 0.0) {
		float core = hw * cobble_core * (0.75 + 0.5 * vnoise(wpos.xz * 0.8 + 7.0));
		float k = 1.0 - smoothstep(core * 0.75, core, off);
		k *= step(0.18, vnoise(wpos.xz * 3.0 + 3.0) + k * 0.6); // missing stones near the worn edge
		c = mix(c, texture(cobble, wpos.xz * 0.13).rgb, k);
		nm = mix(nm, texture(cobble_n, wpos.xz * 0.13).rgb, k);
	}
	c *= tint;
	c = mix(c, vec3(0.9, 0.92, 0.95) * (0.9 + 0.1 * nz), snow * 0.85);
	ALBEDO = c;
	NORMAL_MAP = nm;
	ROUGHNESS = 0.95;
}
