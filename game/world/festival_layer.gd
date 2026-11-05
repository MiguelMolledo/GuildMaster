class_name FestivalLayer
extends RefCounted
## Fiestas (04f 4.25.3 «En la vista»): the decoration of the festivals in force on the town map, a layer per festival
## instance. Reads data/festivals.json view (through Festivals.view_of: the props whose needs are met) and puts each
## prop on a site of the map (where): plaza_center / plaza_center_side (the middle of the plaza and beside it),
## plaza_ring (spread along the plaza's edge), plaza_edge (the plaza's south side), main_street (spread along the
## longest street row), town_hall (beside the town hall's door), gates (inside the map's gates). Each prop is
## game/visuals/props/fiesta/<prop>.tscn (the art worker's scene, assets/art/props/fiesta/<prop>.png) or, until it
## exists, props/fiesta/_greybox.tscn with the prop's id written on it. Placed in the objects layer (Y-sorted with the
## buildings and the walkers), never on a tile with a prop, a stall, the board, a door or a free lot or ruin (plots); the same tiles every time
## (they depend only on the map). The view only: nothing here is read by the sim.

const GREYBOX: String = "fiesta/_greybox"

var world: Node = null          # the WorldView that owns it
var _nodes: Dictionary = {}     # instance id -> [Node2D]
var _sites: Dictionary = {}     # where -> [Vector2i] (computed once per map)
var _taken: Dictionary = {}     # Vector2i -> true (tiles a festival prop already stands on)
var shown: Dictionary = {}      # instance id -> [prop ids placed] (tests, smoke)
var _signature: Dictionary = {} # instance id -> the decor it was built from
var _free: Dictionary = {}      # Vector2i -> true: open walkable ground a footprint may cover (sites()["_free"])


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
		_free = {}
		for t: Vector2i in _sites.get("_free", []):
			_free[t] = true
	var nodes: Array = []
	var placed: Array = []
	for d: Dictionary in decor:
		var prop := str(d.get("prop", ""))
		var fp := footprint(prop)
		for tiles: Array in _pick(str(d.get("where", "")), int(d.get("count", 1)), fp):
			var n := _instance(prop)
			var centre := Vector2.ZERO
			for t: Vector2i in tiles:
				centre += Iso.tile_to_world(t)
				_taken[t] = true
			VisualPaths.place(n, (centre / float(tiles.size())).round())  # Feet = the centre of its footprint
			var o: Vector2i = tiles[0]
			n.name = "Fiesta_%s_%s_%d_%d" % [id, prop, o.x, o.y]
			n.set_meta("tiles", tiles)
			n.set_meta("festival_prop", prop)
			(world.call("objects") as Node2D).add_child(n)
			nodes.append(n)
			placed.append(prop)
	_nodes[id] = nodes
	shown[id] = placed
	if OS.is_debug_build():
		print("[FestivalLayer] %s: %d piezas (%s)" % [id, nodes.size(), placed])


## The art's scene of `prop` (VisualPaths.festival_prop: game/visuals/props/fiesta/<the art's name>.tscn), else the
## labelled greybox (props/fiesta/_greybox.tscn: only the fallback).
func _instance(prop: String) -> Node2D:
	var scene := VisualPaths.festival_prop(prop)
	if VisualPaths.has_scene("props", scene):
		return VisualPaths.instantiate("props", scene)
	var n := VisualPaths.instantiate("props", GREYBOX)
	var l := n.get_node_or_null("Label") as Label
	if l != null:
		l.text = prop
	var g := n.get_node_or_null("Greybox")
	if g != null:
		g.set("color", Color.from_hsv(float(prop.hash() % 360) / 360.0, 0.55, 0.85))
	return n


## The footprint of `prop` in tiles (columns × rows): its scene's metadata/footprint, 1×1 for the greybox.
static func footprint(prop: String) -> Vector2i:
	var scene := VisualPaths.festival_prop(prop)
	if not VisualPaths.has_scene("props", scene):
		return Vector2i(1, 1)
	var ps := VisualPaths.scene("props", scene)
	var st := ps.get_state() if ps != null else null
	if st != null:
		for i: int in st.get_node_property_count(0):
			if st.get_node_property_name(0, i) == &"metadata/footprint":
				var v: Variant = st.get_node_property_value(0, i)
				if v is Vector2i:
					return Vector2i(maxi(1, (v as Vector2i).x), maxi(1, (v as Vector2i).y))
	return Vector2i(1, 1)


## The sites where the props go to the nearest free place (their tiles are sorted by distance), not spread along.
const NEAREST: Array[String] = ["plaza_center", "plaza_center_side", "town_hall", "gates"]


## `count` places of site `where`: each the tiles of a footprint `fp` that holds a tile of the site at one of its
## corners and whose every tile is free (walkable open ground, no prop, nothing of another festival prop). Spread
## along the site, or the nearest ones for the NEAREST sites.
func _pick(where: String, count: int, fp: Vector2i = Vector2i(1, 1)) -> Array:
	var cands: Array = []
	var anchors: Array = [Vector2i(0, 0), Vector2i(1 - fp.x, 0), Vector2i(0, 1 - fp.y), Vector2i(1 - fp.x, 1 - fp.y)]
	for t: Vector2i in _sites.get(where, []):
		for a: Vector2i in anchors:
			var tiles: Array = []
			var ok := true
			for dy: int in fp.y:
				for dx: int in fp.x:
					var u := t + a + Vector2i(dx, dy)
					if _taken.has(u) or world.call("prop_at", u) != null or (u != t and not _free.has(u)):
						ok = false
					tiles.append(u)
			if ok:
				cands.append(tiles)
				break
	if cands.is_empty() or count <= 0:
		return []
	var out: Array = []
	var used := {}
	var near := where in NEAREST
	var n := mini(count, cands.size())
	for i: int in (cands.size() if near else n):
		if out.size() >= n:
			break
		var tiles: Array = cands[i] if near else cands[int(floor(float(i) * float(cands.size()) / float(n)))]
		var clash := false
		for u: Vector2i in tiles:
			clash = clash or used.has(u)
		if clash:
			continue
		for u: Vector2i in tiles:
			used[u] = true
		out.append(tiles)
	return out


## The sites of the map: where -> [tiles] in a fixed order (they depend only on the map and its services).
static func sites(state: WorldState, catalog: Catalog) -> Dictionary:
	var m: Dictionary = catalog.maps().get(state.map_id, {})
	var rows: Array = m.get("rows", [])
	var plaza: Array = []
	var street_rows := {}
	var open: Array = []
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var kind := catalog.tile_kind_of_char(row[c])
			if kind in ["plaza", "street", "grass", "dirt"]:
				open.append(Vector2i(c, r))
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
	for it: Dictionary in m.get("decor", {}).get("items", []):  # the map's dressing (the well, lanterns, yards)
		var at: Array = it.get("at", [])
		if at.size() != 2:
			continue
		var sz: Array = it.get("size", [1, 1])
		var m0 := 1 if str(it.get("kind", "")) == "single" else 0  # a lone piece (the well) keeps a tile around it
		for dy: int in range(-m0, maxi(1, int(sz[1]) if sz.size() == 2 else 1) + m0):
			for dx: int in range(-m0, maxi(1, int(sz[0]) if sz.size() == 2 else 1) + m0):
				busy[Vector2i(int(at[0]) + dx, int(at[1]) + dy)] = true
	for pl: Dictionary in m.get("plots", []):  # parcelas (04 §4.9.1): free lots and ruins keep their ground
		if str(pl.get("state", "")) in ["lot", "ruin"]:
			for t: Vector2i in PlotLayer.tiles_of(pl):
				busy[t] = true
	var out := {"plaza_center": [], "plaza_center_side": [], "plaza_ring": [], "plaza_edge": [], "main_street": [],
		"town_hall": [], "gates": [], "_free": open.filter(func(t: Vector2i) -> bool: return not busy.has(t))}
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
			out["plaza_center"] = free_plaza.duplicate()  # the nearest free place to the middle first
			out["plaza_center_side"] = free_plaza.slice(3)
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
		var near: Array = []
		for dy: int in range(-4, 2):
			for dx: int in range(-5, 6):
				var u := s + Vector2i(dx, dy)
				if absi(dx) >= 2 and not busy.has(u) and u in open:  # beside the door, never on it
					near.append(u)
		near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a - s).length_squared()
			var db := (b - s).length_squared()
			return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
		out["town_hall"] = near
	for g: String in ["west_gate", "east_gate"]:
		var sp: Array = m.get("spawns", {}).get(g, [])
		if sp.size() == 2:
			var t := Vector2i(int(sp[0]), int(sp[1]))
			out["gates"].append(t + (Vector2i(2, 0) if t.x < 5 else Vector2i(-2, 0)))
	return out


static func _ring_angle(t: Vector2i, mid: Vector2) -> float:
	return (Vector2(t) - mid).angle()
