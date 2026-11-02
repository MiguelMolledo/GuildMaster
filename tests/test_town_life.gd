extends "res://tests/test_case.gd"
## H7 · the townsfolk's day (GDD 4.11.2-4.11.3, docs/contratos/h7_ciudad.md): socialising in the plaza at dusk,
## everybody home at night, out to their trades at dawn with different delays, social breaks and greetings, only real
## orders and no refusals, deterministic.

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


func _run_to(sim: Sim, day: int, hh: int, mm: int) -> Array:
	var evs: Array = []
	var target := day * Clock.MINUTES_PER_DAY + hh * 60 + mm
	while int(sim.state.clock["minute"]) < target:
		evs.append_array(sim.step())
	return evs


func _in_plaza(pos: Array) -> bool:
	return int(pos[0]) >= 15 and int(pos[0]) <= 24 and int(pos[1]) >= 13 and int(pos[1]) <= 24


func test_plaza_at_dusk_has_townsfolk_socialising() -> void:
	var sim := _sim("plaza_dusk")
	var evs := _run_to(sim, 1, 20, 15)
	eq(sim.now()["phase"], "dusk", "20:15 is dusk")
	var social := 0
	var in_plaza := 0
	var kinds := {}
	for id: String in Population.townsfolk(sim.state):
		var v := TownLife.view(sim, id)
		if str(v["state"]) in ["social", "market"]:
			social += 1
			kinds[str(v["activity"])] = true
			if _in_plaza(sim.state.characters[id]["position"]):
				in_plaza += 1
	check(social >= 8, "at least half the townsfolk socialise at dusk (%d)" % social)
	check(in_plaza >= 6, "and most of them in the plaza (%d)" % in_plaza)
	check(kinds.size() >= 3, "several activities at once (%s)" % [kinds.keys()])
	var bubbles := 0
	for id: String in Population.townsfolk(sim.state):
		if str(TownLife.view(sim, id)["bubble"]) != "":
			bubbles += 1
	eq(bubbles, social, "every socialising townsperson has a bubble")
	for e: Dictionary in evs:
		check(str(e["type"]) != "order_refused", "no refused orders (%s)" % [e])


func test_everybody_home_at_night() -> void:
	var sim := _sim("plaza_dusk")
	_run_to(sim, 1, 23, 0)
	eq(sim.now()["phase"], "night", "23:00 is night")
	for id: String in Population.townsfolk(sim.state):
		var ch: Dictionary = sim.state.characters[id]
		eq(str(ch["location"]), str(ch["home"]), "%s «%s» is at home" % [id, ch["name"]])
		eq(str(TownLife.view(sim, id)["state"]), "home", "%s state home" % id)
	_run_to(sim, 2, 3, 0)
	for id: String in Population.townsfolk(sim.state):
		eq(str(sim.state.characters[id]["location"]), str(sim.state.characters[id]["home"]), "%s still home at 03:00" % id)


func test_out_at_dawn_with_different_delays_and_working_by_day() -> void:
	var sim := _sim("plaza_dusk")
	_run_to(sim, 2, 0, 0)
	var left := {}
	var target := 2 * Clock.MINUTES_PER_DAY + 9 * 60
	while int(sim.state.clock["minute"]) < target:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "building_left" and TownLife.is_townsperson(sim.state, str(e["actor"])):
				if not left.has(str(e["actor"])):
					left[str(e["actor"])] = int(sim.state.clock["minute"])
	check(left.size() >= 14, "almost everybody leaves home in the morning (%d)" % left.size())
	var minutes := {}
	for k: String in left:
		minutes[int(left[k])] = true
	check(minutes.size() >= 8, "at different minutes (a delay each, %d distinct)" % minutes.size())
	var working := 0
	for id: String in Population.townsfolk(sim.state):
		if str(TownLife.view(sim, id)["state"]) == "working":
			working += 1
	check(working >= 9, "most at their trades by 09:00 (%d)" % working)


func test_day_breaks_and_greetings_happen() -> void:
	var sim := _sim("plaza_dusk")
	var evs := _run_to(sim, 2, 19, 0)
	var breaks := 0
	var greets := 0
	for e: Dictionary in evs:
		if str(e["type"]) == "town_state" and str(e["state"]) == "social" and str(e["activity"]) not in ["", "greet"]:
			breaks += 1
		if str(e["type"]) == "greeted":
			greets += 1
	check(breaks >= 5, "social breaks during the day and evening (%d)" % breaks)
	check(greets >= 1, "townsfolk greet when they cross (%d)" % greets)


func test_town_is_deterministic() -> void:
	var a := _sim("plaza_dusk", 4)
	var b := _sim("plaza_dusk", 4)
	a.run_minutes(900)
	b.run_minutes(900)
	eq(a.state_hash(), b.state_hash(), "same seed, same town")


func test_town_does_not_touch_the_world_rng() -> void:
	var sim := _sim("plaza_dusk")
	var frozen := _sim("plaza_dusk")
	for id: String in Population.townsfolk(frozen.state):
		frozen.state.characters[id]["home"] = ""  # not townsfolk any more: TownLife leaves them alone
	sim.run_minutes(1500)
	frozen.run_minutes(1500)
	eq(sim.state.rng.state, frozen.state.rng.state, "the town uses its own stream (H3-H5 targets keep their dice)")


func test_employees_keep_their_h4_routine() -> void:
	var sim := _sim("town_microevents")
	var emps := Staff.employees_of(sim.state, "bld_0001")
	_run_to(sim, 0, 12, 0)
	for e: String in emps:
		if Staff.is_active(sim, e):
			eq(str(sim.state.characters[e]["location"]), "bld_0001", "%s works at the forge at noon" % e)
