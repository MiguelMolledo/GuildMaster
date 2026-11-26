extends RefCounted
## The living dressing of the town of the sim (pueblo.gd): street furniture, lamps with their light at night, animals,
## field crops by season, the decor trees and hedges of the 2D map, a dock and a cart, all from the catalogues of
## LandmarkBuilder (kit/extras, kit/landmarks) and placed by data (data/pueblo_vivo.json; docs/construccion.md).
## Where things go, so that the sim's walkers never cross them:
## - on tiles nobody walks: the plaza well's tile (fountain), the board's, the yards ('#' tiles no house covers: by the
##   real footprint of each piece on pueblo.gd's lattice of free yard ground), water (pier, boat);
## - on a corner or an edge of walked tiles, with an obstacle the view steers walkers round (pueblo.gd seat_obstacles,
##   as the benches and the wayside cross): lamp posts, stone benches, the decor trees, hedges and bushes;
## - walked over: the crop beds of the fields (meta "flat").
## `--vivo=no` leaves the town as it was without any of it. check() tells how close the sim's steps come to them.

const DATA := "res://data/view3d/pueblo_vivo.json"
const QNATURE := "res://kit/q_nature/glTF/%s.gltf"
const BODY := 0.3
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var town  # the pueblo.gd node (untyped: its members are read as they are)
var cfg := {}
var items: Array = []   # every piece placed: {id, at: Vector2 (godot x/z), rot (deg), rect: Rect2 (local x/z), flat: bool}
var beasts: Array = []  # {id, still: Node3D, anim: Node3D or null, home: Vector2 (godot x/z), rot, tiles, roam, radius}
var lamps: Array = []   # {pos: Vector3, color: Color, energy, range}
var stats := {"pieces": 0, "missing": 0, "no_room": 0, "beasts": 0, "lamps": 0, "trees": 0, "crops": 0, "obstacles": 0}
var _traffic := {}
var _corners := {}
var _got_traffic := false
var _holder: Node3D
var flock: Node3D = null  # pigeons circling over the plaza by day (Flock: one draw call)
var _well_at := Vector2.INF  # plan point of the plaza's fountain
var _yard_of := {}  # house -> {Vector2i: true}: the yard tiles nearest that house
var _handled := {"bench": true, "beehive": true, "clothesline": true, "woodpile": true, "scarecrow": true,
	"planter": true, "flower_pots": true, "market_banner": true}


func _init(t) -> void:
	town = t
	if "--vivo=no" in OS.get_cmdline_user_args():
		return
	var txt := FileAccess.get_file_as_string(DATA)
	if txt == "":
		push_warning("[PuebloVivo] no %s: the town keeps its plain dressing" % DATA)
		return
	cfg = JSON.parse_string(txt)
	if LandmarkBuilder.catalog().is_empty():
		cfg = {}


func on() -> bool:
	return not cfg.is_empty()


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[PuebloVivo] " + msg)


# ---------------------------------------------------------------- pieces
func has(id: String) -> bool:
	return id != "" and not LandmarkBuilder.info(id).is_empty()


func rect_of(id: String, grow := 0.0) -> Rect2:
	## local x/z rectangle of a piece of the catalogue (its bounds in plan: x right, y back -> z = -y)
	var b: Array = LandmarkBuilder.info(id).get("bounds", [])
	if b.size() != 2:
		return Rect2(-0.4, -0.4, 0.8, 0.8).grow(grow)
	return Rect2(float(b[0][0]), -float(b[1][1]), float(b[1][0]) - float(b[0][0]), float(b[1][1]) - float(b[0][1])).grow(grow)


func spawn(id: String, plan: Vector2, rot: float, opts := {}) -> Node3D:
	var n: Node3D
	if opts.has("awning"):
		n = LandmarkBuilder.build(id, {"awning": opts.awning})  # a cloth of the kit dyed (banners)
	else:
		n = LandmarkBuilder.piece(id) if LandmarkBuilder.catalog().pieces.has(id) else LandmarkBuilder.build(id)
	if n == null:
		stats.missing += 1
		return null
	n.position = HouseBuilder.plan_to_godot(Vector3(plan.x, plan.y, float(opts.get("z", 0.0))))
	n.rotation.y = deg_to_rad(rot)
	if opts.get("flat", false):
		n.set_meta("flat", true)
	n.set_meta("vivo", id)
	var parent: Node3D = opts.get("parent", town._q)
	parent.add_child(n)
	var li: Dictionary = LandmarkBuilder.info(id).get("light", {})
	# what a walker can bump into: the whole piece, or the foot of a lamp post (its arm hangs overhead)
	var foot := float(opts.get("foot", 0.0))  # only its foot blocks (a pole: what hangs from it is overhead)
	if not li.is_empty():
		foot = 0.22
	items.append({id = id, at = Vector2(plan.x, -plan.y), rot = rot, rect = rect_of(id) if foot <= 0.0 else Rect2(-foot, -foot, foot * 2.0, foot * 2.0),
		flat = bool(opts.get("flat", false))})
	stats.pieces += 1
	if not li.is_empty():
		# the light just under the lantern (a light inside it, casting shadows, is shut in by its own cage) and the
		# glowing pane where the lantern's flame is: the catalogue's `at` and `glow` (data/pueblo_vivo.json can still
		# override them for its lamp piece with light_at / glow_at)
		var lc: Dictionary = cfg.get("lamps", {})
		var la: Array = lc.get("light_at", li.at) if String(lc.get("piece", "")) == id else li.at
		var ga: Array = lc.get("glow_at", li.get("glow", li.at)) if String(lc.get("piece", "")) == id else li.get("glow", li.at)
		lamps.append({pos = n.transform * HouseBuilder.plan_to_godot(Vector3(la[0], la[1], la[2])),
			glow = n.transform * HouseBuilder.plan_to_godot(Vector3(ga[0], ga[1], ga[2])),
			color = Color(li.color[0], li.color[1], li.color[2]), energy = float(li.get("energy", 1.0)), range = float(li.get("range", 6.0))})
		stats.lamps += 1
	return n


func _face(f: Vector2) -> float:
	## yaw (deg) that turns the front of a piece (its -y in plan) towards the plan direction f
	return rad_to_deg(f.angle()) + 90.0


func _g(plan: Vector2) -> Vector2:
	return Vector2(plan.x, -plan.y)


# ---------------------------------------------------------------- traffic of the trace
func _load_traffic() -> void:
	if _got_traffic:
		return
	_got_traffic = true
	_traffic = town._tile_traffic()
	_corners = town._corner_traffic()


func traf(t: Vector2i) -> int:
	return int(_traffic.get(t, 0))


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * k)


func _clear(p: Vector2, radius: float, skip_tile := Vector2i(-99, -99)) -> bool:
	## plan point with room for a thing of that radius: off the houses, the water, the props, the posts, and far enough
	## from the other obstacles for a walker to pass between the two
	if town._house_at_plan(p, radius + 0.1) != null or town._near_water(_g(p), radius + 0.6):
		return false
	for q: Vector2 in town._prop_spots:
		if q.distance_to(p) < radius + 0.75 and Vector2i(floori(q.x / 2.0), floori(-q.y / 2.0)) != skip_tile:
			return false
	for q: Vector2 in town._post_spots:
		if q.distance_to(p) < radius + 0.5:
			return false
	for ob in town.seat_obstacles:
		if _seg_dist(p, ob[0], ob[1]) < float(ob[2]) + radius + BODY * 2.0 + 0.1:
			return false
	return true


func _obstacle(a: Vector2, b: Vector2, radius: float) -> void:
	town.seat_obstacles.append([a, b, radius])
	stats.obstacles += 1


# ---------------------------------------------------------------- corners of walked tiles
func _corner_tiles(k: Vector2i) -> Array:
	return [Vector2i(k.x - 1, k.y - 1), Vector2i(k.x, k.y - 1), Vector2i(k.x - 1, k.y), Vector2i(k.x, k.y)]


func corner_point(k: Vector2i, radius: float) -> Vector2:
	## plan point for a thing of that radius on the corner k (where four tiles meet), INF if it has no room. Beside a yard
	## or a house it moves off the fence line towards the tiles that are walked.
	var p := Vector2(k.x * 2.0, -k.y * 2.0)
	var shift := Vector2.ZERO
	var solid := 0
	for t: Vector2i in _corner_tiles(k):
		var ch: String = town._t(t.x, t.y)
		if ch in ["w", "b", "S", "N"]:
			return Vector2.INF
		if town.walkable(t.x, t.y):
			shift += town._tp(t.x, t.y) - p
		else:
			solid += 1
	if solid == 4:
		return Vector2.INF  # no walked tile at this corner: a yard's inside
	if solid > 0 and shift != Vector2.ZERO:
		p += shift.normalized() * (radius + 0.2)
	return p if _clear(p, radius) else Vector2.INF


func corner_score(k: Vector2i) -> float:
	var s := float(_corners.get(k, 0)) * 3.0
	for t: Vector2i in _corner_tiles(k):
		s += float(traf(t)) * 0.15
	return s


func _busiest(k: Vector2i, fallback: Vector2) -> Vector2:
	## plan direction from the corner k to the street beside it: the road, path or plaza tile most walked
	var p := Vector2(k.x * 2.0, -k.y * 2.0)
	var best := fallback
	var bs := -1.0
	for t: Vector2i in _corner_tiles(k):
		if not town.walkable(t.x, t.y):
			continue
		var s := float(traf(t)) + (50.0 if town._t(t.x, t.y) in ["=", ",", "P"] else 0.0)
		if s > bs:
			bs = s
			best = (town._tp(t.x, t.y) - p).normalized()
	return best


func _post(id: String, k: Vector2i, face: Vector2, radius: float, opts := {}) -> Node3D:
	var p := corner_point(k, radius)
	if p == Vector2.INF:
		return null
	var n := spawn(id, p, _face(face), opts)
	if n:
		town._prop_spots.append(p)
		_obstacle(p, p, radius)
	return n


func _best_corner(cands: Array, radius: float, want := Vector2.INF, prefer := {}) -> Vector2i:
	var best := Vector2i(-99, -99)
	var bs := 1e9
	for k: Vector2i in cands:
		var p := corner_point(k, radius)
		if p == Vector2.INF:
			continue
		var s := corner_score(k) - float(prefer.get(k, 0.0))
		if want != Vector2.INF:
			s += p.distance_to(want) * 1.5
		if s < bs:
			bs = s
			best = k
	return best


# ---------------------------------------------------------------- the plaza well and the board
func well(p: Vector2) -> bool:
	var id := String(cfg.get("well", ""))
	if not has(id):
		return false
	spawn(id, p, 0.0)
	town._prop_spots.append(p)
	town.prop_stats.placed += 1
	_well_at = p
	_log("well: %s on the plaza well's tile" % id)
	return true


func board(c: int, r: int) -> bool:
	var id := String(cfg.get("board", ""))
	if not has(id):
		return false
	var f := Vector2(0, -1)
	var bd: Dictionary = town.mapd.get("board", {})
	if bd.has("service") and bd.has("tile") and int(bd.tile[0]) == c and int(bd.tile[1]) == r:
		f = Vector2(float(bd.service[0]) - c, -(float(bd.service[1]) - r))
	var p: Vector2 = town._tp(c, r)
	spawn(id, p, _face(f))
	town._prop_spots.append(p)
	town.prop_stats.placed += 1
	_log("board: %s on tile (%d, %d), read from %s" % [id, c, r, f])
	return true


func handles(it: Dictionary) -> bool:
	## decor items this script places (or leaves out: no piece for them) instead of pueblo.gd's own rules
	if not on():
		return false
	var id := String(it.get("id", ""))
	return String(it.get("kind", "")) == "lantern" or _handled.has(id) or id.begins_with("tree_") or id.begins_with("bush") or id.begins_with("hedge")


# ---------------------------------------------------------------- fields
func crops() -> bool:
	## a crop bed of the catalogue on every field tile, by field (a small one is a vegetable plot, a big one wheat) and
	## season; walked over. False: the town keeps its furrows.
	if not on() or not cfg.has("crops") or not has("bancal_trigo_1"):
		return false
	var cc: Dictionary = cfg.crops
	var seen := {}
	var n_field := 0
	for r in town.H:
		for c in town.W:
			var t0 := Vector2i(c, r)
			if town._t(c, r) != "f" or seen.has(t0):
				continue
			var comp := [t0]
			seen[t0] = true
			var i := 0
			while i < comp.size():
				for d: Vector2i in DIRS:
					var q: Vector2i = comp[i] + d
					if town._t(q.x, q.y) == "f" and not seen.has(q):
						seen[q] = true
						comp.append(q)
				i += 1
			var crop := String(cc.small if comp.size() <= int(cc.small_max) else cc.big)
			var phase := int(cc.phase.get(crop, {}).get(town.season_id, 1))
			n_field += 1
			var mix: Dictionary = cc.get("mix", {}).get(crop, {}).get(town.season_id, {})
			if not mix.is_empty():
				_field_mix(comp, crop, mix, n_field)
			elif phase > 0 and has("bancal_%s_%d" % [crop, phase]):
				for t: Vector2i in comp:
					spawn("bancal_%s_%d" % [crop, phase], town._tp(t.x, t.y), 90.0 * (n_field % 2), {flat = true})
					stats.crops += 1
			_log("field %d: %d tiles from %s, %s in phase %d (%s)%s" % [n_field, comp.size(), t0, crop, phase, town.season_id,
				", in strips %s" % [mix.get("strips", [])] if not mix.is_empty() else ""])
	return true

func _field_mix(comp: Array, crop: String, mix: Dictionary, n_field: int) -> void:
	## A field in strips of `rows` tiles across it, each strip one of `strips` in turn (the open field of a village, each
	## family its strip): "sown" (the crop's phase 1), "young" (phase 2 kept to `young_h` of its height: green shoots),
	## "stubble" (the harvest bed cut down to `stubble_h`: its ears still show, it reads as orange lumps), "stooks"
	## (ploughed across, a stook of sheaves on some tiles nobody walks), "plot" (a vegetable plot, phase `plot_phase`).
	## The strips run across the field's long side; the first one is shifted by field, so no two fields start alike.
	_load_traffic()
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for t: Vector2i in comp:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	var along_x := hi.x - lo.x >= hi.y - lo.y  # strips cut the long side
	var rows := maxi(1, int(mix.get("rows", 3)))
	var strips: Array = mix.get("strips", ["sown"])
	var stook := String(mix.get("stook", "gavillas"))
	var n_stooks := 0
	for t: Vector2i in comp:
		var k := ((t.x - lo.x) if along_x else (t.y - lo.y)) / rows
		var kind := String(strips[(k + n_field) % strips.size()])
		var rot := 0.0 if along_x else 90.0  # the furrows along the strip
		var at: Vector2 = town._tp(t.x, t.y)
		match kind:
			"sown":
				spawn("bancal_%s_1" % crop, at, rot, {flat = true})
			"plot":
				spawn("bancal_%s_%d" % [String(mix.get("plot", "huerta")), int(mix.get("plot_phase", 3))], at, rot, {flat = true})
			"young":  # sown early: the growing bed kept low (green shoots)
				var yn := spawn("bancal_%s_2" % crop, at, rot, {flat = true})
				if yn:
					yn.scale.y = float(mix.get("young_h", 0.45))
			_:  # stubble (the harvest bed cut low), stooks (ploughed across, with a stook here and there)
				var n := spawn("bancal_%s_%d" % [crop, 3 if kind == "stubble" else 1], at, rot + (90.0 if kind == "stooks" else 0.0), {flat = true})
				if n and kind == "stubble":
					n.scale.y = float(mix.get("stubble_h", 0.22))
				var h := absi(hash("%d,%d" % [t.x, t.y]))
				var quiet := traf(t) == 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					quiet = quiet and traf(t + d) == 0  # the steps of a walker on the next tile cut its corner
				if kind == "stooks" and has(stook) and quiet and h % int(mix.get("stook_every", 3)) == 0 and _clear(at, 0.95):
					var sn := spawn(stook, at, float(h % 4) * 90.0 + float(h % 23) - 11.0)
					if sn:
						town._prop_spots.append(at)
						_obstacle(at, at, 0.95)
						n_stooks += 1
		stats.crops += 1
	_log("field of %s in strips of %d tiles (%s): %d stooks" % [crop, rows, ", ".join(strips), n_stooks])


# ---------------------------------------------------------------- yards
func _owners() -> void:
	## every yard tile to the house nearest it (within 6 m of its walls)
	if not _yard_of.is_empty():
		return
	for t: Vector2i in town.yard_tiles:
		var p: Vector2 = town._tp(t.x, t.y)
		var best: Node3D = null
		var bd := 6.0
		for h: Node3D in town.houses:
			var wd: Vector2 = h.get_meta("wd")
			var l := h.transform.affine_inverse() * Vector3(p.x, 0, -p.y)
			var d := Vector2(maxf(absf(l.x) - wd.x / 2.0, 0.0), maxf(absf(l.z) - wd.y / 2.0, 0.0)).length()
			if d < bd:
				bd = d
				best = h
		if best != null:
			if not _yard_of.has(best):
				_yard_of[best] = {}
			_yard_of[best][t] = true


func _centre(tiles: Dictionary) -> Vector2:
	## godot x/z centre of a set of tiles
	var c := Vector2.ZERO
	for t: Vector2i in tiles:
		c += Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0)
	return c / maxf(1.0, tiles.size())


func _in_yard(id: String, want: Vector2, tiles: Dictionary, reach := 14.0, rots := [], grow := 0.0) -> Node3D:
	## the piece by its footprint in the free yard ground nearest `want` (godot x/z); null if it has no room
	if not has(id):
		stats.missing += 1
		return null
	var rc := rect_of(id, grow)
	var fit: Array = town.yard_fit(rc, want, null, reach, rots, 1.5, tiles)
	if fit.is_empty():
		stats.no_room += 1
		_log("no room in the yards for %s near %s" % [id, want])
		return null
	var at: Vector2 = fit[0]
	town.yard_take(rc, at, float(fit[1]))
	var n := spawn(id, Vector2(at.x, -at.y), float(fit[1]))
	_log("%s in a yard at tile %s, yaw %.0f" % [id, Vector2i(floori(at.x / 2.0), floori(at.y / 2.0)), float(fit[1])])
	return n


func yards() -> void:
	if not on():
		return
	_load_traffic()
	_owners()
	_holder = Node3D.new()
	_holder.name = "Animals"
	town.add_child(_holder)
	_dock()
	_trough()
	_yard_decor()
	_cart()
	for h: Node3D in town.houses:
		if String(h.get_meta("type", "")) in ["church", "mill"] or h.has_meta("stage"):
			continue
		var look := String(h.get_meta("look", h.get_meta("type", "")))
		if look == "house":
			look = "house_" + String(h.get_meta("wealth", "humble"))
		var tiles: Dictionary = _yard_of.get(h, {})
		var want := _centre(tiles) if not tiles.is_empty() else Vector2(h.position.x, h.position.z)
		for e: Dictionary in cfg.get("yards", {}).get(look, []):
			if e.has("stalls"):
				var k := 0
				for st: Dictionary in h.get_meta("stalls", []):
					var sid := String(e.stalls[k % (e.stalls as Array).size()])
					k += 1
					if has(sid):
						_beast(sid.get_slice("_", 0), sid, st.at, float(st.rot) + 180.0, {})
				continue
			var key := String(e.get("piece", e.get("beasts", "")))
			if float(absi(hash(String(h.name) + key)) % 100) >= float(e.get("chance", 1.0)) * 100.0:
				continue
			if tiles.is_empty():
				continue
			if e.has("piece"):
				_in_yard(String(e.piece), want, tiles)
			elif e.has("beasts"):
				for i in int(e.get("n", 1)):
					var stills: Array = e.get("still", [])
					var sid := String(stills[i % stills.size()]) if not stills.is_empty() else String(e.beasts)
					if not has(sid):
						continue
					var rc := rect_of(sid, 0.2)
					var yaw := float(absi(hash(String(h.name) + key + str(i))) % 360)
					var fit: Array = town.yard_fit(rc, want + Vector2(i * 0.9 - 0.9, (i % 2) * 1.1 - 0.5), null, 12.0, [yaw], 1.5, tiles)
					if fit.is_empty():
						stats.no_room += 1
						_log("no room for a %s in the yard of %s" % [e.beasts, h.name])
						continue
					town.yard_take(rc, fit[0], float(fit[1]), 0.0)
					_beast(String(e.beasts), sid, Vector2((fit[0] as Vector2).x, -(fit[0] as Vector2).y), float(fit[1]), tiles)
	_roam_yard()
	_log("yards: %d pieces so far, %d beasts, %d without room, %d ids missing" % [stats.pieces, beasts.size(), stats.no_room, stats.missing])


func _yard_decor() -> void:
	## what the 2D decor draws on yard tiles: fruit trees, hives, a clothes line, a wood pile, and its lanterns (a post
	## inside the fence, its lamp over the street)
	var dmap: Dictionary = cfg.get("decor", {})
	for it in town.mapd.get("decor", {}).get("items", []):
		if not it.has("at"):
			continue
		var t := Vector2i(int(it.at[0]), int(it.at[1]))
		var id := String(it.get("id", ""))
		var yard: bool = town.yard_tiles.has(t)
		var centre := Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0)
		if String(it.get("kind", "")) == "lantern":
			if cfg.get("lamps", {}).get("decor", false) and not town.walkable(t.x, t.y):
				_yard_lamp(t, it.get("off", [0, 0]))
		elif id.begins_with("tree_") and yard:
			_tree(it, t, true)
		elif dmap.has(id) and yard:
			_in_yard(String(dmap[id]), centre, {}, 14.0)
		elif dmap.has(id) and id in ["planter", "flower_pots"]:
			# pots and planters the 2D map draws on the grass beside a house: in the nearest free yard ground
			_in_yard(String(dmap[id]), centre, {}, 6.0)


func _yard_lamp(t: Vector2i, off: Array) -> void:
	var id := String(cfg.lamps.get("piece", ""))
	if not has(id):
		return
	var sx := 1.0 if float(off[0]) >= 0.0 else -1.0
	var best := Vector2.INF
	var face := Vector2.ZERO
	var bs := -1.0
	if town.yard_tiles.has(t):
		for d: Vector2i in DIRS:
			var o := t + d
			if not town.walkable(o.x, o.y):
				continue
			var s := float(traf(o)) + (40.0 if town._t(o.x, o.y) in ["=", ",", "P"] else 0.0)
			var al := Vector2(-d.y, d.x)  # along the edge, in godot x/z
			for k in [0.6 * sx, -0.6 * sx, 0.0]:
				var g: Vector2 = Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0) + Vector2(d) * 0.5 + Vector2(al) * k
				var ok := true
				for q in [Vector2.ZERO, Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:
					ok = ok and town.lat_open(g + q)
				if ok and s > bs:
					bs = s
					best = g
					face = Vector2(d.x, -d.y)
				if ok:
					break
	if best != Vector2.INF:
		town._mark_disc(best, 0.4)
		spawn(id, Vector2(best.x, -best.y), _face(face))
		_log("lamp inside the fence of yard tile %s, its light over the street to %s" % [t, face])
		return
	# no free ground on that tile (a house stands on it): a post on a corner of the walked tile beside it
	var cands := []
	for d: Vector2i in DIRS:
		var o := t + d
		if town.walkable(o.x, o.y):
			for k: Vector2i in [Vector2i(o.x, o.y), Vector2i(o.x + 1, o.y), Vector2i(o.x, o.y + 1), Vector2i(o.x + 1, o.y + 1)]:
				cands.append(k)
	var kc := _best_corner(cands, 0.25, town._tp(t.x, t.y))
	if kc.x > -90:
		_post(id, kc, _busiest(kc, Vector2(0, -1)), 0.25)
		_log("lamp of tile %s on the corner %s" % [t, kc])
	else:
		stats.no_room += 1


func _dock() -> void:
	## A small landing on the river: the ramp on a yard tile with water beside it (not the mill's), pier modules on the
	## water tiles along that bank and a boat moored to them.
	var dc: Dictionary = cfg.get("dock", {})
	if dc.is_empty() or not has(String(dc.get("ramp", ""))):
		return
	var best := {}
	var bs := -1e9
	for t: Vector2i in town.yard_tiles:
		for dx in [1, -1]:
			if town._t(t.x + dx, t.y) != "w" or town._t(t.x + dx, t.y - 1) != "w" or town._t(t.x + dx, t.y + 1) != "w":
				continue
			var centre := Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0)
			# the half of the tile away from the water must be free ground (pueblo.gd keeps the props off the bank)
			if not (town.lat_open(centre - Vector2(dx * 0.7, 0)) and town.lat_open(centre - Vector2(dx * 0.7, 0.6)) and town.lat_open(centre - Vector2(dx * 0.7, -0.6))):
				continue
			var s := 0.0
			for dy in range(-3, 4):  # away from the bridges
				if town._t(t.x + dx, t.y + dy) == "b":
					s -= 10.0 - absf(dy)
			s += 2.0 if town.yard_tiles.has(Vector2i(t.x, t.y - 1)) and town.yard_tiles.has(Vector2i(t.x, t.y + 1)) else 0.0
			if s > bs:
				bs = s
				best = {t = t, dx = dx}
	if best.is_empty():
		_log("dock: no yard tile with free ground and water along it")
		return
	var t: Vector2i = best.t
	var dx: int = best.dx
	var rot := _face(Vector2(dx, 0))
	var centre := Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0)
	town.yard_take(Rect2(-1.0, -1.0, 2.0, 2.0), centre, 0.0, 0.0)
	spawn(String(dc.ramp), town._tp(t.x, t.y), rot)
	var deck: Array = dc.get("deck", [])
	# along the bank: steps to the water at the north end, a plain module where the ramp lands, the mooring end south
	var rots := [rot, rot, _face(Vector2(0, -1))]
	for i in mini(3, deck.size()):
		if has(String(deck[i])):
			spawn(String(deck[i]), town._tp(t.x + dx, t.y - 1 + i), rots[i])
	if has(String(dc.get("boat", ""))) and town._t(t.x + dx * 2, t.y) == "w":
		var bp: Vector2 = town._tp(t.x + dx, t.y) + Vector2(dx * 1.78, -0.4)
		spawn(String(dc.boat), bp, 180.0 if dx > 0 else 0.0, {z = 0.06})
	_log("dock: ramp on yard tile %s, pier on the water at column %d, boat beside it" % [t, t.x + dx])


func _trough() -> void:
	## The trough set into the fence of a yard, on an edge of two tiles that faces a street: it takes the place of those
	## two fence pieces, the beasts drink from the street. The nearest such edge to the middle of the plaza, first the
	## sides the camera looks at.
	var id := String(cfg.get("trough", {}).get("piece", ""))
	if not has(id):
		return
	var by := {}  # "tile|edge" -> fence entry
	for f: Dictionary in town._fence_pieces:
		if is_instance_valid(f.node) and not f.get("gate", false):
			by["%s|%s" % [f.tile, f.edge]] = f
	var plaza := _plaza_box()
	var mid := Vector2(plaza.get_center()) * 2.0  # godot x/z
	var cam_dir := Vector2(sin(deg_to_rad(town.home_yaw)), cos(deg_to_rad(town.home_yaw)))  # godot x/z, from the town towards the camera
	var best := {}
	var bs := 1e9
	var rc := rect_of(id)
	for key: String in by:
		var f: Dictionary = by[key]
		var t: Vector2i = f.tile
		var e: Vector2i = f.edge
		var al := Vector2i(absi(e.y), absi(e.x))
		var g: Dictionary = by.get("%s|%s" % [t + al, e], {})
		if g.is_empty():
			continue
		if not (town._t(t.x + e.x, t.y + e.y) in ["=", ",", "P", "."]) or not (town._t(t.x + al.x + e.x, t.y + al.y + e.y) in ["=", ",", "P", "."]):
			continue
		var at := Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0) + Vector2(al) * 1.0 + Vector2(e) * 0.5
		var rot := _face(Vector2(e.x, -e.y))
		# the fence pieces themselves hold the lattice cells of the edge: the ground behind them must be free
		var ok: bool = town.lat_open(at - Vector2(e) * 0.25) and town.lat_open(at - Vector2(e) * 0.25 + Vector2(al) * 1.2) and town.lat_open(at - Vector2(e) * 0.25 - Vector2(al) * 1.2)
		if not ok:
			continue
		var s := at.distance_to(mid) - Vector2(e).dot(cam_dir) * 6.0 + float(traf(t + e) + traf(t + al + e)) * 0.05
		if s < bs:
			bs = s
			best = {a = f, b = g, at = at, rot = rot, e = e}
	if best.is_empty():
		stats.no_room += 1
		_log("trough: no yard edge of two tiles facing a street")
		return
	for f in [best.a, best.b]:
		(f.node as Node3D).free()
	town.yard_take(rc, best.at, best.rot, 0.1)
	spawn(id, Vector2(best.at.x, -best.at.y), best.rot)
	_log("trough: %s set into the yard edge at %s facing %s (%.0f m from the middle of the plaza)" % [id, best.at, best.e, (best.at as Vector2).distance_to(mid)])


func _plaza_box() -> Rect2i:
	var box := Rect2i()
	var first := true
	for r in town.H:
		for c in town.W:
			if town._t(c, r) in ["P", "S", "N"]:
				box = Rect2i(c, r, 1, 1) if first else box.expand(Vector2i(c, r)).expand(Vector2i(c + 1, r + 1))
				first = false
	return box


func _cart() -> void:
	## a cart and the beast that pulls it, standing in the yard nearest the market stalls where they fit
	var cc: Dictionary = cfg.get("cart", {})
	if cc.is_empty() or not has(String(cc.get("piece", ""))):
		return
	if cfg.has("convoy") and town.has_method("real_per_game_minute") and not "--simcheck" in OS.get_cmdline_user_args():
		_log("cart: none parked, one crosses the town along the road (scripts/cart_trip.gd)")
		return
	var want := Vector2.ZERO
	var n := 0
	for id in town.mapd.get("stalls", {}):
		var st: Dictionary = town.mapd.stalls[id]
		if st.has("tile"):
			want += Vector2(float(st.tile[0]) * 2.0 + 1.0, float(st.tile[1]) * 2.0 + 1.0)
			n += 1
	if n == 0:
		return
	want /= n
	# the nearest yard where it fits, first the ones no house hides from the camera
	var rc0 := rect_of(String(cc.piece))
	var best_fit := []
	var bs := 1e9
	for h: Node3D in _yard_of:
		var fit0: Array = town.yard_fit(rc0, want, null, 40.0, [], 1.5, _yard_of[h])
		if fit0.is_empty():
			continue
		var s := (fit0[0] as Vector2).distance_to(want) + (30.0 if _hidden(fit0[0]) else 0.0)
		if s < bs:
			bs = s
			best_fit = fit0
	if best_fit.is_empty():
		stats.no_room += 1
		_log("cart: no yard has room for %s" % cc.piece)
		return
	town.yard_take(rc0, best_fit[0], float(best_fit[1]))
	var cart := spawn(String(cc.piece), Vector2((best_fit[0] as Vector2).x, -(best_fit[0] as Vector2).y), float(best_fit[1]))
	if cart == null:
		return
	var still := String(cc.get("still", ""))
	if has(still):
		var rc := rect_of(still, 0.15)
		var at := Vector2(cart.position.x, cart.position.z)
		var fit: Array = town.yard_fit(rc, at, null, 6.0, [rad_to_deg(cart.rotation.y) + 90.0, rad_to_deg(cart.rotation.y)])
		if fit.is_empty():
			stats.no_room += 1
			_log("cart: no room for its %s beside it" % cc.get("beast", ""))
		else:
			town.yard_take(rc, fit[0], float(fit[1]), 0.0)
			_beast(String(cc.get("beast", "")), still, Vector2((fit[0] as Vector2).x, -(fit[0] as Vector2).y), float(fit[1]), {})
	_log("cart: %s on tile %s, %.0f m from the middle of the market" % [cc.piece, Vector2i(floori(cart.position.x / 2.0), floori(cart.position.z / 2.0)), Vector2(cart.position.x, cart.position.z).distance_to(want)])


func _hidden(g: Vector2) -> bool:
	## godot x/z point with a house within 6 m between it and the camera of the town's default view
	var cam_dir := Vector2(sin(deg_to_rad(town.home_yaw)), cos(deg_to_rad(town.home_yaw)))
	for s in range(1, 13):
		var q := g + cam_dir * 0.5 * s
		if town._house_at_plan(Vector2(q.x, -q.y), 0.0) != null:
			return true
	return false


# ---------------------------------------------------------------- beasts
func _beast(id: String, still_id: String, plan: Vector2, rot: float, tiles: Dictionary, roam := "") -> Dictionary:
	## an animal: its still pose (a plain mesh; the same pose of several is one draw call per pass) and, when the
	## catalogue has the animated one, that too, hidden until the camera is near (Life)
	var still := LandmarkBuilder.piece(still_id)
	if still == null:
		stats.missing += 1
		return {}
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "Animals"
		town.add_child(_holder)
	still.position = Vector3(plan.x, town.GROUND_Y, -plan.y)
	still.rotation.y = deg_to_rad(rot)
	_holder.add_child(still)
	var anim: Node3D = null
	if has(id) and String(LandmarkBuilder.info(id).get("kind", "")) == "animal" and DisplayServer.get_name() != "headless":
		anim = LandmarkBuilder.animal(id, "quieto")
		if anim:
			anim.visible = false
			anim.position = still.position
			anim.rotation.y = still.rotation.y
			_holder.add_child(anim)
			var ap := anim.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap:
				ap.pause()
	var rc := rect_of(still_id)
	var b := {id = id, still = still, anim = anim, home = Vector2(plan.x, -plan.y), rot = rot, tiles = tiles, roam = roam,
		radius = maxf(rc.size.x, rc.size.y) / 2.0, spots = [], speed = float(LandmarkBuilder.info(id).get("walk_speed", 0.5))}
	beasts.append(b)
	stats.beasts += 1
	return b


func _roam_yard() -> void:
	## the loose animals that live in a yard (the cat): the first yard of the kinds asked with room
	for e: Dictionary in cfg.get("beasts", {}).get("roam", []):
		var where := String(e.get("where", ""))
		if not where.begins_with("yard:") or not has(String(e.get("still", ""))):
			continue
		var kinds := where.trim_prefix("yard:").split(",")
		var plaza := Vector2(_plaza_box().get_center()) * 2.0
		var best: Node3D = null
		var bd := 1e9
		for h: Node3D in _yard_of:
			if String(h.get_meta("look", "")) in kinds and Vector2(h.position.x, h.position.z).distance_to(plaza) < bd:
				bd = Vector2(h.position.x, h.position.z).distance_to(plaza)
				best = h
		if best == null:
			continue
		var tiles: Dictionary = _yard_of[best]
		var rc := rect_of(String(e.still), 0.15)
		var fit: Array = town.yard_fit(rc, _centre(tiles), null, 12.0, [40.0], 1.5, tiles)
		if fit.is_empty():
			stats.no_room += 1
			continue
		town.yard_take(rc, fit[0], float(fit[1]), 0.0)
		_beast(String(e.id), String(e.still), Vector2((fit[0] as Vector2).x, -(fit[0] as Vector2).y), float(fit[1]), tiles)
		_log("%s in the yard of %s" % [e.id, best.name])


func _roam_plaza() -> void:
	## the loose animals of the plaza (the dog): it trots from corner to corner of the plaza tiles, where nobody stands
	for e: Dictionary in cfg.get("beasts", {}).get("roam", []):
		if String(e.get("where", "")) != "plaza" or not has(String(e.get("still", ""))):
			continue
		var box := _plaza_box()
		var grid := {}
		for r in range(box.position.y + 1, box.end.y):
			for c in range(box.position.x + 1, box.end.x):
				var k := Vector2i(c, r)
				var ok := true
				for t: Vector2i in _corner_tiles(k):
					ok = ok and town._t(t.x, t.y) == "P" and town.walkable(t.x, t.y)
				if ok and _clear(Vector2(c * 2.0, -r * 2.0), 0.3):
					grid[k] = true
		var start := _best_corner(grid.keys(), 0.3, Vector2(box.get_center().x * 2.0, -box.get_center().y * 2.0))
		if start.x < -90:
			stats.no_room += 1
			continue
		var b := _beast(String(e.id), String(e.still), Vector2(start.x * 2.0, -start.y * 2.0), 30.0, {}, "grid")
		if not b.is_empty():
			b["grid"] = grid
			b["cell"] = start
		_log("%s loose on %d corners of the plaza, from %s" % [e.id, grid.size(), start])


# ---------------------------------------------------------------- street: lamps, benches, hedges, bushes
func street() -> void:
	if not on():
		return
	_load_traffic()
	var lc: Dictionary = cfg.get("lamps", {})
	var lamp := String(lc.get("piece", ""))
	var n_lamp := 0
	var n_banner := 0
	for it in town.mapd.get("decor", {}).get("items", []):
		if not it.has("at"):
			continue
		var t := Vector2i(int(it.at[0]), int(it.at[1]))
		var id := String(it.get("id", ""))
		var off: Array = it.get("off", [0, 0]) if it.get("off") is Array else [0, 0]
		if String(it.get("kind", "")) == "lantern":
			if has(lamp) and lc.get("decor", false) and town.walkable(t.x, t.y):
				var prefer := {Vector2i(t.x + (1 if float(off[0]) > 0 else 0), t.y + (1 if float(off[1]) > 0 else 0)): 1.0}
				var k := _best_corner([t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)], 0.25, Vector2.INF, prefer)
				if k.x > -90 and _post(lamp, k, _busiest(k, Vector2(0, -1)), 0.25) != null:
					n_lamp += 1
				else:
					stats.no_room += 1
					_log("lamp: no corner of tile %s has room" % t)
		elif id == "bench" and town.walkable(t.x, t.y):
			_bench(t)
		elif id.begins_with("hedge") and town.walkable(t.x, t.y):
			_hedge(t)
		elif id.begins_with("bush") and town.walkable(t.x, t.y):
			_bush(t, off)
		elif id == "market_banner" and town.walkable(t.x, t.y) and has(String(cfg.get("decor", {}).get(id, ""))):
			# a banner on a pole on a corner of its tile, the cloth dyed in turn with the colours of the market
			var cols: Array = cfg.get("banner_colors", [[0.62, 0.16, 0.12]])
			var col: Array = cols[n_banner % cols.size()]
			n_banner += 1
			# not in the middle of the road that crosses the town (the cart goes along it: scripts/cart_trip.gd)
			var cands := []
			for k0: Vector2i in [t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)]:
				if not (_through_row(k0.y - 1) and _through_row(k0.y)):
					cands.append(k0)
			var k := _best_corner(cands, 0.3)
			if k.x > -90 and _post(String(cfg.decor[id]), k, _busiest(k, Vector2(0, -1)), 0.3, {"awning": Color(col[0], col[1], col[2]), "foot": 0.2}) != null:
				_log("market banner %s on the corner %s of tile %s" % [cfg.decor[id], k, t])
			else:
				stats.no_room += 1
				_log("market banner: no corner of tile %s has room" % t)
		elif id == "scarecrow" and town.walkable(t.x, t.y) and has(String(cfg.get("decor", {}).get(id, ""))):
			var k := _best_corner([t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)], 0.3)
			if k.x > -90:
				_post(String(cfg.decor[id]), k, Vector2(0, -1), 0.3)
	# the plaza: a post on each corner, then on the middle of its long sides
	var box := _plaza_box()
	var want := int(lc.get("plaza", 0))
	if has(lamp) and want > 0 and box.size.x > 0:
		var pts := [box.position, Vector2i(box.end.x, box.position.y), box.end, Vector2i(box.position.x, box.end.y)]
		var long_x := box.size.x >= box.size.y
		var m := (box.position + box.end) / 2
		pts.append_array([Vector2i(m.x, box.position.y), Vector2i(m.x, box.end.y)] if long_x else [Vector2i(box.position.x, m.y), Vector2i(box.end.x, m.y)])
		pts.append_array([Vector2i(box.position.x, m.y), Vector2i(box.end.x, m.y)] if long_x else [Vector2i(m.x, box.position.y), Vector2i(m.x, box.end.y)])
		var centre := Vector2(box.get_center().x * 2.0, -box.get_center().y * 2.0)
		for i in mini(want, pts.size()):
			var c: Vector2i = pts[i]
			var cands := []
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					cands.append(c + Vector2i(dx, dy))
			var k := _best_corner(cands, 0.25, Vector2(c.x * 2.0, -c.y * 2.0))
			if k.x > -90 and _post(lamp, k, (centre - Vector2(k.x * 2.0, -k.y * 2.0)).normalized(), 0.25) != null:
				n_lamp += 1
			else:
				stats.no_room += 1
				_log("lamp: no corner round the plaza point %s has room" % c)
	# the middle of the plaza: a post on a corner of the fountain's tile (the plaza lamps stand round its edge and
	# leave the middle dark at night)
	if has(lamp) and lc.get("well_lamp", false) and _well_at != Vector2.INF:
		var wt := Vector2i(floori(_well_at.x / 2.0), floori(-_well_at.y / 2.0))
		var k := _best_corner([wt, wt + Vector2i(1, 0), wt + Vector2i(0, 1), wt + Vector2i(1, 1)], 0.25)
		if k.x > -90 and _post(lamp, k, (_well_at - Vector2(k.x * 2.0, -k.y * 2.0)).normalized(), 0.25) != null:
			n_lamp += 1
			_log("lamp by the fountain on the corner %s" % k)
		else:
			stats.no_room += 1
			_log("lamp: no corner of the fountain's tile %s has room" % wt)
	# pigeons over the plaza (one draw call; they roost at night: Life hides them)
	var fc: Dictionary = cfg.get("flock", {})
	if not fc.is_empty() and box.size.x > 0:
		flock = Flock.make(int(fc.get("n", 14)), fc)
		var c := box.get_center()
		flock.position = Vector3(c.x * 2.0, 0.0, c.y * 2.0)
		town.add_child(flock)
		_log("flock: %d pigeons over the plaza at %s" % [int(fc.get("n", 14)), flock.position])
	_roam_plaza()
	_log("street: %d lamp posts on corners (%d lamps in all), %d obstacles for the walkers" % [n_lamp, lamps.size(), stats.obstacles])


func _through_row(r: int) -> bool:
	## a row of tiles that is all road, plaza or bridge from one edge of the map to the other
	if r < 0 or r >= town.H:
		return false
	for c in town.W:
		if not String(town._t(c, r)) in ["=", ",", "P", "b", "#"]:
			return false
	return true


func _edge_spot(t: Vector2i, half_len: float, half_depth: float) -> Dictionary:
	## where a long thing goes on the walked tile t: against the side that is not walked (a wall, a fence, the well) or,
	## without one, on the edge it shares with its least walked neighbour. {mid: plan, along: plan dir, out: plan dir
	## (towards the tile), solid: bool}; {} if no side has room.
	var best := {}
	var bs := 1e9
	for d: Vector2i in DIRS:
		var o := t + d
		var ch: String = town._t(o.x, o.y)
		if ch in ["w", "b"]:
			continue
		var solid: bool = not town.walkable(o.x, o.y)
		var dv := Vector2(d.x, -d.y)
		var along := Vector2(-dv.y, dv.x)
		var mid: Vector2 = town._tp(t.x, t.y) + dv * ((1.0 - half_depth - 0.03) if solid else 1.0)
		var ok := true
		for k in [-half_len + 0.2, 0.0, half_len - 0.2]:
			ok = ok and _clear(mid + along * k, half_depth, o)
		if not ok:
			continue
		var s := -40.0 if solid else float(traf(o))
		s += float(_corners.get(Vector2i(t.x + maxi(d.x, 0), t.y + maxi(d.y, 0)), 0))
		if s < bs:
			bs = s
			best = {mid = mid, along = along, out = -dv, solid = solid}
	return best


func _bench(t: Vector2i) -> void:
	var id := String(cfg.get("benches", {}).get("piece", ""))
	if not has(id):
		return
	var e := _edge_spot(t, 0.95, 0.27)
	if e.is_empty():
		stats.no_room += 1
		_log("bench: no side of tile %s has room" % t)
		return
	var mid: Vector2 = e.mid
	spawn(id, mid, _face(e.out))
	town._prop_spots.append(mid)
	_obstacle(mid - (e.along as Vector2) * 0.75, mid + (e.along as Vector2) * 0.75, 0.3)
	_log("bench: %s on tile %s, %s, looking %s" % [id, t, "against what stands beside it" if e.solid else "on the edge with its quietest neighbour", e.out])


func _hedge(t: Vector2i) -> void:
	var hc: Dictionary = cfg.get("hedge", {})
	var end := String(hc.get("end", ""))
	if not has(end):
		return
	var e := _edge_spot(t, 1.0, 0.33)
	if e.is_empty():
		stats.no_room += 1
		return
	var mid: Vector2 = e.mid
	var al: Vector2 = e.along
	var a := rad_to_deg(al.angle())
	spawn(end, mid + al * 0.5, a)
	spawn(end, mid - al * 0.5, a + 180.0)
	town._prop_spots.append(mid)
	_obstacle(mid - al * 0.85, mid + al * 0.85, 0.33)
	_log("hedge on tile %s along %s" % [t, al])


func _bush(t: Vector2i, off: Array) -> void:
	var names: Array = cfg.get("bush", [])
	if names.is_empty():
		return
	var k := _best_corner([t, t + Vector2i(1, 0), t + Vector2i(0, 1), t + Vector2i(1, 1)], 0.45)
	if k.x < -90:
		stats.no_room += 1
		return
	var p := corner_point(k, 0.45)
	var path := QNATURE % String(names[absi(hash(t)) % names.size()])
	if not ResourceLoader.exists(path):
		stats.missing += 1
		return
	var n: Node3D = load(path).instantiate()
	n.position = HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))
	n.rotation.y = float(absi(hash(t)) % 628) / 100.0
	n.add_to_group("tree")
	town.add_child(n)
	town._prop_spots.append(p)
	_obstacle(p, p, 0.45)
	stats.trees += 1


# ---------------------------------------------------------------- the decor trees of the 2D map
func trees() -> void:
	if not on() or not cfg.has("trees"):
		return
	_load_traffic()
	var n := 0
	for it in town.mapd.get("decor", {}).get("items", []):
		if not it.has("at") or not String(it.get("id", "")).begins_with("tree_"):
			continue
		var t := Vector2i(int(it.at[0]), int(it.at[1]))
		if town.yard_tiles.has(t):
			continue  # planted with the yards
		if _tree(it, t, false):
			n += 1
	_log("trees: %d decor trees on their tiles (%d in all with the yards')" % [n, stats.trees])


func _tree(it: Dictionary, t: Vector2i, in_yard: bool) -> bool:
	var parts := String(it.id).split("_")
	var fam := String(parts[1]) if parts.size() > 1 else ""
	var variant := int(parts[2]) if parts.size() > 2 else 0
	var opts: Array = cfg.trees.get(fam, [])
	if opts.is_empty():
		stats.missing += 1
		return false
	var p: Vector2
	if in_yard:
		var g := Vector2(t.x * 2.0 + 1.0, t.y * 2.0 + 1.0)
		var fit: Array = town.yard_fit(Rect2(-0.35, -0.35, 0.7, 0.7), g, null, 2.5, [0.0])
		if fit.is_empty():
			stats.no_room += 1
			return false
		town.yard_take(Rect2(-0.35, -0.35, 0.7, 0.7), fit[0], 0.0)
		p = Vector2((fit[0] as Vector2).x, -(fit[0] as Vector2).y)
	else:
		if not town.walkable(t.x, t.y):
			return false
		# in its tile, towards the corner fewest diagonal steps cut; a walker on the tile's centre passes 0.9 m from it
		var best := Vector2.INF
		var bs := 1e9
		var off: Array = it.get("off", [0, 0]) if it.get("off") is Array else [0, 0]
		for sy in [-1, 1]:
			for sx in [-1, 1]:
				var q: Vector2 = town._tp(t.x, t.y) + Vector2(sx, -sy) * 0.66
				if not _clear(q, 0.3):
					continue
				var k := Vector2i(t.x + maxi(sx, 0), t.y + maxi(sy, 0))
				var s := corner_score(k) - (0.2 if signf(float(off[0])) == sx else 0.0) - (0.2 if signf(float(off[1])) == sy else 0.0)
				for ct: Vector2i in _corner_tiles(k):
					if town._t(ct.x, ct.y) in ["=", ",", "P", "b", "w"]:
						s += 4.0  # not over a road or the bank
				if s < bs:
					bs = s
					best = q
		if best == Vector2.INF:
			stats.no_room += 1
			return false
		p = best
		town._prop_spots.append(p)
		_obstacle(p, p, 0.3)
	var pick := String(opts[variant % opts.size()])
	var n: Node3D
	if pick.begins_with("q:"):
		var path := QNATURE % pick.trim_prefix("q:")
		if not ResourceLoader.exists(path):
			stats.missing += 1
			return false
		n = load(path).instantiate()
	else:
		var tf := pick.get_slice(":", 1)
		var idx := int(pick.get_slice(":", 2)) if pick.get_slice_count(":") > 2 else variant % 3
		town._tree_materials(tf)
		n = load("res://kit/trees/%s_%d.glb" % [tf, idx]).instantiate()
		town._skin_tree(n, tf)
	var h := absi(hash(t))
	var yaw := float(h % 628) / 100.0
	var sc := 0.85 + float(h % 26) / 100.0
	if in_yard:
		sc = minf(sc, 0.9)
	n.position = HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))
	n.rotation.y = yaw
	n.scale = Vector3.ONE * sc
	n.add_to_group("tree")
	town.add_child(n)
	stats.trees += 1
	var fr: Dictionary = cfg.get("fruit", {}).get(fam, {})
	if not fr.is_empty() and String(town.season_id) in fr.get("seasons", []) and has(String(fr.piece)):
		var f := LandmarkBuilder.piece(String(fr.piece))
		f.transform = n.transform
		f.set_meta("flat", true)  # hangs in the crown
		town._q.add_child(f)
	return true


# ---------------------------------------------------------------- life: lamps by the hour, beasts near the camera
var fiestas: Node3D  # the festivals and events of the trace in the town (scripts/fiestas_pueblo.gd)


func live() -> void:
	fiestas = preload("res://game/world3d/town/fiestas_pueblo.gd").new()
	town.add_child(fiestas)
	fiestas.setup(town)
	if not on() or DisplayServer.get_name() == "headless" or (lamps.is_empty() and beasts.is_empty()):
		return
	# where each yard beast may wander: free ground of its yard within a few steps, in a straight line from its place
	for b: Dictionary in beasts:
		if b.anim == null or (b.tiles as Dictionary).is_empty():
			continue
		var home: Vector2 = b.home
		var r0: float = b.radius + 0.25
		for i in 24:
			var a := float(i) * 0.83
			var q := home + Vector2(cos(a), sin(a)) * (0.8 + float(i % 4) * 0.5)
			if not (b.tiles as Dictionary).has(Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))):
				continue
			var ok := true
			var steps := int(ceil(home.distance_to(q) / 0.2))
			for s in range(1, steps + 1):
				var m := home.lerp(q, float(s) / steps)
				if m.distance_to(home) > r0:
					ok = ok and town.lat_open(m) and town.lat_open(m + Vector2(0.22, 0)) and town.lat_open(m - Vector2(0.22, 0)) and town.lat_open(m + Vector2(0, 0.22)) and town.lat_open(m - Vector2(0, 0.22))
			if ok:
				(b.spots as Array).append(q)
			if (b.spots as Array).size() >= 4:
				break
	var life := VivoLife.new()
	life.name = "Life"
	life.vivo = self
	life.town = town
	town.add_child(life)
	life.setup()
	_log("life: %d lamps (%d may cast shadows), %d beasts (%d can be animated, %d at once)" % [lamps.size(), int(cfg.get("lamps", {}).get("shadows", 0)),
		beasts.size(), beasts.filter(func(b): return b.anim != null).size(), int(cfg.get("beasts", {}).get("max_animated", 8))])


class VivoLife extends Node3D:
	var vivo
	var town
	var lights: Array = []
	var glow: StandardMaterial3D
	var max_anim := 8
	var anim_zoom := 30.0
	var shadows := 2
	var shadow_zoom := 30.0
	var energy := 1.6
	var _dark := -1.0
	var _acc := 0.0
	var _rng := RandomNumberGenerator.new()
	var stats := {"animated": 0, "shadow_lamps": 0}


	func setup() -> void:
		_rng.seed = 77
		var lc: Dictionary = vivo.cfg.get("lamps", {})
		var bc: Dictionary = vivo.cfg.get("beasts", {})
		max_anim = int(bc.get("max_animated", 8))
		anim_zoom = float(bc.get("anim_zoom", 30.0))
		shadows = int(lc.get("shadows", 2))
		shadow_zoom = float(lc.get("shadow_zoom", 30.0))
		energy = float(lc.get("energy", 1.6))
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--farolas="):  # --farolas=0 | sombra:<n>: lamps off, or how many cast shadows
				var v := a.trim_prefix("--farolas=")
				if v.begins_with("sombra:"):
					shadows = int(v.trim_prefix("sombra:"))
				elif v == "0":
					energy = 0.0
			elif a.begins_with("--animales="):  # --animales=<n>: how many are animated at once (0: all still)
				max_anim = int(a.trim_prefix("--animales="))
		if vivo.lamps.is_empty():
			return
		glow = StandardMaterial3D.new()
		glow.albedo_color = Color(0.9, 0.7, 0.4)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.72, 0.36)
		glow.emission_energy_multiplier = 0.0
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.28, 0.2)
		box.material = glow
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = vivo.lamps.size()
		for i in vivo.lamps.size():
			var l: Dictionary = vivo.lamps[i]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, l.glow))
			var o := OmniLight3D.new()
			o.position = l.pos
			o.light_color = l.color
			o.omni_range = l.range
			o.light_energy = 0.0
			o.visible = false
			o.shadow_enabled = false
			o.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			add_child(o)
			lights.append(o)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LampGlow"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


	func _process(dt: float) -> void:
		var dark := 0.0
		if town.has_method("daylight") and "t_min" in town:
			dark = clampf((1.0 - town.daylight(town.t_min)) * 1.6 - 0.3, 0.0, 1.0)
		if absf(dark - _dark) > 0.01:
			_dark = dark
			for o: OmniLight3D in lights:
				o.visible = dark > 0.02 and energy > 0.0
				o.light_energy = energy * dark
			if vivo.flock:
				vivo.flock.visible = dark < 0.3
			if glow:
				glow.emission_energy_multiplier = 5.0 * dark
				get_node("LampGlow").visible = dark > 0.02 and energy > 0.0
		_acc += dt
		if _acc >= 0.3:
			_acc = 0.0
			_pick()
		for b: Dictionary in vivo.beasts:
			if b.get("on", false):
				_move(b, dt)


	func _pick() -> void:
		var tg := Vector2(town.target.x, town.target.z)
		var size: float = town.cam.size
		# the lit lamps nearest the camera cast shadows, at game zoom only
		var want := shadows if (_dark > 0.5 and size <= shadow_zoom) else 0
		var order := range(lights.size())
		if want > 0:
			order.sort_custom(func(a: int, b: int) -> bool:
				return Vector2(lights[a].position.x, lights[a].position.z).distance_squared_to(tg) < Vector2(lights[b].position.x, lights[b].position.z).distance_squared_to(tg))
		for i in order.size():
			(lights[order[i]] as OmniLight3D).shadow_enabled = i < want
		stats.shadow_lamps = mini(want, lights.size())
		# the beasts nearest the camera move; the rest, and all of them from afar, are their still pose
		var near := []
		if size <= anim_zoom and max_anim > 0:
			for b: Dictionary in vivo.beasts:
				if b.anim != null:
					var pos := Vector2((b.anim as Node3D).position.x, (b.anim as Node3D).position.z) if b.get("on", false) else (b.home as Vector2)
					var d := pos.distance_to(tg)
					if d < size * 1.2:
						near.append([d, b])
			near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var chosen := {}
		for i in mini(max_anim, near.size()):
			chosen[near[i][1].still] = true
		var n := 0
		for b: Dictionary in vivo.beasts:
			if b.anim == null:
				continue
			var on: bool = chosen.has(b.still)
			if on != bool(b.get("on", false)):
				_switch(b, on)
			n += int(on)
		stats.animated = n


	func _switch(b: Dictionary, on: bool) -> void:
		var still: Node3D = b.still
		var anim: Node3D = b.anim
		b["on"] = on
		if on:
			anim.position = still.position
			anim.rotation.y = still.rotation.y
			anim.visible = true
			still.visible = false
			b["state"] = "idle"
			b["timer"] = _rng.randf_range(1.0, 5.0)
			LandmarkBuilder.play(anim, "comer" if String(still.name).contains("com") or String(still.name).contains("picot") else "quieto")
		else:
			still.position = anim.position
			still.rotation.y = anim.rotation.y
			still.visible = true
			anim.visible = false
			var ap := anim.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap:
				ap.pause()
			# back home next time it wakes far from it? it stays where it was left: the still pose stands there


	func _move(b: Dictionary, dt: float) -> void:
		var anim: Node3D = b.anim
		if String(b.state) == "walk":
			var to: Vector2 = b.to
			var pos := Vector2(anim.position.x, anim.position.z)
			var d := to - pos
			var step: float = float(b.speed) * dt
			if d.length() <= step:
				anim.position = Vector3(to.x, anim.position.y, to.y)
				b.state = "idle"
				b.timer = _rng.randf_range(2.0, 7.0)
				LandmarkBuilder.play(anim, "comer" if _rng.randf() < 0.55 else "quieto")
				return
			var dir := d.normalized()
			anim.position += Vector3(dir.x, 0, dir.y) * step
			anim.rotation.y = lerp_angle(anim.rotation.y, atan2(dir.x, dir.y), 1.0 - exp(-dt * 6.0))
			return
		b.timer = float(b.timer) - dt
		if float(b.timer) > 0.0:
			return
		var to := Vector2.INF
		if String(b.roam) == "grid":
			var cell: Vector2i = b.cell
			var opts := []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if (b.grid as Dictionary).has(cell + d):
					opts.append(cell + d)
			if not opts.is_empty():
				var nc: Vector2i = opts[_rng.randi() % opts.size()]
				b.cell = nc
				to = Vector2(nc.x * 2.0, nc.y * 2.0)
		else:
			var spots: Array = (b.spots as Array) + [b.home]
			var pos := Vector2(anim.position.x, anim.position.z)
			# only back and forth through its own place: the ways from there are the ones checked
			to = b.home if pos.distance_to(b.home) > 0.1 else spots[_rng.randi() % spots.size()]
			if to.distance_to(pos) < 0.1:
				to = Vector2.INF
		if to == Vector2.INF or _rng.randf() < 0.35:
			b.timer = _rng.randf_range(3.0, 8.0)
			LandmarkBuilder.play(anim, "comer" if _rng.randf() < 0.5 else "quieto")
			return
		b.state = "walk"
		b.to = to
		LandmarkBuilder.play(anim, "andar")


# ---------------------------------------------------------------- check (sim3d --simcheck)
func check(points: Array) -> Dictionary:
	## How the sim's walkers (plan points along every step, already steered round the obstacles) stand to the pieces:
	## how many points fall within a body's radius of a footprint (it should be none) and the nearest any comes.
	var grid := {}
	for it: Dictionary in items:
		if it.flat:
			continue
		var rc: Rect2 = it.rect
		var rad := maxf(maxf(absf(rc.position.x), absf(rc.end.x)), maxf(absf(rc.position.y), absf(rc.end.y))) + BODY + 0.2
		var at: Vector2 = it.at
		for cx in range(floori((at.x - rad) / 2.0), floori((at.x + rad) / 2.0) + 1):
			for cy in range(floori((at.y - rad) / 2.0), floori((at.y + rad) / 2.0) + 1):
				var k := Vector2i(cx, cy)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(it)
	var hits := {}
	var nearest := 99.0
	var nearest_id := ""
	for p: Vector2 in points:
		var g := Vector2(p.x, -p.y)
		for it: Dictionary in grid.get(Vector2i(floori(g.x / 2.0), floori(g.y / 2.0)), []):
			var a := deg_to_rad(float(it.rot))
			var d: Vector2 = g - (it.at as Vector2)
			# world -> local of a node turned a about y: x = dx cos - dz sin, z = dx sin + dz cos
			var l := Vector2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a))
			var rc: Rect2 = it.rect
			var out := Vector2(maxf(maxf(rc.position.x - l.x, l.x - rc.end.x), 0.0), maxf(maxf(rc.position.y - l.y, l.y - rc.end.y), 0.0)).length()
			if out < nearest:
				nearest = out
				nearest_id = String(it.id)
			if out < BODY - 0.08:
				hits[String(it.id)] = int(hits.get(String(it.id), 0)) + 1
	return {"pieces": items.size(), "points": points.size(), "inside_a_piece": hits, "nearest_m": snappedf(nearest, 0.01), "nearest": nearest_id,
		"stats": stats}
