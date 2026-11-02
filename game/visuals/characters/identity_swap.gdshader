shader_type canvas_item;
// H8 identity on the Guild Renew character sprites (tools/art/personajes_guild.py): a keyed pixel (alpha 254) has its
// region in blue (50 hair, 100 skin, 150 primary clothes, 200 secondary clothes) and its shade in red (x/127.5 of the
// colour). The person's colours come from CharacterView (Identity + the family's colours). Other pixels are untouched.

uniform vec4 hair : source_color = vec4(0.35, 0.23, 0.13, 1.0);
uniform vec4 skin : source_color = vec4(0.88, 0.71, 0.55, 1.0);
uniform vec4 primary : source_color = vec4(0.55, 0.18, 0.18, 1.0);
uniform vec4 secondary : source_color = vec4(0.78, 0.66, 0.31, 1.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = c.a * 255.0;
	if (a > 253.5 && a < 254.5) {
		float region = floor(c.b * 255.0 / 50.0 + 0.5);
		vec3 base = region < 1.5 ? hair.rgb : (region < 2.5 ? skin.rgb : (region < 3.5 ? primary.rgb : secondary.rgb));
		COLOR = vec4(clamp(base * c.r * 255.0 / 127.5, 0.0, 1.0), 1.0) * tint;
	} else {
		COLOR = c * tint;
	}
}
