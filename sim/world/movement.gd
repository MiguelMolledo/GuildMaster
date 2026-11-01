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
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		var path: Array = ch.get("path", [])
		if path.is_empty():
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


## Validates and starts a walk to `tile` ([col, row]). {"ok", "reason"} like any order.
## A new route replaces the old one; progress toward the next tile is kept only if the next tile is the same.
static func move_to(sim: Sim, actor: String, tile: Variant) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var ch: Dictionary = st.characters[actor]
	if not bool(ch.get("alive", true)):
		return Orders.fail("dead")
	var grid := Grid.of(sim.catalog, st.map_id)
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
	if from != to:
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
