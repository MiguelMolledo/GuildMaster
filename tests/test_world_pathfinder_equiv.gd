extends "res://tests/test_case.gd"
## The fast A* (Grid.link_*, inline indexed heap, route memory) gives exactly the routes of the previous A*: same
## tiles and same cost for any pair, on town_e and on random maps of every tile kind (ties included). The previous
## implementation is kept below, verbatim, as the reference (_ref_*). Also: the route memory hands out copies, and
## Grid.invalidate() forgets it.

const REF_IDX_BITS: int = 16
const REF_F_SHIFT: int = 39
const REF_MASK: int = (1 << REF_IDX_BITS) - 1
const REF_UNSEEN: int = 0x7FFFFFFF

var cat := Catalog.load_from()
var _found: int = 0  # non-empty routes compared


func _random_tile(g: Grid, rng: RandomNumberGenerator) -> Vector2i:
	return g.tile_of(g.walkable_tiles[rng.randi_range(0, g.walkable_tiles.size() - 1)])


func _same(g: Grid, a: Vector2i, b: Vector2i, label: String) -> bool:
	var want := _ref_find(g, a, b)
	var got := Pathfinder.find(g, a, b)
	if got != want:
		eq(got, want, "%s %s -> %s" % [label, a, b])
		return false
	if not want.is_empty():
		_found += 1
	var again := Pathfinder.find(g, a, b)  # from the route memory
	if again != want:
		eq(again, want, "%s %s -> %s (remembered)" % [label, a, b])
		return false
	return true


func test_same_routes_on_town_e() -> void:
	var g := Grid.of(cat, "town_e")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	var ok := 0
	var n := 200
	for i: int in n:
		var a := _random_tile(g, rng)
		var b := _random_tile(g, rng)
		if _same(g, a, b, "town_e"):
			ok += 1
	eq(ok, n, "identical routes on town_e")
	# From every door of the scenario to every other door (the routes the routines walk).
	var st: Dictionary = NewGame.from_scenario("town_e_start")["state"].buildings
	var doors: Array = []
	for id: String in st:
		var d: Array = st[id].get("door", [])
		if d.size() == 2:
			doors.append(Vector2i(int(d[0]), int(d[1])))
	check(doors.size() >= 10, "town_e_start has doors (%d)" % doors.size())
	var bad := 0
	for a: Vector2i in doors:
		for b: Vector2i in doors:
			if not _same(g, a, b, "door"):
				bad += 1
	eq(bad, 0, "identical door-to-door routes")


func test_same_routes_on_random_maps() -> void:
	# Plus a made-up costly kind: a larger step jump needs a larger ring of buckets in Pathfinder (Grid.ring_mask).
	cat.tiles["mud_test"] = {"char": "m", "walk_cost": 50}
	var chars := [".", "=", "P", ",", "f", "b", "m", "#", "w", "T"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bad := 0
	_found = 0
	var tried := 0
	for m: int in 24:
		var w := rng.randi_range(3, 30)
		var h := rng.randi_range(3, 30)
		var blocked_share := rng.randf_range(0.0, 0.4)
		var uniform := m % 4 == 0  # one kind only: every route ties with many others
		var rows: Array = []
		for r: int in h:
			var row := ""
			for c: int in w:
				if rng.randf() < blocked_share:
					row += chars[rng.randi_range(7, 9)]
				elif uniform:
					row += "=" if m % 8 == 0 else "."
				else:
					row += chars[rng.randi_range(0, 6)]
			rows.append(row)
		var id := "t_equiv_%d" % m
		cat.tables["maps"][id] = {"id": id, "size": [w, h], "rows": rows, "spawns": {}}
		var g := Grid.of(cat, id)
		if "m" in "".join(rows):
			check(g.ring_mask + 1 > 50 * Pathfinder.DIAGONAL + Pathfinder.DIAGONAL, "%s: ring wider than a step jump" % id)
		if g.walkable_tiles.is_empty():
			continue
		for i: int in 30:
			var a := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))  # may be blocked: allowed as origin
			var b := _random_tile(g, rng)
			tried += 1
			if not _same(g, a, b, id):
				bad += 1
	eq(bad, 0, "identical routes on random maps")
	check(_found * 2 > tried, "most random pairs have a route (%d of %d)" % [_found, tried])


func test_same_costs() -> void:
	var g := Grid.of(cat, "town_e")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i: int in 20:
		var a := _random_tile(g, rng)
		var b := _random_tile(g, rng)
		eq(Pathfinder.cost_of(g, a, Pathfinder.find(g, a, b)), Pathfinder.cost_of(g, a, _ref_find(g, a, b)),
			"same cost %s -> %s" % [a, b])


func test_memory_hands_out_copies() -> void:
	var g := Grid.of(cat, "town_e")
	var a := Vector2i(20, 21)
	var b := Vector2i(8, 12)
	var p := Pathfinder.find(g, a, b)
	check(p.size() > 2, "a long route")
	var want := p.duplicate(true)
	p.pop_front()  # Movement consumes its path like this
	(p[0] as Array)[0] = -5
	eq(Pathfinder.find(g, a, b), want, "a consumed route does not change the remembered one")
	check(g.routes.size() > 0, "routes are remembered on the grid")


func test_invalidate_forgets_routes() -> void:
	cat.tables["maps"]["t_inval"] = {"id": "t_inval", "size": [3, 3], "rows": ["...", "...", "..."], "spawns": {}}
	var g := Grid.of(cat, "t_inval")
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(2, 2)), [[1, 1], [2, 2]], "open diagonal")
	g.costs[g.index(1, 1)] = Grid.BLOCKED
	g.invalidate()
	eq(g.routes.size(), 0, "memory emptied")
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(2, 2)), _ref_find(g, Vector2i(0, 0), Vector2i(2, 2)),
		"new route after the change, the same as the reference")
	eq(Pathfinder.find(g, Vector2i(0, 0), Vector2i(2, 2)).size(), 4, "goes around the new block")


# ---- Reference: the previous A* (sim/world/pathfinder.gd before the speed-up), unchanged. ----

static func _ref_find(grid: Grid, from: Vector2i, to: Vector2i) -> Array:
	if from == to or not grid.walkable(to.x, to.y) or not grid.in_bounds(from.x, from.y):
		return []
	var pw: int = grid.width + 2
	var cells: PackedInt32Array = grid.padded
	var n: int = cells.size()
	var g_cost := PackedInt32Array()
	g_cost.resize(n)
	g_cost.fill(REF_UNSEEN)
	var came := PackedInt32Array()
	came.resize(n)
	var closed := PackedByteArray()
	closed.resize(n)
	var start: int = (from.y + 1) * pw + from.x + 1
	var goal: int = (to.y + 1) * pw + to.x + 1
	var gc: int = to.x + 1
	var gr: int = to.y + 1
	# Straight k: N, E, S, W. Diagonal k joins straight k and k+1: NE, SE, SW, NW.
	var off := PackedInt32Array([-pw, 1, pw, -1, -pw])
	var doff := PackedInt32Array([1 - pw, 1 + pw, pw - 1, -pw - 1])
	var mult := PackedInt32Array([Pathfinder.STRAIGHT, Pathfinder.STRAIGHT, Pathfinder.STRAIGHT, Pathfinder.STRAIGHT, Pathfinder.DIAGONAL, Pathfinder.DIAGONAL, Pathfinder.DIAGONAL, Pathfinder.DIAGONAL])
	var heap: Array = []
	g_cost[start] = 0
	var h0: int = _ref_h(from.x + 1, from.y + 1, gc, gr)
	_ref_push(heap, (h0 << REF_F_SHIFT) | (h0 << REF_IDX_BITS) | start)
	while not heap.is_empty():
		var cur: int = _ref_pop(heap) & REF_MASK
		if closed[cur] == 1:
			continue
		if cur == goal:
			return _ref_rebuild(pw, came, start, goal)
		closed[cur] = 1
		var gcur: int = g_cost[cur]
		# Walkable straight neighbours, as bits (a diagonal needs both of its straight neighbours).
		var open_bits: int = 0
		for k: int in 8:
			var ni: int
			if k < 4:
				ni = cur + off[k]
			else:
				var j: int = k - 4
				if (open_bits >> j) & 1 == 0 or (open_bits >> ((j + 1) & 3)) & 1 == 0:
					continue
				ni = cur + doff[j]
			var step: int = cells[ni]
			if step == 0:
				continue
			if k < 4:
				open_bits |= 1 << k
			# A consistent heuristic: a closed tile never improves, so this test also skips closed tiles.
			var ng: int = gcur + step * mult[k]
			if ng >= g_cost[ni]:
				continue
			g_cost[ni] = ng
			came[ni] = cur
			var dx: int = absi(ni % pw - gc)
			var dy: int = absi(ni / pw - gr)
			var h: int = Pathfinder.STRAIGHT * dx + (Pathfinder.DIAGONAL - Pathfinder.STRAIGHT) * dy if dx >= dy else Pathfinder.STRAIGHT * dy + (Pathfinder.DIAGONAL - Pathfinder.STRAIGHT) * dx
			_ref_push(heap, ((ng + h) << REF_F_SHIFT) | (h << REF_IDX_BITS) | ni)
	return []


static func _ref_h(c: int, r: int, gc: int, gr: int) -> int:
	var dx := absi(c - gc)
	var dy := absi(r - gr)
	return Pathfinder.STRAIGHT * maxi(dx, dy) + (Pathfinder.DIAGONAL - Pathfinder.STRAIGHT) * mini(dx, dy)


static func _ref_rebuild(pw: int, came: PackedInt32Array, start: int, goal: int) -> Array:
	var out: Array = []
	var cur := goal
	while cur != start:
		out.append([cur % pw - 1, cur / pw - 1])
		cur = came[cur]
	out.reverse()
	return out


# Binary min-heap of int keys.
static func _ref_push(heap: Array, k: int) -> void:
	heap.append(k)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		var pk: int = heap[p]
		if pk <= k:
			break
		heap[i] = pk
		i = p
	heap[i] = k


static func _ref_pop(heap: Array) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	var n := heap.size()
	if n == 0:
		return top
	var i := 0
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var c := l
		var ck: int = heap[l]
		if l + 1 < n and int(heap[l + 1]) < ck:
			c = l + 1
			ck = heap[c]
		if ck >= last:
			break
		heap[i] = ck
		i = c
	heap[i] = last
	return top
