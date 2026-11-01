class_name Pathfinder
extends RefCounted
## Deterministic A* over a Grid (GDD 05 §5.4, D3). No NavigationServer.
## - 8 neighbours; a diagonal step only if both orthogonal tiles beside it are walkable (no corner cutting).
## - Step cost in integers: entering a tile costs walk_cost × 10 straight and walk_cost × 14 diagonally (×1.4).
## - Heuristic: octile distance at the cheapest walk cost (1), so it never overestimates (routes are optimal).
## - Fixed tie-break: lowest f, then lowest h, then lowest tile index; neighbours in a fixed order (N E S W, NE SE SW NW).
## Works on Grid.padded (blocked border) and the moves precomputed in Grid.link_*, so the inner loop has no bounds
## checks or function calls. Found routes are remembered in Grid.routes (static data, never in WorldState).
## (Named Pathfinder, not Path: avoids any clash with Godot's Path2D/Path3D family.)

const STRAIGHT: int = 10
const DIAGONAL: int = 14
# Order inside a bucket = h << 16 | padded tile index (16 bits: maps up to ~254×254).
const _IDX_BITS: int = 16
const _UNSEEN: int = 0x7FFFFFFF
## Routes remembered per grid before the memory is emptied (bounds memory; never changes a result).
const ROUTE_MEMORY: int = 20000


## Tiles to walk from `from` to `to`, without `from` and ending in `to`: [[col, row], ...].
## Empty if from == to or there is no way (the caller tells the two apart).
## The result is a new array every time (the caller may consume it). Routes are remembered per grid (Grid.routes):
## the same grid, origin and target always give the same route, so the memory only saves time.
static func find(grid: Grid, from: Vector2i, to: Vector2i) -> Array:
	if from == to or not grid.walkable(to.x, to.y) or not grid.in_bounds(from.x, from.y):
		return []
	var pw: int = grid.width + 2
	var start: int = (from.y + 1) * pw + from.x + 1
	var goal: int = (to.y + 1) * pw + to.x + 1
	var key: int = start * grid.padded.size() + goal
	var route: Variant = grid.routes.get(key)
	if route == null:
		route = search(grid, start, goal)
		if grid.routes.size() >= ROUTE_MEMORY:
			grid.routes.clear()
		grid.routes[key] = route
	var out: Array = []
	for i: int in route:
		out.append([i % pw - 1, i / pw - 1])
	return out


## The A* itself, on padded tile indices: the padded tiles from `start` (excluded) to `goal`, empty if none.
## Moves come from Grid.link_* (same order N E S W, NE SE SW NW, no corner cutting). Everything lives in packed int
## arrays and the hot loop has no calls and no Variant.
## Open list: the f of the tile being expanded never decreases (consistent heuristic) and an open tile's f is at most
## one step jump above it, so the open tiles sit in a ring of buckets by exact f (Grid.ring_mask); each bucket is a
## doubly linked list and the next tile is the least (h, tile index) of the lowest non-empty bucket. That is the
## same tile a heap keyed by (f, h, tile index) would give: the result is the same A* as with the heap.
static func search(grid: Grid, start: int, goal: int) -> PackedInt32Array:
	var n: int = grid.padded.size()
	var link_start: PackedInt32Array = grid.link_start
	var link_to: PackedInt32Array = grid.link_to
	var link_cost: PackedInt32Array = grid.link_cost
	var pcol: PackedInt32Array = grid.pad_col
	var prow: PackedInt32Array = grid.pad_row
	var mask: int = grid.ring_mask
	var g_cost := PackedInt32Array()
	g_cost.resize(n)
	g_cost.fill(_UNSEEN)
	var came := PackedInt32Array()
	came.resize(n)
	var nxt := PackedInt32Array()  # next / previous tile in the same bucket, -1 = none
	nxt.resize(n)
	var prv := PackedInt32Array()
	prv.resize(n)
	var f_of := PackedInt32Array()  # f of each open tile; -1 = not open (never seen, or expanded)
	f_of.resize(n)
	f_of.fill(-1)
	var hk := PackedInt32Array()  # h << _IDX_BITS | tile: the order inside a bucket (set when first seen)
	hk.resize(n)
	var head := PackedInt32Array()  # first tile of each bucket, -1 = empty
	head.resize(mask + 1)
	head.fill(-1)
	var gc: int = pcol[goal]
	var gr: int = prow[goal]
	var h0: int = _h(pcol[start], prow[start], gc, gr)
	g_cost[start] = 0
	f_of[start] = h0
	hk[start] = (h0 << _IDX_BITS) | start
	nxt[start] = -1
	prv[start] = -1
	head[h0 & mask] = start
	var open_n: int = 1
	var cf: int = h0  # f of the lowest bucket that may hold tiles
	while open_n > 0:
		# Next tile: lowest non-empty bucket, least (h, tile) in it.
		var b: int = cf & mask
		var cur: int = head[b]
		while cur == -1:
			cf += 1
			b = cf & mask
			cur = head[b]
		var best: int = hk[cur]
		var t: int = nxt[cur]
		while t != -1:
			var tk: int = hk[t]
			if tk < best:
				best = tk
				cur = t
			t = nxt[t]
		var cp: int = prv[cur]
		var cn: int = nxt[cur]
		if cp == -1:
			head[b] = cn
		else:
			nxt[cp] = cn
		if cn != -1:
			prv[cn] = cp
		f_of[cur] = -1
		open_n -= 1
		if cur == goal:
			var out := PackedInt32Array()
			var w: int = goal
			while w != start:
				out.append(w)
				w = came[w]
			out.reverse()
			return out
		var gcur: int = g_cost[cur]
		for e: int in range(link_start[cur], link_start[cur + 1]):
			var ni: int = link_to[e]
			# A consistent heuristic: an expanded tile never improves, so this test also skips expanded tiles.
			var ng: int = gcur + link_cost[e]
			if ng >= g_cost[ni]:
				continue
			g_cost[ni] = ng
			came[ni] = cur
			var h: int
			var of: int = f_of[ni]
			if of == -1:
				var dx: int = pcol[ni] - gc
				if dx < 0:
					dx = -dx
				var dy: int = prow[ni] - gr
				if dy < 0:
					dy = -dy
				h = STRAIGHT * dx + (DIAGONAL - STRAIGHT) * dy if dx >= dy else STRAIGHT * dy + (DIAGONAL - STRAIGHT) * dx
				hk[ni] = (h << _IDX_BITS) | ni
				open_n += 1
			else:
				h = hk[ni] >> _IDX_BITS
				# Already open with a worse f: out of its old bucket.
				var op: int = prv[ni]
				var on: int = nxt[ni]
				if op == -1:
					head[of & mask] = on
				else:
					nxt[op] = on
				if on != -1:
					prv[on] = op
			var f: int = ng + h
			f_of[ni] = f
			var fb: int = f & mask
			var fh: int = head[fb]
			nxt[ni] = fh
			prv[ni] = -1
			if fh != -1:
				prv[fh] = ni
			head[fb] = ni
	return PackedInt32Array()


## Total cost of walking `path` from `from` (the same units A* uses). -1 if a step is not allowed.
static func cost_of(grid: Grid, from: Vector2i, path: Array) -> int:
	var total := 0
	var prev := from
	for t: Array in path:
		var cur := Vector2i(int(t[0]), int(t[1]))
		var d := cur - prev
		if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO or not grid.walkable(cur.x, cur.y):
			return -1
		var diagonal := d.x != 0 and d.y != 0
		if diagonal and (not grid.walkable(prev.x + d.x, prev.y) or not grid.walkable(prev.x, prev.y + d.y)):
			return -1
		total += grid.cost(cur.x, cur.y) * (DIAGONAL if diagonal else STRAIGHT)
		prev = cur
	return total


static func _h(c: int, r: int, gc: int, gr: int) -> int:
	var dx := absi(c - gc)
	var dy := absi(r - gr)
	return STRAIGHT * maxi(dx, dy) + (DIAGONAL - STRAIGHT) * mini(dx, dy)
