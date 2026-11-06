class_name Grid
extends RefCounted
## Walk-cost grid of a town map (GDD 05 §5.4, D3), built from Catalog.tiles + Catalog.maps()[map_id].
## Static data: it is cached per catalog and map with Grid.of() and never lives in WorldState.
## cost(c, r) is the walk_cost of entering the tile; BLOCKED for tiles that cannot be entered.

const BLOCKED: int = 0

static var _cache: Dictionary = {}  # "<catalog instance id>:<map_id>" -> Grid

var map_id: String = ""
var width: int = 0
var height: int = 0
var costs: PackedInt32Array = PackedInt32Array()  # index = row * width + col
var walkable_tiles: PackedInt32Array = PackedInt32Array()  # indices of every walkable tile, in row-major order
## The same costs with a 1-tile blocked border, (width + 2) × (height + 2): lets Pathfinder skip bounds checks.
var padded: PackedInt32Array = PackedInt32Array()
## Moves out of each padded tile, precomputed for Pathfinder (8 neighbours, no corner cutting, fixed order N E S W,
## NE SE SW NW): the moves of tile i are link_to/link_cost[link_start[i] .. link_start[i + 1]). link_cost is the step
## cost (walk_cost × 10 straight, × 14 diagonal). Built for every inner tile, walkable or not (a route may start on
## a blocked tile).
var link_start: PackedInt32Array = PackedInt32Array()
var link_to: PackedInt32Array = PackedInt32Array()
var link_cost: PackedInt32Array = PackedInt32Array()
## Pathfinder's open list is a ring of buckets by f; ring_mask + 1 (a power of two) is larger than the largest jump
## of f from a tile to its neighbour (largest step cost + the most the octile heuristic changes in a step), so two
## open tiles with different f never share a bucket.
var ring_mask: int = 255
## Padded column and row of each padded tile (the heuristic reads them instead of dividing).
var pad_col: PackedInt32Array = PackedInt32Array()
var pad_row: PackedInt32Array = PackedInt32Array()
## Routes already found on this grid (Pathfinder): from_index * size + to_index -> PackedInt32Array of padded tiles.
## Only a speed-up: a route is a pure function of the grid, so this never changes a result. Static data like the
## grid itself (never in WorldState). invalidate() empties it if the map ever changes.
var routes: Dictionary = {}
## Plantillas (data/maps "routing"): the ALT landmarks of a large map (RouteAtlas), null for the rest (town_e): then
## Pathfinder.search as it always was.
var atlas: RouteAtlas = null


## The grid of `map_id`, built once per catalog. null if the catalog has no such map.
static func of(catalog: Catalog, id: String) -> Grid:
	if id == "" or not catalog.maps().has(id):
		return null
	var key := "%d:%s" % [catalog.get_instance_id(), id]
	if not _cache.has(key):
		_cache[key] = build(catalog, id)
	return _cache[key]


## H6 (Plots): the grid of the state's town with what has been built on its plots: a building raised on a lot of
## walkable ground (the lots outside, on grass or field) blocks its footprint. With nothing built there it is the map's
## grid (Grid.of), so every game of before walks the same. The derived grids are cached by what blocks them; they keep
## the map's RouteAtlas (blocking tiles only makes routes longer: its ALT heuristic still never overestimates, and is
## still consistent, every move of the derived grid being one of the map's at the same cost).
static func for_state(catalog: Catalog, state: WorldState) -> Grid:
	var base := of(catalog, state.map_id)
	if base == null or state.parcels.is_empty():
		return base
	var rects: Array = []
	var ids: Array = state.parcels.keys()
	ids.sort()
	for pid: String in ids:
		var bld := str(state.parcels[pid].get("building", ""))
		if bld == "" or not state.buildings.has(bld):
			continue
		var o: Array = state.buildings[bld].get("origin", [0, 0])
		var f: Array = state.buildings[bld].get("footprint", [1, 1])
		rects.append([int(o[0]), int(o[1]), int(f[0]), int(f[1])])
	var cells := PackedInt32Array()
	for r: Array in rects:
		for dr: int in int(r[3]):
			for dc: int in int(r[2]):
				var c := int(r[0]) + dc
				var w := int(r[1]) + dr
				if base.in_bounds(c, w) and base.cost(c, w) != BLOCKED:
					cells.append(base.index(c, w))
	if cells.is_empty():
		return base
	var key := "%d:%s:%d" % [catalog.get_instance_id(), state.map_id, str(cells).hash()]
	if not _cache.has(key):
		var g := Grid.new()
		g.map_id = base.map_id
		g.width = base.width
		g.height = base.height
		g.costs = base.costs.duplicate()
		for i: int in cells:
			g.costs[i] = BLOCKED
		for i: int in g.costs.size():
			if g.costs[i] != BLOCKED:
				g.walkable_tiles.append(i)
		g._link()
		g.atlas = base.atlas
		_cache[key] = g
		if OS.is_debug_build():
			print("[Grid] %s con %d casillas edificadas en parcelas" % [state.map_id, cells.size()])
	return _cache[key]


static func build(catalog: Catalog, id: String) -> Grid:
	var g := Grid.new()
	var m: Dictionary = catalog.maps()[id]
	var size: Array = m.get("size", [0, 0])
	g.map_id = id
	g.width = int(size[0])
	g.height = int(size[1])
	g.costs.resize(g.width * g.height)
	var by_char := {}
	for kind: String in catalog.tiles:
		var t: Dictionary = catalog.tiles[kind]
		var wc: Variant = t.get("walk_cost")
		by_char[str(t.get("char", ""))] = BLOCKED if wc == null else maxi(int(wc), 1)
	var rows: Array = m.get("rows", [])
	for r: int in g.height:
		var row := str(rows[r]) if r < rows.size() else ""
		for c: int in g.width:
			var ch := row[c] if c < row.length() else ""
			var cost: int = by_char.get(ch, BLOCKED)
			g.costs[r * g.width + c] = cost
			if cost != BLOCKED:
				g.walkable_tiles.append(r * g.width + c)
	g._link()
	g.atlas = RouteAtlas.for_map(g, m)
	if OS.is_debug_build():
		print("[Grid] built: %s (w=%d, h=%d, walkable=%d, moves=%d)"
			% [id, g.width, g.height, g.walkable_tiles.size(), g.link_to.size()])
	return g


## Rebuilds what is derived from `costs` (padded copy, moves) and forgets the routes found. Call it after changing
## `costs` (today the maps are static: nothing does).
func invalidate() -> void:
	_link()
	if OS.is_debug_build():
		print("[Grid] invalidate: %s (routes cleared)" % map_id)


func _link() -> void:
	routes.clear()
	var pw := width + 2
	var n := pw * (height + 2)
	padded = PackedInt32Array()
	padded.resize(n)
	pad_col = PackedInt32Array()
	pad_col.resize(n)
	pad_row = PackedInt32Array()
	pad_row.resize(n)
	for i: int in n:
		pad_col[i] = i % pw
		pad_row[i] = i / pw
	for r: int in height:
		for c: int in width:
			padded[(r + 1) * pw + c + 1] = costs[r * width + c]
	# Straight k: N, E, S, W. Diagonal j joins straight j and j + 1: NE, SE, SW, NW.
	var off: Array[int] = [-pw, 1, pw, -1]
	var doff: Array[int] = [1 - pw, 1 + pw, pw - 1, -pw - 1]
	link_start = PackedInt32Array()
	link_start.resize(n + 1)
	link_to = PackedInt32Array()
	link_cost = PackedInt32Array()
	for i: int in n:
		link_start[i] = link_to.size()
		if pad_col[i] == 0 or pad_row[i] == 0 or pad_col[i] == pw - 1 or pad_row[i] == height + 1:
			continue  # the border is never a tile of a route
		var open_bits := 0
		for k: int in 4:
			var step: int = padded[i + off[k]]
			if step != BLOCKED:
				open_bits |= 1 << k
				link_to.append(i + off[k])
				link_cost.append(step * Pathfinder.STRAIGHT)
		for j: int in 4:
			if (open_bits >> j) & 1 == 0 or (open_bits >> ((j + 1) & 3)) & 1 == 0:
				continue
			var step: int = padded[i + doff[j]]
			if step != BLOCKED:
				link_to.append(i + doff[j])
				link_cost.append(step * Pathfinder.DIAGONAL)
	link_start[n] = link_to.size()
	var top := 0
	for c: int in link_cost:
		top = maxi(top, c)
	var ring := 16
	while ring <= top + Pathfinder.DIAGONAL:
		ring <<= 1
	ring_mask = ring - 1


func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < width and r < height


func cost(c: int, r: int) -> int:
	return costs[r * width + c] if in_bounds(c, r) else BLOCKED


func walkable(c: int, r: int) -> bool:
	return cost(c, r) != BLOCKED


func index(c: int, r: int) -> int:
	return r * width + c


func tile_of(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)
