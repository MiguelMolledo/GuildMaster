extends Node
## Pictures, measures and clips of the light and the weather (prefix cl_, docs/clima.md). Runs in sim3d_chars.tscn:
##   --cllab=profundidad        the depth sheet: the same views with one switch of scripts/clima/luz.gd at a time,
##                              ms per frame and draw calls of each -> out/cl_profundidad.json + cl_prof_<view>_<cfg>.png
##   --cllab=coste              cost of each weather effect (on / off) in a few views -> out/cl_coste.json
##   --cllab=atardecer          the plaza at 19:15 with --luz=antes, the default and --luz=dorado -> cl_atardecer_*.png
##   --clshots=<n>:<col>,<row>,<zoom>[,<yaw>[,<hour>[,<day>[,<tiempo>]]]];...   pictures (day 1 = the second day of
##                              the trace; tiempo forces the weather from that picture on, "auto" lets the data decide)
##                              -> cl_<n>.png; a name ending in "_rayo" strikes a lightning before the picture
##   --clclip=<col>,<row>,<zoom>,<yaw>,<hour>[,<speed>[,<pan_x>,<pan_z>[,<zoom_to>]]]   a camera for a clip: the clock
##                              runs at <speed> (x of sim3d SPEEDS), the camera pans <pan> m/s; record it with
##                              --write-movie and --quit-after (tools/cl_clip.sh)

const DIR := "/.grimoire/workspace/channels/ch_01m6abhw3phgxh2509d0/files/prueba3d/"
const Luz := preload("res://game/world3d/light/luz.gd")

var clima: Node
var town: Node3D


func _dir() -> String:
	return OS.get_environment("HOME") + DIR


func run(c: Node, arg: String) -> void:
	clima = c
	town = c.town
	get_window().always_on_top = true
	if not arg.begins_with("--clclip"):
		get_window().size = Vector2i(1600, 900)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _hold(1.5)
	if arg == "--cllab=profundidad":
		await _profundidad()
	elif arg == "--cllab=coste":
		await _coste()
	elif arg == "--cllab=atardecer":
		await _atardecer()
	elif arg.begins_with("--clshots="):
		await _shots(arg.trim_prefix("--clshots="))
	elif arg.begins_with("--clclip="):
		await _clip(arg.trim_prefix("--clclip="))
		return
	get_tree().quit()


func _hold(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		town._apply(town.t_min)


func _at(c: float, r: float, y := 1.0) -> Vector3:
	var p: Vector2 = town._tp(c, r)
	return HouseBuilder.plan_to_godot(Vector3(p.x, p.y, y))


func _go(hour: float, at: Vector3, size: float, yaw := -1.0, day := 1) -> void:
	town.paused = true
	town.t_min = town._day_start(town.t0) + 1440.0 * day + hour * 60.0
	town.target = at
	town.cam.size = size
	town.yaw = yaw if yaw >= 0.0 else town.home_yaw
	town._update_camera()
	town._apply(town.t_min)


func _snap(fname: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_dir())
	img.save_png(_dir() + fname)
	print("[ClLab] saved ", _dir() + fname)


func _measure(sec := 2.0) -> Dictionary:
	## ms per frame (vsync off) and the most draw calls in a frame over `sec` seconds
	await _hold(0.4)
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	var dc := 0
	var prims := 0
	while Time.get_ticks_usec() - t0 < int(sec * 1e6):
		await RenderingServer.frame_post_draw
		town._apply(town.t_min)
		dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var frames := maxi(1, Engine.get_frames_drawn() - f0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	return {"ms": snappedf(ms, 0.01), "fps": snappedf(1000.0 / ms, 0.1), "dc": dc, "tris_k": prims / 1000}


func _set_luz(over: Dictionary, base: Dictionary) -> void:
	var c := base.duplicate()
	c.merge(over, true)
	town.luz.cfg = c
	town.luz.apply_static()
	town._apply(town.t_min)


# ---------------------------------------------------------------- depth
const CFGS := [
	["antes", {}, "A"],
	["relieve", {"style": "relieve"}, "A"],
	["contorno_fino", {"outline": 1.6}, "A"],
	["ambiente_bajo", {"amb_day": 0.42, "amb_night": 0.42}, "A"],
	["rebote", {"amb_day": 0.42, "amb_night": 0.42, "bounce": 0.35}, "A"],
	["ssao_fuerte", {"ssao": "fuerte"}, "A"],
	["agx", {"tonemap": "agx", "exposure": 1.2}, "A"],
	["bruma_fondo", {"fog": 0.28}, "A"],
	["sol_arco", {"old_arc": false, "sun_min": 6.0, "sun_e": 1.75}, "A"],
	["contraluz", {"back": 0.45}, "A"],
	["nuevo", {}, "N"],
	["nuevo_toon", {"style": "outline"}, "N"],
	["nuevo_agx", {"tonemap": "agx", "exposure": 1.2}, "N"],
	["nuevo_bruma", {"fog": 0.28}, "N"],
	["nuevo_contraluz", {"back": 0.45}, "N"]]


func _profundidad() -> void:
	clima.forced = "despejado"  # the same sky in every picture (the data may have fog that day)
	clima._cache.clear()
	clima._last_t = -1.0e9
	var views := [["plaza26", _at(19.5, 19.0), 26.0], ["calle12", _at(17.0, 21.0), 12.0]]
	var hours := [["manana", 10.5], ["tarde", 19.25]]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var res := {}
	for v in views:
		for h in hours:
			var key := "%s_%s" % [v[0], h[0]]
			res[key] = {}
			for cf in CFGS:
				if only != "" and not String(cf[0]) in only.split(","):
					continue
				_go(float(h[1]), v[1], float(v[2]))
				_set_luz(cf[1], Luz.ANTES if cf[2] == "A" else Luz.DEFAULT)
				res[key][cf[0]] = await _measure(1.6)
				await _snap("cl_prof_%s_%s.png" % [key, cf[0]])
				print("[ClLab] %s %s: %s" % [key, cf[0], res[key][cf[0]]])
	# the far view: SSAO kept or not there
	for cf in [["antes", {}, Luz.ANTES], ["nuevo", {}, Luz.DEFAULT], ["nuevo_ssao_lejos", {"ssao_far": true}, Luz.DEFAULT]]:
		_go(10.5, Vector3(town.W, 2, town.H), 66.0)
		_set_luz(cf[1], cf[2])
		town.cam.size = 66.0
		await _hold(0.3)
		res["pueblo66_" + cf[0]] = await _measure(1.6)
		await _snap("cl_prof_pueblo66_%s.png" % cf[0])
	_set_luz({}, Luz.DEFAULT)
	var f := FileAccess.open("res://out/cl_profundidad.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()


# ---------------------------------------------------------------- dusk options
func _atardecer() -> void:
	## the plaza at 19:15 (the second day of the trace, autumn) with the old, the new and the golden light
	clima.forced = "despejado"
	clima._cache.clear()
	clima._last_t = -1.0e9
	var d := Luz.DEFAULT.duplicate()
	d.merge(Luz.DORADO, true)
	for cf in [["antes", Luz.ANTES], ["nuevo", Luz.DEFAULT], ["dorado", d]]:
		_go(19.25, _at(19.5, 19.0), 26.0)
		_set_luz({}, cf[1])
		await _hold(1.0)
		await _snap("cl_atardecer_%s.png" % cf[0])


# ---------------------------------------------------------------- pictures
func _shots(spec: String) -> void:
	for part in spec.split(";", false):
		var name := part.get_slice(":", 0)
		var v := part.get_slice(":", 1).split(",")
		if v.size() < 3:
			continue
		var yaw := float(v[3]) if v.size() > 3 else -1.0
		var hour := float(v[4]) if v.size() > 4 else 12.0
		var day := int(v[5]) if v.size() > 5 else 1
		if v.size() > 6:
			clima.forced = "" if v[6] == "auto" else v[6]
			clima._cache.clear()
			clima._last_t = -1.0e9
		_go(hour, _at(float(v[0]), float(v[1])), float(v[2]), yaw, day)
		town.paused = false
		var keep: int = town.speed_i
		town.speed_i = 0
		await _hold(1.6)
		town.paused = true
		town.speed_i = keep
		if name.ends_with("_rayo"):
			clima.strike()
			await _hold(0.08)
		await _snap("cl_%s.png" % name)


# ---------------------------------------------------------------- cost of the effects
func _coste() -> void:
	## ms per frame and draw calls: the old light with no weather and no life, the new light, each weather, rain
	## without each of its parts, and the life switched off (out/cl_coste.json)
	var res := {}
	var views := [["plaza26", _at(19.5, 19.0), 26.0, 10.5], ["calle12", _at(17.0, 21.0), 12.0, 10.5],
		["pueblo66", Vector3(town.W, 2, town.H), 66.0, 10.5], ["plaza26_noche", _at(19.5, 19.0), 26.0, 22.5]]
	var fx: RefCounted = clima.fx
	for v in views:
		var r := {}
		clima.forced = "despejado"
		clima._cache.clear()
		clima._last_t = -1.0e9
		_go(float(v[3]), v[1], float(v[2]))
		# the old: light as it was, no screen pass, no life
		_set_luz({}, Luz.ANTES)
		fx.toggle("post", false)
		clima.vida.suspend(true)
		r["antes"] = await _measure(2.0)
		_set_luz({}, Luz.DEFAULT)
		r["luz_nueva"] = await _measure(2.0)
		fx.toggle("post", true)
		r["luz_nueva_post"] = await _measure(2.0)
		clima.vida.suspend(false)
		r["todo_despejado"] = await _measure(2.0)
		for e in ["nublado", "lluvia", "tormenta", "niebla", "nieve"]:
			clima.forced = e
			clima._cache.clear()
			clima._last_t = -1.0e9
			_go(float(v[3]), v[1], float(v[2]))
			r[e] = await _measure(2.0)
		clima.forced = "lluvia"
		clima._cache.clear()
		clima._last_t = -1.0e9
		_go(float(v[3]), v[1], float(v[2]))
		for part in fx.parts():
			fx.toggle(part, false)
			r["lluvia_sin_" + part] = await _measure(2.0)
			fx.toggle(part, true)
		# the old again, last: the first measure of a view runs colder
		clima.forced = "despejado"
		clima._last_t = -1.0e9
		_go(float(v[3]), v[1], float(v[2]))
		_set_luz({}, Luz.ANTES)
		fx.toggle("post", false)
		clima.vida.suspend(true)
		r["antes_bis"] = await _measure(2.0)
		_set_luz({}, Luz.DEFAULT)
		fx.toggle("post", true)
		clima.vida.suspend(false)
		res[v[0]] = r
		print("[ClLab] coste %s: %s" % [v[0], r])
	var f := FileAccess.open("res://out/cl_coste.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()


# ---------------------------------------------------------------- clips
func _clip(spec: String) -> void:
	var v := spec.split(",")
	var hour := float(v[4])
	_go(hour, _at(float(v[0]), float(v[1])), float(v[2]), float(v[3]))
	var sp := float(v[5]) if v.size() > 5 else 1.0
	town.speed_i = maxi(0, town.SPEEDS.find(sp))
	town.paused = false
	var pan := Vector3(float(v[6]), 0, float(v[7])) if v.size() > 7 else Vector3.ZERO
	var z_to := float(v[8]) if v.size() > 8 else float(v[2])
	var z0 := float(v[2])
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while true:
		await get_tree().process_frame
		frames += 1
		var dt := 1.0 / float(Engine.get_frames_per_second() if Engine.get_frames_per_second() > 0 else 30)
		if Engine.get_write_movie_path() != "":
			dt = 1.0 / 30.0
		town.target += pan * dt
		town.cam.size = lerpf(z0, z_to, clampf(frames / 450.0, 0.0, 1.0))
		town._update_camera()
