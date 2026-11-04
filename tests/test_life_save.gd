extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.28.2): save v17. A v16 game migrates (town gets life, visitors, watch,
## rumors and incidents, empty) through its own step SaveFile._to_v17; a game in the middle of the living town (guards
## on duty, visitors, a raid on its way, rumours heard) comes back identical from a save and goes on the same.

const DAY := 1440


func test_v16_migrates_to_v17() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v16_new_game.json")
	check(bool(r["ok"]), "the v16 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	for k: String in ["life", "visitors", "watch", "rumors", "incidents"]:
		check(st.town.get(k) is Dictionary, "town.%s" % k)
	eq(st.town["incidents"]["active"], [], "no incident in course")
	var d := SaveFile._to_v17({"version": 16, "town": {"counters": {"bld_0001": {"next_at": 5}}}})
	eq(d["town"]["counters"], {"bld_0001": {"next_at": 5}}, "the counters stay")
	var sim := Sim.new(st, Catalog.load_from())
	sim.run_minutes(60)
	check(not Watch.guards(st).is_empty(), "the watch comes after the first steps")


func test_a_living_town_round_trips() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario("life_bandits", 1)
	var sim := Sim.new(r["state"], cat)
	sim.run_minutes(20)  # the raid is on its way
	check(not Incidents.active(sim.state).is_empty(), "an incident in course")
	var text := JSON.stringify(sim.state.to_dict())
	var back: WorldState = SaveFile.from_text(text)["state"]
	var sim2 := Sim.new(back, cat)
	eq(sim2.state_hash(), sim.state_hash(), "identical after the round trip")
	sim.run_minutes(120)
	sim2.run_minutes(120)
	eq(sim2.state_hash(), sim.state_hash(), "and it goes on the same")
