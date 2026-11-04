extends "res://tests/test_case.gd"
## H4 base (docs/contratos/h4_empleados.md): employees' data, the townsfolk and their houses, the v5 save, the orders
## wired, employees allowed into their workplace (by day, normal mode), the scenarios and the queries' shape. The
## systems themselves (Staff, WorkQueue, Routines) are tested by their owners.

var cat := Catalog.load_from()


func _sim(id: String = "town_e_start") -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func test_h4_data_loads() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	var wages := []
	var eff := []
	var spd := []
	for r: String in cat.employees["rank_order"]:
		wages.append(int(cat.rank(r)["wage"]))
		eff.append(float(cat.rank(r)["efficiency"]))
		spd.append(float(cat.rank(r)["speed"]))
		var key := str(cat.rank(r)["name_key"])
		check(TranslationServer.translate(key) != key, "%s has text" % r)
	eq(cat.employees["rank_order"], ["apprentice", "journeyman", "master"], "3 ranks in order")
	eq(wages, [7, 20, 40], "wages 7/20/40 (GDD 4.7.2, H5 balance)")
	eq(eff, [0.5, 1.0, 1.5], "efficiency 50/100/150 %")
	eq(spd, [1.0, 2.0, 3.0], "speed ×1/×2/×3 (GDD 4.7.2, H5 balance)")
	eq([int(cat.rank("apprentice")["promote_after_days"]), int(cat.rank("journeyman")["promote_after_days"])], [8, 16],
		"1 year / 2 years more")
	eq([int(cat.rank("apprentice")["promote_min_loyalty"]), int(cat.rank("journeyman")["promote_min_loyalty"])], [51, 71],
		"loyalty > 50 / > 70")
	eq(int(cat.employees["wages"]["grace_days"]), 1, "1 day of grace")
	eq(cat.employees["theft"]["units"], [1, 3], "theft 1-3 units")
	eq(int(cat.employees["theft"]["no_rehire_days"]), 8, "no rehire 1 year")
	check(not "night" in (cat.employees["schedule"]["work_phases"] as Array), "never at night")
	eq(str(cat.buildings()["house"]["category"]), "residence", "the house type")


func test_town_e_has_houses_and_townsfolk() -> void:
	var m: Dictionary = cat.maps()["town_e"]
	var houses := 0
	for k: String in m["buildings"]:
		if str(m["buildings"][k]["type"]) == "house":
			houses += 1
	eq(houses, 8, "8 houses")
	var ranks := {}
	var n := 0
	for hh: Dictionary in m["population"]:
		eq(str(m["buildings"][str(hh["home"])]["type"]), "house", "%s lives in a house" % hh["family_name"])
		for p: Dictionary in hh["members"]:
			ranks[str(p["rank"])] = int(ranks.get(str(p["rank"]), 0)) + 1
			n += 1
	eq(n, 16, "16 townsfolk")
	eq(ranks, {"apprentice": 9, "journeyman": 5, "master": 2}, "apprentices abundant, masters scarce")


func test_sandbox_townsfolk_are_unemployed_at_home() -> void:
	var sim := _sim()
	var st := sim.state
	var folk: Array = []
	for id: String in st.characters:
		if str(st.characters[id].get("rank", "")) != "":
			folk.append(id)
	eq(folk.size(), 16, "16 townsfolk")
	for id: String in folk:
		var ch: Dictionary = st.characters[id]
		check(Staff.is_unemployed(sim, id), "%s is unemployed" % id)
		eq(str(ch["location"]), str(ch["home"]), "%s is at home" % id)
		eq(str(st.buildings[str(ch["home"])]["owner"]), str(ch["family"]), "%s's house is its family's" % id)
		eq(Routines.state_of(sim, id), "home", "%s state home" % id)
	for id: String in ["chr_0001", "chr_0006"]:
		check(not Staff.is_unemployed(sim, id), "%s is no candidate" % id)
	eq(int(st.buildings["bld_0001"]["employee_slots"]), 1, "the forge has 1 employee place")
	eq(int(st.buildings["bld_0003"]["employee_slots"]), 0, "the armory none")
	eq(st.buildings["bld_0001"]["queue"], {"entries": [], "loop": false, "paused": false}, "an empty queue")


func test_new_game_places_the_townsfolk_after_the_shops() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"]
	eq(str(st.families["fam_0002"]["ai_profile"]), "rival_smith", "the rival is still fam_0002")
	eq(str(st.characters["chr_0002"]["name"]), "Bernat", "Bernat is still chr_0002")
	eq(str(st.buildings["bld_0003"]["type"]), "armory", "the armory is still bld_0003")
	eq(str(st.buildings["bld_0004"]["type"]), "house", "the first house is bld_0004")
	var ch: Dictionary = st.characters["chr_0003"]
	eq([str(ch["family"]), str(ch["home"]), str(ch["location"]), str(ch["rank"])],
		["fam_0003", "bld_0004", "bld_0004", "journeyman"], "the first townsperson at home")
	eq(int(st.buildings["bld_0001"]["employee_slots"]), 1, "the player's forge: base_employees 1")
	eq(str(st.loans.keys()[0]), "lon_0001", "the loan keeps its id")


func test_v4_save_migrates_to_v5() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v4_town_e_start.json")
	check(r["ok"], "the v4 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	for id: String in st.characters:
		var ch: Dictionary = st.characters[id]
		eq([ch["home"], ch["rank"], ch["job"], ch["hire_bans"], ch["routine"]], ["", "", null, {}, {}], "%s v5 fields" % id)
	eq(int(st.buildings["bld_0001"]["employee_slots"]), 1, "forge 1 place")
	eq(int(st.buildings["bld_0003"]["employee_slots"]), 0, "armory 0")
	eq(st.buildings["bld_0002"]["queue"], {"entries": [], "loop": false, "paused": false}, "empty queue")
	var sim := Sim.new(st, cat)
	sim.run_minutes(10)
	eq(Money.gold(sim.state, "fam_0001"), 100, "a migrated game runs")


func test_round_trip_with_h4_state() -> void:
	var sim := _sim("two_employees")
	var st := sim.state
	var emp: Array = Staff.employees_of(st, "bld_0001")
	eq(emp.size(), 2, "2 employees")
	var who := str(emp[0])
	st.characters[who]["job"]["unpaid_days"] = 2
	st.characters[who]["job"]["promotion_offered"] = true
	st.characters[who]["hire_bans"]["fam_0003"] = 20
	st.characters[who]["routine"] = {"state": "to_work", "leave_at": 1755}
	(st.buildings["bld_0001"]["queue"]["entries"] as Array).append({"id": "qen_0099", "recipe": "forge_ingot",
		"qty": -1, "done": 3})
	st.buildings["bld_0001"]["queue"]["loop"] = true
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(typeof(back.characters[who]["job"]["loyalty"]), TYPE_INT, "loyalty is int")
	eq(int(back.buildings["bld_0001"]["queue"]["entries"][1]["qty"]), -1, "infinite survives")
	eq(int(back.characters[who]["hire_bans"]["fam_0003"]), 20, "the ban survives")


func test_h4_orders_are_wired() -> void:
	var sim := _sim()
	for t: String in ["hire", "fire", "promote", "bonus", "queue_add", "queue_remove", "queue_move", "queue_loop",
			"queue_pause", "set_role"]:
		var r := Orders.apply(sim, {"type": t, "actor": "chr_0001"})
		check(r["reason"] != "unknown_order", "%s is wired (%s)" % [t, r["reason"]])


func test_employees_work_their_forge_by_day_in_normal_mode() -> void:
	var sim := _sim("two_employees")
	var st := sim.state
	var smith := ""
	for c: String in Staff.employees_of(st, "bld_0001"):
		if str(st.characters[c]["job"]["role"]) == "anvil":
			smith = c
	check(smith != "", "the anvil employee")
	eq(Buildings.can_enter(sim, smith, "bld_0001")["reason"], "inside_other_building", "at home: leave it first")
	check(Orders.apply(sim, {"type": "exit_building", "actor": smith})["ok"], "leaves home (no interior: on the door)")
	check(Buildings.can_enter(sim, smith, "bld_0001")["ok"], "may enter the forge it works at")
	eq(Buildings.can_enter(sim, smith, "bld_0002")["reason"], "not_your_building", "not the rival's")
	eq(Production.may_work(sim, smith, "bld_0001"), "night_rest", "04:30: not at night")
	var day1 := Clock.MINUTES_PER_DAY
	st.clock["minute"] = day1 + 600
	eq(Production.may_work(sim, smith, "bld_0001"), "", "by day")
	st.clock["minute"] = day1 + 1150
	eq(Production.may_work(sim, smith, "bld_0001"), "off_hours", "not at dusk")
	st.clock["minute"] = day1 + 600
	var ch: Dictionary = st.characters[smith]
	ch["location"] = "bld_0001"
	var careful := Orders.apply(sim, {"type": "work_at", "actor": smith, "building": "bld_0001", "zone": "anvil",
		"recipe": "forge_ingot", "mode": "careful"})
	eq(careful["reason"], "wrong_station", "ingots are made at the furnace")
	careful = Orders.apply(sim, {"type": "work_at", "actor": smith, "building": "bld_0001", "zone": "anvil",
		"recipe": "forge_sword", "mode": "careful"})
	eq(careful["reason"], "mode_not_allowed", "employees do not work carefully")
	Inventory.add(st.buildings["bld_0001"]["inventory"], cat, "iron_ingot", Inventory.NORMAL, 2)
	var r := Orders.apply(sim, {"type": "work_at", "actor": smith, "building": "bld_0001", "zone": "anvil",
		"recipe": "forge_sword", "mode": "normal"})
	check(r["ok"], "a sword in normal mode (%s)" % r["reason"])
	ch["job"]["start_day"] = 2
	eq(Production.may_work(sim, smith, "bld_0001"), "not_controlled", "not before its first day")


func test_staff_queries() -> void:
	var sim := _sim("two_employees")
	var st := sim.state
	eq(Staff.slots(st, "bld_0001"), 2, "2 places")
	eq(Staff.free_slots(st, "bld_0001"), 0, "full")
	var rows := Staff.employees(sim, "bld_0001")
	eq(rows.size(), 2, "2 rows")
	for row: Dictionary in rows:
		for k: String in ["character", "name", "rank", "role", "loyalty", "band", "wage", "days_worked", "rank_days",
				"unpaid_days", "promotion_offered", "active", "start_day", "end_day", "routine", "task"]:
			check(row.has(k), "employee row has %s" % k)
		eq(str(row["routine"]), "home", "at home before dawn")
		check(bool(row["active"]), "working from today")
	var apprentice := ""
	for c: String in Staff.employees_of(st, "bld_0001"):
		if str(st.characters[c]["rank"]) == "apprentice":
			apprentice = c
	eq(Staff.wage(sim, apprentice), 7, "apprentice wage")
	near(Staff.speed(sim, apprentice), 1.0, 0.0001, "apprentice speed")
	near(Staff.efficiency(sim, apprentice), 0.5 * 0.8, 0.0001, "loyalty 50: -20 %")
	near(Staff.speed(sim, "chr_0001"), 1.0, 0.0001, "the player: no rank speed")
	var cands := Staff.candidates(sim, "chr_0001", "bld_0001")
	eq(cands.size(), 14, "the 14 unemployed townsfolk")
	eq(str(cands[0]["rank"]), "master", "masters first")
	eq(str(cands[0]["status"]), "no_slot", "no place left")
	eq(Staff.candidates(sim, "chr_0006", "bld_0001")[0]["status"], "not_your_building", "not the rival's to hire")
	var q := WorkQueue.view(sim, "bld_0001")
	eq((q["entries"] as Array).size(), 1, "a queue entry")
	eq([q["entries"][0]["recipe"], int(q["entries"][0]["qty"])], ["forge_sword", 10], "10 swords")


func test_h4_scenarios_run_a_day() -> void:
	for id: String in ["two_employees", "apprentice_promotion", "town_e_start"]:
		var sim := _sim(id)
		sim.run_minutes(Clock.MINUTES_PER_DAY)  # every system, stubs included, a whole day without breaking anything
		check(int(sim.state.clock["minute"]) > 0, "%s runs" % id)
	var promo := _sim("apprentice_promotion")
	var who: String = Staff.employees_of(promo.state, "bld_0001")[0]
	eq([int(promo.state.characters[who]["job"]["rank_days"]), int(promo.state.characters[who]["job"]["loyalty"])],
		[7, 60], "7 days in rank, loyalty 60")
