extends "res://tests/test_case.gd"
## Sleep and food (GDD 4.2.6, 2026-11-07; sim/family/needs_routine.gd): rest drops awake (x1.5 working at night) and
## comes back sleeping at home; tired and hungry slow the work; Rendido drops everything, sleeps and refuses orders
## until 50; the Rutina takes the controlled character home to sleep at night and to eat at midday; a manual order
## rules; a meal at the tavern costs a coin and raises social; old games load with the defaults.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _new() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	return Sim.new(r["state"], cat)


func _at(sim: Sim, day: int, hh: int, mm: int = 0) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + hh * 60 + mm


func _needs(sim: Sim, hunger: int, rest: int) -> void:
	var n := Needs.of(sim, HERO)
	n["hunger"] = hunger
	n["rest"] = rest


func _stock(sim: Sim, n: int = 20) -> void:
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	Inventory.add(inv, cat, "iron", 0, n)
	Inventory.add(inv, cat, "coal", 0, n)


func _work(sim: Sim) -> Dictionary:
	return Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"})


func test_a_new_game_starts_rested_and_fed() -> void:
	var sim := _new()
	check(Needs.tracked(sim, HERO), "the founder's needs move")
	eq(int(Needs.of(sim, HERO)["rest"]), 100, "rested")
	eq(int(Needs.of(sim, HERO)["hunger"]), 100, "fed")
	check(NeedsRoutine.on(sim, HERO), "the Rutina is on by default")
	eq(Needs.states(sim, HERO), [], "no state")


func test_rest_drops_awake_faster_at_night_and_comes_back_asleep() -> void:
	var sim := _new()
	var st := sim.state
	sim.give({"type": "set_needs_routine", "actor": HERO, "character": HERO, "on": false})
	check(not NeedsRoutine.on(sim, HERO), "Rutina off")
	st.characters[HERO]["location"] = FORGE
	_stock(sim)
	_at(sim, 1, 10)
	_needs(sim, 100, 100)
	check(_work(sim)["ok"], "works by day")
	sim.run_minutes(60)
	eq(int(Needs.of(sim, HERO)["rest"]), 96, "working by day: -4 an hour")
	_at(sim, 1, 22)
	sim.run_minutes(60)
	eq(int(Needs.of(sim, HERO)["rest"]), 90, "working at night: -6 an hour (x1.5)")
	sim.give({"type": "stop_work", "actor": HERO})
	var h0 := int(Needs.of(sim, HERO)["hunger"])
	sim.run_minutes(60)
	eq(Needs.situation(sim, HERO), "sleep", "at home at night, not working: asleep")
	eq(int(Needs.of(sim, HERO)["rest"]), 100, "asleep: +13 an hour (capped)")
	eq(int(Needs.of(sim, HERO)["hunger"]), mini(100, h0 + 6), "the dinner comes with a night at home")
	_needs(sim, 50, 4)
	_at(sim, 8, 20, 59)  # spring: night 21:00-05:00, eight hours
	sim.run_minutes(8 * 60)
	check(int(Needs.of(sim, HERO)["rest"]) >= 100, "8 hours fill it (%d)" % int(Needs.of(sim, HERO)["rest"]))


func test_tired_and_hungry_states_and_their_notices() -> void:
	var sim := _new()
	var st := sim.state
	sim.give({"type": "set_needs_routine", "actor": HERO, "character": HERO, "on": false})
	st.characters[HERO]["location"] = FORGE
	_at(sim, 1, 10)
	_needs(sim, 31, 31)
	sim.run_minutes(60)
	eq(Needs.states(sim, HERO), ["tired", "hungry"], "under 30 both")
	var keys: Array = st.notices.map(func(n: Dictionary) -> String: return str(n.get("key", "")))
	check("notice.tired" in keys, "a notice: tired (%s)" % [keys])
	check("notice.hungry" in keys, "a notice: hungry")
	var sim2 := _new()
	sim2.give({"type": "set_needs_routine", "actor": HERO, "character": HERO, "on": false})
	_at(sim2, 1, 10)
	var n := Needs.of(sim2, HERO)
	n["rest"] = 42
	sim2.run_minutes(60)
	var keys2: Array = sim2.state.notices.map(func(x: Dictionary) -> String: return str(x.get("key", "")))
	check("notice.rest_low" in keys2, "before tired, a clear warning (%s)" % [keys2])


func test_exhausted_drops_everything_sleeps_and_refuses_orders_until_50() -> void:
	var sim := _new()
	var st := sim.state
	sim.give({"type": "set_needs_routine", "actor": HERO, "character": HERO, "on": false})
	st.characters[HERO]["location"] = FORGE
	_stock(sim)
	_at(sim, 1, 9, 30)
	_needs(sim, 80, 3)
	check(_work(sim)["ok"], "works")
	var saw_exhausted := false
	for i: int in 31:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "exhausted":
				saw_exhausted = true
	check(saw_exhausted, "rest 0: Rendido")
	check(Needs.is_exhausted(st, HERO), "exhausted")
	eq(Production.job_zone(sim, HERO, FORGE), "", "drops the work")
	var keys: Array = st.notices.map(func(n: Dictionary) -> String: return str(n.get("key", "")))
	check("notice.exhausted" in keys, "an urgent notice")
	eq(Production.may_work(sim, HERO, FORGE), "exhausted", "may not work")
	var refused := ""
	for e: Dictionary in sim.step([{"type": "exit_building", "actor": HERO}]):
		if str(e["type"]) == "order_refused":
			refused = str(e["reason"])
	eq(refused, "exhausted", "an order from outside is refused")
	eq(str(st.characters[HERO]["location"]), FORGE, "stays home (the forge)")
	check(NeedsRoutine.busy(sim, HERO), "busy for the bots")
	sim.run_minutes(60)
	eq(Needs.situation(sim, HERO), "sleep", "asleep by day")
	var rested := false
	for i: int in 5 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "rested":
				rested = true
		if rested:
			break
	check(rested, "rest back at 50: no longer Rendido")
	check(int(Needs.of(sim, HERO)["rest"]) >= 50, "rest back (%d)" % int(Needs.of(sim, HERO)["rest"]))
	check(not Needs.is_exhausted(st, HERO), "at 50 no longer exhausted")
	sim.step([])
	check(_work(sim)["ok"], "works again")


func test_exhausted_away_from_home_walks_home_to_sleep() -> void:
	var sim := _new()
	var st := sim.state
	sim.give({"type": "set_needs_routine", "actor": HERO, "character": HERO, "on": false})
	_at(sim, 1, 9, 59)
	st.characters[HERO]["location"] = ""
	_needs(sim, 80, 2)
	sim.run_minutes(2)
	check(Needs.is_exhausted(st, HERO), "Rendido in the street")
	for i: int in 120:
		sim.step([])
		if str(st.characters[HERO]["location"]) == FORGE:
			break
	eq(str(st.characters[HERO]["location"]), FORGE, "walks home on its own")


func test_the_rutina_sleeps_at_night_and_lets_the_cycle_end() -> void:
	var sim := _new()
	var st := sim.state
	st.characters[HERO]["location"] = FORGE
	_stock(sim)
	_at(sim, 1, 20, 30)
	_needs(sim, 100, 60)
	check(_work(sim)["ok"], "works at dusk")
	Schedules.note_manual(sim, {"type": "work_at", "actor": HERO})
	var idle_reason := ""
	for i: int in 4 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "work_idle" and str(e["actor"]) == HERO:
				idle_reason = str(e["reason"])
	eq(idle_reason, "routine_sleep", "at night the cycle ends and does not repeat")
	eq(Production.job_zone(sim, HERO, FORGE), "", "not working at night")
	eq(Needs.situation(sim, HERO), "sleep", "asleep at home")
	check(NeedsRoutine.busy(sim, HERO), "the bots wait")
	var r0 := int(Needs.of(sim, HERO)["rest"])
	_at(sim, 1, 23, 0)
	sim.run_minutes(60)
	check(int(Needs.of(sim, HERO)["rest"]) > r0, "rest comes back asleep")


func test_a_manual_order_at_night_rules_over_the_rutina() -> void:
	var sim := _new()
	var st := sim.state
	st.characters[HERO]["location"] = FORGE
	_stock(sim)
	_at(sim, 1, 22)
	sim.step([])
	check(NeedsRoutine.busy(sim, HERO), "night: the Rutina wants sleep")
	sim.step([{"type": "work_at", "actor": HERO, "building": FORGE, "zone": "furnace", "recipe": "forge_ingot",
		"mode": "normal"}])
	check(Production.job_zone(sim, HERO, FORGE) != "", "the player makes him work at night")
	check(not NeedsRoutine.busy(sim, HERO), "the order rules: not busy")
	var done := 0
	for i: int in 4 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "work_done" and str(e["actor"]) == HERO:
				done += 1
	check(done >= 2, "keeps repeating at night (%d cycles)" % done)
	check(Production.job_zone(sim, HERO, FORGE) != "", "still working")


func test_the_rutina_eats_at_midday_when_hungry() -> void:
	var sim := _new()
	var st := sim.state
	st.characters[HERO]["location"] = ""
	_at(sim, 1, 11, 58)
	_needs(sim, 45, 90)
	var ate := false
	for i: int in 3 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "meal_eaten" and str(e["character"]) == HERO:
				ate = true
	check(ate, "goes home and eats")
	check(int(Needs.of(sim, HERO)["hunger"]) > 90, "fed (%d)" % int(Needs.of(sim, HERO)["hunger"]))
	check(not NeedsRoutine.busy(sim, HERO), "once a day: done")
	var sim2 := _new()
	_at(sim2, 1, 11, 58)
	var n := Needs.of(sim2, HERO)
	n["hunger"] = 80
	sim2.run_minutes(10)
	check(not NeedsRoutine.busy(sim2, HERO), "not hungry: no lunch")


func test_eating_at_the_tavern_costs_a_coin_and_raises_social() -> void:
	var sim := _new()
	var st := sim.state
	var inn := NeedsRoutine.nearest_tavern(sim, HERO)
	check(inn != "", "the town has a tavern")
	_at(sim, 1, 10)
	st.characters[HERO]["location"] = ""
	eq(Orders.apply(sim, {"type": "eat", "actor": HERO, "place": "tavern"})["reason"], "not_at_tavern", "far from it")
	var door: Array = st.buildings[inn]["door"]
	st.characters[HERO]["position"] = [int(door[0]), int(door[1]) - 1]
	var g0 := Money.gold(st, FAM)
	var n := Needs.of(sim, HERO)
	n["hunger"] = 20
	n["social"] = 40
	var r := Orders.apply(sim, {"type": "eat", "actor": HERO, "place": "tavern"})
	check(r["ok"], "eats at the tavern (%s)" % r["reason"])
	eq(Money.gold(st, FAM), g0 - 1, "a coin")
	sim.run_minutes(61)
	eq(int(Needs.of(sim, HERO)["hunger"]), 20 - 3 + 60, "+60 hunger (an hour awake in between)")
	check(int(Needs.of(sim, HERO)["social"]) >= 50, "+10 social")
	st.families[FAM]["gold"] = 0
	eq(Orders.apply(sim, {"type": "eat", "actor": HERO, "place": "tavern"})["reason"], "not_enough_gold", "no coin")


func test_eating_at_home_is_free_and_leaving_cancels_it() -> void:
	var sim := _new()
	var st := sim.state
	_at(sim, 1, 16)
	st.characters[HERO]["location"] = FORGE
	var n := Needs.of(sim, HERO)
	n["hunger"] = 10
	var g0 := Money.gold(st, FAM)
	check(Orders.apply(sim, {"type": "eat", "actor": HERO, "place": "home"})["ok"], "eats at home")
	eq(Money.gold(st, FAM), g0, "free")
	check(NeedsRoutine.busy(sim, HERO), "busy while eating")
	sim.run_minutes(10)
	sim.step([{"type": "exit_building", "actor": HERO}])
	sim.step([])
	check(not NeedsRoutine.eating(sim, HERO), "leaving cancels the meal")
	eq(Orders.apply(sim, {"type": "eat", "actor": HERO, "place": "home"})["reason"], "not_home", "not at home")


func test_an_old_game_loads_with_the_defaults() -> void:
	var sim := _new()
	var d: Dictionary = sim.state.to_dict()
	d["characters"][HERO].erase("needs")
	d["characters"][HERO].erase("vitals")
	d["characters"][HERO].erase("needs_routine")
	var res := SaveFile.from_text(JSON.stringify(d))
	check(res.has("state"), "loads")
	var back := Sim.new(res["state"], cat)
	check(NeedsRoutine.on(back, HERO), "Rutina on")
	check(not Needs.is_exhausted(back.state, HERO), "not exhausted")
	eq(int(Needs.of(back, HERO)["rest"]), 100, "needs created at their start")
	back.run_minutes(60)
	var v := Needs.vitals(back, HERO)
	v["exhausted"] = true
	v["act"] = {"kind": "sleep", "at": FORGE, "until_rest": 50, "since": 5}
	back.state.characters[HERO]["needs_routine"] = false
	var again: WorldState = SaveFile.from_text(JSON.stringify(back.state.to_dict()))["state"]
	eq(SaveFile.canonical(again.to_dict()), SaveFile.canonical(back.state.to_dict()), "round trip keeps the new fields")


func test_the_ai_spouse_eats_and_sleeps_by_the_same_rules() -> void:
	var sim := Sim.new(NewGame.from_scenario("kin_tired", 1)["state"], cat)
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	var ate := false
	for i: int in 3 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "meal_eaten" and str(e["character"]) == wife:
				ate = true
	check(ate, "hungry: eats at home")
	var n := Needs.of(sim, wife)
	n["rest"] = 1
	n["hunger"] = 90
	Needs.vitals(sim, wife).erase("act")
	st.characters[wife]["location"] = ""
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 10 * 60 + 59
	sim.run_minutes(2)
	check(Needs.is_exhausted(st, wife), "Rendido too")
	eq(Production.may_work(sim, wife, FORGE), "exhausted", "nor works")
