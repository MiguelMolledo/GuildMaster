extends "res://tests/test_case.gd"
## Saved games (GDD 05 §5.8): round trip, migrations and broken files that never break the game.

const DIR := "user://test_saves"

var cat := Catalog.load_from()


func _busy_state() -> WorldState:
	var st := NewGame.fresh(cat, 42)
	var chr := Ids.next(st, "chr")
	var bld := Ids.next(st, "bld")
	st.characters[chr] = {"id": chr, "name": "Hugo", "gold": 50, "inventory": Inventory.create("weight", 30.0)}
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
	eq(typeof(back.characters["chr_0001"]["gold"]), TYPE_INT, "gold is int")
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
