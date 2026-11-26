shader_type spatial;
render_mode cull_disabled;

// Ducks on the river (scripts/clima/vida.gd): each instance paddles round its own spot in a slow loop, bobbing, the
// body turned the way it goes. INSTANCE_CUSTOM: x phase, y loop radius (m), z direction of the loop.
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float dir = c.z > 0.5 ? 1.0 : -1.0;
	float a = TIME * 0.12 * dir + c.x * 6.2832;
	vec3 off = vec3(cos(a), 0.0, sin(a)) * c.y;
	vec3 fwd = normalize(vec3(-sin(a), 0.0, cos(a)) * dir);
	vec3 right = cross(vec3(0.0, 1.0, 0.0), fwd);
	vec3 v = right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0) + fwd * VERTEX.z;
	v.y += sin(TIME * 2.1 + c.x * 20.0) * 0.015 - 0.04;
	VERTEX = v + off;
	NORMAL = right * NORMAL.x + vec3(0.0, NORMAL.y, 0.0) + fwd * NORMAL.z;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.7;
}
