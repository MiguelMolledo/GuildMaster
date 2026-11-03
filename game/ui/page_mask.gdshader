shader_type canvas_item;
// Page kit (docs/ui/04_kit_de_pagina.md): fades an illustration or a portrait into the paper with a brush mask of the
// kit (assets/art/ui/page_kit/mask_*.png: white = visible, transparent = paper; a 1-bit dithered edge).

uniform sampler2D mask : filter_nearest;

void fragment() {
	COLOR.a *= texture(mask, UV).a;
}
