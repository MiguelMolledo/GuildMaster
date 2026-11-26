shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded, fog_disabled;

// The small life of scripts/clima/vida.gd, drawn by GPUParticles3D (one draw call each, a QuadMesh):
//  kind 3 smoke from a chimney: a soft puff turned to the camera that grows and fades over its life
//  kind 4 spark of the forge: a tiny hot dot
//  kind 5 a leaf falling: a small card that tumbles, its colour from the particle (COLOR)
//  kind 6 a butterfly: two wings that beat, its colour from the particle
//  kind 7 a firefly: a dot that glows and blinks
uniform int kind = 3;
uniform vec3 tint : source_color = vec3(0.6, 0.6, 0.62);
uniform float opacity = 0.5;
uniform float light = 1.0;   // daylight (smoke, leaves, butterflies are lit by it)

varying float age;
varying vec4 pcol;
varying float seed;

mat3 rot_x(float a) {
	return mat3(vec3(1, 0, 0), vec3(0, cos(a), sin(a)), vec3(0, -sin(a), cos(a)));
}

mat3 rot_z(float a) {
	return mat3(vec3(cos(a), sin(a), 0), vec3(-sin(a), cos(a), 0), vec3(0, 0, 1));
}

void vertex() {
	age = INSTANCE_CUSTOM.y;
	pcol = COLOR;
	seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float sc = length(MODEL_MATRIX[0].xyz);
	if (kind == 3 || kind == 4 || kind == 7) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, MODEL_MATRIX[3]);
	} else if (kind == 5) {
		VERTEX = rot_z(TIME * (2.0 + seed * 3.0) + seed * 6.0) * rot_x(TIME * (1.5 + seed * 2.0)) * VERTEX;
	} else if (kind == 6) {
		float flap = sin(TIME * 16.0 + seed * 40.0);
		VERTEX.y += abs(VERTEX.x) * flap * 1.2;
		VERTEX.x *= 0.6 + 0.4 * abs(cos(TIME * 16.0 + seed * 40.0));
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	vec3 col = tint;
	float a = opacity;
	if (kind == 3) {
		float n = sin(UV.x * 9.0 + seed * 20.0) * sin(UV.y * 7.0 + seed * 11.0) * 0.15;
		a *= (1.0 - smoothstep(0.35 + n, 1.0, r)) * smoothstep(0.0, 0.12, age) * (1.0 - age);
		col *= mix(0.3, 1.0, light);
	} else if (kind == 4) {
		a = (1.0 - smoothstep(0.2, 1.0, r)) * (1.0 - age);
		col = vec3(4.0, 1.6, 0.4);
	} else if (kind == 5) {
		// a leaf: an ellipse with a notch at the stem
		float e = length(c * vec2(2.4, 1.3));
		a = step(e, 0.5) * opacity;
		col = pcol.rgb * mix(0.35, 1.0, light) * (0.85 + 0.3 * UV.y);
		if (a < 0.5) { discard; }
	} else if (kind == 6) {
		float wing = length((abs(c) - vec2(0.24, 0.0)) * vec2(1.6, 1.2));
		a = step(wing, 0.36);
		col = pcol.rgb * mix(0.4, 1.0, light);
		if (a < 0.5) { discard; }
	} else if (kind == 7) {
		float blink = smoothstep(0.2, 0.9, sin(TIME * (1.3 + seed * 1.7) + seed * 30.0));
		a = (1.0 - smoothstep(0.0, 1.0, r)) * blink;
		col = vec3(2.6, 3.2, 0.9);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
