shader_type spatial;

// Grass ground: painted tileable texture in world space, broken up by a large-scale tonal
// variation so the repetition does not show, and a season tint.
uniform sampler2D grass : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float snow = 0.0;
uniform float scale = 0.09;
uniform float seco = 0.0; // dry grass (scripts/clima/vida.gd by season): towards straw, broken up by the macro variation

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 g = texture(grass, wpos.xz * scale).rgb;
	vec3 macro = texture(grass, wpos.xz * scale * 0.11 + vec2(0.37, 0.71)).rgb;
	float v = dot(macro, vec3(0.3, 0.59, 0.11)) / 0.42;
	vec3 c = g * vec3(0.8, 0.8, 0.78) * mix(0.9, 1.1, clamp(v - 0.5, 0.0, 1.0)) * tint;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(l) * vec3(1.45, 1.12, 0.55), clamp(seco * (0.7 + 0.6 * (v - 0.5)), 0.0, 1.0));
	c = mix(c, vec3(0.88, 0.91, 0.95) * (0.92 + 0.1 * g.g), snow);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
