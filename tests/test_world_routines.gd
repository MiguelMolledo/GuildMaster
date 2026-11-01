extends "res://tests/test_case.gd"
## H4 · employees' routine (GDD 4.7.1, 4.11.2, 4.4.3; docs/contratos/h4_empleados.md, zone «cola»): from home to
## work at dawn with a drawn delay, by the real orders; back home at dusk (a running cycle ends first); never at work
## at night; hired today stays home; deterministic.

const FORGE: String = "bld_0001"
const JOAN: String = "chr_0007"
const AGNES: String = "chr_0008"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("two_employees", 1)["state"], cat)


func _phase_start(sim: Sim, day: int, phase: String) -> int:
	var starts: Dictionary = cat.time["phase_starts"][Clock.season(day * Clock.MINUTES_PER_DAY, cat.time)]
	return day * Clock.MINUTES_PER_DAY + int(starts[phase])


func test_leave_home_at_dawn_with_delay_and_walk_to_work() -> void:
	var sim := _sim()
	var st := sim.state
	var left := {}
	var entered := {}
	var dawn := _phase_start(sim, 1, "dawn")
	while int(st.clock["minute"]) < dawn + 180:
		for e: Dictionary in sim.step():
			var who := str(e.get("actor", ""))
			if str(e["type"]) == "building_left" and who in [JOAN, AGNES] and not left.has(who):
				left[who] = int(st.clock["minute"])
			if str(e["type"]) == "building_entered" and str(e["building"]) == FORGE and who in [JOAN, AGNES]:
				entered[who] = int(st.clock["minute"])
		if int(st.clock["minute"]) < dawn:
			for c: String in [JOAN, AGNES]:
				eq(str(st.characters[c]["location"]), "bld_0004", "%s at home before dawn" % c)
	var span: Array = cat.employees["schedule"]["leave_home_delay_minutes"]
	for c: String in [JOAN, AGNES]:
		check(left.has(c), "%s leaves home" % c)
		check(int(left.get(c, 0)) >= dawn + int(span[0]) and int(left.get(c, 0)) <= dawn + int(span[1]),
			"%s leaves inside the delay window" % c)
		eq(int(st.characters[c]["routine"]["leave_at"]), int(left.get(c, -1)), "%s at its drawn minute" % c)
		check(entered.has(c), "%s walks in through the door" % c)
		eq(str(st.characters[c]["location"]), FORGE, "%s at work" % c)
		eq(Routines.state_of(sim, c), "at_work", "%s state" % c)
	check(int(left[JOAN]) != int(left[AGNES]), "each its own delay")


func test_never_at_work_at_night_and_home_to_sleep() -> void:
	var sim := _sim()
	var st := sim.state
	var night_inside: Array = []
	var not_home: Array = []
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		sim.step()
		var now := int(st.clock["minute"])
		if Clock.phase(now, cat.time) != "night":
			continue
		var mod := Clock.minute_of_day(now)
		for c: String in [JOAN, AGNES]:
			if str(st.characters[c]["location"]) == FORGE:
				night_inside.append("%s %s" % [c, Routines._hhmm(now)])
			if mod >= 23 * 60 and str(st.characters[c]["location"]) != "bld_0004":
				not_home.append("%s %s" % [c, Routines._hhmm(now)])
	eq(night_inside, [], "never inside the forge at night")
	eq(not_home, [], "home by 23:00")


func test_dusk_ends_the_running_cycle_then_home() -> void:
	# Day 3: Joan's last sword runs into dusk; he finishes it and only then leaves.
	var sim := _sim()
	var st := sim.state
	var dusk := _phase_start(sim, 3, "dusk")
	sim.run_minutes(dusk - int(st.clock["minute"]) - 1)
	var running := Production.job_zone(sim, JOAN, FORGE)
	check(running != "", "Joan is forging when dusk starts")
	var done_at := -1
	var left_at := -1
	var started_at_dusk := 0
	while int(st.clock["minute"]) < dusk + 180:
		for e: Dictionary in sim.step():
			if str(e.get("actor", "")) != JOAN:
				continue
			if str(e["type"]) == "work_done" and done_at < 0:
				done_at = int(st.clock["minute"])
			if str(e["type"]) == "building_left" and left_at < 0:
				left_at = int(st.clock["minute"])
			if str(e["type"]) == "work_started":
				started_at_dusk += 1
			check(str(e["type"]) != "work_interrupted", "not interrupted")
	check(done_at >= dusk, "the cycle ends in dusk")
	eq(left_at, done_at + 1, "and then he leaves")
	eq(started_at_dusk, 0, "no new work at dusk")


func test_night_interrupts_a_cycle_still_running() -> void:
	# Day 1: Joan starts a sword at 18:36 that would end after 21:00: at night he leaves and the inputs go back.
	var sim := _sim()
	var st := sim.state
	var night := _phase_start(sim, 1, "night")
	sim.run_minutes(night - int(st.clock["minute"]) - 1)
	check(Production.job_zone(sim, JOAN, FORGE) != "", "still forging at the end of dusk")
	var ev := sim.step()
	var inter: Array = ev.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == "work_interrupted" and str(e["actor"]) == JOAN)
	eq(inter.size(), 1, "the cycle is interrupted")
	eq(str(st.characters[JOAN]["location"]), "", "out of the forge")
	eq(str(st.characters[JOAN]["routine"]["state"]), "to_home", "walking home")


func test_hired_today_stays_home() -> void:
	var sim := _sim()
	sim.state.characters[AGNES]["job"]["start_day"] = 2  # starts tomorrow
	sim.run_minutes(12 * 60)  # 16:30
	eq(str(sim.state.characters[AGNES]["location"]), "bld_0004", "Agnès at home")
	eq(str(sim.state.characters[JOAN]["location"]), FORGE, "Joan at work")


func test_townsfolk_without_job_stay_home() -> void:
	var sim := _sim()
	sim.run_minutes(12 * 60)
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("rank", "")) != "" and not ch.get("job") is Dictionary:
			eq(str(ch["location"]), str(ch["home"]), "%s at home" % id)


func test_routine_events_and_determinism() -> void:
	var a := _sim()
	var b := _sim()
	var states: Array = []
	for i: int in Clock.MINUTES_PER_DAY:
		for e: Dictionary in a.step():
			if str(e["type"]) == "routine_changed" and str(e["employee"]) == JOAN:
				states.append(str(e["state"]))
		b.step()
	eq(states, ["home", "to_work", "at_work", "to_home", "home"], "Joan's day")
	eq(b.state_hash(), a.state_hash(), "same seed, same day")
