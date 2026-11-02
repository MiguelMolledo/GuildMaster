extends "res://tests/test_case.gd"
## H8 base (docs/contratos/h8_familia.md): the family tables, the v7 save and its migration from v6, the round trip
## with kin, routine and score state, the ages (all at year_changed), a new game with ages and tones, and the family
## scenarios (founder_old, founder_no_heir, courtship, dynasty_start, family_routines).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


func test_family_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	var life: Dictionary = cat.family["life"]
	eq([int(life["school_age"]), int(life["apprentice_age"]), int(life["majority_age"])], [8, 12, 16], "life stages (4.2.5)")
	var ch: Dictionary = cat.family["children"]
	eq([int(ch["first_child_days"]), ch["daily_chance"], int(ch["between_days"]), int(ch["max_per_couple"])],
		[2, 0.1, 8, 3], "children (4.10.3)")
	eq(int(cat.family["courtship"]["propose_min"]), 80, "propose at 80 (4.10.1)")
	eq(int(cat.family["group"]["max"]), 3, "3 controllable (4.10.5)")
	eq(bool(cat.family["succession"]["voluntary_close"]), false, "voluntary close off until D19")
	eq(int(cat.score["points"]["inheritance"]), 100, "new generation 100 points (4.17)")
	eq((cat.goals["goals"] as Array).size(), 3, "3 goals")


func test_ages_change_together_at_year_change() -> void:
	var t := cat.time
	eq(Clock.age_years(-200, 0, t), 25, "25 at the start")
	eq(Clock.age_years(13, 15 * Clock.MINUTES_PER_DAY, t), 0, "born on day 13, still 0 on day 15 (same year)")
	eq(Clock.age_years(13, 16 * Clock.MINUTES_PER_DAY, t), 1, "1 on day 16 (the year changed)")
	eq(Clock.age_years(15, 16 * Clock.MINUTES_PER_DAY, t), 1, "born on the last day of a year: 1 the next day")
	eq(Kin.birth_day_for(60, 3 * Clock.MINUTES_PER_DAY, t), -480, "60 years at day 3: born on day -480")


func test_v6_save_migrates_to_v7() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v6_forge_upgrade_works.json")
	check(r["ok"], "the v6 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	check(WorldState.VERSION >= 7, "v7 or later (H7: v8)")
	var sim := Sim.new(st, cat)
	for id: String in st.characters:
		var c: Dictionary = st.characters[id]
		for k: String in ["birth_day", "death_day", "class", "profession", "spouse", "parents", "children", "assigned",
				"directives", "schedule", "visual", "life"]:
			check(c.has(k), "%s has %s" % [id, k])
		eq(Kin.age(sim, id), SaveFile.MIGRATION_AGE, "%s gets the migration age" % id)
		check(int(c["visual"]["hair"]) < 6 and int(c["visual"]["skin"]) < 4, "%s tones in the palette" % id)
	eq(str(st.characters[HERO]["profession"]), "blacksmith", "the player's people work the forge")
	for f: String in st.families:
		var fd: Dictionary = st.families[f]
		eq(str(fd["head"]), str(fd["members"][0]) if not (fd["members"] as Array).is_empty() else "", "%s head = first" % f)
		eq([fd["heir"], int(fd["generation"]), fd["regent"], fd["goals_done"]], ["", 1, "", []], "%s v7 fields" % f)
	sim.run_minutes(180)
	eq(Staff.employees_of(sim.state, FORGE).size(), 2, "a migrated game runs with its employees")


func test_round_trip_with_h8_state() -> void:
	var sim := _sim("family_routines")
	var st := sim.state
	Courtship.relation(st, HERO, "chr_0003")["affinity"] = 42
	Chronicle.add(st, "wealth_peak", {"family": FAM, "value": 900})
	st.families[FAM]["heir"] = str(st.characters[HERO]["children"][0])
	st.characters[HERO]["routine"] = {"manual": true, "slot": "day", "retry_at": 999}
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(typeof(back.characters[HERO]["birth_day"]), TYPE_INT, "birth_day is int")
	eq(back.characters[HERO]["schedule"]["day"]["action"], "work", "routine survives")
	eq(back.characters[HERO]["children"], st.characters[HERO]["children"], "children survive")
	eq(int(back.relationships[Ids.pair_key(HERO, "chr_0003")]["affinity"]), 42, "affinity survives")
	eq(str(back.families[FAM]["heir"]), str(st.families[FAM]["heir"]), "heir survives")


func test_new_game_has_ages_tones_and_a_head() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"visual": {"hair": 4, "skin": 2}}, 7)
	check(r["ok"], "new game")
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	eq(Kin.age(sim, HERO), 20, "the protagonist is 20 (4.16)")
	eq(st.characters[HERO]["visual"], {"hair": 4, "skin": 2}, "the chosen tones")
	eq([str(st.families[FAM]["head"]), str(st.families[FAM]["founder"]), int(st.families[FAM]["generation"])],
		[HERO, HERO, 1], "head and founder")
	eq(st.characters[HERO]["schedule"], null, "the founder starts without routine (provisional)")
	eq(Kin.age(sim, "chr_0002"), 35, "the rival smith is 35")
	eq(Kin.group(st, FAM), [HERO], "the group is the protagonist")
	eq(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"visual": {"hair": -1}}, 7)["ok"], false, "bad tones")
	var adults := 0
	for id: String in st.characters:
		if str(st.characters[id].get("home", "")) != "":
			adults += 1
			check(Kin.age(sim, id) >= 18 and Kin.age(sim, id) <= 30, "%s is an adult of 18-30" % id)
			check(Kin.is_single(st, id), "%s is single" % id)
	eq(adults, 16, "16 townsfolk")


func test_family_scenarios() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var son := str(st.characters[HERO]["children"][0])
	var wife := str(st.characters[HERO]["spouse"])
	eq([Kin.age(sim, HERO), Kin.age(sim, son), Kin.age(sim, wife)], [60, 16, 56], "founder 60, heir 16")
	eq(Kin.heir(sim, FAM), son, "the son is the heir by default")
	eq(Kin.group(st, FAM), [HERO, son], "founder and heir in the group")
	eq(str(st.characters[wife]["family"]), FAM, "the wife is of the family")
	eq(str(st.characters[wife]["controlled_by"]), "ai", "the spouse acts with AI (4.10.2)")
	check(st.loans.is_empty(), "the loan was repaid")
	sim = _sim("founder_no_heir")
	eq(Kin.age(sim, HERO), 74, "74")
	eq(Kin.heir(sim, FAM), "", "no heir")
	near(Lifecycle.death_chance(sim, HERO), 1.0, 0.0001, "at 74 the formula is over 1: certain death")
	sim.state.characters[HERO]["birth_day"] = Kin.birth_day_for(62, int(sim.state.clock["minute"]), cat.time)
	sim.state.characters[HERO]["stats"]["constitution"] = 5
	near(Lifecycle.death_chance(sim, HERO), 0.02 * pow(1.25, 7), 0.0001, "~10 % at 62 with Constitution 5 (4.2.5)")
	sim.state.characters[HERO]["birth_day"] = Kin.birth_day_for(54, int(sim.state.clock["minute"]), cat.time)
	eq(Lifecycle.death_chance(sim, HERO), 0.0, "none before 55")
	sim = _sim("courtship")
	var agnes := ""
	for id: String in sim.state.characters:
		if str(sim.state.characters[id]["name"]) == "Agnès":
			agnes = id
	eq(Courtship.affinity(sim.state, HERO, agnes), 76, "76 affinity")
	eq(Courtship.status(sim, HERO, agnes), "", "in range to court")
	sim = _sim("family_routines")
	eq(Kin.group(sim.state, FAM).size(), 3, "three in the group")
	for c: String in Kin.group(sim.state, FAM):
		eq(sim.state.characters[c]["schedule"]["day"]["action"], "work", "%s works by day" % c)
