extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## H8 programmable routine (GDD 4.10.8, criterion of 10/H8): with routines, 3 characters work a whole day without
## manual orders; a manual order interrupts the routine and then it is resumed. Also the Work directive of the spouse
## and the set_schedule order.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Pins.classic(Catalog.load_from())  # round pre-H5 figures (recipe durations): see tests/balance_pins.gd


func _sim(s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario("family_routines", s)["state"], cat)


func test_three_work_a_whole_day_without_orders() -> void:
	var sim := _sim()
	var st := sim.state
	var group := Kin.group(st, FAM)
	eq(group.size(), 3, "three controlled")
	var done := {}
	var refused := 0
	var at_noon := {}
	var at_night := {}
	var day := Clock.day(int(st.clock["minute"]))
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "work_done":
				done[str(e["actor"])] = int(done.get(str(e["actor"]), 0)) + 1
			elif str(e["type"]) == "order_refused" and str(e["actor"]) in group:
				refused += 1
		var m := Clock.minute_of_day(int(st.clock["minute"]))
		if m == 12 * 60:
			for c: String in group:
				at_noon[c] = Production.job_zone(sim, c, FORGE)
		if m == 23 * 60:
			for c: String in group:
				at_night[c] = Production.job_zone(sim, c, FORGE)
	for c: String in group:
		check(int(done.get(c, 0)) >= 3, "%s works the whole day (%d cycles)" % [c, int(done.get(c, 0))])
		check(str(at_noon.get(c, "")) != "", "%s is at a station at noon" % c)
		eq(str(at_night.get(c, "x")), "", "%s rests at night" % c)
	eq(refused, 0, "no refused orders")
	eq(Clock.day(int(st.clock["minute"])), day + 1, "a whole day")


func test_a_manual_order_rules_and_then_the_routine_comes_back() -> void:
	var sim := _sim()
	var st := sim.state
	var son := str(Kin.group(st, FAM)[1])
	sim.run_minutes(10 * 60 - 270)  # 10:00, everybody at work
	check(Production.job_zone(sim, son, FORGE) != "", "working at 10:00")
	var door: Array = st.buildings[FORGE]["door"]
	var events: Array = []
	events.append_array(sim.step([{"type": "exit_building", "actor": son}]))
	events.append_array(sim.step([{"type": "move_to", "actor": son, "tile": [int(door[0]) + 4, int(door[1]) + 1]}]))
	check(bool(st.characters[son]["routine"].get("manual", false)), "the manual order pauses the routine")
	eq(Production.job_zone(sim, son, FORGE), "", "he stopped working")
	var resumed := -1
	var back_to_work := -1
	for i: int in 240:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "routine_resumed" and str(e["character"]) == son and resumed < 0:
				resumed = i
			events.append(e)
		if resumed >= 0 and back_to_work < 0 and Production.job_zone(sim, son, FORGE) != "":
			back_to_work = i
	check(resumed > 0, "the routine is resumed when he is idle (minute %d)" % resumed)
	check(back_to_work > resumed, "and he goes back to work (minute %d)" % back_to_work)


func test_the_spouse_follows_the_work_directive_and_rests_at_night() -> void:
	var sim := _sim()
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	st.characters[wife]["stats"]["craft"] = 5
	var worked := 0
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "work_done" and str(e["actor"]) == wife:
				worked += 1
		if Clock.phase(int(st.clock["minute"]), cat.time) == "night" and Clock.minute_of_day(int(st.clock["minute"])) == 22 * 60:
			eq(Production.job_zone(sim, wife, FORGE), "", "the spouse rests at night")
	check(worked >= 1, "the spouse works (Work directive, 4.10.2): %d cycles" % worked)


func test_set_schedule_order() -> void:
	var sim := _sim()
	var st := sim.state
	var son := str(Kin.group(st, FAM)[1])
	var rest_all := {"dawn": {"action": "rest"}, "day": {"action": "rest"}, "dusk": {"action": "rest"},
		"night": {"action": "rest"}}
	eq(Orders.apply(sim, {"type": "set_schedule", "actor": HERO, "character": son, "schedule": rest_all})["ok"], true, "ok")
	eq(st.characters[son]["schedule"]["day"]["action"], "rest", "saved")
	eq(Orders.apply(sim, {"type": "set_schedule", "actor": HERO, "character": son,
		"schedule": {"noon": {"action": "work"}}})["reason"], "bad_schedule", "unknown phase")
	eq(Orders.apply(sim, {"type": "set_schedule", "actor": HERO, "character": son,
		"schedule": {"day": {"action": "work", "building": "bld_0002"}}})["reason"], "not_your_building", "rival forge")
	eq(Orders.apply(sim, {"type": "set_schedule", "actor": HERO, "character": str(st.characters[HERO]["spouse"]),
		"schedule": rest_all})["reason"], "not_controlled", "the spouse has no routine")
	sim.run_minutes(10 * 60 - 270)
	eq(Production.job_zone(sim, son, FORGE), "", "resting all day: not working at 10:00")
	eq(str(st.characters[son]["location"]), FORGE, "at home")
	var with_recipe := {"day": {"action": "work", "building": FORGE, "zone": "furnace", "recipe": "forge_ingot",
		"mode": "careful"}}
	eq(Orders.apply(sim, {"type": "set_schedule", "actor": HERO, "character": son, "schedule": with_recipe})["ok"], true,
		"a slot with station, recipe and mode")
	sim.run_minutes(5)
	var zone := Production.job_zone(sim, son, FORGE)
	check(zone == "furnace" or Production.job_zone(sim, HERO, FORGE) == "furnace" or zone != "", "works (%s)" % zone)
	if zone != "":
		var job: Dictionary = st.buildings[FORGE]["zones"][zone]["job"]
		eq(str(job["mode"]), "careful", "in the chosen mode")


func test_no_orders_while_the_forge_cannot_work() -> void:
	var sim := _sim()
	sim.state.buildings[FORGE]["state"] = "damaged"  # e.g. unpaid upkeep (D15)
	var refused := 0
	for i: int in 6 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "order_refused":
				refused += 1
	eq(refused, 0, "the routine does not ask to work at a damaged forge")
	eq(Production.job_zone(sim, HERO, FORGE), "", "nobody works there")
