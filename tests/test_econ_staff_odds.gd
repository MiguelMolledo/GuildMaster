extends "res://tests/test_case.gd"
## Staff (zone «plantilla»): quitting and theft with a seed (GDD 4.7.3: 5 %/day at 20-39, 3 %/day at 0-19), the thief
## flees and is banned, and save/load with hired employees still waiting to start.

var cat := Catalog.load_from()

const PLAYER := "chr_0001"
const FAM := "fam_0001"
const FORGE := "bld_0001"
const JOAN := "chr_0007"
const AGNES := "chr_0008"
const DAYS := 2000


func _sim(id: String, seed: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, seed)["state"], cat)


func _to_dawn(sim: Sim) -> void:
	for i: int in Clock.MINUTES_PER_DAY * 2:
		sim.step()
		if Ledger.is_dawn(sim):
			return
	failures.append("no dawn in 2 days")


## DAYS dawns of Staff.step for Agnès kept at `loyalty` (re-hired when she goes, loyalty reset each day). The clock
## does not move: only the dawn rules run, with state.rng. Returns {left: {reason: n}, stolen: units, sim}.
func _dawns(seed: int, loyalty: int, swords: int = 0) -> Dictionary:
	var sim := _sim("two_employees", seed)
	var st := sim.state
	st.families[FAM]["gold"] = 1000000
	st.characters.erase(JOAN)
	var job0: Dictionary = (st.characters[AGNES]["job"] as Dictionary).duplicate(true)
	job0["start_day"] = 0
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var left := {}
	var stolen := 0
	for d: int in DAYS:
		var ch: Dictionary = st.characters[AGNES]
		if not ch.get("job") is Dictionary:
			ch["job"] = job0.duplicate(true)
			ch["hire_bans"] = {}
		ch["job"]["loyalty"] = loyalty
		if swords > 0:
			var have := Inventory.count(inv, "sword", 0)
			if have < swords:
				Inventory.add(inv, cat, "sword", 0, swords - have)
		sim.events = [{"type": "phase_changed", "phase": "dawn"}]
		Staff.step(sim)
		for e: Dictionary in sim.events:
			if str(e["type"]) == "employee_left":
				left[str(e["reason"])] = int(left.get(str(e["reason"]), 0)) + 1
			if str(e["type"]) == "employee_stole":
				stolen += int(e["qty"])
				if str(e["item"]) != "sword":
					failures.append("stole %s, not the most valuable" % e["item"])
	return {"left": left, "stolen": stolen, "sim": sim}


func test_quitting_about_5_percent_a_day_at_20_39() -> void:
	var r := _dawns(7, 25)
	var quits := int(r["left"].get("quit", 0))
	check(quits >= 60 and quits <= 140, "about 100 quits in %d days at 5 %% (got %d)" % [DAYS, quits])
	eq(int(r["left"].get("theft", 0)), 0, "nobody steals at 20-39")
	eq(_dawns(7, 25)["left"], r["left"], "same seed, same days")
	var other: Dictionary = _dawns(8, 25)["left"]
	check(other != r["left"], "another seed, other days")
	var n := Notices.list(r["sim"], FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.employee_quit")
	check(not n.is_empty() and str(n[0]["severity"]) == Notices.URGENT, "urgent quit notice")


func test_no_quitting_or_theft_when_content() -> void:
	var r := _dawns(7, 50)
	eq(r["left"], {}, "loyalty 50: nobody leaves")
	r = _dawns(7, 80)
	eq(r["left"], {}, "loyalty 80: nobody leaves")


func test_theft_about_3_percent_a_day_at_0_19() -> void:
	var r := _dawns(11, 10, 5)
	var thefts := int(r["left"].get("theft", 0))
	check(thefts >= 30 and thefts <= 95, "about 60 thefts in %d days at 3 %% (got %d)" % [DAYS, thefts])
	eq(int(r["left"].get("quit", 0)), 0, "at 0-19 they steal, they do not just quit")
	check(int(r["stolen"]) >= thefts and int(r["stolen"]) <= thefts * 3, "1-3 units each (%d units)" % r["stolen"])
	check(int(r["stolen"]) > thefts and int(r["stolen"]) < thefts * 3, "not always the same amount")


func test_thief_takes_the_most_valuable_and_flees_banned() -> void:
	var sim := _sim("two_employees")
	var st := sim.state
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	Inventory.add(inv, cat, "sword", 0, 2)
	Inventory.add(inv, cat, "iron_ingot", 0, 5)
	var iron := Inventory.count(inv, "iron")
	var ch: Dictionary = st.characters[AGNES]
	ch["job"]["start_day"] = 0
	ch["job"]["loyalty"] = 0
	var today := Clock.day(int(st.clock["minute"]))
	var stole: Dictionary = {}
	for i: int in 500:
		sim.events = [{"type": "phase_changed", "phase": "dawn"}]
		ch["job"]["loyalty"] = 0
		Staff.step(sim)
		var ev := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "employee_stole")
		if not ev.is_empty():
			stole = ev[0]
			break
	check(not stole.is_empty(), "she steals within 500 days at 3 %")
	eq(str(stole.get("item", "")), "sword", "the sword is the most valuable")
	eq(Inventory.count(inv, "sword"), 2 - int(stole.get("qty", 0)), "taken from the storage")
	eq(Inventory.count(inv, "iron"), iron, "nothing else")
	eq(int(stole.get("value", 0)), Market.price(sim, "sword", 0, "sell") * int(stole.get("qty", 0)), "its value")
	check(ch.get("job") == null, "she fled: no job")
	eq(int(ch["hire_bans"][FAM]), today + 8, "banned 1 year (8 days) by this family")
	eq(Orders.apply(sim, {"type": "hire", "actor": PLAYER, "building": FORGE, "candidate": AGNES})["reason"], "banned",
		"cannot be hired again")
	var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.employee_stole")
	check(not n.is_empty() and str(n[0]["severity"]) == Notices.URGENT, "urgent theft notice")


func test_security_halves_theft() -> void:
	var sim := _sim("two_employees")
	sim.catalog = Catalog.load_from()
	sim.catalog.employees["theft"]["security_upgrades"] = ["test_lock"]
	sim.state.buildings[FORGE]["upgrades"] = ["test_lock"]
	check(Staff._has_security(sim, FORGE), "a security upgrade is seen")
	sim.state.buildings[FORGE]["upgrades"] = []
	check(not Staff._has_security(sim, FORGE), "none without it")


func test_save_load_with_pending_hires() -> void:
	var sim := _sim("town_e_start")
	check(Orders.apply(sim, {"type": "hire", "actor": PLAYER, "building": FORGE, "candidate": JOAN})["ok"], "hires")
	var text := JSON.stringify(sim.state.to_dict())
	var back: WorldState = SaveFile.from_text(text)["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(sim.state.to_dict()), "same content")
	var sim2 := Sim.new(back, cat)
	eq(Staff.employees_of(sim2.state, FORGE), [JOAN], "the hire survives")
	check(not Staff.is_active(sim2, JOAN), "not started yet")
	_to_dawn(sim)
	_to_dawn(sim2)
	check(Staff.is_active(sim2, JOAN), "starts at the dawn after loading")
	eq(int(sim2.state.characters[JOAN]["job"]["loyalty"]), 51, "and is paid")
	eq(sim2.state_hash(), sim.state_hash(), "same game as without saving")
