extends RefCounted
## Light of the sim town by the hour, and what gives it depth (docs/clima.md, «Profundidad»).
## sim3d.gd builds one (Luz.new(town)) and calls light(t) every frame instead of its old _light. Every switch can be
## changed from the command line for the comparison sheets: `-- --luz=antes` gives the old light exactly, and
## `-- --luz=clave:valor,clave:valor` overrides single keys on top of the default (or of `antes,clave:valor`).
##   style      outline (toon + outline, the old one) | relieve (the kit's own shading and normal maps + outline) | pbr
##   outline    outline width in screen pixels at 1600x900 (0 = the old fixed 0.07 m, whatever the zoom)
##   amb_day / amb_night   ambient energy in full day / at night (old 0.75 / 0.55)
##   bounce     energy of the warm light from below (the ground bouncing the sun onto eaves and the shaded walls; 0 off)
##   back       energy of the cool light from behind the camera's side (rim on the edges; 0 off)
##   ssao       base | fuerte (bigger radius, more intensity: corners, under the eaves, the foot of the walls)
##   ssao_far   keep SSAO in the far view (zoom > 40): opt3d switches it off there (3.6 ms)
##   tonemap    filmic | agx | aces; exposure (multiplier)
##   fog        how much haze at the far edge of the view (depth fog, 0 off): separates the planes; fog_h: height fog
##   sun_max / sun_min  the sun's elevation at noon / at sunrise and sunset, degrees (old: 50 all day, 18 at night)
##   sun_e      sun energy at noon (old 1.45)
##   glare      bloom and a flare when the sun is low (the «sol cegador» hours; 0 off)
##   oro        warm golden hour: ambient and the bounce turn gold and stay up while the sun is low, the sun keeps its
##              energy (0 off). `--luz=dorado` = the new light with oro 1 and the sun at 22° at least at sunrise and sunset

const ANTES := {"style": "outline", "outline": 0.0, "amb_day": 0.75, "amb_night": 0.55, "bounce": 0.0, "back": 0.0,
	"ssao": "base", "ssao_far": false, "tonemap": "filmic", "exposure": 1.0, "fog": 0.0, "fog_h": 0.0, "sun_max": 50.0,
	"sun_min": 18.0, "sun_e": 1.45, "old_arc": true, "glare": 0.0, "sat": 1.04, "contrast": 1.05, "oro": 0.0}
## the default: what gave most depth per ms in the comparison (docs/clima.md, out/cl_profundidad.json)
const DEFAULT := {"style": "relieve", "outline": 1.6, "amb_day": 0.48, "amb_night": 0.42, "bounce": 0.35, "back": 0.0,
	"ssao": "fuerte", "ssao_far": false, "tonemap": "filmic", "exposure": 1.0, "fog": 0.0, "fog_h": 0.0, "sun_max": 50.0,
	"sun_min": 14.0, "sun_e": 1.75, "old_arc": false, "glare": 1.0, "sat": 1.06, "contrast": 1.08, "oro": 0.0}

## --luz=dorado: a warmer, brighter dusk than the default
const DORADO := {"oro": 1.0, "sun_min": 22.0}

var town: Node3D
var sun: DirectionalLight3D
var env: Environment
var cfg: Dictionary
var bounce: DirectionalLight3D
var back: DirectionalLight3D
var cloud_dim := 0.0      # 0..1: how much a cloud over the camera takes from the sun (scripts/clima/clima.gd)
var weather_dim := 0.0    # 0..1: overcast sky (nublado, lluvia, tormenta, niebla, nieve)
var flash := 0.0          # lightning: added to the light for a few frames
var _outline_px := -1.0
var _last_size := -1.0


static func parse(args: PackedStringArray) -> Dictionary:
	var c := DEFAULT.duplicate()
	for a in args:
		if not a.begins_with("--luz="):
			continue
		for part in a.trim_prefix("--luz=").split(",", false):
			if part == "antes":
				c = ANTES.duplicate()
			elif part == "nuevo":
				c = DEFAULT.duplicate()
			elif part == "dorado":
				c = DEFAULT.duplicate()
				c.merge(DORADO, true)
			elif part.contains(":"):
				var k := part.get_slice(":", 0)
				var v := part.get_slice(":", 1)
				var old = c.get(k, "")
				if old is bool:
					c[k] = v in ["1", "true", "si", "on"]
				elif old is float or old is int:
					c[k] = float(v)
				else:
					c[k] = v
	return c


func _init(t: Node3D, c: Dictionary) -> void:
	town = t
	cfg = c
	sun = t._sun
	env = t._env
	if env == null or sun == null:
		return
	bounce = DirectionalLight3D.new()
	bounce.name = "LuzRebote"
	bounce.shadow_enabled = false
	bounce.light_color = Color(1.0, 0.78, 0.55)
	bounce.light_specular = 0.0
	bounce.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	t.add_child(bounce)
	back = DirectionalLight3D.new()
	back.name = "LuzContra"
	back.shadow_enabled = false
	back.light_color = Color(0.7, 0.8, 1.0)
	back.light_specular = 0.3
	back.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	t.add_child(back)
	apply_static()


func apply_static() -> void:
	## what does not change with the hour: shading style, SSAO, tonemap, fog
	if env == null:
		return
	if String(cfg.style) != String(town.style):
		town.set_style(String(cfg.style))
	match String(cfg.ssao):
		"fuerte":
			env.ssao_radius = 1.6
			env.ssao_intensity = 3.2
			env.ssao_power = 1.6
			env.ssao_detail = 0.6
			env.ssao_horizon = 0.06
			env.ssao_light_affect = 0.15
			env.ssao_ao_channel_affect = 0.4
		_:
			env.ssao_radius = 1.0
			env.ssao_intensity = 2.0
			env.ssao_power = 1.5
			env.ssao_detail = 0.5
			env.ssao_horizon = 0.06
			env.ssao_light_affect = 0.0
			env.ssao_ao_channel_affect = 0.0
	match String(cfg.tonemap):
		"agx":
			env.tonemap_mode = Environment.TONE_MAPPER_AGX
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		_:
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(cfg.exposure)
	env.adjustment_saturation = float(cfg.sat)
	env.adjustment_contrast = float(cfg.contrast)
	env.fog_enabled = float(cfg.fog) > 0.0 or float(cfg.fog_h) > 0.0
	if env.fog_enabled:
		# depth fog: the camera is 80 m away (sim3d _update_camera); the haze grows from the near part of the view to
		# the far one, so the roofs (nearer the camera) stand out from the streets and the far edge of the view
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_density = float(cfg.fog)
		env.fog_depth_curve = 1.6
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0
		env.fog_light_color = Color(0.72, 0.78, 0.88)
		env.fog_height = float(cfg.fog_h)
		env.fog_height_density = 0.08 if float(cfg.fog_h) > 0.0 else 0.0
	bounce.visible = float(cfg.bounce) > 0.0
	back.visible = float(cfg.back) > 0.0
	var z := town.get_node_or_null("Opt3DZoom")
	if z != null and "far_ssao" in z:
		z.far_ssao = "keep" if bool(cfg.ssao_far) else "off"
	if OS.is_debug_build():
		print("[Luz] %s" % JSON.stringify(cfg))


## Elevation of the sun (degrees) at minute md of a day with these phase bounds: a real arc from sunrise (half way
## through dawn) to sunset (half way through dusk), sun_min at both ends, sun_max at noon; below the horizon the moon.
func _elevation(md: float, b: Dictionary, d: float) -> float:
	if bool(cfg.old_arc):
		return lerpf(float(cfg.sun_min), float(cfg.sun_max), d)
	var rise := (float(b.get("dawn", 300)) + float(b.get("day", 420))) / 2.0
	var set_ := (float(b.get("dusk", 1140)) + float(b.get("night", 1260))) / 2.0
	var k := (md - rise) / maxf(1.0, set_ - rise)
	if k <= 0.0 or k >= 1.0:
		return 32.0  # the moon: high enough that the night shadows stay short
	var s := sin(PI * k)
	return lerpf(float(cfg.sun_min), float(cfg.sun_max) * _season_k(), pow(s, 0.8))


func _season_k() -> float:
	return {"summer": 1.12, "spring": 1.0, "autumn": 0.86, "winter": 0.72}.get(String(town.season_id), 1.0)


## 0..1: how low and golden the sun is (1 at sunrise and sunset, 0 from mid-morning to mid-afternoon and at night)
func golden(t: float) -> float:
	var d: float = town.daylight(t)
	if d <= 0.0:
		return 0.0
	var b: Dictionary = town._day_info(t).bounds
	var md := fmod(t, 1440.0)
	var rise := (float(b.get("dawn", 300)) + float(b.get("day", 420))) / 2.0
	var set_ := (float(b.get("dusk", 1140)) + float(b.get("night", 1260))) / 2.0
	var near := minf(absf(md - rise), absf(md - set_))
	return clampf(1.0 - near / 100.0, 0.0, 1.0)


func light(t: float) -> void:
	if sun == null:
		return
	var d: float = town.daylight(t)
	var md := fmod(t, 1440.0)
	var b: Dictionary = town._day_info(t).bounds
	var warm := clampf((1.0 - d) * 2.2, 0.0, 1.0) if d > 0.0 else 0.0  # orange through dawn and dusk
	var g := golden(t) if not bool(cfg.old_arc) else 0.0
	warm = maxf(warm, g * 0.85)
	var dim := clampf(cloud_dim * 0.55 + weather_dim * 0.6, 0.0, 0.85)
	var se := float(cfg.sun_e)
	var day_e := lerpf(0.3, se, pow(d, 1.4))
	if not bool(cfg.old_arc):
		day_e = lerpf(0.32, se, pow(d, 1.4)) * lerpf(1.0, 0.82, g * (1.0 - float(cfg.oro)))
	sun.light_energy = day_e * (1.0 - dim) + flash * 6.0
	var col := Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.62, 0.35), warm).lerp(Color(0.55, 0.62, 0.95), 1.0 - minf(1.0, d * 3.0))
	if not bool(cfg.old_arc):
		col = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.6, 0.3), warm).lerp(Color(0.5, 0.6, 1.0), 1.0 - minf(1.0, d * 3.0) * (1.0 - float(cfg.oro) * g * 0.7))
		col = col.lerp(Color(0.86, 0.9, 1.0), weather_dim * 0.6)
	sun.light_color = col.lerp(Color(0.9, 0.93, 1.0), flash)
	sun.rotation_degrees = Vector3(-_elevation(md, b, d), -35.0 + (md / 60.0 - 13.0) * 9.0 + town.home_yaw - 45.0, 0)
	sun.shadow_opacity = lerpf(1.0, 0.35, weather_dim)
	if env == null:
		return
	var oro := float(cfg.oro) * g * (1.0 - weather_dim)
	var amb := lerpf(float(cfg.amb_night), float(cfg.amb_day), d) + weather_dim * 0.28 * d + oro * 0.22
	env.ambient_light_energy = amb + flash * 1.5
	var acol := Color(0.62, 0.7, 0.92).lerp(Color(0.36, 0.42, 0.78), 1.0 - d)
	if not bool(cfg.old_arc):
		# blue sky light in the shade; warmer as the sun goes down, the blue hour after it
		acol = Color(0.58, 0.68, 0.95).lerp(Color(0.62, 0.58, 0.8), g * 0.5).lerp(Color(0.32, 0.4, 0.8), 1.0 - d)
		acol = acol.lerp(Color(0.72, 0.76, 0.82), weather_dim * 0.7)
		acol = acol.lerp(Color(1.0, 0.74, 0.5), oro * 0.6)  # the gold of the low sun in the shade too
	env.ambient_light_color = acol
	if bounce:
		bounce.light_energy = float(cfg.bounce) * maxf(d, 0.15) * (1.0 - dim * 0.7) * (1.0 + oro * 0.8)
		bounce.light_color = Color(1.0, 0.78, 0.55).lerp(Color(0.5, 0.55, 0.8), 1.0 - d)
		# from below, opposite the sun: lights the undersides of the eaves and the walls in shade
		bounce.rotation_degrees = Vector3(35.0, sun.rotation_degrees.y + 180.0, 0)
	if back:
		back.light_energy = float(cfg.back) * maxf(d, 0.3)
		back.rotation_degrees = Vector3(-25.0, town.yaw + 180.0 + 35.0, 0)
	# glow: after dusk the windows and lanterns bloom; with glare also when the sun is low (blinding sun)
	var glare := float(cfg.glare) * g * (1.0 - weather_dim)
	var want_glow := d < 0.5 or glare > 0.05
	if env.glow_enabled != want_glow:
		env.glow_enabled = want_glow
		env.glow_bloom = 0.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if want_glow:
		env.glow_intensity = lerpf(0.8, 1.1, glare)
		env.glow_bloom = 0.06 * glare
		env.glow_hdr_threshold = lerpf(1.0, 0.85, glare)
	var bg := Color(0.55, 0.65, 0.8).lerp(Color(0.95, 0.6, 0.4), warm * 0.6).lerp(Color(0.06, 0.08, 0.16), 1.0 - d)
	env.background_color = bg.lerp(Color(0.5, 0.53, 0.58) * maxf(d, 0.2), weather_dim * 0.7)
	if env.fog_enabled:
		env.fog_light_color = bg.lerp(Color(0.7, 0.74, 0.8), 0.5)
		var cs: float = town.cam.size
		env.fog_depth_begin = 80.0 - cs * 0.35
		env.fog_depth_end = 80.0 + cs * 0.9
	_outline(t)


func _outline(_t: float) -> void:
	## outline width by zoom: about cfg.outline pixels at 1600x900 at any zoom (the old one was 0.07 m: 5 px at zoom 12)
	var px := float(cfg.outline)
	if px <= 0.0 or town._outline_mat == null:
		return
	var size: float = town.cam.size
	if absf(size - _last_size) < 0.05 and px == _outline_px:
		return
	_last_size = size
	_outline_px = px
	town._outline_mat.grow_amount = clampf(px * size / 900.0, 0.012, 0.12)
