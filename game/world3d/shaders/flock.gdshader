shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// A flock of birds circling, all of it in the vertex shader: one MultiMesh, one draw call, nothing to update from
// script. Every instance carries in INSTANCE_CUSTOM where it is in the flock (x: place along the circle 0..1,
// y: radius factor, z: height offset in metres, w: a random number for its wing beat and its tint).
// The bird's mesh looks to +z with its wings along x; COLOR.r is 1 on the wings (they beat), COLOR.g shades the faces.
uniform float radius = 16.0;       // metres
uniform float height = 11.0;       // metres above the node
uniform float speed = 6.5;         // metres a second along the circle
uniform float beat = 11.0;         // wing beats: radians a second
uniform float bank = 0.35;         // radians they lean into the turn
uniform vec3 color_a : source_color = vec3(0.34, 0.36, 0.42);
uniform vec3 color_b : source_color = vec3(0.82, 0.82, 0.86);
varying float tint;
varying float shade;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float r = radius * c.y;
	float ang = c.x * TAU + TIME * speed / r;
	vec3 centre = vec3(cos(ang) * r, height + c.z + 0.5 * sin(TIME * 0.6 + c.w * 37.0), sin(ang) * r);
	vec3 fwd = vec3(-sin(ang), 0.0, cos(ang));
	vec3 outw = vec3(cos(ang), 0.0, sin(ang));
	vec3 right = normalize(outw * cos(bank) + vec3(0.0, 1.0, 0.0) * sin(bank));
	vec3 up = cross(fwd, right);
	// a few beats and a glide, each bird in its own time
	float flapping = smoothstep(-0.3, 0.2, sin(TIME * 0.9 + c.w * 61.0));
	float a = sin(TIME * beat + c.w * 113.0) * 0.75 * flapping + 0.12;
	vec3 v = VERTEX;
	float w = COLOR.r;
	float x = v.x;
	v.x = mix(x, x * cos(a), w);
	v.y += w * abs(x) * sin(a);
	VERTEX = centre + right * v.x + up * v.y + fwd * v.z;
	NORMAL = up;
	tint = step(0.72, fract(c.w * 7.3));
	shade = COLOR.g;
}

void fragment() {
	ALBEDO = mix(color_a, color_b, tint) * shade;
}
