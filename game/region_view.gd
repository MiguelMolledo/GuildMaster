class_name RegionView
extends RefCounted
## The region as the view sees it (docs/gdd/09b_region.md): reads data/world/region.json (the settlements, the routes
## and their identity) and answers what the «Mapa de la región» screen draws: which settlement is home, how many game
## hours each one is from it (shortest way over the routes), which routes a world event in force cuts. View only: the
## sim reads the same file (Region); what moves (trips, caravans, the regional events) is read from the state.

const PATH: String = "res://data/world/region.json"

static var _cache: Dictionary = {}


## The region data (cached; {} if the file is missing or broken).
static func data() -> Dictionary:
	if _cache.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(PATH)) == OK and json.data is Dictionary:
			_cache = json.data
		else:
			push_warning("RegionView: cannot read %s" % PATH)
	return _cache


static func settlements() -> Array:
	return data().get("settlements", [])


static func routes() -> Array:
	return data().get("routes", [])


static func settlement(id: String) -> Dictionary:
	for s: Dictionary in settlements():
		if str(s.get("id", "")) == id:
			return s
	return {}


## Home: the settlement whose map is the game's map (map_id of the state); if none is, the region's «home» (the
## villa: the start towns of today all are town_e).
static func home_of(map_id: String) -> String:
	for s: Dictionary in settlements():
		if str(s.get("map", "")) == map_id and map_id != "":
			return str(s["id"])
	return str(data().get("home", ""))


## Game hours from `from` to every settlement (shortest way over the routes; Dijkstra over a handful of nodes).
## Routes in `cut` (ids) are left out; a settlement that cannot be reached is not in the result.
static func hours_from(from: String, cut: Array = []) -> Dictionary:
	var dist := {from: 0.0}
	var todo := [from]
	while not todo.is_empty():
		todo.sort_custom(func(a: String, b: String) -> bool: return float(dist[a]) < float(dist[b]))
		var at: String = todo.pop_front()
		for r: Dictionary in routes():
			if str(r.get("id", "")) in cut:
				continue
			var other := ""
			if str(r["a"]) == at:
				other = str(r["b"])
			elif str(r["b"]) == at:
				other = str(r["a"])
			if other == "":
				continue
			var d := float(dist[at]) + float(r.get("hours", 0))
			if not dist.has(other) or d < float(dist[other]):
				dist[other] = d
				if not other in todo:
					todo.append(other)
	return dist


## The routes of `id` ([route dictionaries], in data order).
static func routes_of(id: String) -> Array:
	return routes().filter(func(r: Dictionary) -> bool: return str(r["a"]) == id or str(r["b"]) == id)


## The ids of the events in force that cut `route` (home's world events in its cut_by and the regional ones, snow
## and flood: Region.cut_by); [] without a game.
static func cut_by_now(sim: Sim, route: Dictionary) -> Array:
	if sim == null:
		return []
	return Region.cut_by(sim, route)


## The routes cut now ({route id: [event ids]}).
static func cut_routes(sim: Sim) -> Dictionary:
	var out := {}
	for r: Dictionary in routes():
		var by := cut_by_now(sim, r)
		if not by.is_empty():
			out[str(r["id"])] = by
	return out


## The points of a route on the map (its two ends and its path between them).
static func route_points(route: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a := settlement(str(route["a"]))
	var b := settlement(str(route["b"]))
	pts.append(Vector2(a["pos"][0], a["pos"][1]))
	for p: Array in route.get("path", []):
		pts.append(Vector2(p[0], p[1]))
	pts.append(Vector2(b["pos"][0], b["pos"][1]))
	return pts
