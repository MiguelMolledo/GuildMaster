extends "res://tests/test_case.gd"
## Plantillas, rendimiento: the large towns route with the ALT landmarks (sim/world/route_atlas.gd), at the same cost
## as Pathfinder's A*; town_e keeps Pathfinder.search (the targets); the quiet minutes of TownLife (TownLife._quiet)
## change nothing: the same game with them and without them, in Vilarrasa and in Bellcaire (also with the wanderer);
## the level of detail keeps the town as alive.

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


func _played(scenario: String, minutes: int, quiet: bool, wanderer: bool = false) -> String:
	TownLife.quiet = quiet
	var sim := Sim.new(NewGame.from_scenario(scenario, 1)["state"], cat)
	var bot: Object = BotWanderer.new() if wanderer else BotIdle.new()
	for i: int in minutes:
		sim.step(bot.orders(sim))
	TownLife.quiet = true
	return sim.state_hash()


func test_the_quiet_minutes_change_nothing() -> void:
	for sc: String in ["town_e_start", "region_capital_start", "life_plaza", "life_bandits"]:
		eq(_played(sc, 900, false), _played(sc, 900, true), "%s: the same game with and without the quiet minutes" % sc)
	# the wanderer sends the townsfolk on walks of its own (some while they wait to ask for a route again)
	for sc: String in ["town_e_start", "region_capital_start"]:
		eq(_played(sc, 900, false, true), _played(sc, 900, true, true), "%s with the wanderer: the same game" % sc)
	# the Taberna-Posada with the festivals on: a neighbour at the tavern's door takes its one try to come in
	eq(_inn_played(false), _inn_played(true), "innkeeper_start with the festivals: the same game")


## A day of innkeeper_start as the inn QA plays it (life and festivals on), its state hash every hour.
func _inn_played(quiet: bool) -> String:
	var c := Catalog.load_from()
	c.life_tables.get("life", {})["enabled"] = true
	c.festivals["enabled"] = true
	TownLife.quiet = quiet
	var sim := Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], c)
	var bot := BotInnkeeper.new()
	var hashes: Array = []  # every hour: a difference can heal when the activity ends
	for i: int in Clock.MINUTES_PER_DAY:
		sim.step(bot.orders(sim))
		if i % 60 == 59:
			hashes.append(sim.state_hash())
	TownLife.quiet = true
	return ",".join(hashes)


## A day of `scenario` with the settled townsfolk every `every` minutes (0 = every minute): activities started by
## kind, orders refused, townsfolk at the end.
func _day(scenario: String, every: int) -> Dictionary:
	var c := Catalog.load_from()
	var m: Dictionary = c.maps()[NewGame.from_scenario(scenario)["state"].map_id]
	if every > 0:
		m["detail"] = {"settled_every": every}
	else:
		m.erase("detail")
	var sim := Sim.new(NewGame.from_scenario(scenario, 1)["state"], c)
	var acts := {}
	var refused := 0
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			match str(e.get("type", "")):
				"order_refused":
					refused += 1
				"town_state":
					var a := str(e.get("activity", ""))
					if a != "":
						acts[a] = int(acts.get(a, 0)) + 1
	return {"acts": acts, "refused": refused, "folk": Population.townsfolk(sim.state).size()}


func test_the_level_of_detail_keeps_the_town_alive() -> void:
	check(not (cat.maps()["town_e"] as Dictionary).has("detail"), "Vilarrasa keeps every townsperson every minute")
	check(int(cat.maps()["region_capital"].get("detail", {}).get("settled_every", 0)) > 1, "Bellcaire has its level of detail")
	var full := _day("region_capital_start", 0)
	var lod := _day("region_capital_start", 5)
	eq(lod["refused"], 0, "no order refused with the level of detail")
	eq(lod["folk"], full["folk"], "the same townsfolk")
	for a: String in ["shopping", "chat", "wash", "water", "stroll"]:
		var f := float(full["acts"].get(a, 0))
		var l := float(lod["acts"].get(a, 0))
		check(f == 0.0 or absf(l - f) / f <= 0.35, "%s: %d with every minute, %d with the level of detail" % [a, f, l])
