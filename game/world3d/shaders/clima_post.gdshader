shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

// The weather over the whole view in one screen pass (scripts/clima/fx.gd): from the depth and the normals of what
// is drawn it knows where each pixel is in the world and which way it faces, and
//  - darkens it under the shadow of the clouds that drift with the wind (only the sunlit part: faces towards the sun),
//  - wets the roofs and the ground (darker, a sheen of the sky) and fills puddles on the dirt streets, rippled by rain,
//  - lays snow on what faces up,
//  - lays the morning mist over the river and the fields and the fog of a foggy day,
//  - draws rain and snow in screen space for the far view (the particles stop there).
// A quad of 2x2 that covers the screen; drawn first of the transparent pass (render_priority -127): what it reads is
// the opaque scene.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// @LEJOS@  (scripts/clima/fx.gd turns this line into #define LEJOS for the far view: no normal buffer, which there,
// with SSAO off, would cost a whole extra pass of the town; what faces up is taken from the height instead)
#ifndef LEJOS
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest;
#endif
uniform sampler2D mapa : filter_linear; // the tile map: r water, g fields, b dirt street, a open ground
uniform vec4 mapa_rect = vec4(0.0, 0.0, 80.0, 80.0); // world x0, z0, width, depth of the map texture

uniform float day = 1.0;          // daylight 0..1
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2); // towards the sun, world
uniform float nubes = 0.2;        // share of the sky covered
uniform float nube_fuerza = 0.5;  // how dark a cloud shadow is
uniform float nube_escala = 0.018;
uniform vec2 nube_off = vec2(0.0);
uniform float mojado = 0.0;
uniform float lluvia = 0.0;
uniform float nieve = 0.0;        // snow settled
uniform float bruma = 0.0;        // morning mist over water and fields
uniform float niebla = 0.0;       // fog over everything
uniform vec3 niebla_col = vec3(0.7, 0.74, 0.8);
uniform vec3 cielo = vec3(0.55, 0.62, 0.75); // the sky colour the wet surfaces mirror
uniform float lluvia_pantalla = 0.0; // far view: rain streaks drawn here
uniform float nieve_pantalla = 0.0;  // far view: snow flakes drawn here
uniform float viento = 0.2;
uniform float tiempo = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 11.0) * 0.28 + vnoise(p * 4.1 + 23.0) * 0.17;
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float ripples(vec2 p, float t) {
	// rain drops on a puddle: an expanding ring in each cell of 0.6 m, each at its own time
	vec2 cell = floor(p / 0.6);
	float r = 0.0;
	for (int k = 0; k < 2; k++) {
		vec2 c = cell + vec2(float(k), 0.0);
		float h = hash(c);
		vec2 centre = (c + vec2(hash(c + 3.1), hash(c + 7.7))) * 0.6;
		float ph = fract(t * 1.3 + h);
		float d = length(p - centre);
		float ring = 1.0 - smoothstep(0.0, 0.03, abs(d - ph * 0.35));
		r += ring * (1.0 - ph);
	}
	return r;
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float depth = texture(depth_tex, SCREEN_UV).r;
	ALPHA = 1.0;
	if (depth <= 0.00001) {
		ALBEDO = col;
	} else {
		vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec4 vp = INV_PROJECTION_MATRIX * ndc;
		vp.xyz /= vp.w;
		vec3 w = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).xyz;
#ifdef LEJOS
		float dyn = 0.0;
		vec3 n = normalize(cross(dFdy(w), dFdx(w)));  // the face's normal from the depth
		if (n.y < 0.0) { n = -n; }
#else
		vec4 nr = texture(nr_tex, SCREEN_UV);
		float dyn = nr.w > 0.5 ? 1.0 : 0.0; // skinned / moving objects (the townsfolk): no snow, no puddles on them
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(normalize(nr.xyz * 2.0 - 1.0), 0.0)).xyz);
#endif
		vec2 muv = (w.xz - mapa_rect.xy) / mapa_rect.zw;
		vec4 m = texture(mapa, muv);
		if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0) {
			m = vec4(0.0, 0.0, 0.0, 1.0);
		}
		float up = smoothstep(0.35, 0.85, n.y);
		float lit = clamp(dot(n, sun_dir) * 1.6, 0.0, 1.0);

		// cloud shadows: where the sun reaches, a drifting cloud takes most of it
		if (nubes > 0.01 && day > 0.01) {
			float c = fbm(w.xz * nube_escala + nube_off);
			float sh = smoothstep(1.0 - nubes - 0.08, 1.0 - nubes + 0.18, c);
			col *= 1.0 - sh * nube_fuerza * day * (0.3 + 0.7 * lit);
		}

		// wet: darker, a sheen of the sky on what faces up; puddles in the dirt streets and the open ground
		if (mojado > 0.01) {
			float wet = mojado * mix(0.55, 1.0, up);
			col *= 1.0 - 0.32 * wet;
			float sheen = up * mojado * (0.5 + 0.5 * vnoise(w.xz * 0.7));
			col += cielo * 0.07 * sheen * day;
			float flat_ = smoothstep(0.9, 0.98, n.y) * (1.0 - smoothstep(0.25, 0.6, w.y)) * (1.0 - dyn);
			float where = max(m.b, m.a * 0.15) * flat_;
			float pn = fbm(w.xz * 0.45 + 31.0);
			float pud = smoothstep(0.68 - mojado * 0.05, 0.71 - mojado * 0.05, pn) * where * mojado;
			if (pud > 0.0) {
				vec3 refl = mix(cielo * (0.18 + 0.32 * day), col * 0.35, 0.4);
				float rip = lluvia > 0.05 ? ripples(w.xz, tiempo) * lluvia : 0.0;
				col = mix(col, refl + vec3(rip * 0.12 * (0.3 + day)), pud * 0.85);
			}
		}

		// snow on what faces up, broken at its edges
		if (nieve > 0.01) {
			float br = vnoise(w.xz * 1.7) * 0.6 + vnoise(w.xz * 6.0) * 0.4;
			float s = smoothstep(0.0, 0.25, nieve * 1.25 * up - br * 0.45 * (1.0 - nieve)) * (1.0 - m.r) * (1.0 - dyn);
			float shade = clamp(lum(col) * 1.7, 0.22, 0.82);
			vec3 snow = vec3(0.86, 0.9, 0.98) * shade;
			col = mix(col, snow, s);
		}

		// mist over the river and the fields (low, drifting) and the fog of a foggy day
		float depth_v = -vp.z;
		if (bruma > 0.01) {
			float low = 1.0 - smoothstep(0.2, 3.2, w.y);
			float place = clamp(m.r * 1.2 + m.g * 0.75 + m.a * 0.12, 0.0, 1.0);
			float drift = smoothstep(0.25, 0.8, fbm(w.xz * 0.07 + vec2(tiempo * 0.012, tiempo * 0.006)));
			float a = bruma * low * place * (0.25 + 0.75 * drift) * 0.72;
			col = mix(col, niebla_col * (0.4 + 0.45 * day), clamp(a, 0.0, 0.8));
		}
		if (niebla > 0.01) {
			float low = 1.0 - smoothstep(0.0, 9.0, w.y);
			float drift = fbm(w.xz * 0.04 + vec2(tiempo * 0.01, 0.0)) * 0.5 + 0.5;
			float a = niebla * (0.16 + 0.42 * low * drift);
			col = mix(col, niebla_col * (0.35 + 0.45 * day), clamp(a, 0.0, 0.7));
		}
	}
	// far view: rain and snow in screen space
	if (lluvia_pantalla > 0.01) {
		vec2 uv = SCREEN_UV * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
		uv.x += uv.y * (0.12 + viento * 0.2);
		vec2 g = vec2(uv.x * 160.0, uv.y * 7.0 - tiempo * 9.0);
		vec2 id = floor(g);
		float h = hash(id);
		float streak = step(0.86, h) * (1.0 - smoothstep(0.0, 0.18, abs(fract(g.x) - 0.5))) * smoothstep(0.0, 0.5, fract(g.y + h)) ;
		col = mix(col, vec3(0.75, 0.8, 0.88) * (0.4 + 0.6 * day), streak * 0.35 * lluvia_pantalla);
	}
	if (nieve_pantalla > 0.01) {
		vec2 uv = SCREEN_UV * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0) * 60.0;
		uv += vec2(sin(tiempo * 0.7 + uv.y * 0.2) * 0.6, -tiempo * 2.2);
		vec2 id = floor(uv);
		vec2 f = fract(uv) - vec2(hash(id), hash(id + 5.0));
		float flake = step(0.8, hash(id + 9.0)) * (1.0 - smoothstep(0.03, 0.09, length(f)));
		col = mix(col, vec3(0.95, 0.97, 1.0), flake * 0.8 * nieve_pantalla);
	}
	ALBEDO = col;
}
