extends "res://tests/test_case.gd"
## Saved games (GDD 05 §5.8): round trip, migrations and broken files that never break the game.

const DIR := "user://test_saves"

var cat := Catalog.load_from()


func _busy_state() -> WorldState:
	var st := NewGame.fresh(cat, 42)
	var chr := Ids.next(st, "chr")
	var bld := Ids.next(st, "bld")
	st.families["fam_0001"] = {"id": "fam_0001", "name": "Herrero", "gold": 50, "reputation": 0}
	st.characters[chr] = {"id": chr, "name": "Hugo", "family": "fam_0001", "inventory": Inventory.create("weight", 30.0)}
	st.buildings[bld] = {"id": bld, "type": "forge", "owner": chr, "inventory": Inventory.create("stacks", 10)}
	Inventory.add(st.buildings[bld]["inventory"], cat, "iron", Inventory.NORMAL, 120)
	Inventory.add(st.buildings[bld]["inventory"], cat, "sword", Inventory.GOOD, 2)
	st.market["demand"]["sword"] = 0.85
	Chronicle.add(st, "building_bought", {"building": bld, "by": chr})
	st.rng.randi()  # the rng has moved: its state must survive
	return st


func test_round_trip_keeps_everything() -> void:
	var st := _busy_state()
	var path := DIR.path_join("round.json")
	eq(SaveFile.save(st, path), OK, "saves")
	var r := SaveFile.load_file(path)
	check(r["ok"], "loads")
	var back: WorldState = r["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(back.rng.randi(), st.rng.randi(), "rng continues the same")
	eq(Ids.next(back, "chr"), "chr_0002", "ids are not reused")
	check(not FileAccess.file_exists(path + ".tmp"), "no temporary left")


func test_loaded_numbers_are_ints() -> void:
	var st := _busy_state()
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(typeof(back.clock["minute"]), TYPE_INT, "minute is int")
	eq(typeof(back.families["fam_0001"]["gold"]), TYPE_INT, "gold is int")
	eq(typeof(back.market["demand"]["sword"]), TYPE_FLOAT, "demand stays float")


func test_broken_files_are_refused() -> void:
	eq(SaveFile.load_file(DIR.path_join("nope.json"))["error"], "missing", "missing")
	eq(SaveFile.from_text("")["error"], "empty", "empty")
	eq(SaveFile.from_text("{\"version\": 1, \"clock\": ")["error"], "bad_json", "cut")
	eq(SaveFile.from_text("[1, 2]")["error"], "not_a_save", "not a dict")
	eq(SaveFile.from_text("{\"hello\": 1}")["error"], "not_a_save", "no version")
	eq(SaveFile.from_text("{\"version\": %d}" % (WorldState.VERSION + 1))["error"], "newer_version", "newer")


func test_every_scenario_loads() -> void:
	var ids := NewGame.scenario_ids()
	check(ids.size() > 0, "there are scenarios")
	for id: String in ids:
		var r := NewGame.from_scenario(id)
		check(r["ok"], "scenario %s loads (%s)" % [id, r.get("error", "")])


# --- H3: guardado v4 -------------------------------------------------------------------------------------------------

func test_v3_save_migrates_gold_to_the_family_purse() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v3_town_e_start.json")
	check(r["ok"], "the v3 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated to the current version")
	eq(Money.gold(st, "fam_0001"), 100 + 20 + 20, "Hugo 100 + Elena 20 + Tomás 20")
	eq(Money.gold(st, "fam_0002"), 20 + 20, "Marta 20 + Pere 20")
	for id: String in st.characters:
		check(not st.characters[id].has("gold"), "%s has no gold of its own" % id)
	eq(int(st.families["fam_0001"]["reputation"]), 0, "reputation 0")
	eq(str(st.families["fam_0001"]["ai_profile"]), "", "no ai profile")
	eq(int(st.buildings["bld_0001"]["upkeep_debt"]), 0, "no unpaid upkeep")
	eq(int(st.buildings["bld_0001"]["upkeep_unpaid_since"]), -1, "never unpaid")
	eq(st.ledger, {"entries": [], "summaries": {}}, "empty ledger")
	eq(st.contracts, {"board": [], "accepted": [], "cooldowns": {}, "relations": {}}, "empty contracts")
	check(st.notices.is_empty() and st.loans.is_empty() and st.deliveries.is_empty() and st.objectives.is_empty(),
		"no notices, loans, errands or objectives")
	eq(st.difficulty, "normal", "normal difficulty")
	eq(st.ending, {}, "the game goes on")
	var sim := Sim.new(st, cat)
	sim.run_minutes(10)  # a migrated game runs
	eq(Money.gold(sim.state, "fam_0001"), 140, "nothing changes the gold by itself")


func test_round_trip_with_h3_state() -> void:
	var st := _busy_state()
	var sim := Sim.new(st, cat)
	check(Money.change(sim, "fam_0001", -20, Money.PURCHASES, "buy", "bld_0001", "chr_0001"), "pays")
	Notices.add(sim, "fam_0001", Notices.URGENT, "notice.loan_due", {"days": 2, "amount": 200}, "bld_0001")
	st.loans["lon_0001"] = {"id": "lon_0001", "family": "fam_0001", "lender": "moneylender", "principal": 200,
		"outstanding": 150, "due_minute": 11520, "extended": false, "state": "active"}
	st.contracts["board"].append({"id": "ctr_0001", "client": "carpenter", "item": "hammer", "qty": 2,
		"min_quality": 0, "deadline_days": 2, "pay": 69, "posted": 300, "script": "carpenter_hammers"})
	st.contracts["cooldowns"]["farmer"] = 16
	st.contracts["relations"]["fam_0001|carpenter"] = 5
	st.deliveries.append({"id": "dlv_0001", "family": "fam_0001", "actor": "chr_0001", "stall": "resources",
		"to": "bld_0001", "item": "iron", "quality": 0, "qty": 4, "arrive": 420})
	st.difficulty = "hard"
	st.objectives["fam_0001"] = {"chain": ["forge_sword"], "index": 0, "progress": [1, 0], "done": []}
	st.ending = {"kind": "ruin", "family": "fam_0001", "minute": 20000}
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(typeof(back.ledger["entries"][0]["amount"]), TYPE_INT, "amounts are int")
	eq(int(back.ledger["entries"][0]["amount"]), -20, "the entry survives")
	eq(back.difficulty, "hard", "difficulty survives")
	eq(int(back.loans["lon_0001"]["outstanding"]), 150, "the loan survives")
	eq(int(back.deliveries[0]["arrive"]), 420, "the errand on its way survives")
