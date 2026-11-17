class_name Movement
extends RefCounted
## Characters walking the town, one sim step = one game minute (GDD 05 §5.4, D3).
## A character with a `path` adds a minute to `move_progress`; at `minutes_per_tile` (data/time.json) it enters the
## next tile of the path. Events: character_moved {actor, from, to} per tile, character_arrived {actor, tile} at the end.
## Routes come from Pathfinder over the map's Grid; the move_to order (Orders) sets them.


static func minutes_per_tile(catalog: Catalog) -> int:
	return maxi(int(catalog.time.get("minutes_per_tile", 1)), 1)


## Moves every walking character one minute. Called by Sim.step after the clock.
static func step(sim: Sim) -> void:
	var mpt := minutes_per_tile(sim.catalog)
	NpcActions.step_holds(sim)
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		var path: Array = ch.get("path", [])
		if path.is_empty():
			continue
		if NpcActions.held(sim.state, id):   # it waits for whoever hailed it (NpcActions.order_hail)
			continue
		if not bool(ch.get("alive", true)):
			ch["path"] = []
			ch["move_progress"] = 0
			continue
		var progress := int(ch.get("move_progress", 0)) + 1
		if progress < mpt:
			ch["move_progress"] = progress
			continue
		var from: Array = ch.get("position", [0, 0])
		var next: Array = path.pop_front()
		var to := [int(next[0]), int(next[1])]
		ch["position"] = to
		ch["move_progress"] = 0
		sim.events.append({"type": "character_moved", "actor": id, "from": [int(from[0]), int(from[1])], "to": to})
		if path.is_empty():
			sim.events.append({"type": "character_arrived", "actor": id, "tile": to})
			if OS.is_debug_build():
				print("[Movement] %s llega (tile=%s)" % [id, to])


## Whether a walker on `from` may step onto its neighbour `from + d` (one of the 8): the tile is walkable and a
## diagonal step has both tiles beside it walkable (no corner cutting, as Pathfinder).
static func can_step(grid: Grid, from: Vector2i, d: Vector2i) -> bool:
	if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
		return false
	var to := from + d
	if not grid.in_bounds(to.x, to.y) or not grid.walkable(to.x, to.y):
		return false
	if d.x != 0 and d.y != 0:
		return grid.walkable(from.x + d.x, from.y) and grid.walkable(from.x, from.y + d.y)
	return true


const ROUTE_MAX: int = 32  # tiles of a move_to's own route at most


## The route of a move_to that brings its own ("route": the keys walk tile by tile, WorldView.key_walk) as a path
## [[col, row], ...], or [] if it is not one: every tile a step (can_step) from the one before, the first from
## `from`, the last one `to`, ROUTE_MAX tiles at most.
static func checked_route(grid: Grid, from: Vector2i, to: Vector2i, route: Array) -> Array:
	if route.is_empty() or route.size() > ROUTE_MAX:
		return []
	var path: Array = []
	var at := from
	for t: Variant in route:
		if not (t is Array and (t as Array).size() == 2):
			return []
		var next := Vector2i(int((t as Array)[0]), int((t as Array)[1]))
		if not can_step(grid, at, next - at):
			return []
		path.append([next.x, next.y])
		at = next
	return path if at == to else []


## Validates and starts a walk to `tile` ([col, row]). {"ok", "reason"} like any order.
## A new route replaces the old one; progress toward the next tile is kept only if the next tile is the same.
## `route` (an Array of tiles ending on `tile`): walk exactly those tiles instead of the cheapest route; blocked if
## it is not a walk (checked_route).
static func move_to(sim: Sim, actor: String, tile: Variant, route: Variant = null) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	if not bool(ch.get("alive", true)):
		return Orders.fail("dead")
	var grid := Grid.for_state(sim.catalog, st)  # H6: with what is built on the plots
	if grid == null:
		return Orders.fail("no_map")
	if not (tile is Array and (tile as Array).size() == 2):
		return Orders.fail("out_of_bounds")
	var to := Vector2i(int(tile[0]), int(tile[1]))
	if not grid.in_bounds(to.x, to.y):
		return Orders.fail("out_of_bounds")
	if not grid.walkable(to.x, to.y):
		return Orders.fail("blocked")
	var pos: Array = ch.get("position", [0, 0])
	var from := Vector2i(int(pos[0]), int(pos[1]))
	var old: Array = ch.get("path", [])
	var path: Array = []
	if from != to and route is Array:
		path = checked_route(grid, from, to, route as Array)
		if path.is_empty():
			return Orders.fail("blocked")
	elif from != to:
		path = Pathfinder.find(grid, from, to)
		if path.is_empty():
			return Orders.fail("unreachable")
	var same_next := not old.is_empty() and not path.is_empty() \
		and int(old[0][0]) == int(path[0][0]) and int(old[0][1]) == int(path[0][1])
	ch["path"] = path
	ch["move_progress"] = int(ch.get("move_progress", 0)) if same_next else 0
	if OS.is_debug_build():
		print("[Movement] %s move_to %s desde %s (tiles=%d)" % [actor, [to.x, to.y], [from.x, from.y], path.size()])
	return Orders.ok()
