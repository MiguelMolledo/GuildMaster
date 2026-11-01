extends "res://tests/test_case.gd"
## Grid and A* (GDD 05 §5.4, D3): valid routes, no corner cutting, optimal, deterministic, streets before grass.

var cat := Catalog.load_from()


## The catalog with an extra test map (unique id per test: grids are cached per catalog and map).
func _with_map(id: String, rows: Array) -> Grid:
	cat.tables["maps"][id] = {"id": id, "size": [str(rows[0]).length(), rows.size()], "rows": rows, "spawns": {}}
	return Grid.of(cat, id)


func _town() -> Grid:
	return Grid.of(cat, "town_e")


func test_grid_reads_the_map() -> void:
	var g := _town()
	check(g != null, "town_e has a grid")
	eq(g.width, 40, "width")
	eq(g.height, 40, "height")
	eq(g.cost(7, 12), 1, "street costs 1")
	eq(g.cost(0, 0), 10, "grass costs 10")
	check(not g.walkable(9, 8), "building is blocked")
	check(not g.walkable(35, 0), "water is blocked")
	check(not g.walkable(-1, 0) and not g.walkable(40, 0), "outside is blocked")
	check(Grid.of(cat, "town_e") == g, "cached")
	check(Grid.of(cat, "") == null and Grid.of(cat, "nowhere") == null, "no map, no grid")


func test_route_is_valid() -> void:
	var g := _town()
	var from := Vector2i(20, 21)
	var to := Vector2i(8, 12)
	var p := Pathfinder.find(g, from, to)
	check(not p.is_empty(), "there is a route")
	eq(p[-1], [8, 12], "ends at the target")
	check(Pathfinder.cost_of(g, from, p) > 0, "every step is adjacent, walkable and cuts no corner")
	eq(Pathfinder.find(g, from, from), [], "same tile: no route")


func test_no_corner_cutting() -> void:
	var g := _with_map("t_corner", [".#", ".."])
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(1, 1)), [[0, 1], [1, 1]], "goes around the corner")
	var g2 := _with_map("t_pinch", [".#", "#."])
	eq(Pathfinder.find(g2, Vector2i(0, 0), Vector2i(1, 1)), [], "no squeezing between two corners")
	var g3 := _with_map("t_open3", ["...", "...", "..."])
	eq(Pathfinder.find(g3, Vector2i(0, 0), Vector2i(2, 2)), [[1, 1], [2, 2]], "open diagonal is used")


func test_unreachable() -> void:
	var g := _with_map("t_wall", [".#.", ".#.", ".#."])
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(2, 2)), [], "a wall in between")
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(1, 1)), [], "a blocked target")


func test_fixed_tie_break() -> void:
	# Several routes cost the same here; the tie-break picks always this one.
	var g := _with_map("t_open5", [".....", ".....", ".....", ".....", "....."])
	var want := [[1, 0], [2, 0], [3, 1], [4, 2]]
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(4, 2)), want, "fixed route")
	eq(Pathfinder.find(Grid.build(cat, "t_open5"), Vector2i(0, 0), Vector2i(4, 2)), want, "same on a new grid")
	var a := Pathfinder.find(_town(), Vector2i(2, 2), Vector2i(37, 37))
	for i: int in 3:
		eq(Pathfinder.find(_town(), Vector2i(2, 2), Vector2i(37, 37)), a, "same route every time")


func test_routes_are_optimal() -> void:
	# A* against a plain Dijkstra on town_e (same step costs, same corner rule).
	var g := _town()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 6:
		var a := g.tile_of(g.walkable_tiles[rng.randi_range(0, g.walkable_tiles.size() - 1)])
		var b := g.tile_of(g.walkable_tiles[rng.randi_range(0, g.walkable_tiles.size() - 1)])
		var p := Pathfinder.find(g, a, b)
		eq(Pathfinder.cost_of(g, a, p), _dijkstra(g, a, b), "optimal %s -> %s" % [a, b])


func test_prefers_streets() -> void:
	# H1 criterion: (7,12) and (31,12) are joined by a straight row of grass (23 tiles) and by the streets
	# (down col 7, along row 18 across the plaza, up col 31). The route must take the streets.
	var g := _town()
	var from := Vector2i(7, 12)
	var p := Pathfinder.find(g, from, Vector2i(31, 12))
	check(not p.is_empty(), "there is a route")
	for t: Array in p:
		var kind := cat.tile_kind_of_char(str(cat.maps()["town_e"]["rows"][int(t[1])])[int(t[0])])
		check(kind in ["street", "plaza"], "tile %s is %s, not street or plaza" % [t, kind])
	var straight: Array = []
	for c: int in range(8, 32):
		straight.append([c, 12])
	check(Pathfinder.cost_of(g, from, p) < Pathfinder.cost_of(g, from, straight), "cheaper than the grass line")
	check(p.size() > straight.size(), "even if it walks more tiles")


func _dijkstra(g: Grid, a: Vector2i, b: Vector2i) -> int:
	var n := g.width * g.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[g.index(a.x, a.y)] = 0
	while true:
		var best := -1
		for i: int in n:
			if done[i] == 0 and dist[i] >= 0 and (best == -1 or dist[i] < dist[best]):
				best = i
		if best == -1:
			return -1
		if best == g.index(b.x, b.y):
			return dist[best]
		done[best] = 1
		var t := g.tile_of(best)
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var c := t.x + dx
				var r := t.y + dy
				if not g.walkable(c, r):
					continue
				var diag := dx != 0 and dy != 0
				if diag and (not g.walkable(t.x + dx, t.y) or not g.walkable(t.x, t.y + dy)):
					continue
				var nd := dist[best] + g.cost(c, r) * (Pathfinder.DIAGONAL if diag else Pathfinder.STRAIGHT)
				var ni := g.index(c, r)
				if dist[ni] == -1 or nd < dist[ni]:
					dist[ni] = nd
	return -1
