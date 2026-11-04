extends "res://tests/test_case.gd"
## H9 base (docs/contratos/h9_titulos.md): the title and politics tables (GDD 4.12.2 figures), the town hall of the
## map, the v9 save and its migration from v8 (title, class modifiers, reputation log and caps of every family), the
## round trip with titles and reputation, a new game's families and the title_ready scenario.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func test_title_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	eq(cat.title_ladder(), ["common", "citizen", "patrician", "baron", "noble"], "the 5 titles of 4.12.2, in order")
	eq(cat.title_ladder(), cat.upgrade_rules["titles"], "the same ladder the upgrades use")
	var want := {"citizen": [100, 50], "patrician": [500, 200], "baron": [2000, 500], "noble": [10000, 1000]}
	for t: String in want:
		eq([int(cat.titles()[t]["cost_gold"]), int(cat.titles()[t]["reputation"])], want[t], "%s: gold and reputation" % t)
	eq(int(cat.titles()["citizen"]["requires"]["businesses"]), 1, "citizen: 1 business")
	eq(int(cat.titles()["patrician"]["requires"]["employees"]), 2, "patrician: 2 employees")
	eq(int(cat.titles()["baron"]["requires"]["businesses"]), 3, "baron: 3 businesses")
	eq(str(cat.titles()["noble"]["requires"]["event"]), "noble_event", "noble: a special event")
	var builds: Array = []
	for t: String in cat.title_ladder():
		builds.append(cat.titles()[t]["unlocks"]["max_buildings"])
	eq(builds, [1, 2, 4, 6, null], "own buildings by title (4.9)")
	var rp: Dictionary = cat.politics["reputation"]
	eq(rp["classes"], ["artisan", "patron", "scholar", "rogue"], "the 4 classes of 4.12.1")
	eq(int(rp["passive"]["per_business_with_staff"]), 1, "+1/day per business with staff (ap. A)")
	eq(int(cat.politics["ceremony"]["min_affinity"]), 30, "the approver's affinity (4.12.2)")


func test_map_has_a_town_hall() -> void:
	var th: Dictionary = cat.maps()["town_e"]["town_hall"]
	eq(th["footprint"], [6, 4], "the south block of the plaza")
	var rows: Array = cat.maps()["town_e"]["rows"]
	var svc: Array = th["service"]
	check(cat.tile_kind_of_char(str(rows[int(svc[1])])[int(svc[0])]) != "building", "the service tile is walkable")


func test_v8_save_migrates_to_v9() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/v8_town_microevents.json"))
	eq(int(raw["version"]), 8, "the fixture is v8")
	var rep_before := {}
	for f: String in raw["families"]:
		rep_before[f] = int(raw["families"][f].get("reputation", 0))
	var r := SaveFile.load_file("res://tests/data/saves/v8_town_microevents.json")
	check(r["ok"], "the v8 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	check(WorldState.VERSION >= 9, "v9 or later")
	eq(st.version, WorldState.VERSION, "migrated")
	for f: String in st.families:
		var fam: Dictionary = st.families[f]
		eq(str(fam["title"]), "common", "%s: the common title" % f)
		eq(fam["class_reputation"], {}, "%s: no class modifiers" % f)
		eq(fam["reputation_log"], [], "%s: empty log" % f)
		eq(fam["reputation_caps"], {}, "%s: no caps counted" % f)
		eq(int(fam["reputation"]), int(rep_before[f]), "%s: the reputation it had" % f)
	var sim := Sim.new(st, cat)
	sim.run_minutes(60)
	check(true, "a migrated game runs")


func test_round_trip_with_titles_and_reputation() -> void:
	var st: WorldState = NewGame.from_scenario("title_ready", 1)["state"]
	var sim := Sim.new(st, cat)
	Reputation.change(sim, FAM, 3, "contract_done")
	st.families[FAM]["title"] = "citizen"
	var text := JSON.stringify(st.to_dict(), "\t", true, true)
	var back: WorldState = SaveFile.from_text(text)["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same state after save and load")
	eq(str(back.families[FAM]["title"]), "citizen", "the title")
	eq(int(back.families[FAM]["class_reputation"]["artisan"]), int(st.families[FAM]["class_reputation"]["artisan"]),
		"the class modifier")
	eq((back.families[FAM]["reputation_log"] as Array).size(), (st.families[FAM]["reputation_log"] as Array).size(),
		"the log")


func test_new_game_families_have_titles() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	check(r["ok"], "new game")
	var st: WorldState = r["state"]
	for f: String in st.families:
		if not TownLife.is_household(st, f):  # H10: the households get their titles from the procedural government
			eq(str(st.families[f]["title"]), "common", "%s starts common" % f)
		eq(st.families[f]["class_reputation"], {}, "%s: no class modifiers" % f)
	eq(int(st.families[FAM]["reputation"]), 0, "the protagonist starts at 0 (4.16)")


func test_title_ready_scenario() -> void:
	var sim := Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)
	var s := Titles.status(sim, HERO)
	eq(str(s["current"]), "common", "common")
	eq(str(s["next"]), "citizen", "next: citizen")
	check(bool(s["at_town_hall"]), "Hugo at the town hall")
	eq(str(s["reason"]), "", "he can ask now")
	eq(sim.state.loans, {}, "no loan")
	eq(Reputation.of(sim.state, FAM), 60, "reputation 60")
	eq(Titles.employees(sim, FAM), 1, "one employee")
	eq(Titles.businesses(sim, FAM), 1, "the forge")
