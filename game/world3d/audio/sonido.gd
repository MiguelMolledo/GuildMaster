extends Node
## The sound of the sim town (sim3d_chars.tscn): buses, the listener on the ground the camera looks at, the ambient
## layers by hour, season, weather, place and zoom, the music by rules with crossfades, the weather (the node in
## group "clima") with thunder after each lightning, the reverb and the ducking when a house is open. The sounds of
## things in their place (blows of the animations, steps, doors, animals, bells, the market, fountain, river, fires,
## the cart) are scripts/audio/sonido_vida.gd. All the levels and rules: data/sonido.json (docs/sonido.md).
## Args: --mudo (everything runs, nothing is heard) · --musica=<dB> (music level offset) or --musica=no ·
##       --sonido=no (no sound system at all) · --so_clima=<estado>[:<intensidad>[:<viento>]] (without a clima node) ·
##       --suceso=<fiesta|boda|feria> · --so_vista=<col>,<row>,<zoom>,<yaw>,<HH:MM>[,<day>[,abrir[,<speed>]]] (a fixed
##       view for a clip; with Movie Maker) · --so_coste=<file> (cost of the system, written at exit)
## Keys: M mute / unmute.

const Pool := preload("res://game/world3d/audio/sonido_pool.gd")
const Vida := preload("res://game/world3d/audio/sonido_vida.gd")
const Fiestas := preload("res://game/world3d/audio/sonido_fiestas.gd")
const CFG := "res://data/view3d/sonido.json"
const BUSES := ["Musica", "Ambiente", "Efectos", "Voces", "Lejos"]
const PHASES := ["dawn", "day", "dusk", "night"]

var town: Node3D
var cfg := {}
var pool: RefCounted
var vida: RefCounted
var fiestas: RefCounted  # the festivals of the town (scripts/audio/sonido_fiestas.gd)
var listener: AudioListener3D
var layers := {}        # id -> {p: AudioStreamPlayer, w: current linear, target}
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_id := ""
var _music_since := -1e9
var _music_tw: Tween
var clima_node: Node = null
var clima_fake := {"estado": "despejado", "intensidad": 0.0, "viento": 0.0}
var suceso := ""
var opened := false     # a house is open
var _open_type := ""
var _reverb: Array = []  # [bus index, effect]
var _muffle: AudioEffectLowPassFilter
var _music_offset := 0.0
var _tick := 0.0
var _clima_look := 0.0
var _first := true
var state := {}         # what the rules see this tick: hour, phase, season, zoom, places, weather...
var cost := {"frames": 0, "us": 0, "us_max": 0, "ticks": 0, "tick_us": 0, "tick_us_max": 0}
var _cost_out := ""
var _log_t := 0.0
var vista := {}
var _settle := 2.0      # until this clock the music changes without a fade (the town settling: the festival mounts, a clip view)
var _t_seen := -1.0e9
var clock := 0.0        # seconds of the frames' delta: the timers follow it (Movie Maker and --fixed-fps run off the wall clock)


func _init(t: Node3D) -> void:
	town = t
	name = "Sonido"


func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Sonido] " + msg)


func _ready() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--musica="):
			var v := a.trim_prefix("--musica=")
			_music_offset = -80.0 if v == "no" else float(v)
		elif a.begins_with("--so_clima="):
			var parts := a.trim_prefix("--so_clima=").split(":")
			clima_fake.estado = parts[0]
			clima_fake.intensidad = float(parts[1]) if parts.size() > 1 else 0.7
			clima_fake.viento = float(parts[2]) if parts.size() > 2 else (0.6 if parts[0] == "tormenta" else 0.2)
		elif a.begins_with("--suceso="):
			suceso = a.trim_prefix("--suceso=")
		elif a.begins_with("--so_coste="):
			_cost_out = a.trim_prefix("--so_coste=")
		elif a.begins_with("--so_vista="):
			_parse_vista(a.trim_prefix("--so_vista="))
	_buses()
	if "--mudo" in args:
		AudioServer.set_bus_mute(0, true)
	listener = AudioListener3D.new()
	listener.name = "Oyente"
	add_child(listener)
	listener.make_current()
	pool = Pool.new(self, int(cfg.get("limites", {}).get("pool", 20)))
	music_a = _flat_player("MusicaA", "Musica")
	music_b = _flat_player("MusicaB", "Musica")
	for id in cfg.ambiente:
		if id.begins_with("_"):
			continue
		_layer(id)
	for typ in cfg.get("interior", {}):
		if not typ.begins_with("_") and typ != "volume_db":
			_layer(String(cfg.interior[typ]))
	for r in cfg.musica.reglas:
		pool.streams(String(r.id), true)  # loaded now, not on the frame the music changes
	vida = Vida.new(self)
	fiestas = Fiestas.new(self, vida)
	dbg("ready: %d ambient layers with file, music rules %d, buses %s, mute %s, music offset %.0f dB" % [
		_live_layers(), (cfg.musica.reglas as Array).size(), BUSES, "--mudo" in args, _music_offset])
	if not vista.is_empty():
		_start_vista.call_deferred()


func _flat_player(n: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _layer(id: String) -> void:
	if layers.has(id) or not pool.has(id):
		return
	var p := _flat_player("Capa_" + id, "Ambiente")
	p.stream = pool.pick(id, true)
	layers[id] = {p = p, w = 0.0, target = 0.0, idle = 0.0}


func _live_layers() -> int:
	return layers.size()


# ---------------------------------------------------------------- buses
func _bus(n: String, send := "Master") -> int:
	var i := AudioServer.get_bus_index(n)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
	AudioServer.set_bus_send(i, send)
	return i


## GuildMaster-3d: the town's buses send to the game's own (default_bus_layout.tres), so the volume options apply; the
## music is the AudioDirector's, the Master bus is not touched.
const GM_SEND := {"Musica": "Music", "Ambiente": "Ambient", "Efectos": "Sfx", "Voces": "Voice", "Lejos": "Ambient"}


func _gm() -> bool:
	return Pool.resolver.is_valid()


func _buses() -> void:
	var b: Dictionary = cfg.buses
	for n in BUSES:
		var c: Dictionary = b.get(n, {})
		var i := _bus(n, GM_SEND.get(n, "Master") if _gm() else String(c.get("send", "Master")))
		AudioServer.set_bus_volume_db(i, float(c.get("volume_db", 0.0)) + (_music_offset if n == "Musica" else 0.0))
		while AudioServer.get_bus_effect_count(i) > 0:
			AudioServer.remove_bus_effect(i, 0)
		if c.has("lowpass_hz"):
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = float(c.lowpass_hz)
			AudioServer.add_bus_effect(i, lp)
	var rv: Dictionary = b.get("reverb_open", {})
	for n in ["Efectos", "Voces"]:
		var r := AudioEffectReverb.new()
		r.room_size = float(rv.get("room", 0.38))
		r.damping = float(rv.get("damping", 0.6))
		r.wet = 0.0
		r.dry = 1.0
		var i := AudioServer.get_bus_index(n)
		AudioServer.add_bus_effect(i, r)
		_reverb.append([i, r])
	# the music gives way to the voices (sidechain), the ambience is dulled by snow and fog
	var dv: Dictionary = b.get("duck_voice", {})
	var comp := AudioEffectCompressor.new()
	comp.sidechain = &"Voces"
	comp.threshold = float(dv.get("threshold_db", -26.0))
	comp.ratio = float(dv.get("ratio", 4.0))
	comp.release_ms = float(dv.get("release_ms", 600.0))
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Musica"), comp)
	_muffle = AudioEffectLowPassFilter.new()
	_muffle.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambiente"), _muffle)
	if _gm():
		dbg("buses: %s, sending to the game's" % ", ".join(BUSES.map(func(n): return "%s -> %s" % [n, GM_SEND.get(n, "Master")])))
		return
	AudioServer.set_bus_volume_db(0, float(b.get("Master", {}).get("volume_db", 0.0)))
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, 0)
	AudioServer.add_bus_effect(0, lim)
	dbg("buses: %s" % ", ".join(BUSES.map(func(n): return "%s %.0f dB" % [n, AudioServer.get_bus_volume_db(AudioServer.get_bus_index(n))])))


# ---------------------------------------------------------------- what the camera sees
func zoom() -> float:
	return float(town.cam.size) if town.get("cam") != null else 26.0


func hear_point() -> Vector3:
	var t: Vector3 = town.target
	return Vector3(t.x, 0.0, t.z)


## 1 near (point sounds in their place), 0 in the far view
func near_k() -> float:
	var z: Dictionary = cfg.zoom
	return 1.0 - smoothstep(float(z.near), float(z.far), zoom())


func radius() -> float:
	var z: Dictionary = cfg.zoom
	return lerpf(float(z.radius_near), float(z.radius_far), clampf((zoom() - float(z.near)) / maxf(1.0, float(z.far) - float(z.near)), 0.0, 1.0))


## linear gain of a point sound at a ground point: (1 - d/r)^2, times how near the view is
func gain_at(pos: Vector3, r := -1.0) -> float:
	if r < 0.0:
		r = radius()
	var h := hear_point()
	var d := Vector2(pos.x - h.x, pos.z - h.z).length()
	var g := clampf(1.0 - d / r, 0.0, 1.0)
	return g * g * near_k()


func weather() -> Dictionary:
	if clima_node != null and is_instance_valid(clima_node):
		return {"estado": String(clima_node.get("estado")), "intensidad": float(clima_node.get("intensidad")),
			"viento": float(clima_node.get("viento"))}
	return clima_fake


func _find_clima() -> void:
	var n := get_tree().get_first_node_in_group("clima")
	if n != null and n != clima_node:
		clima_node = n
		if n.has_signal("relampago") and not n.is_connected("relampago", _on_relampago):
			n.connect("relampago", _on_relampago)
		dbg("weather node found: %s (estado %s)" % [n.name, String(n.get("estado"))])


func _on_relampago(pos: Vector3) -> void:
	var th: Dictionary = cfg.clima.thunder
	var h := hear_point()
	var d := Vector2(pos.x - h.x, pos.z - h.z).length()
	var delay := minf(d / float(th.speed), float(th.max_delay_s))
	var id := String(th.near) if d < float(th.near_m) else String(th.far)
	var db := float(th.volume_db) - clampf(d / float(th.fall_m), 0.0, 1.0) * 14.0
	dbg("lightning at %.0f m: thunder %s in %.1f s at %.1f dB" % [d, id, delay, db])
	get_tree().create_timer(delay).timeout.connect(func(): pool.play_flat(id, db, {"bus": "Ambiente", "tag": "thunder", "max": 2, "jitter": 0.06}))


func _phase(t: float) -> String:
	var b: Dictionary = town._day_info(t).bounds
	var md := fmod(t, 1440.0)
	var ph := "night"
	for k in PHASES:
		if b.has(k) and md >= float(b[k]):
			ph = k
	return ph


func _state() -> void:
	var t: float = town.t_min
	var di: Dictionary = town._day_info(t)
	var w := weather()
	state = {"t": t, "hour": fmod(t, 1440.0) / 60.0, "phase": _phase(t), "season": String(di.get("season", "spring")),
		"zoom": zoom(), "near": near_k(), "estado": w.estado, "intensidad": w.intensidad, "viento": w.viento,
		"places": vida.places_at(hear_point()), "open": opened, "open_type": _open_type, "suceso": _suceso()}


func _suceso() -> String:
	## the kind of the festival standing (data sucesos: fiesta, boda, feria, carnaval, torneo, procesion...), or the
	## one of --suceso= (a kind or a festival id)
	return fiestas.kind_now(suceso) if fiestas != null else suceso


# ---------------------------------------------------------------- ambient layers
static func curve(pts: Array, x: float) -> float:
	if pts.is_empty():
		return 1.0
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if x <= float(b[0]):
			var k := (x - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), k)
	return float(pts.back()[1])


func layer_weight(id: String, c: Dictionary) -> float:
	var w := curve(c.get("horas", []), float(state.hour))
	w *= float(c.get("estacion", {}).get(state.season, 1.0))
	var cl: Dictionary = c.get("clima", {})
	w *= float(cl.get(state.estado, 1.0))
	if c.has("lluvia_x"):
		w *= curve(cfg.clima.get(String(c.lluvia_x), [[0, 0], [1, 1]]), float(state.intensidad))
	if c.get("viento_x", false):
		w *= clampf(float(state.viento), 0.0, 1.0)
	if c.has("lugar"):
		var pl := float(state.places.get(String(c.lugar), 0.0))
		w *= lerpf(float(c.get("lugar_min", 0.0)), 1.0, pl)
	if c.has("suceso"):
		w *= float(c.suceso.get(state.suceso, 0.0))
	if c.has("acto") and not fiestas.acts.has(String(c.acto)):
		w = 0.0
	if c.get("gente", false):
		w *= clampf(0.35 + float(vida.street_people) / 18.0, 0.35, 1.0)
	var nk := float(state.near)
	w *= lerpf(float(c.get("lejos", 1.0)), float(c.get("cerca", 1.0)), nk)
	return clampf(w, 0.0, 1.5)


func _layers(dt: float) -> void:
	var targets := {}
	for id in layers:
		targets[id] = 0.0
	for id in cfg.ambiente:
		if layers.has(id):
			targets[id] = layer_weight(id, cfg.ambiente[id])
	if opened and cfg.get("interior", {}).has(_open_type):
		var iid := String(cfg.interior[_open_type])
		if layers.has(iid):
			targets[iid] = maxf(float(targets[iid]), 1.0)
	var k := 1.0 if _first else 1.0 - exp(-dt / 1.2)
	for id in layers:
		var L: Dictionary = layers[id]
		L.target = float(targets[id])
		L.w = lerpf(float(L.w), float(L.target), k)
		var p: AudioStreamPlayer = L.p
		var base := float(cfg.ambiente.get(id, {}).get("volume_db", cfg.get("interior", {}).get("volume_db", -12.0)))
		if float(L.w) < 0.004:
			L.idle = float(L.idle) + dt
			if p.playing and float(L.idle) > 2.0:
				p.stream_paused = true
			p.volume_db = -80.0
			continue
		L.idle = 0.0
		if not p.playing:
			p.play(randf() * maxf(0.0, p.stream.get_length() - 1.0))
		p.stream_paused = false
		p.volume_db = base + linear_to_db(float(L.w))
	# snow and fog dull the town
	var hz := float(cfg.clima.muffle_hz.get(state.estado, 20000.0))
	_muffle.cutoff_hz = lerpf(_muffle.cutoff_hz, hz, k)


# ---------------------------------------------------------------- music
func _rule_ok(si: Dictionary) -> bool:
	if si.has("fase") and not state.phase in si.fase:
		return false
	if si.has("estacion") and not state.season in si.estacion:
		return false
	if si.has("clima") and not state.estado in si.clima:
		return false
	if si.has("suceso") and not state.suceso in si.suceso:
		return false
	if si.has("horas"):
		var h := float(state.hour)
		if h < float(si.horas[0]) or h >= float(si.horas[1]):
			return false
	if si.has("lugar") and float(state.places.get(String(si.lugar), 0.0)) * float(state.near) < 0.5:
		return false
	return true


func _music() -> void:
	if _gm():
		return   # GuildMaster: the music is the AudioDirector's (phase, festival)
	var m: Dictionary = cfg.musica
	var want := ""
	var urgent := false
	for r in m.reglas:
		if pool.has(String(r.id)) and _rule_ok(r.get("si", {})):
			want = String(r.id)
			urgent = bool(r.get("urgent", false))
			break
	if want == music_id:
		return
	var now := clock
	if not _first and clock >= _settle and not urgent and now - _music_since < float(m.hold) and music_id != "":
		return
	dbg("music: %s -> %s (phase %s, %s, %s, places %s)" % [music_id if music_id != "" else "-", want, state.phase,
		state.season, state.estado, JSON.stringify(state.places)])
	music_id = want
	_music_since = now
	var fade := 0.01 if _first or clock < _settle else float(m.fade)
	var old := music_a if music_a.playing else null
	var nw := music_b if old == music_a else music_a
	if _music_tw:
		_music_tw.kill()
	_music_tw = create_tween().set_parallel(true)
	if want != "":
		nw.stream = pool.pick(want, true)
		nw.volume_db = -60.0
		nw.play()
		_music_tw.tween_method(func(x: float): nw.volume_db = linear_to_db(maxf(x, 0.0001)) + float(m.volume_db.get(want, 0.0)), 0.001, 1.0, fade)
	if old != null:
		var v0 := db_to_linear(old.volume_db)
		_music_tw.tween_method(func(x: float): old.volume_db = linear_to_db(maxf(x, 0.0001)), v0, 0.0001, fade)
		_music_tw.chain().tween_callback(old.stop)


# ---------------------------------------------------------------- a house open
func _interior() -> void:
	var now_open: bool = bool(town.get("inside")) and town.get("situ_house") != null
	if now_open == opened:
		return
	opened = now_open
	_open_type = ""
	if opened:
		var h: Node3D = town.situ_house
		var b: String = String(town.live_bld)
		_open_type = String(town.trace.buildings.get(b, {}).get("type", h.get_meta("type", "house"))) if b != "" else String(h.get_meta("type", "house"))
	var rv: Dictionary = cfg.buses.get("reverb_open", {})
	var tw := create_tween().set_parallel(true)
	for e in _reverb:
		var r: AudioEffectReverb = e[1]
		tw.tween_property(r, "wet", float(rv.get("wet", 0.22)) if opened else 0.0, 0.8)
	var mi := AudioServer.get_bus_index("Musica")
	var base := float(cfg.buses.Musica.volume_db) + _music_offset
	tw.tween_method(func(x: float): AudioServer.set_bus_volume_db(mi, x), AudioServer.get_bus_volume_db(mi),
		base + (float(cfg.buses.get("duck_open_db", -7.0)) if opened else 0.0), 1.0)
	dbg("house %s: %s (type %s): reverb %s, music %+.0f dB" % ["open" if opened else "closed",
		town.situ_house.name if town.get("situ_house") else "-", _open_type, "on" if opened else "off",
		float(cfg.buses.get("duck_open_db", -7.0)) if opened else 0.0])


# ---------------------------------------------------------------- the frame
func _process(delta: float) -> void:
	if town.get("trace") == null or (town.trace as Dictionary).is_empty():
		return
	var u0 := Time.get_ticks_usec()
	clock += delta
	var t: Vector3 = town.target
	listener.global_position = Vector3(t.x, float(cfg.zoom.listener_h), t.z)
	listener.rotation = Vector3(0, deg_to_rad(float(town.yaw)), 0)
	_clima_look -= delta
	if _clima_look <= 0.0:
		_clima_look = 1.0
		_find_clima()
	vida.frame(delta)  # the blows of the animations: every frame, on their frame
	var tm: float = town.t_min
	if absf(tm - _t_seen) > 30.0:  # the clock jumped (a view, a measure, R): everything settles again without fades
		_first = true
		_settle = clock + 2.0
	_t_seen = tm
	_tick -= delta
	if _tick <= 0.0 or _first:
		var u1 := Time.get_ticks_usec()
		_tick = 0.1
		fiestas.tick(0.1)  # first: the music and the layers read the festival standing
		_state()
		_interior()
		_layers(0.1)
		_music()
		vida.tick(0.1)
		var tu := Time.get_ticks_usec() - u1
		cost.ticks += 1
		cost.tick_us += tu
		cost.tick_us_max = maxi(int(cost.tick_us_max), tu)
		_first = false
	var us := Time.get_ticks_usec() - u0
	cost.frames += 1
	cost.us += us
	cost.us_max = maxi(int(cost.us_max), us)
	_log_t += delta
	if _log_t > 10.0 and OS.is_debug_build():
		_log_t = 0.0
		dbg("%02d:%02d %s %s %s zoom %.0f places %s · layers %s · music %s · voices %d (peak %d, played %d, refused %d) · %.3f ms/frame avg, tick %.3f ms" % [
			int(state.hour), int(fmod(float(state.hour) * 60.0, 60.0)), state.phase, state.season, state.estado, zoom(),
			JSON.stringify(state.places), _layer_txt(), music_id, pool.busy(), pool.stats.peak, pool.stats.played,
			pool.stats.refused, float(cost.us) / maxf(1.0, float(cost.frames)) / 1000.0,
			float(cost.tick_us) / maxf(1.0, float(cost.ticks)) / 1000.0])


func _layer_txt() -> String:
	var out := []
	for id in layers:
		if float(layers[id].w) > 0.02:
			out.append("%s %.2f" % [String(id).trim_prefix("ambient_"), float(layers[id].w)])
	return ", ".join(out)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_M:
		AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
		dbg("mute %s" % AudioServer.is_bus_mute(0))


func report() -> Dictionary:
	return {"frames": cost.frames, "ms_avg": snappedf(float(cost.us) / maxf(1.0, float(cost.frames)) / 1000.0, 0.001),
		"ms_max": snappedf(float(cost.us_max) / 1000.0, 0.001),
		"tick_ms_avg": snappedf(float(cost.tick_us) / maxf(1.0, float(cost.ticks)) / 1000.0, 0.001),
		"tick_ms_max": snappedf(float(cost.tick_us_max) / 1000.0, 0.001), "voices_peak": pool.stats.peak,
		"played": pool.stats.played, "refused": pool.stats.refused, "stolen": pool.stats.stolen,
		"by_kind": vida.counts, "missing": pool.missing(), "layers": layers.size()}


func _exit_tree() -> void:
	var r := report()
	dbg("cost: %s" % JSON.stringify(r))
	if _cost_out != "":
		var f := FileAccess.open(_cost_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(r, "  "))


# ---------------------------------------------------------------- a fixed view for a clip (Movie Maker)
func _parse_vista(spec: String) -> void:
	var p := spec.split(",")
	vista = {"col": float(p[0]), "row": float(p[1]), "zoom": float(p[2]), "yaw": float(p[3]), "at": p[4],
		"day": int(p[5]) if p.size() > 5 and p[5] != "" else 1, "abrir": p.size() > 6 and p[6] == "abrir",
		"speed": float(p[7]) if p.size() > 7 else -1.0}


func _start_vista() -> void:
	var v := vista
	var day0: float = town._day_start(float(town.t0))
	town.t_min = day0 + 1440.0 * int(v.day) + int(String(v.at).get_slice(":", 0)) * 60 + int(String(v.at).get_slice(":", 1))
	if float(v.speed) > 0.0:
		town.speed_i = maxi(0, town.SPEEDS.find(float(v.speed)))
	town.target = town._plan3(float(v.col), float(v.row))
	town.cam.size = float(v.zoom)
	town.yaw = float(v.yaw) if float(v.yaw) >= 0.0 else float(town.home_yaw)
	town._update_camera()
	_first = true
	_settle = clock + 2.0
	dbg("clip view: tile %.1f,%.1f zoom %.0f yaw %.0f at day %d %s%s" % [float(v.col), float(v.row), float(v.zoom),
		float(town.yaw), int(v.day), v.at, " (house opened)" if v.abrir else ""])
	if v.abrir:
		await get_tree().process_frame
		var h: Node3D = town._house_near(town.target, 6.0)
		if h != null:
			town.enter(false, h)
