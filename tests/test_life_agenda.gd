extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.24.1, docs/contratos/vida.md): the townsfolk's agenda. With the living town
## on, the townsfolk have needs, do many different things (not only work), work is the duty of the day, the choice is
## deterministic and the economy's numbers do not move (shopping buys nothing). With it off, H7's day as it was.

const DAY := 1440


func _sim(on: bool = true, scenario: String = "town_e_start", seed: int = 1) -> Sim:
	var cat := Catalog.load_from()
	cat.life_tables["life"]["enabled"] = on
	var r := NewGame.from_scenario(scenario, seed)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _starts(sim: Sim, minutes: int) -> Dictionary:
	var out := {}
	for i: int in minutes:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "town_state" and str(e.get("activity", "")) != "":
				out[str(e["activity"])] = int(out.get(str(e["activity"]), 0)) + 1
	return out


func test_townsfolk_do_many_things_in_a_day() -> void:
	var sim := _sim()
	var seen := _starts(sim, DAY)
	var kinds := 0
	for a: String in ["shopping", "water", "wash", "mass", "chat", "bench", "dice", "stroll", "errand", "court"]:
		if seen.has(a):
			kinds += 1
	check(kinds >= 7, "at least 7 kinds of activity in a day (saw %s)" % [seen.keys()])
	for id: String in Population.townsfolk(sim.state):
		if not TownLife.is_adult(sim.state, sim.catalog, id) or sim.state.characters[id].get("job") is Dictionary:
			continue
		var v := Agenda.view(sim, id)
		check(not v.is_empty(), "%s has needs" % id)
		for k: String in v.get("needs", {}):
			check(int(v["needs"][k]) >= 0 and int(v["needs"][k]) <= 100, "%s.%s in 0-100" % [id, k])


func test_work_is_the_duty_of_the_day() -> void:
	var sim := _sim()
	sim.run_minutes(11 * 60 - Clock.minute_of_day(int(sim.state.clock["minute"])))  # 11:00 of the first day
	var working := 0
	var adults := 0
	for id: String in Population.townsfolk(sim.state):
		var ch: Dictionary = sim.state.characters[id]
		if ch.get("job") is Dictionary or not TownLife.is_adult(sim.state, sim.catalog, id):
			continue
		adults += 1
		if str(ch.get("town", {}).get("activity", "")) == "work":
			working += 1
	check(adults > 0 and float(working) / float(adults) >= 0.5, "most adults work at 11:00 (%d of %d)" % [working, adults])


func test_the_agenda_is_deterministic() -> void:
	var a := _sim()
	var b := _sim()
	a.run_minutes(DAY / 2)
	b.run_minutes(DAY / 2)
	eq(a.state_hash(), b.state_hash(), "same seed, same day")


## No new kind of money flow: the townsfolk's book has the same categories with the life on as off (shopping buys
## nothing; who walks into a counter may change, the rules do not).
func test_living_opens_no_new_money_flow() -> void:
	var cats := {}
	for on: bool in [false, true]:
		var sim := _sim(on)
		Life.ensure(sim.state)
		sim.state.town["incidents"]["mult"] = 0.0  # the incidents' fines are theirs: here only the agenda
		sim.run_minutes(DAY)
		var seen := {}
		for f: String in sim.state.families:
			if not TownLife.is_household(sim.state, f):
				continue
			for e: Dictionary in sim.state.ledger.get("entries", []):
				# Equilibrio 15: the houses' wages and food (Households, ref jornal / food) are the one flow the
				# living town adds, by design (04g §4.6.5.7); the agenda itself still moves no gold
				if str(e.get("family", "")) == f and not str(e.get("ref", "")) in ["jornal", "food"]:
					seen[str(e.get("category", ""))] = true
		cats[on] = seen.keys()
		(cats[on] as Array).sort()
	for c: Variant in cats[true]:
		check(c in (cats[false] as Array), "category %s also without the life" % c)


func test_off_is_h7() -> void:
	var sim := _sim(false)
	sim.run_minutes(DAY)
	check(not sim.state.families.has(Life.FAMILY_WATCH), "no watch with the life off")
	check(not sim.state.families.has(Life.FAMILY_VISITORS), "no visitors with the life off")
	for id: String in Population.townsfolk(sim.state):
		var t: Dictionary = sim.state.characters[id].get("town", {})
		check(not t.has("needs"), "%s: no needs with the life off" % id)


func test_needs_fall_and_activities_raise_them() -> void:
	var sim := _sim()
	sim.run_minutes(60)
	var id := ""
	for c: String in Population.townsfolk(sim.state):
		if TownLife.is_adult(sim.state, sim.catalog, c) and not sim.state.characters[c].get("job") is Dictionary:
			id = c
			break
	var t: Dictionary = sim.state.characters[id]["town"]
	var now := int(sim.state.clock["minute"])
	var before := int(Agenda.needs(sim, t, now)["social"])
	var later := int(Agenda.needs(sim, t, now + 300)["social"])
	eq(later, maxi(0, before - 50), "social falls 10 tenths an hour")
	Agenda.raise(sim, t, {"social": 30}, now + 300)
	eq(int(t["needs"]["social"]), mini(1000, later + 300), "chatting raises it 30 points")


func test_an_event_routine_effect_reaches_the_choice() -> void:
	var sim := _sim()
	sim.catalog.world_events()["festival"]["effects"].append({"kind": "routine", "activity": "mass", "mult": 5.0})
	sim.state.events_active.append({"id": "gev_x", "def": "festival", "start": 0, "end": DAY * 3, "by": ""})
	near(Life.event_mult(sim, "routine", "mass"), 5.0, 0.0001, "the festival's routine effect multiplies the mass")
	near(Life.event_mult(sim, "routine", "dice"), 1.0, 0.0001, "and nothing else")
	check(Life.festival(sim), "a festival is on")
