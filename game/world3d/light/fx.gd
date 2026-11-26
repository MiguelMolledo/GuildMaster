extends RefCounted
## What the weather looks like (scripts/clima/clima.gd decides it; docs/clima.md):
##   post     one screen pass (shaders/clima_post.gdshader): cloud shadows, wet roofs and ground, puddles with rain
##            rings, snow laid on what faces up, morning mist over river and fields, fog; rain and snow in screen
##            space in the far view
##   rain     drops round the camera (GPUParticles3D, one draw call) and their splashes on the ground (another)
##   snow     flakes round the camera (one draw call)
##   water    the river: sun glints when the sun is low, rain rings (shaders/water.gdshader)
## Each part can be switched off for measuring (toggle; cl_lab --cllab=coste). Past lejos_zoom (the whole-town view)
## the particles stop and the screen pass draws the rain and the snow.

const PARTS := ["post", "rain", "splash", "snow"]

var clima: Node
var town: Node3D
var post: MeshInstance3D
var post_mat: ShaderMaterial
var post_near: ShaderMaterial
var post_far: ShaderMaterial
var rain: GPUParticles3D
var splash: GPUParticles3D
var snow: GPUParticles3D
var enabled := {"post": true, "rain": true, "splash": true, "snow": true}
var _off := Vector2.ZERO
var _time := 0.0
var _bucket := -1
var fx_cfg: Dictionary
var stats := {}


func _init(c: Node) -> void:
	clima = c
	town = c.town
	fx_cfg = c.cfg.efectos
	if DisplayServer.get_name() == "headless":
		return
	_make_post()
	rain = _particles("Lluvia", 0)
	splash = _particles("Salpicaduras", 1)
	snow = _particles("Nieve", 2)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clima_sin="):
			for p in a.trim_prefix("--clima_sin=").split(","):
				toggle(p, false)
	if OS.is_debug_build():
		print("[ClimaFX] post pass, rain, splashes and snow ready (map mask %dx%d)" % [town.W, town.H])


func parts() -> Array:
	return PARTS


func toggle(part: String, on: bool) -> void:
	enabled[part] = on
	if part == "post" and post:
		post.visible = on


# ---------------------------------------------------------------- the screen pass
func _make_post() -> void:
	post = MeshInstance3D.new()
	post.name = "ClimaPost"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	post.mesh = q
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.ignore_occlusion_culling = true
	var near_sh: Shader = load("res://game/world3d/shaders/clima_post.gdshader")
	var far_sh := Shader.new()
	far_sh.code = near_sh.code.replace("// @LEJOS@", "#define LEJOS")
	var mask := _map_mask()
	for sh in [near_sh, far_sh]:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = -127
		m.set_shader_parameter("mapa", mask)
		m.set_shader_parameter("mapa_rect", Vector4(0, 0, town.W * 2.0, town.H * 2.0))
		m.set_shader_parameter("nube_escala", float(fx_cfg.nube_escala))
		if sh == near_sh:
			post_near = m
		else:
			post_far = m
	post_mat = post_near
	post.material_override = post_mat
	post.add_to_group("tree")  # no outline pass (sim3d set_style skips the "tree" group)
	town.cam.add_child(post)


func _map_mask() -> ImageTexture:
	## one pixel per tile: r water, g fields, b dirt street (paths and roads), a open ground (grass, trees)
	var img := Image.create(town.W, town.H, false, Image.FORMAT_RGBA8)
	for r in town.H:
		for c in town.W:
			var t: String = town._t(c, r)
			var px := Color(0, 0, 0, 0)
			match t:
				"w":
					px = Color(1, 0, 0, 0)
				"f":
					px = Color(0, 1, 0, 1)
				",", "=":
					px = Color(0, 0, 1, 0.3)
				"P", "S", "N":
					px = Color(0, 0, 0.35, 0)
				".", "T":
					px = Color(0, 0.25, 0, 1)
			img.set_pixel(c, r, px)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- particles
func _particles(name: String, kind: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.local_coords = false
	p.emitting = false
	p.visible = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-80, -40, -80), Vector3(160, 80, 160))
	p.fixed_fps = 0
	p.interpolate = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var q := QuadMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/world3d/shaders/clima_gota.gdshader")
	sm.set_shader_parameter("kind", kind)
	match kind:
		0:
			pm.direction = Vector3(0, -1, 0)
			pm.spread = 3.0
			pm.initial_velocity_min = 19.0
			pm.initial_velocity_max = 23.0
			pm.gravity = Vector3(0, -6, 0)
			p.lifetime = 0.75
			q.size = Vector2(0.035, 0.75)
			sm.set_shader_parameter("opacity", 0.42)
		1:
			pm.direction = Vector3(0, 1, 0)
			pm.initial_velocity_min = 0.0
			pm.initial_velocity_max = 0.0
			pm.gravity = Vector3.ZERO
			p.lifetime = 0.32
			q.size = Vector2(0.32, 0.32)
			q.orientation = PlaneMesh.FACE_Y
			sm.set_shader_parameter("opacity", 0.55)
			sm.set_shader_parameter("tint", Color(0.85, 0.9, 0.97))
		2:
			pm.direction = Vector3(0, -1, 0)
			pm.spread = 12.0
			pm.initial_velocity_min = 0.9
			pm.initial_velocity_max = 1.5
			pm.gravity = Vector3(0, -0.25, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.2
			pm.turbulence_noise_scale = 3.0
			pm.turbulence_influence_min = 0.05
			pm.turbulence_influence_max = 0.12
			p.lifetime = 9.0
			q.size = Vector2(0.09, 0.09)
			sm.set_shader_parameter("opacity", 0.9)
			sm.set_shader_parameter("tint", Color(0.96, 0.97, 1.0))
	p.process_material = pm
	q.material = sm
	p.draw_pass_1 = q
	p.add_to_group("tree")
	town.add_child(p)
	return p


func _count(base: float, size: float) -> int:
	## drops for the area in view: base at zoom 26, scaled with the area, capped
	return int(clampf(base * pow(size / 26.0, 2.0), base * 0.3, float(fx_cfg.gotas_max)))


func _place(p: GPUParticles3D, amount: int, height: float, half: float, show: bool, kind: int) -> void:
	if not show or not enabled.get(p.name.to_lower().replace("lluvia", "rain").replace("salpicaduras", "splash").replace("nieve", "snow"), true):
		if p.visible:
			p.emitting = false
			p.visible = false
		return
	var pm: ParticleProcessMaterial = p.process_material
	if p.amount != amount:
		p.amount = amount
	pm.emission_box_extents = Vector3(half, 0.2 if kind != 2 else height * 0.5, half)
	# the emitter follows the camera target; a step back towards the camera so the drops cover the top of the view
	var t: Vector3 = town.target
	var back: Vector3 = town.cam.basis.z * Vector3(1, 0, 1) * (height * 0.4)
	p.global_position = Vector3(t.x, (0.03 if kind == 1 else height), t.z) + back
	if not p.visible:
		p.visible = true
		p.emitting = true
		p.restart()


# ---------------------------------------------------------------- per frame
func cloud_at(p: Vector3) -> float:
	## the cloud shadow over a world point (as the screen pass draws it): 0 clear .. 1 under a cloud
	var n: float = clima.now.nubes
	if n < 0.01:
		return 0.0
	var q := Vector2(p.x, p.z) * float(fx_cfg.nube_escala) + _off
	var c := _vnoise(q) * 0.55 + _vnoise(q * 2.03 + Vector2(11, 11)) * 0.28 + _vnoise(q * 4.1 + Vector2(23, 23)) * 0.17
	return smoothstep(1.0 - n - 0.08, 1.0 - n + 0.18, c)


static func _hash(p: Vector2) -> float:
	var v := sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453
	return v - floorf(v)


static func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash(i), _hash(i + Vector2(1, 0)), f.x), lerpf(_hash(i + Vector2(0, 1)), _hash(i + Vector2(1, 1)), f.x), f.y)


func update(t: float) -> void:
	if post == null:
		return
	var dt := town.get_process_delta_time()
	if Engine.get_write_movie_path() != "":
		dt = 1.0 / 30.0
	_time += dt
	var w: Dictionary = clima.now
	var day: float = town.daylight(t)
	var wind_dir := Vector2(0.8, 0.6)
	_off += wind_dir * float(fx_cfg.nube_vel) * (0.3 + clima.viento) * dt * float(fx_cfg.nube_escala)
	var size: float = town.cam.size
	var far := size > float(fx_cfg.lejos_zoom)
	var sun: DirectionalLight3D = town._sun
	var sd := sun.global_transform.basis.z.normalized() if sun else Vector3(0, 1, 0)
	var want: ShaderMaterial = post_far if far else post_near
	if want != post_mat:
		post_mat = want
		post.material_override = want
	var pm := post_mat
	pm.set_shader_parameter("tiempo", _time)
	pm.set_shader_parameter("day", day)
	pm.set_shader_parameter("sun_dir", sd)
	pm.set_shader_parameter("nubes", float(w.nubes))
	pm.set_shader_parameter("nube_fuerza", lerpf(0.5, 0.25, float(w.velo)))
	pm.set_shader_parameter("nube_off", _off)
	pm.set_shader_parameter("mojado", clima.mojado)
	pm.set_shader_parameter("lluvia", float(w.lluvia))
	pm.set_shader_parameter("nieve", clima.nieve_suelo)
	pm.set_shader_parameter("bruma", clima.bruma)
	pm.set_shader_parameter("niebla", float(w.niebla) * 0.85)
	pm.set_shader_parameter("viento", clima.viento)
	var env: Environment = town._env
	var bg: Color = env.background_color if env else Color(0.55, 0.62, 0.75)
	pm.set_shader_parameter("cielo", Vector3(bg.r, bg.g, bg.b).lerp(Vector3(0.6, 0.66, 0.75), 0.4))
	var fc := Color(0.72, 0.75, 0.8).lerp(Color(0.95, 0.78, 0.6), town.luz.golden(t) * 0.5 if town.luz else 0.0)
	pm.set_shader_parameter("niebla_col", Vector3(fc.r, fc.g, fc.b))
	pm.set_shader_parameter("lluvia_pantalla", float(w.lluvia) if far else 0.0)
	pm.set_shader_parameter("nieve_pantalla", float(w.nieve) if far else 0.0)
	# the season's snow on the ground and the streets follows the snow laid by the weather (set_season gives 1 in winter)
	if town.gm:
		town.gm.set_shader_parameter("snow", clima.nieve_suelo * 0.9)
	for rm in town._road_mats:
		rm.set_shader_parameter("snow", clima.nieve_suelo * 0.8)
	for wm in town._water:
		wm.set_shader_parameter("lluvia", float(w.lluvia))
		wm.set_shader_parameter("glint", (town.luz.golden(t) if town.luz else 0.0) * (1.0 - float(w.velo)) + day * 0.25 * (1.0 - float(w.velo)))
		wm.set_shader_parameter("glint_col", sun.light_color if sun else Color(1, 0.8, 0.5))
	# particles round the camera (not in the far view)
	var lr := float(w.lluvia)
	var ln := float(w.nieve)
	var half := size * 0.95
	_place(rain, _count(float(fx_cfg.gotas) * clampf(lr, 0.25, 1.0), size), 15.0, half, lr > 0.03 and not far, 0)
	_place(splash, _count(float(fx_cfg.salpicaduras) * clampf(lr, 0.25, 1.0), size), 0.0, half, lr > 0.03 and not far, 1)
	_place(snow, _count(float(fx_cfg.copos) * clampf(ln, 0.3, 1.0), size), 14.0, half, ln > 0.03 and not far, 2)
	for p in [rain, splash, snow]:
		if p.visible:
			((p.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("light", maxf(day, 0.15) + clima.flash)
			if p == rain:
				var pmat: ParticleProcessMaterial = p.process_material
				pmat.direction = Vector3(0.18 * clima.viento, -1, 0.12 * clima.viento).normalized()


func bolt(_p: Vector3) -> void:
	pass  # the flash is the light (luz.flash); the sound listens to clima.relampago
