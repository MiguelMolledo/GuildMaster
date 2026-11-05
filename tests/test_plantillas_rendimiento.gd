extends "res://tests/test_case.gd"
## Plantillas, rendimiento: the large towns route with the ALT landmarks (sim/world/route_atlas.gd), at the same cost
## as Pathfinder's A*; town_e keeps Pathfinder.search (the targets); the quiet minutes of TownLife (TownLife._quiet)
## change nothing: the same game with them and without them, in Vilarrasa and in Bellcaire.

var cat := Catalog.load_from()


func _route_cost(g: Grid, start: int, path: PackedInt32Array) -> int:
	var pw := g.width + 2
	var total := 0
	var prev := start
	for x: int in path:
		var diag := absi(x - prev) != 1 and absi(x - prev) != pw
		total += g.padded[x] * (Pathfinder.DIAGONAL if diag else Pathfinder.STRAIGHT)
		prev = x
	return total


func test_the_large_towns_route_with_landmarks_at_the_same_cost() -> void:
	check(Grid.of(cat, "town_e").atlas == null, "Vilarrasa keeps Pathfinder.search (no routing in its map)")
	var g := Grid.of(cat, "region_capital")
	check(g.atlas != null and g.atlas.landmarks.size() == 4, "Bellcaire routes with 4 landmarks")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pw := g.width + 2
	var bad: Array = []
	for i: int in 150:
		var a := g.tile_of(g.walkable_tiles[rng.randi_range(0, g.walkable_tiles.size() - 1)])
		var b := g.tile_of(g.walkable_tiles[rng.randi_range(0, g.walkable_tiles.size() - 1)])
		var s := (a.y + 1) * pw + a.x + 1
		var e := (b.y + 1) * pw + b.x + 1
		var p1 := Pathfinder.search(g, s, e)
		var p2 := g.atlas.search(g, s, e)
		if p1.is_empty() != p2.is_empty() or _route_cost(g, s, p1) != _route_cost(g, s, p2):
			bad.append([a, b])
	eq(bad, [], "every route of the landmarks costs what A*'s costs")
	var again := g.atlas.search(g, (5 + 1) * pw + 40 + 1, (60 + 1) * pw + 30 + 1)
	eq(again, g.atlas.search(g, (5 + 1) * pw + 40 + 1, (60 + 1) * pw + 30 + 1), "the same route every time")


func _played(scenario: String, minutes: int, quiet: bool) -> String:
	TownLife.quiet = quiet
	var sim := Sim.new(NewGame.from_scenario(scenario, 1)["state"], cat)
	var bot := BotIdle.new()
	for i: int in minutes:
		sim.step(bot.orders(sim))
	TownLife.quiet = true
	return sim.state_hash()


func test_the_quiet_minutes_change_nothing() -> void:
	for sc: String in ["town_e_start", "region_capital_start", "life_plaza"]:
		eq(_played(sc, 900, false), _played(sc, 900, true), "%s: the same game with and without the quiet minutes" % sc)
