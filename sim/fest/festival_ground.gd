class_name FestivalGround
extends RefCounted
## Fiestas (owner, 2026-11-05): the outskirts of a town (data/festivals.json rules.view_sites.outskirts), the free
## meadow by its gates where the cattle fairs were held. One rule for the sim and the view: the sim asks whether the
## fair's pens fit (if not, the cattle is sold at stalls and the chronicle says so); FestivalLayer places them there.
## Pure data from the map (data/maps/<id>.json rows, spawns *_gate, decor items, building doors, social points).

## {near: [Vector2i] (meadow tiles within radius of a gate, nearest first), meadow: [Vector2i]} of map `map_id`.
## `extra_busy`: more tiles to keep off (the view adds its services).
static func outskirts(catalog: Catalog, map_id: String, extra_busy: Dictionary = {}) -> Dictionary:
	var m: Dictionary = catalog.maps().get(map_id, {})
	var rows: Array = m.get("rows", [])
	var busy := extra_busy.duplicate()
	for b: Dictionary in m.get("buildings", {}).values():
		var dr: Array = b.get("door", [])
		if dr.size() == 2:
			busy[Vector2i(int(dr[0]), int(dr[1]))] = true
	for p: Dictionary in m.get("social_points", []):
		for s: Array in p.get("slots", []):
			busy[Vector2i(int(s[0]), int(s[1]))] = true
	for it: Dictionary in m.get("decor", {}).get("items", []):
		var at: Array = it.get("at", [])
		if at.size() != 2:
			continue
		var sz: Array = it.get("size", [1, 1])
		var m0 := 1 if str(it.get("kind", "")) == "single" else 0
		for dy: int in range(-m0, maxi(1, int(sz[1]) if sz.size() == 2 else 1) + m0):
			for dx: int in range(-m0, maxi(1, int(sz[0]) if sz.size() == 2 else 1) + m0):
				busy[Vector2i(int(at[0]) + dx, int(at[1]) + dy)] = true
	var cfg: Dictionary = (catalog.festivals.get("rules", {}) as Dictionary).get("view_sites", {}).get("outskirts", {})
	var ground: Array = cfg.get("ground", ["grass"])
	var radius := int(cfg.get("radius", 10))
	var margin := int(cfg.get("gate_margin", 1))
	var gates: Array = []
	var spawns: Dictionary = m.get("spawns", {})
	var names: Array = spawns.keys()
	names.sort()
	for g: Variant in names:
		var sp: Array = spawns[g]
		if str(g).ends_with("_gate") and sp.size() == 2:
			gates.append(Vector2i(int(sp[0]), int(sp[1])))
	var meadow: Array = []
	var dist := {}
	for r: int in rows.size():
		var row := str(rows[r])
		for c: int in row.length():
			var t := Vector2i(c, r)
			if busy.has(t) or not catalog.tile_kind_of_char(row[c]) in ground:
				continue  # never a road (keep_off kinds are never ground), a door, a seat or the map's dressing
			var best := 1 << 20
			for gt: Vector2i in gates:
				best = mini(best, maxi(absi(t.x - gt.x), absi(t.y - gt.y)))
			if best <= margin:
				continue  # not at the gate
			meadow.append(t)
			if best <= radius:
				dist[t] = best
	var near: Array = dist.keys()
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(dist[a]) < int(dist[b]) or (int(dist[a]) == int(dist[b]) and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	return {"near": near, "meadow": meadow}


## Whether `count` footprints of `fp` tiles fit in the outskirts of `map_id` without overlapping (any of the four
## corners of a footprint on a tile of the outskirts, the whole footprint on the meadow).
static func fits(catalog: Catalog, map_id: String, fp: Vector2i, count: int = 1) -> bool:
	var o := outskirts(catalog, map_id)
	var meadow := {}
	for t: Vector2i in o["meadow"]:
		meadow[t] = true
	var used := {}
	var placed := 0
	var anchors: Array = [Vector2i(0, 0), Vector2i(1 - fp.x, 0), Vector2i(0, 1 - fp.y), Vector2i(1 - fp.x, 1 - fp.y)]
	for t: Vector2i in o["near"]:
		for a: Vector2i in anchors:
			var tiles: Array = []
			var ok := true
			for dy: int in fp.y:
				for dx: int in fp.x:
					var u := t + a + Vector2i(dx, dy)
					ok = ok and meadow.has(u) and not used.has(u)
					tiles.append(u)
			if ok:
				for u: Vector2i in tiles:
					used[u] = true
				placed += 1
				break
		if placed >= count:
			return true
	return placed >= count
