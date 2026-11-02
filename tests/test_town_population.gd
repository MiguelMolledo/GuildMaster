extends "res://tests/test_case.gd"
## H7 · the town renews itself (the gap of H8, docs/contratos/h7_ciudad.md): townsfolk marry, have children (with a
## cap), grow up into apprentices, die, and newcomers fill the gaps. A long sim jumping from midnight to dawn (only the
## steps where those rules act) for the years of data/targets.json town_population.

var cat := Catalog.load_from()


func _targets() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/targets.json"))["town_population"]


## One step at midnight (year_changed) and one at dawn (weddings, births) of `day`.
func _jump_day(sim: Sim, day: int, evs: Array) -> void:
	var st := sim.state
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY - 1
	evs.append_array(sim.step())
	var dawn := int(cat.time["phase_starts"][Clock.season(day * Clock.MINUTES_PER_DAY, cat.time)]["dawn"])
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + dawn - 1
	evs.append_array(sim.step())


func _fertile_singles(sim: Sim) -> int:
	var n := 0
	var max_age := int(cat.family["children"]["mother_max_age"]) - 5
	for id: String in Population.singles(sim):
		var a := Kin.age(sim, id)
		if bool(sim.state.characters[id]["female"]) and a >= 18 and a <= max_age:
			n += 1
	return n


func test_population_stays_stable_for_generations() -> void:
	var t := _targets()
	var years := int(t["years"][0])
	var lo := int(t["townsfolk"][0])
	var hi := int(t["townsfolk"][1])
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	var evs: Array = []
	var dpy := Clock.days_per_year(cat.time)
	var low := 999
	var high := 0
	for d: int in range(1, years * dpy + 1):
		_jump_day(sim, d, evs)
		var n := Population.townsfolk(sim.state).size()
		low = mini(low, n)
		high = maxi(high, n)
	var count := {}
	for e: Dictionary in evs:
		count[str(e["type"])] = int(count.get(str(e["type"]), 0)) + 1
	print("[test] población %d años: entre %d y %d vecinos; bodas %d, nacimientos %d, muertes %d, llegadas %d, al final %d (solteras fértiles %d)" % [
		years, low, high, int(count.get("townsfolk_married", 0)), int(count.get("child_born", 0)),
		int(count.get("character_died", 0)), int(count.get("newcomer_arrived", 0)),
		Population.townsfolk(sim.state).size(), _fertile_singles(sim)])
	check(low >= lo and high <= hi, "townsfolk always in [%d, %d] (%d-%d)" % [lo, hi, low, high])
	check(int(count.get("townsfolk_married", 0)) >= 3, "townsfolk marry")
	check(int(count.get("child_born", 0)) >= 3, "townsfolk have children")
	check(int(count.get("character_died", 0)) >= 10, "townsfolk die of old age (a generation passes)")
	check(_fertile_singles(sim) >= int(t["fertile_singles"][0]), "there are still women to marry at the end (%d)" % _fertile_singles(sim))
	for id: String in Population.townsfolk(sim.state):
		var ch: Dictionary = sim.state.characters[id]
		if TownLife.is_adult(sim.state, cat, id):
			check(str(ch["rank"]) != "", "%s adult with a trade rank (a hire candidate)" % id)
			check(str(ch["occupation"]) != "", "%s adult with a trade" % id)
		eq(str(ch["location"]) == str(ch["home"]) or str(ch["location"]) == "" or ch.get("job") is Dictionary, true,
			"%s lives somewhere" % id)
	for f: String in sim.state.families:
		if TownLife.is_household(sim.state, f):
			var alive := (sim.state.families[f]["members"] as Array).filter(func(m: Variant) -> bool: return Kin.alive(sim.state, str(m)))
			if not alive.is_empty():
				check(Kin.head(sim.state, f) != "", "household %s keeps a head while someone lives" % f)


func test_children_are_born_at_home_and_capped() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	var evs: Array = []
	for d: int in range(1, 8 * 12):
		_jump_day(sim, d, evs)
	for e: Dictionary in evs:
		if str(e["type"]) == "child_born" and TownLife.is_household(sim.state, str(e["family"])):
			var c: Dictionary = sim.state.characters[str(e["character"])]
			check(str(c["home"]) != "", "a townsfolk child has a house")
			eq(str(c["location"]), str(c["home"]), "and is born in it")
	check(Population.townsfolk(sim.state).size() <= int(cat.town["population"]["max_total"]), "never more than max_total")
