extends "res://tests/test_case.gd"
## Equilibrio 1 (docs/decisiones.json): only the first gift of the day to each suitor raises the affinity; the others
## are taken without effect, and the next day the first one counts again.

const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim(s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario("courtship", s)["state"], cat)


func _named(sim: Sim, name: String) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(sim.state.characters[id]["name"]) == name:
			return id
	return ""


func test_one_gift_a_day_counts() -> void:
	var sim := _sim()
	var st := sim.state
	var agnes := _named(sim, "Agnès")
	Courtship.relation(st, HERO, agnes)["affinity"] = 10
	Inventory.add(st.characters[HERO]["inventory"], cat, "sword", 0, 3)
	eq(Courtship.gifted_today(st, HERO, agnes), false, "no gift yet")
	eq(Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "sword", "quality": 0})["ok"],
		true, "first gift")
	var after_first := Courtship.affinity(st, HERO, agnes)
	check(after_first > 10, "the first gift raises the affinity")
	eq(Courtship.gifted_today(st, HERO, agnes), true, "the screen can tell")
	sim.events = []
	eq(Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "sword", "quality": 0})["ok"],
		true, "a second gift is taken")
	eq(Courtship.affinity(st, HERO, agnes), after_first, "but it does not count")
	eq(Inventory.count(st.characters[HERO]["inventory"], "sword"), 1, "the sword still leaves the actor")
	var said := false
	for e: Dictionary in sim.events:
		said = said or str(e["type"]) == "court_gift_no_effect"
	check(said, "an event says it had no effect")
	st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
	eq(Courtship.gifted_today(st, HERO, agnes), false, "a new day")
	eq(Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "sword", "quality": 0})["ok"],
		true, "next day")
	check(Courtship.affinity(st, HERO, agnes) > after_first, "the first gift of the next day counts again")


func test_the_cap_is_per_suitor() -> void:
	var sim := _sim()
	var st := sim.state
	var agnes := _named(sim, "Agnès")
	var cands := Courtship.candidates(sim, HERO)
	var other := ""
	for c: Dictionary in cands:
		if str(c["character"]) != agnes and str(c["status"]) in ["", "too_far"]:
			other = str(c["character"])
			break
	check(other != "", "another single woman")
	Inventory.add(st.characters[HERO]["inventory"], cat, "sword", 0, 2)
	Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "sword", "quality": 0})
	eq(Courtship.gifted_today(st, HERO, other), false, "the other suitor has no gift yet")
