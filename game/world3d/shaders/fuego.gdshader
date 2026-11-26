// Flames of the festival pieces (kit/fiestas: bonfire, torches, braziers): the surfaces of the material MI_Fuego get this
// shader from scripts/fiestas.gd. Each tongue is a card with u round the fire and v from the root (0) to the tip (1),
// coloured yellow at the root and red at the tip by vertex colour. Additive and unshaded: the tips fade to black, so
// they vanish without sorting; the vertices sway with time, more towards the tip. No outline pass (it is not a
// StandardMaterial3D) and no shadow (fiestas.gd turns it off on the flame mesh).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform float strength : hint_range(0.0, 3.0) = 1.4;
uniform float sway : hint_range(0.0, 0.5) = 0.08;
uniform float speed : hint_range(0.0, 20.0) = 5.0;

void vertex() {
	float k = UV.y * UV.y;
	float ph = UV.x * 12.566;
	float t = TIME * speed;
	VERTEX.x += sin(t + ph) * sway * k;
	VERTEX.z += cos(t * 1.3 + ph * 1.7) * sway * k;
	VERTEX.y += (sin(t * 2.1 + ph * 0.7) * 0.5 + 0.5) * sway * 1.5 * k;
}

void fragment() {
	float k = UV.y;
	float flick = 0.8 + 0.2 * sin(TIME * 9.0 + UV.x * 20.0) * sin(TIME * 5.3 + UV.x * 7.0);
	ALBEDO = COLOR.rgb * strength * flick * (1.0 - 0.75 * k * k);
	ALPHA = 1.0;
}
