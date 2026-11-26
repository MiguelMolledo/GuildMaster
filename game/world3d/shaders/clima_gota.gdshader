shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Rain, splashes and snow of scripts/clima/fx.gd (GPUParticles3D draw pass, a QuadMesh).
//  kind 0: a rain streak, a billboard turned to the camera round the vertical (fixed Y)
//  kind 1: a splash, a ring lying on the ground that grows over the particle's life
//  kind 2: a snow flake, a soft round billboard
uniform int kind = 0;
uniform vec3 tint : source_color = vec3(0.78, 0.83, 0.92);
uniform float opacity = 0.5;
uniform float light = 1.0; // daylight: the drops are lit by the sky

varying float age;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	if (kind == 0) {
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
		vec3 fwd = normalize(cross(right, up));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	} else if (kind == 2) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float a;
	vec2 c = UV - 0.5;
	if (kind == 0) {
		a = (1.0 - smoothstep(0.0, 0.5, abs(c.x))) * smoothstep(0.0, 0.7, UV.y) * opacity;
	} else if (kind == 1) {
		float r = length(c) * 2.0;
		float rad = mix(0.15, 0.95, age);
		a = (1.0 - smoothstep(0.0, 0.14, abs(r - rad))) * (1.0 - age) * opacity;
	} else {
		a = (1.0 - smoothstep(0.15, 0.5, length(c))) * opacity;
	}
	ALBEDO = tint * mix(0.25, 1.0, light);
	ALPHA = a;
}
