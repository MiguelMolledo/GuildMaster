class_name FestivalLayer
extends RefCounted
## Fiestas (04f 4.25.3 «En la vista»): the decoration of the festivals in force on the town map, a layer per festival
## instance. Reads data/festivals.json view (through Festivals.view_of: the props whose needs are met) and puts each
## prop on a site of the map (where): plaza_center / plaza_center_side (the middle of the plaza and beside it),
## plaza_ring (spread along the plaza's edge), plaza_edge (the plaza's south side), main_street (spread along the
## longest street row), town_hall (beside the town hall's door), gates (inside the map's gates). Each prop is
## game/visuals/props/fiesta/<prop>.tscn (the art worker's scene, assets/art/props/fiesta/<prop>.png) or, until it
## exists, props/fiesta/_greybox.tscn with the prop's id written on it. Placed in the objects layer (Y-sorted with the
## buildings and the walkers), never on a tile with a prop, a stall, the board or a door; the same tiles every time
## (they depend only on the map). The view only: nothing here is read by the sim.

const GREYBOX: String = "fiesta/_greybox"

var world: Node = null          # the WorldView that owns it
var _nodes: Dictionary = {}     # instance id -> [Node2D]
var _sites: Dictionary = {}     # where -> [Vector2i] (computed once per map)
var _taken: Dictionary = {}     # Vector2i -> true (tiles a festival prop already stands on)
var shown: Dictionary = {}      # instance id -> [prop ids placed] (tests, smoke)
var _signature: Dictionary = {} # instance id -> the decor it was built from


func setup(w: Node) -> void:
	world = w
	clear()
	_sites = {}


func clear() -> void:
	for id: String in _nodes:
		for n: Node2D in _nodes[id]:
			if is_instance_valid(n):
				n.queue_free()
	_nodes = {}
	_taken = {}
	shown = {}


## Follows the state: a layer for each festival in force, gone when it ends (or when its props change: a sponsored
## bull, a delivered arch). Cheap when nothing changed (a signature per instance).
func refresh(sim: Sim) -> void:
	if sim == null or world == null:
		return
	var want := {}
	for inst: Dictionary in Festivals.active(sim):
		want[str(inst["id"])] = Festivals.view_of(sim, inst)
	for id: String in _nodes.keys():
		if not want.has(id):
			_drop(id)
	for id: String in want:
		var sig := str(want[id]["decor"])
		if _nodes.has(id) and str(_signature.get(id, "")) == sig:
			continue
		if _nodes.has(id):
			_drop(id)
		_build(sim, id, want[id]["decor"])
		_signature[id] = sig


## The festive look of the clothes now ({} = everyday): the first festival in force with view clothes; its
## rules.view_looks entry {color, amount, mask}.
static func clothes(sim: Sim) -> Dictionary:
	if sim == null:
		return {}
	for inst: Dictionary in Festivals.active(sim):
		var c := str(Festivals.view_of(sim, inst).get("clothes", ""))
		if c != "":
			var look: Dictionary = (Festivals.rules(sim).get("view_looks", {}) as Dictionary).get(c, {})
			if not look.is_empty():
				var out := look.duplicate()
				out["id"] = c
				return out
	return {}


## The music of the festival in force (its view music id), "" if none.
static func music(sim: Sim) -> String:
	if sim == null:
		return ""
	for inst: Dictionary in Festivals.active(sim):
		var m := str(Festivals.view_of(sim, inst).get("music", ""))
		if m != "":
			return m
	return ""


func _drop(id: String) -> void:
	for n: Node2D in _nodes.get(id, []):
		if is_instance_valid(n):
			for t: Variant in n.get_meta("tiles", []):
				_taken.erase(t)
			n.queue_free()
	_nodes.erase(id)
	_signature.erase(id)
	shown.erase(id)


func _build(sim: Sim, id: String, decor: Array) -> void:
	if _sites.is_empty():
		_sites = sites(sim.state, sim.catalog)
	var nodes: Array = []
	var placed: Array = []
	for d: Dictionary in decor:
		var prop := str(d.get("prop", ""))
		var tiles := _pick(str(d.get("where", "")), int(d.get("count", 1)))
		for t: Vector2i in tiles:
			var n := _instance(prop)
			VisualPaths.place(n, Iso.tile_to_world(t))
			n.name = "Fiesta_%s_%s_%d_%d" % [id, prop, t.x, t.y]
			n.set_meta("tiles", [t])
			n.set_meta("festival_prop", prop)
			(world.call("objects") as Node2D).add_child(n)
			nodes.append(n)
			placed.append(prop)
			_taken[t] = true
	_nodes[id] = nodes
	shown[id] = placed
	if OS.is_debug_build():
		print("[FestivalLayer] %s: %d piezas (%s)" % [id, nodes.size(), placed])


## The art worker's scene of `prop`, else the labelled greybox.
func _instance(prop: String) -> Node2D:
	if VisualPaths.has_scene("props", "fiesta/" + prop):
		return VisualPaths.instantiate("props", "fiesta/" + prop)
	var n := VisualPaths.instantiate("props", GREYBOX)
	var l := n.get_node_or_null("Label") as Label
	if l != null:
		l.text = prop
	var g := n.get_node_or_null("Greybox")
	if g != null:
		g.set("color", Color.from_hsv(float(prop.hash() % 360) / 360.0, 0.55, 0.85))
	return n


## `count` free tiles of site `where`, spread along it.
func _pick(where: String, count: int) -> Array:
	var cands: Array = []
	for t: Vector2i in _sites.get(where, []):
		if not _taken.has(t) and world.call("prop_at", t) == null:
			cands.append(t)
	if cands.is_empty() or count <= 0:
		return []
	var out: Array = []
	var n := mini(count, cands.size())
	for i: int in n:
		var t: Vector2i = cands[int(floor(float(i) * float(cands.size()) / float(n)))]
		if not t in out:
			out.append(t)
	return out


## The sites of the map: where -> [tiles] in a fixed order (they depend only on the map and its services).
static func sites(state: WorldState, catalog: Catalog) -> Dictionary:
	var m: Dictionary = catalog.maps().get(state.map_id, {})
	var rows: Array = m.get("rows", [])
	var plaza: Array = []
	var street_rows := {}
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var kind := catalog.tile_kind_of_char(row[c])
			if kind == "plaza":
				plaza.append(Vector2i(c, r))
			elif kind == "street":
				if not street_rows.has(r):
					street_rows[r] = []
				(street_rows[r] as Array).append(Vector2i(c, r))
	var busy := {}
	for svc: Dictionary in SimQuery.map_services(state, catalog):
		busy[svc["tile"]] = true
		busy[svc.get("service", svc["tile"])] = true
	for p: Dictionary in m.get("social_points", []):
		for s: Array in p.get("slots", []):
			busy[Vector2i(int(s[0]), int(s[1]))] = true
	for b: Dictionary in m.get("buildings", {}).values():
		var dr: Array = b.get("door", [])
		if dr.size() == 2:
			busy[Vector2i(int(dr[0]), int(dr[1]))] = true
	var out := {"plaza_center": [], "plaza_center_side": [], "plaza_ring": [], "plaza_edge": [], "main_street": [],
		"town_hall": [], "gates": []}
	if not plaza.is_empty():
		var lo := Vector2i(100000, 100000)
		var hi := Vector2i(-1, -1)
		var mid := Vector2.ZERO
		for t: Vector2i in plaza:
			lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
			hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
			mid += Vector2(t)
		mid /= float(plaza.size())
		var free_plaza: Array = plaza.filter(func(t: Vector2i) -> bool: return not busy.has(t))
		free_plaza.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := Vector2(a).distance_squared_to(mid)
			var db := Vector2(b).distance_squared_to(mid)
			return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
		if not free_plaza.is_empty():
			out["plaza_center"] = [free_plaza[0]]
			out["plaza_center_side"] = free_plaza.slice(3, 6)
		var ring: Array = free_plaza.filter(func(t: Vector2i) -> bool:
			return t.x == lo.x or t.x == hi.x or t.y == lo.y or t.y == hi.y)
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _ring_angle(a, mid) < _ring_angle(b, mid))
		out["plaza_ring"] = ring
		out["plaza_edge"] = free_plaza.filter(func(t: Vector2i) -> bool: return t.y >= hi.y - 1)
	var best := -1
	for r: Variant in street_rows:
		if best < 0 or (street_rows[r] as Array).size() > (street_rows[best] as Array).size():
			best = int(r)
	if best >= 0:
		out["main_street"] = (street_rows[best] as Array).filter(func(t: Vector2i) -> bool: return not busy.has(t))
	var th: Dictionary = m.get("town_hall", {})
	var svc_th: Array = th.get("service", [])
	if svc_th.size() == 2:
		var s := Vector2i(int(svc_th[0]), int(svc_th[1]))
		for d: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-3, -1), Vector2i(3, -1)]:
			out["town_hall"].append(s + d)
	for g: String in ["west_gate", "east_gate"]:
		var sp: Array = m.get("spawns", {}).get(g, [])
		if sp.size() == 2:
			var t := Vector2i(int(sp[0]), int(sp[1]))
			out["gates"].append(t + (Vector2i(2, 0) if t.x < 5 else Vector2i(-2, 0)))
	return out


static func _ring_angle(t: Vector2i, mid: Vector2) -> float:
	return (Vector2(t) - mid).angle()
