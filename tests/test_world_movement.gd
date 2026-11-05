extends "res://tests/test_case.gd"
## Movement in the sim (GDD 05 §5.4, D3): the move_to order, walking tile by tile, refusals, save round trip,
## determinism.

var cat := Catalog.load_from()


func _sim() -> Sim:
	var st: WorldState = NewGame.from_scenario("town_e_start", 1)["state"]
	st.families["fam_0003"]["ai_profile"] = ""  # the rival smith (H3) off: these tests count one actor's events
	return Sim.new(st, cat)


func _go(actor: String, tile: Variant) -> Dictionary:
	return {"type": "move_to", "actor": actor, "tile": tile}


func _chr(sim: Sim, id: String) -> Dictionary:
	return sim.state.characters[id]


func _of_type(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func test_minutes_per_tile_comes_from_data() -> void:
	eq(Movement.minutes_per_tile(cat), int(cat.time["minutes_per_tile"]), "data/time.json")
	check(Movement.minutes_per_tile(cat) >= 1, "at least one minute")


func test_walks_and_arrives_on_time() -> void:
	var sim := _sim()
	var mpt := Movement.minutes_per_tile(cat)
	var target := [8, 12]
	var route := Pathfinder.find(Grid.of(cat, "town_e"), Vector2i(20, 21), Vector2i(8, 12))
	var n := route.size()
	var moved := 0
	var arrived: Array = []
	var ev := sim.step([_go("chr_0001", target)])
	eq(_of_type(ev, "order_refused"), [], "accepted")
	eq(_chr(sim, "chr_0001")["path"], route, "the route is the A* one")
	var steps := 1
	while steps < n * mpt:
		moved += _mine(_of_type(ev, "character_moved")).size()  # H7: the townsfolk walk too
		arrived.append_array(_mine(_of_type(ev, "character_arrived")))
		ev = sim.step()
		steps += 1
		if steps == n * mpt - 1:
			check(_chr(sim, "chr_0001")["position"] != target, "not there one minute early")
	moved += _mine(_of_type(ev, "character_moved")).size()
	arrived.append_array(_mine(_of_type(ev, "character_arrived")))
	eq(_chr(sim, "chr_0001")["position"], target, "there after tiles × minutes_per_tile")
	eq(moved, n, "one character_moved per tile")
	eq(arrived.size(), 1, "one character_arrived")
	eq(arrived[0], {"type": "character_arrived", "actor": "chr_0001", "tile": target}, "arrival event")
	eq(_chr(sim, "chr_0001")["path"], [], "still again")
	eq(_chr(sim, "chr_0001")["move_progress"], 0, "no progress left")
	eq(_chr(sim, "chr_0002")["position"], [21, 21], "the others did not move")


## The events of chr_0001 only (H7: the townsfolk walk the town too).
func _mine(evs: Array) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("actor", "")) == "chr_0001")


func test_moved_event_says_from_and_to() -> void:
	var sim := _sim()
	var first: Array = Pathfinder.find(Grid.of(cat, "town_e"), Vector2i(20, 21), Vector2i(20, 18))[0]
	var ev := _of_type(sim.step([_go("chr_0001", [20, 18])]), "character_moved")
	for i: int in Movement.minutes_per_tile(cat) - 1:
		ev.append_array(_of_type(sim.step(), "character_moved"))
	eq(ev.size(), 1, "moved one tile in minutes_per_tile minutes")
	eq(ev[0]["from"], [20, 21], "from")
	eq(ev[0]["to"], first, "to")


func test_new_order_replaces_the_route() -> void:
	var sim := _sim()
	sim.step([_go("chr_0001", [8, 12])])
	sim.run_minutes(5)
	var pos: Array = _chr(sim, "chr_0001")["position"]
	sim.step([_go("chr_0001", [30, 22])])
	var p: Array = _chr(sim, "chr_0001")["path"]
	eq(p[-1], [30, 22], "goes to the new target")
	sim.run_minutes(Clock.MINUTES_PER_DAY / 4)
	eq(_chr(sim, "chr_0001")["position"], [30, 22], "and gets there")
	check(pos != [30, 22], "it was elsewhere")
	sim.step([_go("chr_0001", [30, 22])])
	eq(_chr(sim, "chr_0001")["path"], [], "target = current tile: ok, no route")


func test_refusals_say_why_and_change_nothing() -> void:
	cat.tables["maps"]["t_island"] = {"id": "t_island", "size": [3, 1], "rows": [".w."], "spawns": {}}
	var cases := [
		[_go("chr_0099", [8, 12]), "unknown_actor", ""],
		[_go("chr_0001", [40, 3]), "out_of_bounds", ""],
		[_go("chr_0001", [-1, 3]), "out_of_bounds", ""],
		[_go("chr_0001", "here"), "out_of_bounds", ""],
		[_go("chr_0001", [9, 8]), "blocked", ""],
		[_go("chr_0001", [35, 5]), "blocked", ""],
		[_go("chr_0001", [8, 12]), "dead", "dead"],
		[_go("chr_0001", [8, 12]), "no_map", "no_map"],
		[_go("chr_0001", [2, 0]), "unreachable", "island"],
	]
	for c: Array in cases:
		var sim := _sim()
		match str(c[2]):
			"dead":
				_chr(sim, "chr_0001")["alive"] = false
			"no_map":
				sim.state.map_id = ""
			"island":
				sim.state.map_id = "t_island"
				_chr(sim, "chr_0001")["position"] = [0, 0]
		var before := SaveFile.canonical(sim.state.characters)
		eq(Orders.apply(sim, c[0])["reason"], c[1], "reason")
		eq(SaveFile.canonical(sim.state.characters), before, "%s changes nothing" % c[1])
		var refused := _of_type(sim.step([c[0]]), "order_refused")
		eq(refused.size(), 1, "%s: refused event" % c[1])
		if refused.size() == 1:
			eq(refused[0]["reason"], c[1], "event reason")


func test_refusal_reasons_have_texts() -> void:
	var keys := {}
	for line: String in FileAccess.get_file_as_string("res://i18n/strings.csv").split("\n"):
		var parts := line.split(",")
		if parts.size() >= 3 and parts[1].strip_edges() != "" and parts[2].strip_edges() != "":
			keys[parts[0]] = true
	for r: String in ["unknown_actor", "no_map", "out_of_bounds", "blocked", "unreachable", "dead"]:
		check(keys.has("reason." + r), "reason.%s in i18n/strings.csv with en and es" % r)


func test_save_mid_route_and_continue() -> void:
	var a := _sim()
	a.step([_go("chr_0001", [8, 12]), _go("chr_0004", [30, 25])])
	var mpt := Movement.minutes_per_tile(cat)
	a.run_minutes(3 * mpt + mpt / 2 - 1)  # three tiles and half of the fourth
	check(not (_chr(a, "chr_0001")["path"] as Array).is_empty(), "half-way")
	check(int(_chr(a, "chr_0001")["move_progress"]) > 0 or mpt == 1, "between tiles")
	var b := Sim.new(SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"], cat)
	eq(SaveFile.canonical(b.state.characters), SaveFile.canonical(a.state.characters), "same characters after load")
	var ea: Array = []
	var eb: Array = []
	for i: int in 120:
		ea.append_array(a.step())
		eb.append_array(b.step())
	eq(b.state_hash(), a.state_hash(), "the loaded game walks on exactly like the original")
	eq(eb, ea, "same events")
	eq(_chr(b, "chr_0001")["position"], [8, 12], "and arrives")


func _run(world_seed: int, days: int) -> Sim:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", world_seed)["state"], cat)
	sim.run_days(days, BotWanderer.new())
	return sim


func test_determinism_with_movement() -> void:
	var a := _run(4, 1)
	eq(_run(4, 1).state_hash(), a.state_hash(), "same seed, same walks")
	check(_run(5, 1).state_hash() != a.state_hash(), "another seed, other walks")
	var start := NewGame.from_scenario("town_e_start", 4)["state"] as WorldState
	var moved := 0
	for id: String in a.state.characters:
		if start.characters.has(id) and a.state.characters[id]["position"] != start.characters[id]["position"]:  # vida: guards and visitors come later
			moved += 1
	check(moved > 0, "the wanderer moved people")


func test_wanderer_only_gives_valid_orders() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 2)["state"], cat)
	var bot := BotWanderer.new()
	var refused := 0
	var arrivals := 0
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if e["type"] == "order_refused" and e["reason"] != "unreachable":
				refused += 1
			elif e["type"] == "character_arrived":
				arrivals += 1
	eq(refused, 0, "no refusals but unreachable")
	check(arrivals > 0, "people arrive")
