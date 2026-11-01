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


## The grid of `map_id`, built once per catalog. null if the catalog has no such map.
static func of(catalog: Catalog, id: String) -> Grid:
	if id == "" or not catalog.maps().has(id):
		return null
	var key := "%d:%s" % [catalog.get_instance_id(), id]
	if not _cache.has(key):
		_cache[key] = build(catalog, id)
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
	var pw := g.width + 2
	g.padded.resize(pw * (g.height + 2))
	for r: int in g.height:
		for c: int in g.width:
			g.padded[(r + 1) * pw + c + 1] = g.costs[r * g.width + c]
	if OS.is_debug_build():
		print("[Grid] built: %s (w=%d, h=%d, walkable=%d)" % [id, g.width, g.height, g.walkable_tiles.size()])
	return g


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
