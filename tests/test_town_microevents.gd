extends "res://tests/test_case.gd"
## H7 · microevents (GDD 4.20): without an answer the default applies at 2 h; each choice does what its card says;
## the AI chooses at once; Security foils the thief with its probability; at most one a day per family and a cooldown
## per building; haggling starts with a customer at the counter.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String = "town_microevents", s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


func _smith(sim: Sim) -> String:
	for e: String in Staff.employees_of(sim.state, FORGE):
		if str(sim.state.characters[e]["job"]["role"]) == "any":
			return e
	return ""


func _resolved(evs: Array) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "microevent_resolved")


func test_default_applies_at_two_hours() -> void:
	var sim := _sim()
	sim.state.clock["minute"] = Clock.MINUTES_PER_DAY + 300
	var emp := _smith(sim)
	var loyalty := int(sim.state.characters[emp]["job"]["loyalty"])
	var id := Microevents.start(sim, "sick_employee", FAM, FORGE, emp)
	check(id != "", "the card starts")
	eq(Microevents.view(sim, id)["minutes_left"], 120, "2 h of game time to answer")
	check(not Staff.is_active(sim, emp), "sick: not at work today")
	var evs: Array = []
	for i: int in 119:
		evs.append_array(sim.step())
	eq(_resolved(evs).size(), 0, "still waiting at 1:59")
	evs = sim.step()
	var res := _resolved(evs)
	eq(res.size(), 1, "resolved at 2:00")
	eq([str(res[0]["choice"]), str(res[0]["by"])], ["day_off", "timeout"], "the default: paid day off (4.20)")
	eq(int(sim.state.characters[emp]["job"]["loyalty"]), loyalty + 2, "loyalty +2")
	eq(Microevents.active_for(sim, FAM).size(), 0, "the card is gone")
	sim.state.clock["minute"] = 2 * Clock.MINUTES_PER_DAY + 400
	check(Staff.is_active(sim, emp), "back the next day")


func test_choices_do_what_they_say() -> void:
	var sim := _sim()
	var emp := _smith(sim)
	var gold := Money.gold(sim.state, FAM)
	var loyalty := int(sim.state.characters[emp]["job"]["loyalty"])
	var id := Microevents.start(sim, "sick_employee", FAM, FORGE, emp)
	var r := Orders.apply(sim, {"type": "resolve_microevent", "actor": HERO, "microevent": id, "choice": "doctor"})
	check(r["ok"], "choose the doctor (%s)" % r["reason"])
	eq(Money.gold(sim.state, FAM), gold - 10, "the doctor costs 10")
	eq(int(sim.state.characters[emp]["job"]["loyalty"]), loyalty + 5, "loyalty +5")
	var dock := _sim()
	var e2 := _smith(dock)
	var g2 := Money.gold(dock.state, FAM)
	var l2 := int(dock.state.characters[e2]["job"]["loyalty"])
	var id2 := Microevents.start(dock, "sick_employee", FAM, FORGE, e2)
	check(Orders.apply(dock, {"type": "resolve_microevent", "actor": HERO, "microevent": id2, "choice": "dock"})["ok"], "dock")
	eq(int(dock.state.characters[e2]["job"]["loyalty"]), l2 - 5, "loyalty −5")
	eq(Money.gold(dock.state, FAM), g2 + Staff.wage(dock, e2), "the day's wage comes back")
	var until := int(dock.state.characters[e2]["job"]["absent_until"])
	var today := Clock.day(int(dock.state.clock["minute"]))
	check(until == today or until == today + 1, "misses 1-2 days")
	eq(Orders.apply(dock, {"type": "resolve_microevent", "actor": HERO, "microevent": id2, "choice": "dock"})["reason"],
		"unknown_microevent", "a closed card cannot be chosen again")


func test_ai_family_chooses_at_once() -> void:
	var sim := _sim()
	var rival := "fam_0003"
	var rbld := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["owner"]) == rival:
			rbld = b
	sim.state.events_active = []
	sim.events = []
	var id := Microevents.start(sim, "night_thief", rival, rbld, "", Kin.head(sim.state, rival))
	eq(Microevents.active_for(sim, rival).size(), 0, "the AI resolved it at once")
	check(_resolved(sim.events).size() == 1 and str(_resolved(sim.events)[0]["choice"]) == "let", "with the default (%s)" % id)


func test_security_foils_the_thief_with_its_probability() -> void:
	for lvl: Array in [[0, 0.0], [1, 0.2], [2, 0.4], [3, 0.6]]:
		var sim := _sim()
		for n: int in range(1, int(lvl[0]) + 1):
			check(Upgrades.complete(sim, FORGE, "forge_security_%d" % n), "security %d" % n)
		near(Upgrades.amount(sim, FORGE, "protection"), float(lvl[1]), 0.0001, "protection %.1f" % float(lvl[1]))
		var foiled := 0
		var n_tries := 1500
		for i: int in n_tries:
			if Microevents.security_foils(sim, FORGE, "try%d" % i):
				foiled += 1
		var p := float(foiled) / n_tries
		check(absf(p - float(lvl[1])) < 0.04, "Security %d foils %.0f %% (%.3f)" % [lvl[0], float(lvl[1]) * 100.0, p])


func test_thief_with_nobody_inside_and_with_somebody() -> void:
	var sim := _sim()
	sim.state.characters[HERO]["location"] = ""
	var swords := Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword")
	var now := int(sim.state.clock["minute"])
	(sim.state.microevents["pending"] as Array).append({"def": "night_thief", "family": FAM, "building": FORGE, "day": 0,
		"at": now + 1})
	var evs: Array = []
	for i: int in 3:
		evs.append_array(sim.step())
	var thefts := evs.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "theft")
	eq(thefts.size(), 1, "nobody inside: it steals at once, no card")
	eq(str(thefts[0]["item"]), "sword", "the most valuable product")
	var q := int(thefts[0]["qty"])
	check(q >= 1 and q <= 3, "1-3 units (%d)" % q)
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword"), swords - q, "they leave the storage")
	eq(Microevents.active_for(sim, FAM).size(), 0, "no card")
	var inside := _sim()
	inside.state.characters[HERO]["location"] = FORGE
	(inside.state.microevents["pending"] as Array).append({"def": "night_thief", "family": FAM, "building": FORGE,
		"day": 0, "at": int(inside.state.clock["minute"]) + 1})
	inside.run_minutes(3)
	eq(Microevents.active_for(inside, FAM).size(), 1, "Hugo inside: a card (confront / let him)")
	var outcomes := {}
	for k: int in 12:
		var s2 := _sim()
		s2.state.characters[HERO]["location"] = FORGE
		s2.state.clock["minute"] = int(s2.state.clock["minute"]) + k
		var mid := Microevents.start(s2, "night_thief", FAM, FORGE, "", HERO)
		var before := Inventory.count(s2.state.buildings[FORGE]["inventory"], "sword")
		Orders.apply(s2, {"type": "resolve_microevent", "actor": HERO, "microevent": mid, "choice": "confront"})
		outcomes[Inventory.count(s2.state.buildings[FORGE]["inventory"], "sword") == before] = true
	eq(outcomes.size(), 2, "confronting: sometimes he flees empty-handed, sometimes he steals anyway")


func test_one_a_day_and_cooldown() -> void:
	var sim := _sim()
	var today := Clock.day(int(sim.state.clock["minute"]))
	Microevents.start(sim, "sick_employee", FAM, FORGE, _smith(sim))
	var el := Microevents.eligible(sim, FAM, today + 1)
	var defs: Array = el.map(func(x: Dictionary) -> String: return str(x["def"]))
	check(not "sick_employee" in defs, "sick_employee cools down at that building")
	check(Microevents.eligible(sim, FAM, today + 8).map(func(x: Dictionary) -> String: return str(x["def"])).has("sick_employee"),
		"after 8 days (1 year) it may come again")
	eq(int(sim.state.microevents["last_day"][FAM]), today, "today's microevent is spent")


func test_haggling_starts_with_a_customer() -> void:
	var sim := _sim()
	var today := Clock.day(int(sim.state.clock["minute"]))
	(sim.state.microevents["pending"] as Array).append({"def": "haggling_customer", "family": FAM, "building": FORGE,
		"day": today, "at": -1})
	var started := {}
	for i: int in 12 * 60:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "microevent_started":
				started = e
		if not started.is_empty():
			break
	eq(str(started.get("def", "")), "haggling_customer", "the next served customer haggles")
	var cust := str(started["target"])
	check(Microevents.holding(sim, cust), "the customer waits for the answer")
	var gold := Money.gold(sim.state, FAM)
	var v := Microevents.view(sim, str(started["id"]))
	check(Orders.apply(sim, {"type": "resolve_microevent", "actor": HERO, "microevent": str(started["id"]),
		"choice": "accept"})["ok"], "accept −15 %")
	eq(Money.gold(sim.state, FAM) - gold, roundi(int(v["params"]["price"]) * 0.85), "sold at −15 %")
