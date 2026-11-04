extends "res://tests/test_case.gd"
## H10 base (docs/contratos/h10_cargos.md): the office and politics tables (GDD 4.12.3-4.12.4 figures), the v10 save
## and its migration from v9 (offices, elections and regulations get their shape; the government is handed out the
## first time the sim runs), the round trip with offices and elections, a new game's procedural government and the
## three office scenarios.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func test_office_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	eq(cat.office_chart(), ["mayor", "councillor", "judge", "constable", "tax_collector", "market_inspector"],
		"the 6 offices of 4.12.3, top of the chart first")
	var want := {"market_inspector": ["citizen", 2, 1, 1, "minor"], "tax_collector": ["citizen", 3, 1, 1, "minor"],
		"constable": ["patrician", 4, 2, 1, "middle"], "judge": ["patrician", 5, 2, 1, "middle"],
		"councillor": ["baron", 6, 3, 2, "major"], "mayor": ["baron", 10, 4, 1, "mayor"]}
	for o: String in want:
		var d: Dictionary = cat.offices()[o]
		eq([str(d["min_title"]), int(d["salary"]), int(d["term_years"]), int(d["seats"]), str(d["rank"])], want[o],
			"%s: title, salary, term, seats, rank" % o)
	var el: Dictionary = cat.politics["elections"]
	eq([int(el["levels"]["basic"]["gold"]), int(el["levels"]["medium"]["gold"]), int(el["levels"]["high"]["gold"])],
		[0, 50, 200], "campaign levels: free, 50, 200 (4.12.4)")
	eq([int(el["levels"]["basic"]["bonus_permil"]), int(el["levels"]["medium"]["bonus_permil"]),
		int(el["levels"]["high"]["bonus_permil"])], [50, 150, 300], "+5 %, +15 %, +30 %")
	near(float(el["vote"]["affinity"]) + float(el["vote"]["reputation"]) + float(el["vote"]["class"])
		+ float(el["vote"]["campaign"]), 1.0, 0.0001, "the vote weights of ap. A add up to 1")
	eq(int(el["actions"]["bribe"]["gold"]), 20, "a bribe: 20 gold base")
	eq(float(el["actions"]["visit"]["busy_hours"]), 4.0, "a visit: 4 hours")
	eq([int(cat.politics["taxes"]["min"]), int(cat.politics["taxes"]["max"])], [5, 15], "taxes 5-15 %")
	eq(int(cat.politics["regulation"]["percent"]), 10, "regulation ±10 %")


func test_v9_save_migrates_to_v10() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/v9_title_ready.json"))
	eq(int(raw["version"]), 9, "the fixture is v9")
	var r := SaveFile.load_file("res://tests/data/saves/v9_title_ready.json")
	check(r["ok"], "the v9 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	check(WorldState.VERSION >= 10, "v10 or later")
	eq(st.version, WorldState.VERSION, "migrated")
	eq(st.offices, {}, "no government yet")
	eq(st.elections, [], "no elections")
	eq(st.market["regulations"], [], "no regulations")
	var sim := Sim.new(st, cat)
	sim.run_minutes(1)
	eq((st.offices as Dictionary).keys().size(), 6, "the first step hands out the government")
	eq(Offices.holders(sim, "judge").size(), 1, "a judge from the patrician household")
	eq(Offices.holders(sim, "market_inspector"), [], "the inspector is vacant")
	sim.run_minutes(59)
	check(true, "a migrated game runs")


func test_old_shapes_start_empty() -> void:
	var d := {"version": 9, "offices": {"mayor": {"holder": "chr_0001"}}, "elections": "x", "market": {"demand": {}}}
	var m := SaveFile.migrate(d)
	check(m["ok"], "migrates")
	eq(m["data"]["offices"], {}, "an office without seats is dropped")
	eq(m["data"]["elections"], [], "elections become a list")
	eq(m["data"]["market"]["regulations"], [], "regulations become a list")


func test_round_trip_with_offices_and_elections() -> void:
	var st: WorldState = NewGame.from_scenario("office_election_eve", 1)["state"]
	var sim := Sim.new(st, cat)
	Orders.apply(sim, {"type": "use_office_power", "actor": "chr_0004", "power": "pardon", "args": {}})
	(st.market["regulations"] as Array).append({"item": "sword", "percent": 10, "until": 99999, "by": HERO,
		"family": FAM})
	var text := JSON.stringify(st.to_dict(), "\t", true, true)
	var back: WorldState = SaveFile.from_text(text)["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same state after save and load")
	eq((back.elections[0]["candidates"] as Array).size(), 2, "the candidates")
	eq(Offices.regulation(Sim.new(back, cat), "sword"), 10, "the regulation")


func test_new_game_government() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	check(r["ok"], "new game")
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	var homes: Array = []
	for f: String in st.families:
		if TownLife.is_household(st, f):
			homes.append(f)
	homes.sort()
	var titles: Array = cat.politics["government"]["household_titles"]
	for i: int in homes.size():
		eq(str(st.families[homes[i]]["title"]), str(titles[i]) if i < titles.size() else "common",
			"household %s gets its title" % homes[i])
	eq(str(st.families[FAM]["title"]), "common", "the player starts common")
	eq(Offices.holders(sim, "mayor"), [], "nobody in town is a baron: no mayor")
	eq(Offices.holders(sim, "councillor"), [], "nor councillors")
	eq(Offices.holders(sim, "judge").size(), 1, "a patrician judge")
	eq(Offices.holders(sim, "constable").size(), 1, "a patrician constable")
	check(Offices.holders(sim, "judge") != Offices.holders(sim, "constable"), "one office per person")
	eq(Offices.holders(sim, "market_inspector"), [], "inspector left free (4.12.3: 1-2 minor offices)")
	eq(Offices.holders(sim, "tax_collector"), [], "collector left free: no taxes")
	eq(int(st.offices["judge"]["seats"][0]["until"]), 16, "the judge's 2-year term ends at the start of year 3")
	eq(Offices.election_day(sim, "market_inspector"), 8, "the vacant inspector votes at the first year change")
	eq(Offices.election_day(sim, "judge"), -1, "the judge does not vote this year")
	eq(Elections.voters(sim).size(), 10, "the adults of the five titled households vote")
	eq(Offices.tax_percent(sim), 0, "no collector, no taxes")


func test_office_scenarios() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_campaign", 1)["state"], cat)
	eq(Elections.run_status(sim, HERO, "market_inspector", "medium"), "", "Hugo can run for inspector")
	check(Titles.at_town_hall(sim, HERO), "at the town hall")
	sim = Sim.new(NewGame.from_scenario("office_election_eve", 1)["state"], cat)
	var el := Elections.open_election(sim.state, "market_inspector")
	eq((el["candidates"] as Array).size(), 2, "two candidates")
	eq(int(el["day"]), 8, "the vote at the year change")
	check(Elections.in_campaign(sim, el), "in campaign")
	sim = Sim.new(NewGame.from_scenario("office_inspector", 1)["state"], cat)
	eq(Offices.of_character(sim.state, HERO), "market_inspector", "Hugo is the inspector")
	eq(Offices.power_status(sim, HERO, "regulate_price", {"item": "sword", "percent": 10}), "", "he can regulate")
