extends RefCounted
## A cart with its beast that comes into the town along the main road and goes out at the other end, by the clock of
## the sim (sim3d.gd): a trip one way in the morning and back in the afternoon (data/pueblo_vivo.json, `convoy`).
## The road is the row pair of road tiles that crosses the whole map (town_e: rows 18-19, over the plaza and the
## bridge); the cart keeps to the lateral offset with most room from the props, posts and benches beside it, and
## starts and ends `outside` metres past the edge of the map. Walkers are pushed aside as it passes (sim3d.avoid:
## the cart is a moving capsule), so it never runs over anyone. Each way is its own Convoy (scripts/convoy.gd), only
## one shown at a time; when no trip is on, nothing is drawn.

const ConvoyScript := preload("res://game/world3d/town/convoy.gd")

var town  # the sim3d.gd node
var cfg := {}
var trips: Array = []   # {convoy, from_min (minute of day), dur (min), len (m)}
var capsule := []       # [a, b, radius] in plan coordinates while a trip is on, else []
var speed := 0.8        # m per game minute
var _shown: Node3D = null
var _anim := ""
var verbose := false


func _init(t, c: Dictionary) -> void:
	town = t
	cfg = c


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[CartTrip] " + msg)


func setup() -> void:
	if cfg.is_empty() or not LandmarkBuilder.info(String(cfg.get("cart", ""))).has("hitch"):
		return
	var rows := _road_rows()
	if rows.is_empty():
		_log("no road crosses the whole map: no cart")
		return
	var out := float(cfg.get("outside", 14.0))
	var z_mid: float = (int(rows[0]) + int(rows[-1]) + 1) * 1.0  # plan -y of the middle of the road (tiles are 2 m)
	if OS.is_debug_build():
		var band := []
		for q: Vector2 in town._prop_spots:
			if absf(-q.y - z_mid) < 2.6:
				band.append("prop %s" % q)
		for ob in town.seat_obstacles:
			if absf(-(ob[0] as Vector2).y - z_mid) < 2.6 + float(ob[2]):
				band.append("obstacle %s-%s r %.2f" % [ob[0], ob[1], ob[2]])
		_log("on the road band: %s" % ", ".join(band))
	var offs: Array = cfg.get("offsets", [-0.4, -0.2, -0.6, 0.0, -0.8, 0.2, -1.0, 0.4, 0.6, -1.2, 0.8, 1.0, 1.2, 1.4, 1.6, -1.4, -1.6])
	# lane by stretch: every metre the offsets with room for the cart (its length about that point), the one it is on
	# kept while it has room, else the free one nearest; a change of lane eases over a few metres (Convoy rounds it)
	var x0 := -out
	var x1: float = town.W * 2.0 + out
	var free := []  # per metre: {offset: room}
	var x := x0
	while x <= x1:
		var f := {}
		for o: float in offs:
			f[o] = _room(x - 2.0, x + 2.0, -(z_mid + o))
		free.append(f)
		x += 1.0
	var lane: float = offs[0]
	var best_first := -99.0
	for o: float in offs:
		if float(free[0][o]) > best_first:
			best_first = float(free[0][o])
			lane = o
	var pts := [Vector2(x0, -(z_mid + lane))]
	var least := 99.0
	for i in free.size():
		var f: Dictionary = free[i]
		if float(f[lane]) < 0.1:
			var nl := lane
			var nd := 99.0
			for o: float in offs:
				if float(f[o]) >= 0.1 and absf(o - lane) < nd:
					nd = absf(o - lane)
					nl = o
			if nl == lane:  # no lane has room here: the one with most
				for o: float in offs:
					if float(f[o]) > float(f[nl]):
						nl = o
			if nl != lane:
				var xc := x0 + i
				if xc - 4.0 > (pts[-1] as Vector2).x + 0.5:
					pts.append(Vector2(xc - 4.0, -(z_mid + lane)))
				pts.append(Vector2(xc - 1.0, -(z_mid + nl)))
				lane = nl
		least = minf(least, float(f[lane]))
	pts.append(Vector2(x1, -(z_mid + lane)))
	speed = float(cfg.get("pace", 0.7)) * 2.0 / maxf(0.1, float(town.mpt))
	var back := pts.duplicate()
	back.reverse()
	var ways := {"east": pts, "west": back}
	_log("lanes along the road: %s (least room %.2f m)" % [pts, least])
	for tr: Array in cfg.get("trips", [[8.0, "east"], [16.0, "west"]]):
		var way: Array = ways.get(String(tr[1]), ways.east)
		var c: Node3D = ConvoyScript.make(String(cfg.cart), String(cfg.get("animal", "burro")), way, {"seed": trips.size()})
		if c == null:
			return
		c.set_process(false)
		c.visible = false
		town.add_child(c)
		var ln := 0.0
		for i in range(1, way.size()):
			ln += (way[i - 1] as Vector2).distance_to(way[i])
		trips.append({convoy = c, from_min = float(tr[0]) * 60.0, dur = ln / speed, len = ln})
	_log("%s with a %s along road rows %s, %d lane changes (least room %.2f m), %.0f m a trip at %.2f m per game minute (%.0f min): %s" % [
		cfg.cart, cfg.get("animal", "burro"), rows, (pts.size() - 2) / 2, least, (trips[0].len if not trips.is_empty() else 0.0), speed,
		(trips[0].dur if not trips.is_empty() else 0.0), cfg.get("trips", [])])


func _road_rows() -> Array:
	## the rows whose every tile is road, plaza or bridge
	var out := []
	for r in town.H:
		var ok := true
		for c in town.W:
			if not String(town._t(c, r)) in ["=", ",", "P", "b"] and not (String(town._t(c, r)) == "#" and _plaza_hole(c, r)):
				ok = false
				break
		if ok:
			out.append(r)
	return out


func _plaza_hole(c: int, r: int) -> bool:
	## a '#' tile with plaza on both sides along the row (the fountain's): the road goes round it
	return String(town._t(c - 1, r)) == "P" and String(town._t(c + 1, r)) == "P"


func _room(x0: float, x1: float, y: float) -> float:
	## the least room, along the line y from x0 to x1, between the cart's side (half its width) and what stands there
	var half := float(LandmarkBuilder.info(String(cfg.cart)).get("footprint", [1.7, 4.0])[0]) / 2.0
	var least := 99.0
	var what := ""
	var x := x0
	while x <= x1:
		var p := Vector2(x, y)
		for ob in town.seat_obstacles:
			var a: Vector2 = ob[0]
			var b: Vector2 = ob[1]
			var ab := b - a
			var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var r := p.distance_to(a + ab * k) - float(ob[2]) - half
			if r < least:
				least = r
				what = "obstacle %s-%s at x %.1f" % [a, b, x]
		for q: Vector2 in town._prop_spots:
			var r := p.distance_to(q) - 0.5 - half
			if r < least:
				least = r
				what = "prop at %s" % q
		for side: float in [-half, half]:
			var tx := floori(p.x / 2.0)
			var ty := floori(-(p.y + side) / 2.0)
			if (tx >= 0 and tx < town.W) and not town.walkable(tx, ty) and least > -1.0:
				least = -1.0  # off the walked ground (a yard, a fence): not a way for a cart
				what = "off the walked tiles at x %.1f" % x
		if town._house_at_plan(p, half) != null and least > -1.0:
			least = -1.0
			what = "house at x %.1f" % x
		x += 0.5
	if verbose:
		_log("  line y %.1f from x %.1f to %.1f: least room %.2f m (%s)" % [y, x0, x1, least, what])
	return least


func update(t: float) -> void:
	## the trip on at minute t (of any day), placed; the others hidden
	if trips.is_empty():
		return
	var m := fposmod(t, 1440.0)
	var on: Dictionary = {}
	for tr: Dictionary in trips:
		if m >= float(tr.from_min) and m <= float(tr.from_min) + float(tr.dur):
			on = tr
	var c: Node3D = on.get("convoy", null)
	if _shown != null and _shown != c:
		_shown.visible = false
	_shown = c
	if c == null:
		capsule = []
		return
	var s: float = (m - float(on.from_min)) * speed
	var ds: float = s - float(c.travelled)
	if not c.visible or ds < 0.0 or ds > 6.0:
		# shown again, or the clock jumped: put the team at once where it should be
		c.travelled = s
		c._axle = c._at(s) - c._dir(s) * (c._axle_y - c._hitch_y)
		c._place(0.0)
		c.visible = true
	elif ds > 0.0:
		c.travelled = s
		c._place(ds)
	# the beast walks at the pace of the clock (paused: it stands)
	var real_speed: float = speed / maxf(1e-4, town.real_per_game_minute()) if not town.paused else 0.0
	var want := "andar" if real_speed > 0.01 else "quieto"
	for an: Node3D in c.animals:
		var ap := an.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null:
			continue
		if want != _anim:
			LandmarkBuilder.play(an, want)
		ap.speed_scale = clampf(real_speed / maxf(0.1, float(c._walk)), 0.0, 8.0) if want == "andar" else 1.0
	_anim = want
	# what walkers are pushed off: from the beast's head to the back of the cart
	var hitch: Vector2 = c._at(c.travelled)
	var fwd: Vector2 = (hitch - c._axle).normalized()
	var half := float(LandmarkBuilder.info(String(cfg.cart)).get("footprint", [1.7, 4.0])[0]) / 2.0
	capsule = [hitch + fwd * 1.3, c._axle - fwd * 1.0, half]
