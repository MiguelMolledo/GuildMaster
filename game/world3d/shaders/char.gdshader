shader_type spatial;
// Character material for the Quaternius kit: kit textures with toon lighting (like the town's "outline" style),
// a multiply tint (skin tone, hair colour) and two HSV recolour bands for clothes.
// A band selects texels by hue/saturation/value (soft edges) and repaints them with a target hue and
// saturation/value multipliers, so the painted shading survives. Vertex colour R masks the recolour
// (the bake sets it to 1 - hand weight: hands painted in the cloth texture keep their skin colour).
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform bool use_orm = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_gain = 1.0;  // > 1 lightens (albedo above the texture)
uniform float roughness = 1.0;

// band: x = hue centre (0-1), y = hue half width (>= 0.5 selects any hue)
uniform vec2 a_hue = vec2(0.0, 1.0);
uniform vec4 a_sv = vec4(0.0, 1.0, 0.0, 1.0);  // sat min, sat max, val min, val max
uniform vec4 a_dye = vec4(0.0, 1.0, 0.0, 0.5);  // target hue (0-1, < 0 keeps hue), sat mul, sat add, target value
uniform float a_ref = 0.5;  // mean value of the band's texels: they land on the target value, the rest compressed around it
uniform float a_on = 0.0;
uniform vec2 b_hue = vec2(0.0, 1.0);
uniform vec4 b_sv = vec4(0.0, 1.0, 0.0, 1.0);
uniform vec4 b_dye = vec4(0.0, 1.0, 0.0, 0.5);
uniform float b_ref = 0.5;
uniform float b_on = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float band(vec3 hsv, vec2 hue, vec4 sv) {
	float dh = abs(fract(hsv.x - hue.x + 0.5) - 0.5);
	float wh = hue.y >= 0.5 ? 1.0 : 1.0 - smoothstep(hue.y, hue.y + 0.04, dh);
	float ws = smoothstep(sv.x - 0.05, sv.x + 0.05, hsv.y) * (1.0 - smoothstep(sv.y - 0.05, sv.y + 0.05, hsv.y));
	float wv = smoothstep(sv.z - 0.05, sv.z + 0.05, hsv.z) * (1.0 - smoothstep(sv.w - 0.05, sv.w + 0.05, hsv.z));
	return wh * ws * wv;
}

vec3 dye(vec3 hsv, vec4 d, float ref) {
	float v = d.w * pow(max(hsv.z, 1e-3) / ref, 0.6);
	return hsv2rgb(vec3(d.x < 0.0 ? hsv.x : d.x, clamp(hsv.y * d.y + d.z, 0.0, 1.0), clamp(v, 0.0, 1.0)));
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float m = COLOR.r;
	if (a_on > 0.0 || b_on > 0.0) {
		// bands and dyes are defined on the painted (sRGB) colours; the sampler gives linear ones
		vec3 cs = pow(c, vec3(1.0 / 2.2));
		vec3 hsv = rgb2hsv(cs);
		vec3 o = cs;
		if (a_on > 0.0) {
			o = mix(o, dye(hsv, a_dye, a_ref), band(hsv, a_hue, a_sv) * a_on * m);
		}
		if (b_on > 0.0) {
			o = mix(o, dye(hsv, b_dye, b_ref), band(hsv, b_hue, b_sv) * b_on * m);
		}
		c = pow(o, vec3(2.2));
	}
	ALBEDO = c * tint.rgb * tint_gain;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = roughness;
	if (use_orm) {
		AO = texture(orm_tex, UV).r;
		AO_LIGHT_AFFECT = 0.6;
	}
}
