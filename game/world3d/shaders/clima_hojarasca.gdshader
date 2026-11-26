shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Leaf litter on the ground (scripts/clima/vida.gd): a MultiMesh of flat cards, each a scatter of small leaves cut out
// of the card by noise, its hues from the instance colour (yellow, orange, red-brown, dry brown).
uniform float amount = 1.0; // 0 none .. 1 all the leaves of the card

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec4 icol;

void vertex() {
	icol = COLOR;
}

void fragment() {
	vec2 g = UV * 7.0;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id + icol.a * 17.0);
	float ang = h * 6.2832;
	vec2 q = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * f;
	float leaf = step(length(q * vec2(2.2, 1.1)), 0.42);
	float r = length(UV - 0.5) * 2.0;
	float keep = step(h, amount * (1.0 - smoothstep(0.35, 1.0, r)) * 0.95);
	if (leaf * keep < 0.5) {
		discard;
	}
	vec3 c = icol.rgb * (0.75 + 0.5 * hash(id * 3.1 + 2.0));
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
