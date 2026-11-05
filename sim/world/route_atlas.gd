class_name RouteAtlas
extends RefCounted
## Faster routes for the large town maps (data/maps "routing": {"landmarks": K}; plantillas, Bellcaire): A* with the
## ALT heuristic (A*, Landmarks and the Triangle inequality). For K landmarks on the map's edge it keeps the walking
## cost from each landmark to every tile and from every tile to it (one Dijkstra each way, computed once per map and
## kept across catalogs: static data, never in WorldState); the heuristic of a tile n towards the goal g is the largest
## of the octile distance (Pathfinder's) and, per landmark L, d(L, g) - d(L, n) and d(n, L) - d(g, L). It never
## overestimates and is consistent, so routes keep their optimal cost; where the streets cost 1 and the grass 10 it
## is far tighter than the octile distance and A* opens far fewer tiles. Deterministic: same grid, origin and goal,
## same route. Only for the maps that ask for it: town_e (the targets) keeps Pathfinder.search as it was.

const INF: int = 1 << 29
const _IDX_BITS: int = 16
const RING_MASK: int = 1023  # larger than the largest jump of f between neighbours (two step costs: h is asymmetric)

static var _cache: Dictionary = {}  # "<map>|<rows hash>|<K>" -> RouteAtlas (the same map in any catalog)

var landmarks: PackedInt32Array = PackedInt32Array()  # padded indices
var fwd: Array = []  # per landmark: PackedInt32Array cost from it to each padded tile (INF unreachable)
var bwd: Array = []  # per landmark: PackedInt32Array cost from each padded tile to it
## The same, flat for the search's inner loop: lm[i * 2K + 2j] = cost from landmark j to tile i, + 1 = from i to j.
var lm: PackedInt32Array = PackedInt32Array()


## The atlas of `grid` for map data `m` ("routing" in it), built once per map; null if the map does not ask for one.
static func for_map(grid: Grid, m: Dictionary) -> RouteAtlas:
	var rt: Variant = m.get("routing")
	if not rt is Dictionary or int((rt as Dictionary).get("landmarks", 0)) <= 0:
		return null
	var k := int(rt["landmarks"])
	var key := "%s|%d|%d" % [grid.map_id, str(m.get("rows", [])).hash(), k]
	if not _cache.has(key):
		var t0 := Time.get_ticks_usec()
		var a := RouteAtlas.new()
		a._build(grid, k)
		_cache[key] = a
		if OS.is_debug_build():
			print("[RouteAtlas] %s: %d hitos en %.1f ms" % [grid.map_id, a.landmarks.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	return _cache[key]


func _build(grid: Grid, k: int) -> void:
	var pw := grid.width + 2
	var ph := grid.height + 2
	# the walkable tiles nearest to the corners and the middle of each edge (the first k of them), by Chebyshev
	# distance to that point and then by index: the same landmarks every time
	var points: Array = [Vector2i(0, 0), Vector2i(pw - 1, ph - 1), Vector2i(pw - 1, 0), Vector2i(0, ph - 1),
		Vector2i(pw / 2, 0), Vector2i(pw / 2, ph - 1), Vector2i(0, ph / 2), Vector2i(pw - 1, ph / 2)]
	for p: Vector2i in points.slice(0, k):
		var best := -1
		var bd := INF
		for i: int in grid.padded.size():
			if grid.padded[i] == Grid.BLOCKED:
				continue
			var d := maxi(absi(grid.pad_col[i] - p.x), absi(grid.pad_row[i] - p.y))
			if d < bd:
				bd = d
				best = i
		if best >= 0 and not best in landmarks:
			landmarks.append(best)
	for l: int in landmarks:
		fwd.append(_dijkstra(grid, l, true))
		bwd.append(_dijkstra(grid, l, false))
	var kk := landmarks.size()
	var n := grid.padded.size()
	lm.resize(n * 2 * kk)
	for j: int in kk:
		var fj: PackedInt32Array = fwd[j]
		var bj: PackedInt32Array = bwd[j]
		for i: int in n:
			lm[i * 2 * kk + 2 * j] = fj[i]
			lm[i * 2 * kk + 2 * j + 1] = bj[i]


## Costs from `src` to every tile (forward) or from every tile to `src` (backward), over Grid's moves (the cost of a
## move is the walk cost of the tile entered, × 10 straight or × 14 diagonal). Dial's algorithm on a ring of buckets.
static func _dijkstra(grid: Grid, src: int, forward: bool) -> PackedInt32Array:
	var n := grid.padded.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(INF)
	var done := PackedByteArray()
	done.resize(n)
	var ring: Array = []  # buckets of plain Arrays (a PackedInt32Array inside an Array is copied when read)
	for i: int in RING_MASK + 1:
		ring.append([])
	dist[src] = 0
	(ring[0] as Array).append(src)
	var pending := 1
	var cur := 0
	var link_start := grid.link_start
	var link_to := grid.link_to
	var link_cost := grid.link_cost
	var padded := grid.padded
	var pcol := grid.pad_col
	var prow := grid.pad_row
	while pending > 0:
		var bucket: Array = ring[cur & RING_MASK]
		if bucket.is_empty():
			cur += 1
			continue
		ring[cur & RING_MASK] = []
		pending -= bucket.size()
		for u: int in bucket:
			if done[u] == 1 or dist[u] != cur:
				continue
			done[u] = 1
			for e: int in range(link_start[u], link_start[u + 1]):
				var v: int = link_to[e]
				var c: int
				if forward:
					c = link_cost[e]  # u -> v: the cost of entering v
				else:
					# v -> u (we go backwards): the cost of entering u from v; u must be enterable
					if padded[u] == Grid.BLOCKED:
						continue
					c = padded[u] * (Pathfinder.DIAGONAL if pcol[u] != pcol[v] and prow[u] != prow[v] else Pathfinder.STRAIGHT)
				var nd := cur + c
				if nd < dist[v]:
					dist[v] = nd
					(ring[nd & RING_MASK] as Array).append(v)
					pending += 1
		cur += 1
	return dist


## A* from padded `start` to padded `goal` with the ALT heuristic: the padded tiles of the route (without start),
## empty if none. Same open-list shape and tie-break as Pathfinder.search (lowest f, then h, then tile index).
func search(grid: Grid, start: int, goal: int) -> PackedInt32Array:
	var n: int = grid.padded.size()
	var link_start: PackedInt32Array = grid.link_start
	var link_to: PackedInt32Array = grid.link_to
	var link_cost: PackedInt32Array = grid.link_cost
	var pcol: PackedInt32Array = grid.pad_col
	var prow: PackedInt32Array = grid.pad_row
	var mask: int = RING_MASK
	var kk := landmarks.size()
	var k2 := 2 * kk
	var fg := PackedInt32Array()  # d(L, goal)
	var bg := PackedInt32Array()  # d(goal, L)
	fg.resize(kk)
	bg.resize(kk)
	var gl := PackedInt32Array()  # the goal's row of lm
	gl.resize(k2)
	for j: int in kk:
		fg[j] = (fwd[j] as PackedInt32Array)[goal]
		bg[j] = (bwd[j] as PackedInt32Array)[goal]
		gl[2 * j] = fg[j]
		gl[2 * j + 1] = bg[j]
	var g_cost := PackedInt32Array()
	g_cost.resize(n)
	g_cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	var nxt := PackedInt32Array()
	nxt.resize(n)
	var prv := PackedInt32Array()
	prv.resize(n)
	var f_of := PackedInt32Array()
	f_of.resize(n)
	f_of.fill(-1)
	var hk := PackedInt32Array()
	hk.resize(n)
	var head := PackedInt32Array()
	head.resize(mask + 1)
	head.fill(-1)
	var gc: int = pcol[goal]
	var gr: int = prow[goal]
	var h0: int = _h(start, gc, gr, pcol, prow, fg, bg, kk)
	g_cost[start] = 0
	f_of[start] = h0
	hk[start] = (h0 << _IDX_BITS) | start
	nxt[start] = -1
	prv[start] = -1
	head[h0 & mask] = start
	var open_n: int = 1
	var cf: int = h0
	while open_n > 0:
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
				h = 10 * dx + 4 * dy if dx >= dy else 10 * dy + 4 * dx  # octile (STRAIGHT 10, DIAGONAL 14)
				var base: int = ni * k2
				for j2: int in range(0, k2, 2):
					var fi: int = lm[base + j2]
					var fgj: int = gl[j2]
					if fi < INF and fgj < INF and fgj - fi > h:
						h = fgj - fi
					var bi: int = lm[base + j2 + 1]
					var bgj: int = gl[j2 + 1]
					if bi < INF and bgj < INF and bi - bgj > h:
						h = bi - bgj
				hk[ni] = (h << _IDX_BITS) | ni
				open_n += 1
			else:
				h = hk[ni] >> _IDX_BITS
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


func _h(i: int, gc: int, gr: int, pcol: PackedInt32Array, prow: PackedInt32Array, fg: PackedInt32Array,
		bg: PackedInt32Array, kk: int) -> int:
	var dx: int = pcol[i] - gc
	if dx < 0:
		dx = -dx
	var dy: int = prow[i] - gr
	if dy < 0:
		dy = -dy
	var h: int = Pathfinder.STRAIGHT * dx + (Pathfinder.DIAGONAL - Pathfinder.STRAIGHT) * dy if dx >= dy \
		else Pathfinder.STRAIGHT * dy + (Pathfinder.DIAGONAL - Pathfinder.STRAIGHT) * dx
	for j: int in kk:
		var fi: int = (fwd[j] as PackedInt32Array)[i]
		var fgj: int = fg[j]
		if fi < INF and fgj < INF and fgj - fi > h:
			h = fgj - fi
		var bi: int = (bwd[j] as PackedInt32Array)[i]
		var bgj: int = bg[j]
		if bi < INF and bgj < INF and bi - bgj > h:
			h = bi - bgj
	return h
