extends "res://tests/test_case.gd"
## H11 base (docs/contratos/h11_tribunal.md): the court's tables (GDD 4.12.5 figures), the v11 save and its migration
## from v10 (attitudes, banished_until, trials, justice), the round trip with a trial, a new game's attitudes and the
## trial scenarios.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL_FAM: String = "fam_0002"

var cat := Catalog.load_from()


func test_justice_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	var j: Dictionary = cat.justice
	eq(j["severities"], ["light", "medium", "grave", "maximum"], "the 4 severities of 4.12.5")
	eq(j["sentences"]["light"]["fine"], [10, 50], "light: a fine of 10-50")
	eq(str(j["sentences"]["medium"]["kind"]), "confiscation", "medium: confiscation")
	eq(str(j["sentences"]["grave"]["kind"]), "office_loss", "grave: the office and a title")
	eq(str(j["sentences"]["maximum"]["kind"]), "banishment", "maximum: banishment")
	eq(int(j["banishment_days"]), Clock.days_per_year(cat.time), "banishment: 1 year")
	eq([int(j["sentences"]["light"]["reputation"]), int(j["sentences"]["medium"]["reputation"]),
		int(j["sentences"]["grave"]["reputation"])], [-10, -30, -50], "4.12.1: fine -10, confiscation -30, office -50")
	eq(j["trial"]["witnesses"], [3, 5], "3-5 witnesses")
	eq(int(j["trial"]["prep_days"]), int(cat.time["days_per_season"]), "preparation: 1 season")
	eq([int(j["trial"]["rhetoric"]), int(j["trial"]["witness"]), int(j["trial"]["proof"])], [2, 15, 20], "ap. A")
	near(float(j["trial"]["reputation"]), 0.1, 0.0001, "reputation × 0,1")
	eq(int(j["judge"]["manipulate_honesty"]), -20, "4.12.5: manipulating -20 honesty")
	eq(int(j["accuse"]["false_reputation"]), -50, "4.12.1: false accusation -50")
	for p: String in ["arrest", "investigate", "preside_trial", "pardon"]:
		var off := "constable" if p in ["arrest", "investigate"] else "judge"
		var ready: Variant = null
		for pw: Dictionary in cat.offices()[off]["powers"]:
			if str(pw["id"]) == p:
				ready = pw["ready"]
		eq(ready, true, "%s is ready in H11" % p)


func test_v10_save_migrates_to_v11() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/v10_office_campaign.json"))
	eq(int(raw["version"]), 10, "the fixture is v10")
	var r := SaveFile.load_file("res://tests/data/saves/v10_office_campaign.json")
	check(r["ok"], "the v10 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	check(WorldState.VERSION >= 11, "v11 or later")
	eq(st.version, WorldState.VERSION, "migrated")
	for f: String in st.families:
		eq(st.families[f]["attitudes"], {"honesty": 0, "generosity": 0, "diplomacy": 0}, "%s: attitudes 0" % f)
	for c: String in st.characters:
		eq(int(st.characters[c]["banished_until"]), -1, "%s: not banished" % c)
	eq(st.trials, [], "no trials")
	eq(st.justice, {"facts": []}, "no facts")
	Sim.new(st, cat).run_minutes(60)
	check(true, "a migrated game runs")


func test_round_trip_with_a_trial() -> void:
	var st: WorldState = NewGame.from_scenario("accused_player", 1)["state"]
	var sim := Sim.new(st, cat)
	Tribunal.add_fact(sim, "bribe_scandal", RIVAL_FAM, "chr_0002")
	st.characters["chr_0003"]["banished_until"] = 20
	var text := JSON.stringify(st.to_dict(), "\t", true, true)
	var back: WorldState = SaveFile.from_text(text)["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same state after save and load")
	eq((back.trials[0]["witnesses"] as Array).size(), (st.trials[0]["witnesses"] as Array).size(), "the witnesses")
	check(Tribunal.is_banished(back, "chr_0003"), "the banishment")


func test_new_game_attitudes() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"]
	eq(st.families[FAM]["attitudes"], {"honesty": 0, "generosity": 0, "diplomacy": 0}, "the player starts at 0")
	eq(int(st.families[RIVAL_FAM]["attitudes"]["honesty"]), 20, "the rival from its profile (04c, provisional)")
	eq(st.trials, [], "no trials")


func test_trial_scenarios() -> void:
	var sim := Sim.new(NewGame.from_scenario("accused_player", 1)["state"], cat)
	var t := Tribunal.of_family(sim, FAM)
	check(not t.is_empty(), "Hugo is on trial")
	eq(str(t["charge"]), "tax_evasion", "tax evasion (double accounting)")
	eq(str(t["status"]), "preparation", "in preparation")
	var disp: Array = (t["witnesses"] as Array).map(func(w: Dictionary) -> String: return str(w["disposition"]))
	check("against" in disp and "favor" in disp, "witnesses for and against (%s)" % [disp])
	sim = Sim.new(NewGame.from_scenario("trial_hearing", 1)["state"], cat)
	sim.run_minutes(6)
	eq(str(Tribunal.of_family(sim, FAM)["status"]), "hearing", "the hearing starts")
	sim = Sim.new(NewGame.from_scenario("rival_accused", 1)["state"], cat)
	eq(str(Tribunal.accuse_options(sim, HERO, "chr_0002")["reason"]), "", "Hugo can accuse the rival")
	check(NewGame.from_scenario("founder_old", 1)["ok"], "founder_old loads")
