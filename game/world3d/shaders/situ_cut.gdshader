shader_type spatial;
// A house of the town cut open in place (scripts/situ_cut.gd): the kit's albedo/normal with the town's toon shading and
// two per-instance controls, as shaders/interior_wall.gdshader. cut_y: world height above which nothing is drawn (a
// lowered wall reads as a stub, the inside of the wall box is drawn as a flat cap). fade: ordered-dither see-through
// (0 = solid, 1 = gone): roofs and upper floors melt away without leaving the opaque pipeline. base_fade: the same
// dither fixed per material (window glass).
render_mode cull_disabled, diffuse_toon, specular_toon;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float rough = 1.0;
uniform float base_fade = 0.0;
uniform vec4 cap_color : source_color = vec4(0.2, 0.15, 0.12, 1.0);

instance uniform float cut_y = 1000.0;
instance uniform float fade = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	UV = UV * uv_scale.xy + uv_offset.xy;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	if (wpos.y > cut_y) {
		discard;
	}
	float f = max(fade, base_fade);
	if (f > 0.0 && bayer4(FRAGCOORD.xy) < f) {
		discard;
	}
	if (!FRONT_FACING) {
		ALBEDO = cap_color.rgb;
		ROUGHNESS = 1.0;
		NORMAL = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	} else {
		ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb;
		ROUGHNESS = rough;
		if (use_normal) {
			NORMAL_MAP = texture(normal_tex, UV).rgb;
		}
	}
}
