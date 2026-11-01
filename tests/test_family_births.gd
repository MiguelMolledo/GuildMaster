extends "res://tests/test_case.gd"
## H8 children (GDD 4.10.3, 4.10.9; docs/contratos/h8_familia.md): the first child not before 1 season after the
## wedding and ~1.5 years on average, 1 year between children, at most 3, the stats formula and the hair and skin of a
## parent.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


## A fresh couple married today (day `day`): Hugo and Agnès of the courtship scenario.
func _couple(s: int, day: int = 1) -> Dictionary:
	var sim := Sim.new(NewGame.from_scenario("courtship", s)["state"], cat)
	var agnes := ""
	for id: String in sim.state.characters:
		if str(sim.state.characters[id]["name"]) == "Agnès":
			agnes = id
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 300
	Courtship.marry(sim, HERO, agnes)
	return {"sim": sim, "wife": agnes}


## One dawn of Births on day `day` (only that system).
func _dawn(sim: Sim, day: int) -> Array:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 300
	sim.events = [{"type": "phase_changed", "phase": "dawn"}]
	Births.step(sim)
	return sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "child_born")


func test_first_child_not_before_a_season_and_about_one_and_a_half_years() -> void:
	var total := 0
	var seeds := 40
	for s: int in range(1, seeds + 1):
		var c := _couple(s)
		var sim: Sim = c["sim"]
		var first := -1
		for d: int in range(1, 80):
			if not _dawn(sim, d).is_empty():
				first = d
				break
		check(first >= 3, "seed %d: no child before day 1 + 2 (got %d)" % [s, first])
		total += first - 1
	var mean := float(total) / seeds
	check(mean >= 8.0 and mean <= 16.0, "first child ~1.5 years (12 days) after the wedding on average: %.1f" % mean)


func test_one_year_between_children_and_three_at_most() -> void:
	var c := _couple(3)
	var sim: Sim = c["sim"]
	var wife: String = c["wife"]
	var days: Array = []
	for d: int in range(1, 200):
		if not _dawn(sim, d).is_empty():
			days.append(d)
	eq(days.size(), 3, "three children at most")
	for i: int in range(1, days.size()):
		check(int(days[i]) - int(days[i - 1]) >= 8, "a year between children (%s)" % [days])
	eq((sim.state.characters[wife]["children"] as Array).size(), 3, "the mother's children")
	for k: Variant in sim.state.characters[wife]["children"]:
		var ch: Dictionary = sim.state.characters[str(k)]
		eq(ch["parents"], [HERO, wife], "parents")
		eq(str(ch["family"]), FAM, "of the family")
		eq(str(ch["controlled_by"]), "ai", "not controllable")
		eq(str(ch["location"]), "bld_0001", "lives in the residence (the forge)")
		eq(float(ch["inventory"]["limit"]), 0.0, "no inventory of its own")
	var births := sim.state.chronicle.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "birth")
	eq(births.size(), 3, "births in the chronicle")


func test_stats_and_traits_come_from_the_parents() -> void:
	var c := _couple(5)
	var sim: Sim = c["sim"]
	var wife: String = c["wife"]
	var f: Dictionary = sim.state.characters[HERO]
	var m: Dictionary = sim.state.characters[wife]
	f["stats"]["craft"] = 9
	m["stats"]["craft"] = 7
	f["stats"]["stealth"] = 2
	m["stats"]["stealth"] = 3
	f["visual"] = {"hair": 0, "skin": 3}
	m["visual"] = {"hair": 5, "skin": 1}
	var from_parent := 0
	var n := 60
	for i: int in n:
		var key := "test|%d" % i
		var st := Births.child_stats(sim, m["stats"], f["stats"], key)
		check(int(st["craft"]) >= 8 and int(st["craft"]) <= 10, "craft (9+7)/2 ± 1 + 1, clamped (%d)" % int(st["craft"]))
		check(int(st["stealth"]) >= 1 and int(st["stealth"]) <= 3, "stealth (2+3)/2 ± 1 (%d)" % int(st["stealth"]))
		var v := Births.child_visual(sim, m["visual"], f["visual"], key)
		if int(v["hair"]) in [0, 5] and int(v["skin"]) in [3, 1]:
			from_parent += 1
	check(from_parent >= n * 0.7, "hair and skin of a parent most of the time (%d/%d)" % [from_parent, n])
	var kid := Births.born(sim, wife, HERO)
	var kv: Dictionary = sim.state.characters[kid]["visual"]
	check(int(kv["hair"]) >= 0 and int(kv["hair"]) < 6 and int(kv["skin"]) >= 0 and int(kv["skin"]) < 4, "in the palette")
