shader_type canvas_item;
// The veil behind a menu panel (docs/ui/02_menu_inicial.md, "Común a todas"): the town below, darkened and
// desaturated. Pixel exact: the screen is read with nearest filtering.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float darken : hint_range(0.0, 1.0) = 0.45;
uniform float desaturate : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g), desaturate) * (1.0 - darken), 1.0);
}
