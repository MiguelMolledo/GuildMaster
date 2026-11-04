extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.24.3, O-R9 b, O-V2): with the living town II the cap of townsfolk is the
## map's own (5 per house, up to 32: town_e has 8 houses -> 32). A long sim jumping from midnight to dawn, like
## tests/test_town_population.gd (H7's renewal with its cap of 20, unchanged): the town grows to the new cap and keeps
## people to marry; the band is data/targets.json town_population_life (proposed: it moves H7's [14, 22]).

var cat := Catalog.load_from()


func _targets() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/targets.json"))["town_population_life"]


func _jump_day(sim: Sim, day: int) -> void:
	var st := sim.state
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY - 1
	sim.step()
	var dawn := int(cat.time["phase_starts"][Clock.season(day * Clock.MINUTES_PER_DAY, cat.time)]["dawn"])
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + dawn - 1
	sim.step()


func test_the_map_cap() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	eq(Population.max_total(sim), 32, "town_e: 8 houses × 5, up to 32")
	var off := Catalog.load_from()
	off.life_tables["life"]["enabled"] = false
	eq(Population.max_total(Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], off)), 20, "life off: H7's 20")


func test_the_town_grows_to_its_cap_and_holds() -> void:
	var t := _targets()
	var years := int(t["years"][0])
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	var dpy := Clock.days_per_year(cat.time)
	var low := 999
	var high := 0
	for d: int in range(1, years * dpy + 1):
		_jump_day(sim, d)
		var n := Population.townsfolk(sim.state).size()
		low = mini(low, n)
		high = maxi(high, n)
	var fertile := 0
	for id: String in Population.singles(sim):
		var a := Kin.age(sim, id)
		if bool(sim.state.characters[id]["female"]) and a >= 18 and a <= int(cat.family["children"]["mother_max_age"]) - 5:
			fertile += 1
	print("[test] población con la vida (tope %d) %d años: entre %d y %d vecinos, al final %d (solteras fértiles %d)" % [
		Population.max_total(sim), years, low, high, Population.townsfolk(sim.state).size(), fertile])
	check(low >= int(t["townsfolk"][0]) and high <= int(t["townsfolk"][1]), "townsfolk in %s (%d-%d)" % [t["townsfolk"], low, high])
	check(fertile >= int(t["fertile_singles"][0]), "women to marry at the end (%d)" % fertile)
