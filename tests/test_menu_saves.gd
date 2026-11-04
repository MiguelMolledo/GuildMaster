extends "res://tests/test_case.gd"
## The load / save screens (docs/ui/02_menu_inicial.md §3): the light header of a save (SaveFile.peek), the slots
## (SaveSlots), a slot saved and loaded with the same state, broken files listed with their reason, and the screen.

const GameScript := preload("res://game/autoload/game.gd")

var cat := Catalog.load_from()


func _dir() -> String:
	var d := "user://test_menu_saves_%d" % randi()
	DirAccess.make_dir_recursive_absolute(d)
	SaveSlots.dir = d
	return d


func _cleanup(d: String) -> void:
	for f: String in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d)
	SaveSlots.dir = "user://saves"


func _started() -> WorldState:
	return NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed", "name": "Hugo", "family_name": "Herrero"}, 7)["state"]


func _game(state: WorldState) -> Node:
	var g: Node = GameScript.new()
	g.start(state, cat)
	return g


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_peek_reads_the_header_without_building_the_state() -> void:
	var d := _dir()
	var st := _started()
	eq(SaveFile.save(st, d.path_join("slot_1.json")), OK, "saved")
	var r := SaveFile.peek(d.path_join("slot_1.json"))
	check(bool(r["ok"]), "readable")
	var h: Dictionary = r["header"]
	eq(str(h["family_name"]), "Herrero", "the family")
	eq(str(h["head_name"]), "Hugo", "the head")
	eq(str(h["profession"]), "blacksmith", "the trade")
	eq(str(h["title"]), "common", "the title")
	eq(int(h["gold"]), 30, "the family purse")
	eq(int(h["debt"]), int(cat.difficulty_levels("normal")["start_debt"]), "what is owed")
	eq(int(h["minute"]), int(st.clock["minute"]), "when in the game")
	eq(int(h["version"]), WorldState.VERSION, "the version")
	_cleanup(d)


func test_peek_migrates_old_saves_and_reports_broken_ones() -> void:
	var old := SaveFile.peek("res://tests/data/saves/v3_town_e_start.json")
	check(bool(old["ok"]), "a v3 save migrates in memory")
	var d := _dir()
	_write(d.path_join("slot_1.json"), "")
	_write(d.path_join("slot_2.json"), "{\"version\": 12, \"clock\": {\"minu")
	_write(d.path_join("slot_3.json"), JSON.stringify({"version": WorldState.VERSION + 1}))
	eq(str(SaveFile.peek(d.path_join("slot_1.json"))["error"]), "empty", "empty")
	eq(str(SaveFile.peek(d.path_join("slot_2.json"))["error"]), "bad_json", "cut")
	eq(str(SaveFile.peek(d.path_join("slot_3.json"))["error"]), "newer_version", "newer")
	eq(str(SaveFile.peek(d.path_join("nothing.json"))["error"]), "missing", "missing")
	var entries := SaveSlots.list(true)
	eq(entries.size(), 4, "the autosave and three slots")
	check(not bool(entries[0]["exists"]), "no autosave yet")
	for i: int in [1, 2, 3]:
		check(bool(entries[i]["exists"]) and not bool(entries[i]["ok"]), "slot %d listed as broken" % i)
	check(SaveSlots.most_recent().is_empty(), "nothing to continue")
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	eq(MenuKit.broken_label("newer_version"), "No se puede leer: es de una versión más nueva del juego.", "says why")
	TranslationServer.set_locale(before)
	_cleanup(d)


func test_save_and_load_a_slot_keeps_the_state() -> void:
	var d := _dir()
	var g := _game(_started())
	for i: int in 30:
		g.advance(0.5, false)
	check(g.unsaved(), "played and not saved")
	eq(g.save_slot("slot_2"), OK, "saved in slot 2")
	check(not g.unsaved(), "nothing unsaved after saving")
	var want := SaveFile.canonical(g.sim.state.to_dict())
	var h: Dictionary = SaveSlots.entry("slot_2")["header"]
	eq(int(h["minute"]), int(g.sim.state.clock["minute"]), "the header says when")
	var g2 := _game(NewGame.from_scenario("town_e_start")["state"])
	var r: Dictionary = g2.load_slot("slot_2")
	check(bool(r["ok"]), "loaded")
	eq(SaveFile.canonical(g2.sim.state.to_dict()), want, "the same state")
	check(not g2.unsaved(), "a loaded game is saved")
	g2.advance(1.0, false)
	check(g2.unsaved(), "and unsaved once it runs")
	eq(str(SaveSlots.most_recent()["slot"]), "slot_2", "Continue loads it")
	eq(SaveSlots.delete(SaveSlots.AUTOSAVE), ERR_INVALID_PARAMETER, "the autosave is not deleted from the menu")
	eq(SaveSlots.delete("slot_2"), OK, "a slot is")
	check(not SaveSlots.entry("slot_2")["exists"], "gone")
	g.free()
	g2.free()
	_cleanup(d)


func test_load_screen_lists_rows_and_reasons() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var d := _dir()
	SaveFile.save(_started(), SaveSlots.path_of("slot_1"))
	_write(SaveSlots.path_of("slot_3"), JSON.stringify({"version": WorldState.VERSION + 1}))
	var s: SaveScreen = (load("res://game/ui/save_screen.tscn") as PackedScene).instantiate()
	s.time_config = cat.time
	var loads: Array = []
	s.load_requested.connect(func(slot: String) -> void: loads.append(slot))
	s.open_mode("load")
	check(s.visible, "shown")
	for slot: String in ["auto", "slot_1", "slot_2", "slot_3"]:
		check(s.row(slot) != null, "a row for %s" % slot)
	var auto_del := s.row("auto").find_child("Delete", true, false) as Button
	check(auto_del.disabled, "the autosave cannot be deleted")
	var r1 := s.row("slot_1")
	check(not (r1.find_child("Load", true, false) as Button).disabled, "slot 1 loads")
	var who := (r1.find_child("Who", true, false) as Label).text
	check(who.contains("Hugo") and who.contains("herrero") and who.contains("Día 1"), "who and when: %s" % who)
	check((r1.find_child("How", true, false) as Label).text.contains("30 de oro"), "how it goes")
	var r3 := s.row("slot_3")
	check((r3.find_child("Load", true, false) as Button).disabled, "a broken slot does not load")
	check(not (r3.find_child("Delete", true, false) as Button).disabled, "but can be deleted")
	check((r3.find_child("Broken", true, false) as Label).text.contains("versión más nueva"), "and says why")
	check((s.row("slot_2").find_child("Load", true, false) as Button).disabled, "an empty slot does not load")
	(r1.find_child("Load", true, false) as Button).pressed.emit()
	eq(loads, ["slot_1"], "Load asks the app")
	(r3.find_child("Delete", true, false) as Button).pressed.emit()
	var confirm := s.get_node("%Confirm") as ConfirmDialog
	check(confirm.visible, "deleting asks first")
	confirm.button("delete").pressed.emit()
	check(not SaveSlots.entry("slot_3")["exists"], "deleted")
	s.free()
	_cleanup(d)
	TranslationServer.set_locale(before)


func test_save_screen_asks_before_overwriting() -> void:
	var d := _dir()
	SaveFile.save(_started(), SaveSlots.path_of("slot_1"))
	var s: SaveScreen = (load("res://game/ui/save_screen.tscn") as PackedScene).instantiate()
	s.time_config = cat.time
	var saves: Array = []
	s.save_requested.connect(func(slot: String) -> void: saves.append(slot))
	s.open_mode("save")
	check(s.row("auto") == null, "no autosave row when saving")
	(s.row("slot_2").find_child("Save", true, false) as Button).pressed.emit()
	eq(saves, ["slot_2"], "an empty slot saves at once")
	(s.row("slot_1").find_child("Save", true, false) as Button).pressed.emit()
	eq(saves.size(), 1, "a slot with a game asks first")
	var confirm := s.get_node("%Confirm") as ConfirmDialog
	check(confirm.visible, "the confirmation")
	check(confirm.button("cancel") != null and confirm.button("overwrite") != null, "Cancel and Overwrite")
	confirm.button("cancel").pressed.emit()
	eq(saves.size(), 1, "cancelled")
	(s.row("slot_1").find_child("Save", true, false) as Button).pressed.emit()
	confirm.button("overwrite").pressed.emit()
	eq(saves, ["slot_2", "slot_1"], "overwritten when confirmed")
	s.free()
	_cleanup(d)
