class_name BotWanderer
extends RefCounted
## Bot that walks everybody around the town (GDD 07 §7.2, H1): to each living character standing still it gives,
## now and then, a move_to to a random walkable tile of the map. Who is inside a building is left alone (H3: the
## rival smith starts in his forge). The randomness comes from state.rng.
## Measures that routes, movement and arrivals hold up for days. Gives the same orders as the UI.

const ID: String = "wanderer"
const CHANCE_PER_MINUTE: float = 0.05  # a still character sets off after ~20 min on average (test bot, not a rule)


func orders(sim: Sim) -> Array:
	var grid := Grid.of(sim.catalog, sim.state.map_id)
	if grid == null or grid.walkable_tiles.is_empty():
		return []
	var out: Array = []
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		if not bool(ch.get("alive", true)) or not (ch.get("path", []) as Array).is_empty() \
				or str(ch.get("location", "")) != "" or Life.offstage(sim.state, id):  # vida: not on the map
			continue
		if sim.state.rng.randf() >= CHANCE_PER_MINUTE:
			continue
		var t := grid.tile_of(grid.walkable_tiles[sim.state.rng.randi_range(0, grid.walkable_tiles.size() - 1)])
		out.append({"type": "move_to", "actor": id, "tile": [t.x, t.y]})
	return out
