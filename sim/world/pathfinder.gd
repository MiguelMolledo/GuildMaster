class_name Pathfinder
extends RefCounted
## Deterministic A* over a Grid (GDD 05 §5.4, D3). No NavigationServer.
## - 8 neighbours; a diagonal step only if both orthogonal tiles beside it are walkable (no corner cutting).
## - Step cost in integers: entering a tile costs walk_cost × 10 straight and walk_cost × 14 diagonally (×1.4).
## - Heuristic: octile distance at the cheapest walk cost (1), so it never overestimates (routes are optimal).
## - Fixed tie-break: lowest f, then lowest h, then lowest tile index; neighbours in a fixed order (N E S W, NE SE SW NW).
## Works on Grid.padded (blocked border) so the inner loop has no bounds checks or function calls.
## (Named Pathfinder, not Path: avoids any clash with Godot's Path2D/Path3D family.)

const STRAIGHT: int = 10
const DIAGONAL: int = 14
# Heap key = f (24 bits) | h (23 bits) | padded tile index (16 bits: maps up to ~254×254, costs well below 2^23).
const _IDX_BITS: int = 16
const _F_SHIFT: int = 39
const _MASK: int = (1 << _IDX_BITS) - 1
const _UNSEEN: int = 0x7FFFFFFF


## Tiles to walk from `from` to `to`, without `from` and ending in `to`: [[col, row], ...].
## Empty if from == to or there is no way (the caller tells the two apart).
static func find(grid: Grid, from: Vector2i, to: Vector2i) -> Array:
	if from == to or not grid.walkable(to.x, to.y) or not grid.in_bounds(from.x, from.y):
		return []
	var pw: int = grid.width + 2
	var cells: PackedInt32Array = grid.padded
	var n: int = cells.size()
	var g_cost := PackedInt32Array()
	g_cost.resize(n)
	g_cost.fill(_UNSEEN)
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
	var mult := PackedInt32Array([STRAIGHT, STRAIGHT, STRAIGHT, STRAIGHT, DIAGONAL, DIAGONAL, DIAGONAL, DIAGONAL])
	var heap: Array = []
	g_cost[start] = 0
	var h0: int = _h(from.x + 1, from.y + 1, gc, gr)
	_push(heap, (h0 << _F_SHIFT) | (h0 << _IDX_BITS) | start)
	while not heap.is_empty():
		var cur: int = _pop(heap) & _MASK
		if closed[cur] == 1:
			continue
		if cur == goal:
			return _rebuild(pw, came, start, goal)
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
			var h: int = STRAIGHT * dx + (DIAGONAL - STRAIGHT) * dy if dx >= dy else STRAIGHT * dy + (DIAGONAL - STRAIGHT) * dx
			_push(heap, ((ng + h) << _F_SHIFT) | (h << _IDX_BITS) | ni)
	return []


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


static func _rebuild(pw: int, came: PackedInt32Array, start: int, goal: int) -> Array:
	var out: Array = []
	var cur := goal
	while cur != start:
		out.append([cur % pw - 1, cur / pw - 1])
		cur = came[cur]
	out.reverse()
	return out


# Binary min-heap of int keys.
static func _push(heap: Array, k: int) -> void:
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


static func _pop(heap: Array) -> int:
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
