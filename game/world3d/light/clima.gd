extends Node
## The weather of the sim town (data/clima.json, docs/clima.md). sim3d.gd adds one node "Clima" and calls update(t)
## every frame from _light. Contract with the sound (scripts/audio/*): this node is in group "clima" with
##   estado      "despejado" | "nublado" | "lluvia" | "tormenta" | "niebla" | "nieve"
##   intensidad  0..1
##   viento      0..1
##   signal relampago(pos: Vector3)  (the flash; the thunder is up to the listener)
## Each day is cut in tramos (tramo_h hours); a tramo draws its weather with the seed from the season's probabilities
## (or keeps the one before), the same in every run; the change blends over transicion_min game minutes.
##   -- --tiempo=lluvia|tormenta|niebla|nieve|nublado|despejado[:intensidad]   forces it
##   -- --clima=no   no weather effects (light only), for measuring
## What the weather looks like (cloud shadows, rain, snow, mist, wet ground) is scripts/clima/fx.gd; the life of the
## season (tree colours, leaves, birds, insects, smoke) is scripts/clima/vida.gd.

signal relampago(pos: Vector3)

const ESTADOS := ["despejado", "nublado", "lluvia", "tormenta", "niebla", "nieve"]
const KEYS := ["nubes", "velo", "lluvia", "nieve", "niebla"]

var estado := "despejado"
var intensidad := 0.6
var viento := 0.2
## the weather as it looks now (blended over the change): nubes, velo, lluvia, nieve, niebla 0..1, tormenta 0..1
var now := {"nubes": 0.18, "velo": 0.0, "lluvia": 0.0, "nieve": 0.0, "niebla": 0.0, "tormenta": 0.0}
var mojado := 0.0        # 0..1 the ground and the roofs wet
var nieve_suelo := 0.0   # 0..1 snow settled on the ground and the roofs
var bruma := 0.0         # 0..1 morning mist over the river and the fields
var flash := 0.0         # 0..1 lightning
var t_game := 0.0

var town: Node3D
var cfg: Dictionary
var forced := ""
var forced_i := -1.0
var fx: RefCounted
var vida: RefCounted
var on := true
var _cache := {}
var _last_t := -1.0e9
var _rng := RandomNumberGenerator.new()
var _flash_t := 0.0
var _flash_dur := 0.45
var _rayos_k := 1.0  # -- --rayos=<x>: more (or fewer) lightning strikes than the data says (clips)


func setup(t: Node3D) -> void:
	add_to_group("clima")
	town = t
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/clima.json"))
	_rng.seed = 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tiempo="):
			var v := a.trim_prefix("--tiempo=")
			forced = v.get_slice(":", 0)
			if v.contains(":"):
				forced_i = float(v.get_slice(":", 1))
			if not forced in ESTADOS:
				push_warning("[Clima] unknown weather %s (%s)" % [forced, ESTADOS])
				forced = ""
		elif a == "--clima=no":
			on = false
		elif a.begins_with("--rayos="):
			_rayos_k = float(a.trim_prefix("--rayos="))
	if on:
		fx = preload("res://game/world3d/light/fx.gd").new(self)
		vida = preload("res://game/world3d/light/vida.gd").new(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cllab") or a.begins_with("--clshots") or a.begins_with("--clclip"):
			var d: Node = preload("res://game/world3d/light/cl_lab.gd").new()
			d.name = "ClLab"
			add_child(d)
			d.call_deferred("run", self, a)
	if OS.is_debug_build():
		print("[Clima] setup: forced=%s seed=%d tramo %sh, effects %s" % [forced if forced != "" else "no", int(cfg.semilla),
			cfg.tramo_h, "on" if on else "off"])


# ---------------------------------------------------------------- the weather by tramo
func _season() -> String:
	return String(town.season_id)


func _tramo_min() -> float:
	return float(cfg.tramo_h) * 60.0


## [estado, intensidad, viento] of tramo `slot` (minutes / tramo_min), deterministic
func tramo(slot: int, depth := 0) -> Array:
	if forced != "":
		var p: Dictionary = cfg.estados[forced]
		var i := forced_i if forced_i >= 0.0 else float(p.intensidad[1]) * 0.9
		return [forced, i, lerpf(float(p.viento[0]), float(p.viento[1]), 0.6)]
	if _cache.has(slot):
		return _cache[slot]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(cfg.semilla), slot])
	var out: Array
	if depth < 6 and rng.randf() < float(cfg.persiste):
		out = tramo(slot - 1, depth + 1)
	else:
		var probs: Dictionary = cfg.estaciones.get(_season(), cfg.estaciones.spring)
		var r := rng.randf()
		var acc := 0.0
		var pick := "despejado"
		for e in ESTADOS:
			acc += float(probs.get(e, 0.0))
			if r <= acc:
				pick = e
				break
		var p: Dictionary = cfg.estados[pick]
		out = [pick, rng.randf_range(float(p.intensidad[0]), float(p.intensidad[1])),
			rng.randf_range(float(p.viento[0]), float(p.viento[1]))]
	if depth == 0:
		_cache[slot] = out
	return out


func _profile(tr: Array) -> Dictionary:
	var p: Dictionary = cfg.estados[tr[0]]
	var i := float(tr[1])
	var o := {}
	o.nubes = lerpf(float(p.nubes) * 0.6, float(p.nubes), i)
	for k in ["velo", "lluvia", "nieve", "niebla"]:
		o[k] = float(p[k]) * i
	o.tormenta = i if tr[0] == "tormenta" else 0.0
	o.viento = float(tr[2])
	return o


## the weather at minute t, blended across the change of tramo
func weather_at(t: float) -> Dictionary:
	var tm := _tramo_min()
	var slot := floori(t / tm)
	var a := tramo(slot - 1)
	var b := tramo(slot)
	var k := smoothstep(0.0, 1.0, clampf((t - slot * tm) / float(cfg.transicion_min), 0.0, 1.0))
	var pa := _profile(a)
	var pb := _profile(b)
	var o := {}
	for key in pa:
		o[key] = lerpf(float(pa[key]), float(pb[key]), k)
	o.estado = b[0] if k >= 0.5 else a[0]
	o.intensidad = lerpf(float(a[1]), float(b[1]), k) if a[0] == b[0] else (float(b[1]) * k if k >= 0.5 else float(a[1]) * (1.0 - k))
	return o


func mist_at(t: float) -> float:
	## the morning mist over the river and the fields: some mornings (niebla_manana), thick before the day, gone by hasta_h
	var nm: Dictionary = cfg.niebla_manana
	var day := floori(t / 1440.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(cfg.semilla), day, "bruma"])
	var lucky := rng.randf() < float(nm.get(_season(), 0.2))
	if forced == "niebla":
		lucky = true
	elif forced != "":
		lucky = false
	if not lucky:
		return 0.0
	var h := fmod(t, 1440.0) / 60.0
	var a := float(nm.desde_h)
	var b := float(nm.hasta_h)
	if h < a - 6.0 or h > b:
		return 0.0
	var peak := lerpf(a, b, 0.42)
	if h < peak:
		return smoothstep(a - 6.0, peak, h)
	return 1.0 - smoothstep(peak, b, h)


func _ground_step(w: Dictionary, dt: float) -> void:
	var s: Dictionary = cfg.suelo
	if float(w.lluvia) > 0.05:
		mojado = minf(1.0, mojado + dt / float(s.mojar_min) * clampf(float(w.lluvia) * 1.5, 0.2, 1.0))
	else:
		mojado = maxf(0.0, mojado - dt / float(s.secar_min) * (1.0 + (1.0 - float(w.velo)) * 1.5))
	if float(w.nieve) > 0.05:
		nieve_suelo = minf(1.0, nieve_suelo + dt / float(s.cuajar_min) * float(w.nieve))
		mojado = maxf(mojado - dt / 60.0, 0.0)
	elif float(w.lluvia) > 0.05:
		nieve_suelo = maxf(0.0, nieve_suelo - dt / float(s.fundir_min) * 3.0)
	else:
		var melt := 0.4 if _season() == "winter" else 2.0
		nieve_suelo = maxf(0.0, nieve_suelo - dt / float(s.fundir_min) * melt * (1.0 - float(w.velo) * 0.5))


func update(t: float) -> void:
	t_game = t
	var w := weather_at(t)
	if absf(t - _last_t) > 90.0:
		# a jump in time (start, a picture at another hour): the ground as the last twelve hours left it
		mojado = 0.0
		nieve_suelo = 0.0
		var tt := t - 720.0
		while tt < t:
			_ground_step(weather_at(tt), 15.0)
			tt += 15.0
		if forced in ["lluvia", "tormenta"]:
			mojado = 1.0
		elif forced == "nieve":
			nieve_suelo = 1.0
	elif t > _last_t:
		_ground_step(w, t - _last_t)
	_last_t = t
	estado = String(w.estado)
	intensidad = float(w.intensidad)
	viento = float(w.viento)
	for k in now:
		now[k] = float(w.get(k, 0.0))
	bruma = mist_at(t) * (1.0 - float(w.tormenta))
	_lightning(get_process_delta_time())
	var l: RefCounted = town.luz
	if l != null:
		l.weather_dim = clampf(float(w.velo), 0.0, 1.0)
		l.flash = flash
		l.cloud_dim = fx.cloud_at(town.target) if fx != null else 0.0
	if fx != null:
		fx.update(t)
	if vida != null:
		vida.update(t)


func _lightning(dt: float) -> void:
	var st := float(now.tormenta)
	if _flash_t > 0.0:
		_flash_t -= dt
		var k := 1.0 - _flash_t / _flash_dur
		# two strokes: a bright one, a dimmer one a moment later
		flash = maxf(0.0, (1.0 - k * 3.0)) + maxf(0.0, 0.6 - absf(k - 0.45) * 4.0)
		flash = clampf(flash, 0.0, 1.0)
	else:
		flash = 0.0
	if st < 0.2 or dt <= 0.0 or not on:
		return
	var rel: Dictionary = cfg.relampagos
	if _rng.randf() < float(rel.por_s) * st * dt * _rayos_k:
		strike()


func strike() -> void:
	## a lightning flash somewhere around the view (also from the shots: a picture with the flash)
	var rel: Dictionary = cfg.relampagos
	_flash_dur = float(rel.dur_s)
	_flash_t = _flash_dur
	var c: Camera3D = town.cam
	var p := Vector3(town.target.x, 0.0, town.target.z) + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * c.size
	relampago.emit(p)
	if fx != null:
		fx.bolt(p)
	if OS.is_debug_build():
		print("[Clima] relampago at %s" % p)
