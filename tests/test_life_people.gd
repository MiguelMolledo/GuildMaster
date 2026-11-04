extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.24.3-4.24.4): visitors and the town watch. Visitors come in by a gate from a
## town of the region, walk their plan and leave at dusk (out of the state); the beggar takes alms. The watch: two at
## the gates by day, two on the night round with a lantern, the plaza guard in a festival; a cry within 12 tiles sends
## them; a constable in office adds a night guard; off duty they are off the map.

const DAY := 1440
const HERO := "chr_0001"


func _sim(scenario: String = "town_e_start") -> Sim:
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario loads")
	return Sim.new(r["state"], Catalog.load_from())


func test_visitors_come_and_go() -> void:
	var sim := _sim()
	var came := 0
	var left := 0
	var cities := {}
	for i: int in DAY:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "visitor_arrived":
				came += 1
				cities[str(e["city"])] = true
				check(Life.gates(sim).has(str(e["gate"])), "through a gate")
			elif str(e.get("type", "")) == "visitor_left":
				left += 1
	check(came >= 2 and came <= 4, "2-4 visitors a day (%d)" % came)
	check(not cities.has("villa"), "from another town of the region")
	eq(left, came, "they all left by night")
	eq(Visitors.alive(sim.state).size(), 0, "none left on the map")
	for id: String in sim.state.characters:
		check(not sim.state.characters[id].get("visitor") is Dictionary, "visitors are out of the state")


func test_alms_for_the_beggar() -> void:
	var sim := _sim()
	Life.ensure(sim.state)
	Life.service_family(sim.state, Life.FAMILY_VISITORS, "family.visitors", {})
	var tile: Array = sim.state.characters[HERO]["position"]
	sim.state.characters[HERO]["location"] = ""
	var b := Life.add_person(sim, Life.FAMILY_VISITORS, "Mendigo", false, 50, {}, {}, tile,
		{"visitor": {"kind": "beggar", "city": "hamlet", "gate": "west_gate", "plan": [], "stop": 0, "until": -1}})
	Life.put_on(sim, b, [int(tile[0]) + 1, int(tile[1])])
	var fam := "fam_0001"
	var gold := Money.gold(sim.state, fam)
	var rep := Reputation.of(sim.state, fam)
	var r := Orders.apply(sim, {"type": "give_alms", "actor": HERO, "target": b})
	check(bool(r["ok"]), "alms given (%s)" % r.get("reason", ""))
	eq(Money.gold(sim.state, fam), gold - 1, "1 gold")
	eq(Reputation.of(sim.state, fam), rep + 1, "+1 reputation")
	Orders.apply(sim, {"type": "give_alms", "actor": HERO, "target": b})
	eq(Reputation.of(sim.state, fam), rep + 1, "once a day")
	eq(str(Orders.apply(sim, {"type": "give_alms", "actor": HERO, "target": HERO}).get("reason", "")), "not_a_beggar", "only a beggar")


func test_the_watch_at_the_gates_by_day_and_on_the_round_at_night() -> void:
	var sim := _sim()
	sim.run_minutes(10 * 60)
	var roles := {}
	for g: String in Watch.guards(sim.state):
		roles[str(sim.state.characters[g]["guard"]["role"])] = g
	for r: String in ["gate_west_gate", "gate_east_gate", "night_1", "night_2", "festival_1"]:
		check(roles.has(r), "a guard for %s (%s)" % [r, roles.keys()])
	var gw: String = roles["gate_west_gate"]
	eq(Life.dist(Life.tile_of(sim.state, gw), Watch.gate_post(sim, "west_gate")), 0, "the west gate guard at its post")
	check(Life.offstage(sim.state, str(roles["night_1"])), "the night guard is off the map by day")
	check(Life.offstage(sim.state, str(roles["festival_1"])), "no plaza guard without a festival")
	var night := 22 * 60 + 30
	sim.run_minutes(night - int(sim.state.clock["minute"]))
	check(not Life.offstage(sim.state, str(roles["night_1"])), "the night guard is out at night")
	check(Life.offstage(sim.state, gw), "the gate guard went home")
	check(LifeQuery.lantern(sim, str(roles["night_1"])), "with a lantern")
	var seen := {}
	for i: int in 240:
		sim.step()
		seen[str(Life.tile_of(sim.state, str(roles["night_1"])))] = true
	check(seen.size() >= 6, "the round walks (%d tiles)" % seen.size())


func test_a_cry_sends_the_guards_near() -> void:
	var sim := _sim()
	sim.run_minutes(10 * 60)
	var gw := ""
	for g: String in Watch.guards(sim.state):
		if str(sim.state.characters[g]["guard"]["role"]) == "gate_west_gate":
			gw = g
	var post := Watch.gate_post(sim, "west_gate")
	sim.state.town["incidents"]["mult"] = 0.0
	sim.state.town["incidents"]["last"]["altercation_pending"] = -1
	sim.state.town["incidents"]["active"] = []
	sim.state.town["watch"]["dispatch"] = {}
	var sent := Watch.respond(sim, [int(post[0]) + 6, int(post[1])], "inc_test")
	check(gw in sent, "the guard 6 tiles away goes")
	var far := Watch.respond(sim, [38, 18], "inc_far")
	check(not gw in far, "a cry 30 tiles away is not heard")
	sim.state.town["incidents"]["mult"] = 0.0  # no brawl of the evening calls it away meanwhile
	sim.state.town["incidents"]["last"]["altercation_pending"] = -1
	sim.state.town["incidents"]["active"] = []
	var got := false
	for i: int in 30:
		for e: Dictionary in sim.step():
			got = got or (str(e.get("type", "")) == "guard_arrived" and str(e.get("character", "")) == gw)
	check(got and gw in Watch.arrived(sim.state, "inc_test"), "it gets there")
	Watch.release(sim.state, "inc_test")
	eq(Watch.arrived(sim.state, "inc_test").size(), 0, "released")


func test_a_constable_adds_a_night_guard() -> void:
	var sim := _sim()
	sim.step()
	sim.state.offices["constable"] = {"seats": [{"holder": "", "since": 0, "until": 99999}]}
	var before := Watch.roles(sim).size()
	sim.state.offices["constable"] = {"seats": [{"holder": "chr_0004", "since": 0, "until": 99999}]}
	eq(Watch.roles(sim).size(), before + 1, "+1 night guard with the constable in office")


func test_guards_are_not_townsfolk() -> void:
	var sim := _sim()
	sim.run_minutes(60)
	for g: String in Watch.guards(sim.state):
		check(not TownLife.is_townsperson(sim.state, g), "%s is not a townsperson" % g)
		check(not g in Population.townsfolk(sim.state), "%s does not count in the town" % g)
	check(not TownLife.is_household(sim.state, Life.FAMILY_WATCH), "the watch is not a household (not hired, no weddings)")
