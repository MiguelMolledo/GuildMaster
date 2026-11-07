extends "res://tests/test_case.gd"
## H14 base (docs/contratos/h14_ia_familiar.md): the directives, needs, morale and trade tables, the v12 save and its
## migration from v11 (needs and ai of every character), the round trip, a new game's needs and the scenarios.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func test_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	var d: Dictionary = cat.family["directives"]
	eq(d["known"], ["work", "trade", "socialize", "leisure", "learn"], "the directives of GDD 4.10.6")
	eq(d["ready"]["learn"], "EA", "learn stays off (the GDD does not say how a stat grows)")
	for x: String in ["work", "trade", "socialize", "leisure"]:
		eq(d["ready"][x], true, "%s is ready" % x)
	eq(cat.family["needs"]["ids"], ["hunger", "rest", "social", "fun"], "the 4 needs of GDD 4.2.6")
	check(float(cat.family["morale"]["productivity"]["min_mult"]) < 1.0, "low morale slows the work down")


func test_v11_save_migrates_to_v12() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/saves/v11_accused_player.json"))
	eq(int(raw["version"]), 11, "the fixture is v11")
	var r := SaveFile.load_file("res://tests/data/saves/v11_accused_player.json")
	check(r["ok"], "the v11 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	check(WorldState.VERSION >= 12, "v12 or later")
	eq(st.version, WorldState.VERSION, "migrated")
	for c: String in st.characters:
		eq(st.characters[c]["needs"], {"hunger": 80, "rest": 80, "social": 80, "fun": 80}, "%s: needs at 80" % c)
		eq(st.characters[c]["ai"], {}, "%s: no AI memory" % c)
	Sim.new(st, cat).run_minutes(60)
	check(true, "a migrated game runs")


func test_round_trip_and_new_game() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"]
	eq(st.characters[HERO]["needs"], {"hunger": 100, "rest": 100, "social": 80, "fun": 80}, "a new game: needs.start (start_of: rested and fed, GDD 4.2.6)")
	var sim := Sim.new(st, cat)
	st.characters[HERO]["needs"]["fun"] = 12
	st.characters[HERO]["ai"] = {"doing": "trade", "why": "directive"}
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same state after save and load")
	check(sim != null, "sim")


func test_scenarios() -> void:
	var st: WorldState = NewGame.from_scenario("kin_trader", 1)["state"]
	var wife := str(st.characters[HERO]["spouse"])
	check(wife != "", "Hugo is married")
	eq(st.characters[wife]["directives"], ["trade", "work"], "Agnès trades first")
	eq(Inventory.count(st.buildings[FORGE]["inventory"], "iron"), 0, "no iron in the forge")
	st = NewGame.from_scenario("kin_tired", 1)["state"]
	check(int(st.characters[str(st.characters[HERO]["spouse"])]["needs"]["hunger"]) < 30, "a hungry spouse")
