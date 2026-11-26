extends RefCounted
## The sounds of things in their place and at their time (scripts/audio/sonido.gd runs it; data/sonido.json):
## - places under the camera (plaza, market, water, fountain, field, forge, street): a distance field per place,
##   read at the point the camera looks at; in the far view each place weighs its town share.
## - blows on the frame of the animation: the AnimationPlayers of who is near (street and the open house) are read
##   every frame; when the clip passes a blow time (data golpes, or the "sharp" keys of data/chars/anims.json) the
##   sound plays a little in front of the body (the anvil, the bench). Footsteps the same with the walk clips.
## - doors when somebody of the trace goes in or out; greetings, dice; the vendors at the stalls while people shop;
##   the crier at the board; the church bells at the hours and before mass (from the trace); animals of PuebloVivo,
##   the rooster at dawn, dogs far away at night, pigeons taking off; looped sources (fountain, river, forge fires,
##   hearths, the cart) on a few players given to the nearest.

var S          # the director (sonido.gd)
var town
var cfg: Dictionary
var counts := {}
var street_people := 0
var rng := RandomNumberGenerator.new()

var _place_pts := {}    # place -> Array[Vector2] (ground x/z) for point places
var _place_d := {}      # place -> PackedFloat32Array (m to the nearest tile of the place, per tile)
var _hits := {}         # anim -> {id, t, db, max, reach, every}
var _cands: Array = []  # [{ap, node, street}]
var _ap_prev := {}      # AnimationPlayer id -> [anim, position, blows]
var _ap_cache := {}     # actor node id -> AnimationPlayer
var _cand_t := 0.0
var _loc_prev := {}
var _doing_prev := {}
var _greeted := {}
var _greet_next := 0.0
var _stalls: Array = []
var _board := Vector3.INF
var _vendor_next := 0.0
var _dice_next := 0.0
var _t_prev := -1.0
var _bell_q := 0
var _bell_next := 0.0
var _mass: Array = []   # game minutes of the first 'mass' of each gathering
var _crow_day := -1
var _crows_left := 0
var _crow_next := 0.0
var _flock_vis = null
var emitters: Array = []   # {key, kind, id, pos, db, r, bus, on, node}
var _players: Array = []   # {p: AudioStreamPlayer3D, key, w, target}
var _timers := {}
var _inside := {}          # building -> {awake, work}


func _init(director) -> void:
	S = director
	town = director.town
	cfg = director.cfg
	rng.randomize()
	_setup_places()
	_setup_hits()
	_setup_market()
	_setup_mass()
	_setup_sources()


func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Sonido] " + msg)


func _count(kind: String) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1


func _now() -> float:
	return float(S.clock)


static func in_hours(h: float, w: Array) -> bool:
	var a := float(w[0])
	var b := float(w[1])
	return (h >= a and h < b) if a <= b else (h >= a or h < b)


func _tile_pos(c: float, r: float, y := 1.0) -> Vector3:
	return Vector3(c * 2.0 + 1.0, y, r * 2.0 + 1.0)


# ---------------------------------------------------------------- places
func _setup_places() -> void:
	var W: int = town.W
	var H: int = town.H
	for pl in cfg.lugares:
		if pl.begins_with("_"):
			continue
		var c: Dictionary = cfg.lugares[pl]
		if c.has("point") and String(c.point) == "well":
			var wa: Vector2 = town.vivo._well_at if town.vivo != null else Vector2.INF
			if wa != Vector2.INF:
				_place_pts[pl] = [Vector2(wa.x, -wa.y)]
			continue
		if c.has("types"):
			var pts := []
			for b in town.bld_anchor:
				if String(town.bld_anchor[b].type) in c.types:
					var hp: Vector3 = (town.bld_anchor[b].house as Node3D).global_position
					pts.append(Vector2(hp.x, hp.z))
			_place_pts[pl] = pts
			continue
		# a distance field over the tiles (two-pass chamfer, metres)
		var big := 1e6
		var d := PackedFloat32Array()
		d.resize(W * H)
		var tiles := String(c.get("tiles", ""))
		var n := 0
		for r in H:
			for cc in W:
				var on := tiles.contains(town._t(cc, r))
				d[r * W + cc] = 0.0 if on else big
				n += 1 if on else 0
		var a := 2.0
		var dg := 2.83
		for r in H:
			for cc in W:
				var i := r * W + cc
				if cc > 0: d[i] = minf(d[i], d[i - 1] + a)
				if r > 0: d[i] = minf(d[i], d[i - W] + a)
				if cc > 0 and r > 0: d[i] = minf(d[i], d[i - W - 1] + dg)
				if cc < W - 1 and r > 0: d[i] = minf(d[i], d[i - W + 1] + dg)
		for r in range(H - 1, -1, -1):
			for cc in range(W - 1, -1, -1):
				var i := r * W + cc
				if cc < W - 1: d[i] = minf(d[i], d[i + 1] + a)
				if r < H - 1: d[i] = minf(d[i], d[i + W] + a)
				if cc < W - 1 and r < H - 1: d[i] = minf(d[i], d[i + W + 1] + dg)
				if cc > 0 and r < H - 1: d[i] = minf(d[i], d[i + W - 1] + dg)
		_place_d[pl] = d
		dbg("place %s: %d tiles" % [pl, n])
	dbg("point places: %s" % JSON.stringify(_place_pts.keys().map(func(k): return "%s x%d" % [k, (_place_pts[k] as Array).size()])))


## weight 0..1 of each place at a ground point; in the far view the town share
func places_at(p: Vector3) -> Dictionary:
	var out := {}
	var W: int = town.W
	var H: int = town.H
	var c := clampi(floori(p.x / 2.0), 0, W - 1)
	var r := clampi(floori(p.z / 2.0), 0, H - 1)
	var outside := Vector2(maxf(0.0, absf(p.x - (c * 2.0 + 1.0)) - 1.0), maxf(0.0, absf(p.z - (r * 2.0 + 1.0)) - 1.0)).length()
	var nk: float = S.near_k()
	for pl in cfg.lugares:
		if pl.begins_with("_"):
			continue
		var lc: Dictionary = cfg.lugares[pl]
		var d := 1e6
		if _place_d.has(pl):
			d = float((_place_d[pl] as PackedFloat32Array)[r * W + c]) + outside
		elif _place_pts.has(pl):
			for q in _place_pts[pl]:
				d = minf(d, (q as Vector2).distance_to(Vector2(p.x, p.z)))
		var local := clampf(1.0 - d / float(lc.radius), 0.0, 1.0)
		out[pl] = snappedf(lerpf(float(lc.get("town_share", 0.0)), local, nk), 0.01)
	return out


# ---------------------------------------------------------------- blows of the animations and steps
func _setup_hits() -> void:
	var anims: Dictionary = {}
	var txt := FileAccess.get_file_as_string("res://game/world3d/kit_data/chars/anims.json")
	if txt != "":
		anims = (JSON.parse_string(txt) as Dictionary).get("anims", {})
	for a in cfg.golpes:
		if a.begins_with("_"):
			continue
		var g: Dictionary = (cfg.golpes[a] as Dictionary).duplicate()
		if not g.has("t"):
			var ts := []
			for k in anims.get(a, {}).get("keys", []):
				if k.get("sharp", false):
					ts.append(float(k.t))
			g.t = ts
		_hits[a] = g
	dbg("blows: %s" % ", ".join(_hits.keys().map(func(k): return "%s %s" % [k, JSON.stringify(_hits[k].t)])))


func _refresh_cands() -> void:
	_cands.clear()
	var r: float = S.radius()
	var hp: Vector3 = S.hear_point()
	if S.zoom() > float(cfg.zoom.anim_zoom):
		return
	for id in town._chr:
		var root: Node3D = town.people[id].node
		if not root.visible:
			continue
		var q := root.global_position
		if Vector2(q.x - hp.x, q.z - hp.z).length() > r:
			continue
		_cands.append({ap = town._chr[id].ap, node = town._chr[id].node, street = true})
	var iv = town.get("inside_view")
	if iv != null and is_instance_valid(iv) and bool(town.inside) and iv.get("live_actors") != null:
		for id in iv.live_actors:
			var a: Dictionary = iv.live_actors[id]
			var n = a.get("node")
			if n == null or not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree():
				continue
			var key: int = (n as Node).get_instance_id()
			if not _ap_cache.has(key) or not is_instance_valid(_ap_cache[key]):
				_ap_cache[key] = (n as Node).find_child("AnimationPlayer", true, false)
			if _ap_cache[key] != null:
				_cands.append({ap = _ap_cache[key], node = n, street = false})


func frame(dt: float) -> void:
	_cand_t -= dt
	if _cand_t <= 0.0:
		_cand_t = 0.25
		_refresh_cands()
	if _cands.is_empty():
		return
	var steps_on: bool = S.zoom() <= float(cfg.zoom.steps_zoom)
	var pc: Dictionary = cfg.pasos
	var hp: Vector3 = S.hear_point()
	for c in _cands:
		# untyped first: a freed instance (a house closed, a figure of a festival taken down) cannot even be assigned
		# to a typed variable, so it is checked before
		var apv = c.ap
		var bodyv = c.node
		if not is_instance_valid(apv) or not is_instance_valid(bodyv):
			continue
		var ap: AnimationPlayer = apv
		if not ap.active or not ap.is_playing():
			continue
		var name := String(ap.current_animation)
		var key := name.trim_prefix("own/")
		var pos := ap.current_animation_position
		var iid := ap.get_instance_id()
		var prev: Array = _ap_prev.get(iid, [])
		var n_blows := int(prev[2]) if prev.size() > 2 else 0
		_ap_prev[iid] = [name, pos, n_blows]
		if prev.is_empty() or String(prev[0]) != name:
			continue
		var p0 := float(prev[1])
		if _hits.has(key):
			var g: Dictionary = _hits[key]
			for t in g.t:
				if _crossed(p0, pos, float(t)):
					n_blows += 1
					_ap_prev[iid][2] = n_blows
					if n_blows % int(g.get("every", 1)) != 0:
						continue
					var body: Node3D = bodyv
					var at := body.global_position + body.global_basis.z.normalized() * float(g.get("reach", 0.5)) + Vector3(0, 0.85, 0)
					if S.pool.play_at(String(g.id), at, S.gain_at(at), float(g.get("volume_db", -6.0)),
							{"tag": "blow_" + String(g.id), "max": int(g.get("max", 2)), "jitter": 0.06, "limit": int(cfg.limites.voces)}):
						_count("golpe:" + key)
		elif steps_on and c.street and pc.clips.has(name):
			var body2: Node3D = bodyv
			var q := body2.global_position
			if Vector2(q.x - hp.x, q.z - hp.z).length() > float(pc.radius):
				continue
			var L := ap.current_animation_length
			for f in pc.clips[name]:
				if _crossed(p0, pos, float(f) * L):
					var ch := String(town._t(floori(q.x / 2.0), floori(q.z / 2.0)))
					var sid := String(pc.id_piedra) if String(pc.piedra).contains(ch) else String(pc.id_tierra)
					if S.pool.play_at(sid, q + Vector3(0, 0.05, 0), S.gain_at(q, float(pc.radius)), float(pc.volume_db),
							{"tag": "step", "max": int(pc.max), "jitter": 0.12, "limit": int(cfg.limites.voces)}):
						_count("paso")


static func _crossed(p0: float, p1: float, t: float) -> bool:
	if p1 >= p0:
		return p0 < t and t <= p1
	return t > p0 or t <= p1  # looped back


# ---------------------------------------------------------------- the tick (every 0.1 s)
func tick(dt: float) -> void:
	var t: float = town.t_min
	var jump := _t_prev < 0.0 or absf(t - _t_prev) > 30.0
	var st: Dictionary = S.state
	_people(t, jump)
	_animals(dt, st, t)
	_bells(t, jump, st)
	_market(dt, t, st, jump)
	_sources(dt, st)
	_t_prev = t


func _people(t: float, jump: bool) -> void:
	var hp: Vector3 = S.hear_point()
	_inside.clear()
	street_people = 0
	var r: float = S.radius()
	for id in town.people:
		var p: Dictionary = town.people[id]
		if t < float(p.first) or not p.has("loc"):
			continue
		var loc := String(p.loc)
		var doing := String(p.get("doing", ""))
		if loc != "" and loc != "~":
			var e: Dictionary = _inside.get(loc, {"awake": 0, "work": 0})
			if doing != "sleep":
				e.awake += 1
			if doing.begins_with("work"):
				e.work += 1
			_inside[loc] = e
		var node: Node3D = p.node
		if loc == "" and node.visible:
			var q := node.global_position
			if Vector2(q.x - hp.x, q.z - hp.z).length() < 14.0:
				street_people += 1
		var prev = _loc_prev.get(id, null)
		_loc_prev[id] = loc
		_doing_prev[id] = doing
		if jump or prev == null:
			continue
		if prev != loc:
			var b := loc if prev == "" else (String(prev) if loc == "" else "")
			if b != "" and b != "~" and town.bld_anchor.has(b):
				var dp: Vector2 = town.bld_anchor[b].door
				var at := Vector3(dp.x, 1.0, -dp.y)
				var pc: Dictionary = cfg.puertas
				if S.pool.play_at(String(pc.id), at, S.gain_at(at), float(pc.volume_db), {"tag": "door", "max": int(pc.max), "jitter": 0.06}):
					_count("puerta")
		# a greeting: one voice per greeting, also when it had begun before the camera came (a breath between two)
		if not doing in ["greet", "guard_greet"]:
			_greeted.erase(id)
		elif loc == "" and node.visible and not _greeted.has(id) and _now() >= _greet_next:
			var q2 := node.global_position + Vector3(0, 1.5, 0)
			var mc: Dictionary = cfg.mercado
			var g2: float = S.gain_at(q2)
			if g2 > 0.02 and S.pool.play_at(String(mc.saludo), q2, g2, float(mc.saludo_db), {"tag": "greet", "max": 1, "bus": "Voces", "jitter": 0.04}):
				_greeted[id] = true
				_greet_next = _now() + rng.randf_range(2.5, 5.0)
				_count("saludo")


func _beast_pos(b: Dictionary) -> Vector3:
	var a = b.get("anim")
	if a != null and is_instance_valid(a) and (a as Node3D).visible:
		return (a as Node3D).global_position
	var st = b.get("still")
	return (st as Node3D).global_position if is_instance_valid(st) else Vector3.INF


func _animals(dt: float, st: Dictionary, t: float) -> void:
	var ac: Dictionary = cfg.animales
	var h := float(st.hour)
	var vivo = town.vivo
	if vivo != null:
		for b in vivo.beasts:
			var c: Dictionary = ac.get(String(b.id), {})
			if c.is_empty() or float(c.rate) <= 0.0 or not in_hours(h, c.horas):
				continue
			if rng.randf() >= float(c.rate) * dt:
				continue
			var at := _beast_pos(b) + Vector3(0, 0.5, 0)
			if S.pool.play_at(String(c.id), at, S.gain_at(at), float(c.volume_db), {"tag": "animal", "max": int(ac.max), "jitter": 0.08}):
				_count("animal:" + String(b.id))
	# the rooster through dawn
	var ga: Dictionary = ac.gallo_alba
	var day := int(floor(t / 1440.0))
	if st.phase == String(ga.start):
		if _crow_day != day:
			_crow_day = day
			_crows_left = int(ga.crows)
			_crow_next = t + rng.randf_range(0.3, 1.5)
		if _crows_left > 0 and t >= _crow_next:
			_crows_left -= 1
			_crow_next = t + float(ga.every_min) * rng.randf_range(0.7, 1.3)
			var best := Vector3.INF
			var bg := 0.0
			if vivo != null:
				for b in vivo.beasts:
					if String(b.id) == "gallo" or (best == Vector3.INF and String(b.id) == "gallina"):
						var at := _beast_pos(b) + Vector3(0, 0.6, 0)
						var g: float = S.gain_at(at, 30.0)
						if best == Vector3.INF or g > bg:
							best = at
							bg = g
			if bg > 0.05:
				S.pool.play_at(String(ga.id), best, bg, float(ga.volume_db), {"tag": "rooster", "max": 1, "jitter": 0.05})
			else:
				S.pool.play_flat(String(ga.id), float(ga.far_db), {"tag": "rooster", "max": 1})
			_count("gallo")
	# dogs far away at night
	var pl: Dictionary = ac.perros_lejos
	if in_hours(h, pl.horas) and rng.randf() < float(pl.rate) * dt:
		if S.pool.play_flat(String(pl.id), float(pl.volume_db) + rng.randf_range(-4.0, 0.0), {"tag": "dog_far", "max": 1, "jitter": 0.1}):
			_count("perro_lejos")
	# pigeons
	if vivo != null and vivo.flock != null and is_instance_valid(vivo.flock):
		var pc: Dictionary = ac.palomas
		var fl: Node3D = vivo.flock
		var at := fl.global_position + Vector3(0, 6, 0)
		var g: float = S.gain_at(at, float(pc.radius))
		if _flock_vis != null and fl.visible and not _flock_vis:
			if g > 0.02:
				S.pool.play_at(String(pc.despegue), at, g, float(pc.volume_db) + 2.0, {"tag": "pigeons", "max": 1})
			else:
				S.pool.play_flat(String(pc.despegue), float(pc.volume_db) - 10.0, {"tag": "pigeons", "max": 1})
			_count("palomas_despegue")
		elif fl.visible and g > 0.02 and rng.randf() < float(pc.rate) * dt:
			var id := String(pc.arrullo) if rng.randf() < 0.6 else String(pc.despegue)
			if S.pool.play_at(id, at, g, float(pc.volume_db) - (0.0 if id == String(pc.arrullo) else 6.0), {"tag": "pigeons", "max": 1}):
				_count("palomas")
		_flock_vis = fl.visible


# ---------------------------------------------------------------- bells, mass
func _setup_mass() -> void:
	var ms := []
	for id in town.trace.characters:
		for row in town.trace.characters[id].st:
			if String(row[2]) == "mass":
				ms.append(float(row[0]))
	ms.sort()
	var last := -1e9
	for m in ms:
		if m - last > 90.0:
			_mass.append(m)
		last = m
	dbg("mass in the trace at %s" % JSON.stringify(_mass.map(func(m): return "d%d %02d:%02d" % [int(m / 1440.0), int(fmod(m, 1440.0) / 60.0), int(fmod(m, 60.0))])))


func _church_pos() -> Vector3:
	var c = town.get("church")
	if c != null and is_instance_valid(c):
		return (c as Node3D).global_position + Vector3(0, 6, 0)
	return Vector3.INF


func _ring(id: String, db: float) -> void:
	var bc: Dictionary = cfg.campanas
	var at := _church_pos()
	var g: float = S.gain_at(at, float(bc.near_m)) if at != Vector3.INF else 0.0
	if g > 0.05:
		S.pool.play_at(id, at, maxf(g, 0.3), db, {"tag": "bell", "max": 3, "jitter": 0.0})
	else:
		S.pool.play_flat(id, float(bc.far_db) + (db - float(bc.volume_db)), {"tag": "bell", "max": 3, "jitter": 0.0})
	_count("campana")


func _bells(t: float, jump: bool, st: Dictionary) -> void:
	var bc: Dictionary = cfg.campanas
	if not jump:
		var h0 := floori(_t_prev / 60.0)
		var h1 := floori(t / 60.0)
		if h1 > h0:
			var hd := h1 % 24
			if hd >= int(bc.horas[0]) and hd <= int(bc.horas[1]):
				var n := hd % 12
				if n == 0:
					n = 12
				if float(town.SPEEDS[town.speed_i]) > 1.0:
					n = 1  # fast forward: one stroke, not a pile-up
				_bell_q = n
				_bell_next = 0.0
				dbg("bells: %02d:00, %d strokes" % [hd, n])
		for m in _mass:
			var at := float(m) - float(bc.misa_antes)
			if _t_prev < at and t >= at:
				_ring(String(bc.misa), float(bc.misa_db))
				dbg("bells: peal for mass at %02d:%02d" % [int(fmod(m, 1440.0) / 60.0), int(fmod(m, 60.0))])
	if _bell_q > 0 and _now() >= _bell_next:
		_bell_q -= 1
		_bell_next = _now() + float(bc.every)
		_ring(String(bc.id), float(bc.volume_db))


# ---------------------------------------------------------------- the market
func _setup_market() -> void:
	for r in town.H:
		for c in town.W:
			var ch := String(town._t(c, r))
			if ch == "S":
				_stalls.append(_tile_pos(c, r, 1.6))
			elif ch == "N":
				_board = _tile_pos(c, r, 1.6)
	dbg("market: %d stalls, board %s" % [_stalls.size(), _board])


func _market(dt: float, t: float, st: Dictionary, jump: bool) -> void:
	var mc: Dictionary = cfg.mercado
	var h := float(st.hour)
	var now := _now()
	if in_hours(h, mc.horas) and now >= _vendor_next and not _stalls.is_empty():
		var shoppers := []
		for id in town.people:
			var p: Dictionary = town.people[id]
			if String(p.get("loc", "x")) == "" and String(p.get("doing", "")) in ["shopping", "market", "visit_merchant"] and (p.node as Node3D).visible:
				shoppers.append((p.node as Node3D).global_position)
		if OS.is_debug_build():
			dbg("market %02d:%02d: %d shopping in the street" % [int(h), int(fmod(h * 60.0, 60.0)), shoppers.size()])
		if not shoppers.is_empty():
			var who: Vector3 = shoppers[rng.randi() % shoppers.size()]
			var best: Vector3 = _stalls[0]
			for s in _stalls:
				if (s as Vector3).distance_to(who) < best.distance_to(who):
					best = s
			if best.distance_to(who) < 12.0:
				var g: float = S.gain_at(best)
				var id := String(mc.voces[rng.randi() % (mc.voces as Array).size()])
				if S.pool.play_at(id, best, g, float(mc.volume_db), {"tag": "vendor", "max": int(mc.max), "bus": "Voces", "jitter": 0.03}):
					_count("vendedor")
					if rng.randf() < 0.4:
						S.pool.play_at(String(mc.coins), best, g, float(mc.coins_db), {"tag": "coins", "max": 1, "jitter": 0.05})
			_vendor_next = now + rng.randf_range(float(mc.every[0]), float(mc.every[1]))
	if not jump and _board != Vector3.INF:
		for ph in mc.pregon_horas:
			var at := floorf(t / 1440.0) * 1440.0 + float(ph) * 60.0
			if _t_prev < at and t >= at:
				dbg("crier at the board at %02d:%02d" % [int(ph), int(fmod(float(ph) * 60.0, 60.0))])
				var g2: float = S.gain_at(_board, 30.0)
				if g2 > 0.02:
					S.pool.play_at(String(mc.pregon), _board, maxf(g2, 0.25), float(mc.pregon_db), {"tag": "crier", "max": 1, "bus": "Voces"})
				else:
					S.pool.play_flat(String(mc.pregon), float(mc.pregon_db) - 16.0, {"tag": "crier", "max": 1})
				_count("pregon")
	# dice at the plaza table
	if now >= _dice_next:
		_dice_next = now + rng.randf_range(4.0, 9.0)
		for id in town.people:
			var p: Dictionary = town.people[id]
			if String(p.get("doing", "")) == "dice" and (p.node as Node3D).visible:
				var q := (p.node as Node3D).global_position + Vector3(0, 0.8, 0)
				if S.pool.play_at(String(mc.dados), q, S.gain_at(q), float(mc.dados_db), {"tag": "dice", "max": 1}):
					_count("dados")
				break


# ---------------------------------------------------------------- looped sources
func _setup_sources() -> void:
	var fc: Dictionary = cfg.fuentes
	if town.vivo != null and town.vivo._well_at != Vector2.INF:
		var w: Vector2 = town.vivo._well_at
		_emit("fuente", "fuente", Vector3(w.x, 0.8, -w.y), "Ambiente")
	var picked: Array = []
	var step := float(fc.rio.step)
	for r in town.H:
		for c in town.W:
			if String(town._t(c, r)) in ["w", "b"]:
				var q := _tile_pos(c, r, 0.3)
				var ok := true
				for o in picked:
					if (o as Vector3).distance_to(q) < step:
						ok = false
						break
				if ok:
					picked.append(q)
	for i in picked.size():
		_emit("rio%d" % i, "rio", picked[i], "Ambiente")
	for b in town.bld_anchor:
		var hp: Vector3 = (town.bld_anchor[b].house as Node3D).global_position
		if String(town.bld_anchor[b].type) == "forge":
			_emit("fragua_" + b, "fragua", hp + Vector3(0, 1.2, 0), "Efectos", b)
		_emit("hogar_" + b, "hogar", hp + Vector3(0, 1.0, 0), "Efectos", b)
	if town.get("cart_trip") != null:
		_emit("carro", "carro", Vector3.INF, "Efectos")
	for i in int(fc.players):
		var p := AudioStreamPlayer3D.new()
		p.name = "Fuente%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.volume_db = -80.0
		S.add_child(p)
		_players.append({p = p, key = "", w = 0.0, target = 0.0})
	var kinds := {}
	for e in emitters:
		kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
	dbg("looped sources: %s on %d players" % [JSON.stringify(kinds), _players.size()])


func _emit(key: String, kind: String, pos: Vector3, bus: String, bld := "") -> void:
	var c: Dictionary = cfg.fuentes[kind]
	if not S.pool.has(String(c.id)):
		return
	emitters.append({key = key, kind = kind, id = String(c.id), pos = pos, db = float(c.volume_db), r = float(c.radius),
		bus = bus, bld = bld, g = 0.0})


func _sources(dt: float, st: Dictionary) -> void:
	var fc: Dictionary = cfg.fuentes
	var h := float(st.hour)
	var dark: float = 1.0 - float(town.daylight(town.t_min))
	var want := {}
	for e in emitters:
		var on := 1.0
		match String(e.kind):
			"fragua":
				on = 1.0 if int(_inside.get(e.bld, {}).get("work", 0)) > 0 else 0.0
			"hogar":
				var awake := int(_inside.get(e.bld, {}).get("awake", 0))
				on = 1.0 if awake > 0 and (dark > 0.45 or h < 8.0) and String(e.bld) != "" and String(town.bld_anchor[e.bld].type) != "forge" else 0.0
			"carro":
				var ct = town.cart_trip
				var shown = ct.get("_shown") if ct != null else null
				if shown != null and is_instance_valid(shown) and (shown as Node3D).visible and not (ct.capsule as Array).is_empty():
					e.pos = (shown as Node3D).global_position + Vector3(0, 0.6, 0)
				else:
					on = 0.0
		if on <= 0.0 or e.pos == Vector3.INF:
			e.g = 0.0
			continue
		e.g = S.gain_at(e.pos, float(e.r))
		if float(e.g) > 0.01:
			want[e.key] = e
	# the nearest get a player
	var keys := want.keys()
	keys.sort_custom(func(a, b): return float(want[a].g) > float(want[b].g))
	keys = keys.slice(0, _players.size())
	var have := {}
	for pl in _players:
		if pl.key != "" and pl.key in keys:
			have[pl.key] = pl
		else:
			pl.target = 0.0
	for k in keys:
		if have.has(k):
			continue
		for pl in _players:
			if pl.key == "" :
				var e: Dictionary = want[k]
				var p: AudioStreamPlayer3D = pl.p
				p.stream = S.pool.pick(String(e.id), true)
				p.bus = String(e.bus)
				p.global_position = e.pos
				p.volume_db = -80.0
				p.play(rng.randf() * maxf(0.0, p.stream.get_length() - 0.5))
				pl.key = k
				pl.w = 0.0
				have[k] = pl
				_count("fuente:" + String(e.kind))
				break
	var kk := 1.0 - exp(-dt / 0.6)
	for pl in _players:
		if pl.key == "":
			continue
		var p: AudioStreamPlayer3D = pl.p
		if want.has(pl.key) and pl.key in keys:
			var e: Dictionary = want[pl.key]
			pl.target = float(e.g)
			pl.db = float(e.db)
			p.global_position = e.pos
		pl.w = lerpf(float(pl.w), float(pl.target), 1.0 if S._first else kk)
		if float(pl.target) <= 0.0 and float(pl.w) < 0.005:
			p.stop()
			pl.key = ""
			continue
		p.volume_db = float(pl.get("db", -12.0)) + linear_to_db(maxf(float(pl.w), 0.0001))
	# the bellows of a working forge and the donkey of the cart, now and then
	var now := _now()
	for e in emitters:
		if float(e.g) <= 0.02:
			continue
		if e.kind == "fragua" and now >= float(_timers.get(e.key, 0.0)):
			_timers[e.key] = now + rng.randf_range(float(fc.fragua.fuelle_every[0]), float(fc.fragua.fuelle_every[1]))
			if S.pool.play_at(String(fc.fragua.fuelle), e.pos, float(e.g), float(fc.fragua.fuelle_db), {"tag": "bellows", "max": 1}):
				_count("fuelle")
		elif e.kind == "carro" and now >= float(_timers.get(e.key, 0.0)):
			var first: bool = not _timers.has(e.key)
			_timers[e.key] = now + rng.randf_range(float(fc.carro.rebuzno_every[0]), float(fc.carro.rebuzno_every[1]))
			if not first and S.pool.play_at(String(fc.carro.rebuzno), e.pos, float(e.g), -9.0, {"tag": "animal", "max": 2}):
				_count("rebuzno")
