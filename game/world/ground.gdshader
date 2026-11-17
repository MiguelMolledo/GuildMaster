shader_type canvas_item;
// Ground of the town (GroundLayer, data/view.json "ground_shader"): one quad over the map whose pixels pick their
// material from the tile kinds around them. Soft materials (grass, dirt, street, plaza, yard, field) blend between
// the four tiles nearest the pixel (bilinear weights + per-material noise + priority), so borders meander and a
// diagonal street drawn as a stair of tiles reads as one ribbon; hard materials (water, bridge, dock...) keep their
// exact diamond. World materials are textures that repeat every `period` tiles, sampled with the world position (no
// tile grid); tile materials are the 64x32 diamond of assets/art/tiles/<kind>.png, sampled inside each tile; flat
// materials are the greybox colour. Paved materials get a curb: a darker 1 px rim where they meet a lower one, and a
// thin shadow on the lower side under it.

uniform sampler2D kind_map : filter_nearest;   // one texel per tile: r = material index / 255, g = border fade
uniform ivec2 map_origin;                       // tile of texel (0, 0)
uniform ivec2 map_size;                         // texels
uniform sampler2D atlas : filter_nearest;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec4 mat_rect[32];      // atlas rect (x, y, w, h) in pixels
uniform vec4 mat_color[32];     // flat colour (mode 2)
uniform vec4 mat_info[32];      // x = mode (0 world, 1 tile, 2 flat), y = priority, z = hard (1/0), w = curb
uniform vec4 mat_extra[32];     // x = drift (px per second, world materials), y = water (1/0: bank and foam)
uniform vec4 bank_colors[4] : source_color;  // the bank face under the far shore: top, middle, wet line; foam
uniform vec4 fade_to : source_color;
uniform float edge_noise = 0.16;
uniform float noise_tiles = 3.0;   // tiles per period of noise_tex

varying vec2 world;

void vertex() {
	world = VERTEX;
}

vec2 tile_of(vec2 p) {
	return vec2(p.x / 64.0 + p.y / 32.0, p.y / 32.0 - p.x / 64.0);
}

// material index of a tile (-1 = outside the drawn area)
int mat_at(ivec2 t) {
	ivec2 i = t - map_origin;
	if (i.x < 0 || i.y < 0 || i.x >= map_size.x || i.y >= map_size.y) {
		return -1;
	}
	int v = int(texelFetch(kind_map, i, 0).r * 255.0 + 0.5);
	return v >= 255 ? -1 : v;
}

float noise_of(int m, vec2 t) {
	vec4 n = texture(noise_tex, t / noise_tiles + vec2(float(m) * 0.137, float(m) * 0.291));
	int c = m - (m / 4) * 4;
	float v = c == 0 ? n.r : (c == 1 ? n.g : (c == 2 ? n.b : n.a));
	return v - 0.5;
}

// the material shown at world point p
int pick(vec2 p) {
	vec2 t = tile_of(p);
	ivec2 own_t = ivec2(floor(t + 0.5));
	int own = mat_at(own_t);
	if (own < 0) {
		return -1;
	}
	if (mat_info[own].z > 0.5) {
		return own;
	}
	vec2 b = floor(t);
	vec2 f = t - b;
	ivec2 bi = ivec2(b);
	int m[4];
	m[0] = mat_at(bi);
	m[1] = mat_at(bi + ivec2(1, 0));
	m[2] = mat_at(bi + ivec2(0, 1));
	m[3] = mat_at(bi + ivec2(1, 1));
	float w[4];
	w[0] = (1.0 - f.x) * (1.0 - f.y);
	w[1] = f.x * (1.0 - f.y);
	w[2] = (1.0 - f.x) * f.y;
	w[3] = f.x * f.y;
	int best = own;
	float best_s = -1e9;
	for (int i = 0; i < 4; i++) {
		int mi = m[i];
		if (mi < 0 || mat_info[mi].z > 0.5) {
			continue;
		}
		float s = 0.0;
		for (int j = 0; j < 4; j++) {
			if (m[j] == mi) {
				s += w[j];
			}
		}
		s += mat_info[mi].y * 0.01 + noise_of(mi, t) * edge_noise;
		if (s > best_s) {
			best_s = s;
			best = mi;
		}
	}
	return best;
}

vec4 sample_mat(int m, vec2 p) {
	vec4 info = mat_info[m];
	vec4 r = mat_rect[m];
	if (info.x < 0.5) {
		vec2 uv = mod(floor(p + vec2(TIME * mat_extra[m].x, TIME * mat_extra[m].x * 0.5)), r.zw);
		return texelFetch(atlas, ivec2(r.xy + uv), 0);
	}
	if (info.x < 1.5) {
		vec2 t = tile_of(p);
		ivec2 own_t = ivec2(floor(t + 0.5));
		vec2 centre = vec2(float(own_t.x - own_t.y) * 32.0, float(own_t.x + own_t.y) * 16.0);
		vec2 local = clamp(floor(p - centre + vec2(32.0, 16.0)), vec2(0.0), r.zw - 1.0);
		vec4 c = texelFetch(atlas, ivec2(r.xy + local), 0);
		if (c.a < 0.5) {  // the transparent corner of a diamond: its nearest opaque neighbour in the row
			c = texelFetch(atlas, ivec2(r.xy + vec2(clamp(local.x, 2.0, r.z - 3.0), local.y)), 0);
		}
		return c;
	}
	vec4 c = mat_color[m];
	vec2 t = tile_of(p);
	ivec2 own_t = ivec2(floor(t + 0.5));
	if (((own_t.x + own_t.y) & 1) == 1) {
		c.rgb *= 0.95;
	}
	return c;
}

void fragment() {
	vec2 p = floor(world) + 0.5;
	int m = pick(p);
	if (m < 0) {
		discard;
	}
	vec4 col = sample_mat(m, p);
	if (mat_extra[m].y > 0.5) {
		// water: the bank face of the far shore (land just above), foam along the near one (land just below)
		int u1 = pick(p + vec2(0.0, -1.0));
		int u2 = pick(p + vec2(0.0, -2.0));
		int u3 = pick(p + vec2(0.0, -3.0));
		int d1 = pick(p + vec2(0.0, 1.0));
		bool l1 = u1 >= 0 && mat_extra[u1].y < 0.5 && mat_info[u1].z < 0.5;
		bool l2 = u2 >= 0 && mat_extra[u2].y < 0.5 && mat_info[u2].z < 0.5;
		bool l3 = u3 >= 0 && mat_extra[u3].y < 0.5 && mat_info[u3].z < 0.5;
		bool ld = d1 >= 0 && mat_extra[d1].y < 0.5 && mat_info[d1].z < 0.5;
		if (l1) {
			col = bank_colors[0];
		} else if (l2) {
			col = bank_colors[1];
		} else if (l3) {
			col = bank_colors[2];
		} else if (ld) {
			col = bank_colors[3];
		}
	} else {
	// curb and shadow (paved materials over lower ones)
	float pr = mat_info[m].y;
	int up = pick(p + vec2(0.0, -1.0));
	int dn = pick(p + vec2(0.0, 1.0));
	int lf = pick(p + vec2(-1.0, 0.0));
	int rt = pick(p + vec2(1.0, 0.0));
	float curb = mat_info[m].w;
	if (curb > 0.0) {
		bool rim = false;
		if (dn >= 0 && dn != m && mat_info[dn].y < pr && mat_info[dn].z < 0.5) rim = true;
		if (up >= 0 && up != m && mat_info[up].y < pr && mat_info[up].z < 0.5) rim = true;
		if (lf >= 0 && lf != m && mat_info[lf].y < pr && mat_info[lf].z < 0.5) rim = true;
		if (rt >= 0 && rt != m && mat_info[rt].y < pr && mat_info[rt].z < 0.5) rim = true;
		if (rim) {
			col.rgb *= 1.0 - curb;
		}
	} else if (mat_info[m].z < 0.5) {
		// shadow on the lower material just under a curb (light from the top left)
		if (up >= 0 && up != m && mat_info[up].w > 0.0 && mat_info[up].y > pr) {
			col.rgb *= 0.82;
		} else if (lf >= 0 && lf != m && mat_info[lf].w > 0.0 && mat_info[lf].y > pr) {
			col.rgb *= 0.88;
		}
	}
	}
	vec2 t = tile_of(p);
	ivec2 own_t = ivec2(floor(t + 0.5));
	float fade = texelFetch(kind_map, own_t - map_origin, 0).g;
	col.rgb *= mix(vec3(1.0), fade_to.rgb, fade);
	col.a = 1.0;
	COLOR = col;
}
