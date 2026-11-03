extends "res://tests/test_case.gd"
## The forge from inside (docs/ui/mecanicas/forja_interior.md §10): the station menu in one box (2 clicks to work), each
## recipe that cannot be made says why without the mouse, the quality bar and the duration follow the mode, the master
## touch window is on the station's bar from the first minute, the bar's badges, the numbered marks of the active pause
## and the routine as a strip of the day (wider nights in winter). Orders through the sim (Orders.apply).

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)


func _inside(sim: Sim) -> void:
	sim.step([{"type": "enter_building", "actor": HUGO, "building": BLD}])
	for i: int in 600:
		if str(sim.state.characters[HUGO]["location"]) == BLD:
			break
		sim.step()


func _interior(sim: Sim) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, HUGO, false)
	return v


func _set_stock(sim: Sim, item: String, n: int) -> void:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	inv["stacks"] = (inv["stacks"] as Array).filter(func(st: Dictionary) -> bool: return str(st["item"]) != item)
	if n > 0:
		Inventory.add(inv, cat, item, 0, n)


func _buttons(menu: StationMenu) -> Dictionary:
	var out := {}
	for b: Button in menu.recipe_buttons():
		out[str(b.name)] = b
	return out


func test_two_clicks_to_work_and_the_reasons_in_sight() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_inside(sim)
	sim.state.characters[HUGO]["stats"]["craft"] = 7
	_set_stock(sim, "iron_ingot", 2)
	_set_stock(sim, "coal", 1)
	var v := _interior(sim)
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.open_station_menu("anvil", Vector2(300, 120))   # click 1: right click on the anvil
	var menu := v.station_menu()
	var by := _buttons(menu)
	check(by.has("forge_sword") and not (by["forge_sword"] as Button).disabled, "the sword at once, no second step")
	check((by["forge_armor"] as Button).disabled, "armor: disabled")
	eq(menu.reason_of("forge_armor"), "Falta: 1 × lingote de hierro", "with its reason written under it")
	eq(menu.reason_of("forge_sword"), "", "no reason when it can be made")
	(by["forge_sword"] as Button).pressed.emit()   # click 2
	eq(got.size(), 1, "one order")
	eq(str(got[0]["type"]), "work_at", "work_at")
	eq(str(got[0]["mode"]), "normal", "in the default mode")
	var ev := sim.step(got)
	check(ev.all(func(e: Dictionary) -> bool: return str(e["type"]) != "order_refused"), "the sim takes it")
	TranslationServer.set_locale(before)
	v.free()


func test_locked_recipes_say_what_they_need() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_inside(sim)
	sim.state.characters[HUGO]["stats"]["craft"] = 3
	var v := _interior(sim)
	v.open_station_menu("anvil", Vector2(300, 120))
	eq(v.station_menu().reason_of("forge_sword"), "Artesanía 4 (tienes 3)", "the craft needed and the one you have")
	sim.state.characters[HUGO]["stats"]["craft"] = 10
	v.open_station_menu("anvil", Vector2(300, 120))
	var steel := ""
	for opt: Dictionary in v.station_menu().recipe_options():
		if str(opt["reason"]) == "needs_upgrade":
			steel = str(opt["recipe"])
	if steel == "":
		v.open_station_menu("furnace", Vector2(300, 120))
		for opt: Dictionary in v.station_menu().recipe_options():
			if str(opt["reason"]) == "needs_upgrade":
				steel = str(opt["recipe"])
	check(steel != "", "a recipe that needs an upgrade")
	check(v.station_menu().reason_of(steel).begins_with("Necesita "), "«Necesita <mejora> → Mejoras»")
	TranslationServer.set_locale(before)
	v.free()


func test_quality_and_duration_follow_the_mode() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_inside(sim)
	sim.state.characters[HUGO]["stats"]["craft"] = 7
	sim.state.characters[HUGO]["equipment"]["tool"] = null
	_set_stock(sim, "iron_ingot", 2)
	_set_stock(sim, "coal", 1)
	var v := _interior(sim)
	v.open_station_menu("anvil", Vector2(300, 120))
	var menu := v.station_menu()
	var dur := func() -> String:
		var row := menu.get_node("%RecipeList").get_node("Row_forge_sword")
		return (row.get_child(0).get_node("Duration") as Label).text
	menu.choose_mode("normal")
	eq(menu.shown_chances(), [20, 50, 30], "normal: read with Artesanía 7")
	eq(dur.call(), "3 h 54", "normal: 3 h 54")
	menu.choose_mode("fast")
	eq(menu.shown_chances(), [50, 40, 10], "fast: read with Artesanía 4")
	eq(dur.call(), "2 h 44", "fast: 2 h 44")
	menu.choose_mode("careful")
	eq(dur.call(), "5 h 51", "careful: 5 h 51")
	check((menu.get_node("%ModeLine") as Label).text.contains("toque de maestro"), "careful adds the master touch")
	v.open_station_menu("anvil", Vector2(300, 120))
	eq(v.station_menu().mode, "careful", "the mode is remembered for Hugo at the anvil")
	TranslationServer.set_locale(before)
	v.free()


func test_management_mode_shows_the_job_and_production() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, "", true)
	v.open_station_menu("anvil", Vector2(300, 120))
	var menu := v.station_menu()
	check((menu.get_node("%Hint") as Label).text.contains("Entra con un personaje"), "go in with someone to work")
	check((menu.get_node("%ProductionButton") as Button).visible, "a Production button")
	(menu.get_node("%ProductionButton") as Button).pressed.emit()
	check(v.production_panel().visible, "it opens the production panel")
	TranslationServer.set_locale(before)
	v.free()


func test_touch_window_on_the_bar_from_the_first_minute() -> void:
	var sim := _sim()
	_inside(sim)
	_set_stock(sim, "iron_ingot", 2)
	_set_stock(sim, "coal", 1)
	sim.step([{"type": "work_at", "actor": HUGO, "building": BLD, "zone": "anvil", "recipe": "forge_sword", "mode": "careful"}])
	var job := SimQuery.job_view(sim, BLD, "anvil")
	check(float(job.get("window_from", -1.0)) > 0.0 and float(job["window_to"]) > float(job["window_from"]),
		"job_view gives the window as fractions (%s..%s)" % [job.get("window_from"), job.get("window_to")])
	var v := _interior(sim)
	v.sync()
	var sv := v.station_view("anvil")
	check(sv.window_from > 0.0 and not sv.window_open, "the station knows the window before it opens")
	eq(sv.status(), "working", "the mark says it works")
	v.free()


func test_bar_badges_and_pause_marks() -> void:
	var sim := _sim()
	_inside(sim)
	var v := _interior(sim)
	sim.state.buildings[BLD]["queue"] = {"entries": [], "loop": false, "paused": false, "stalled": "missing_inputs"}
	v.refresh_status()
	check(bool(v.badges()["production"]), "the queue stalled: «!» on Production")
	var badge := (v.get_node("%ProductionButton") as Button).get_node_or_null("Badge") as Control
	check(badge != null and badge.visible, "drawn on the button")
	sim.state.characters[HUGO]["order_queue"] = [{"type": "go_to_station", "actor": HUGO, "zone": "furnace"},
		{"type": "work_at", "actor": HUGO, "building": BLD, "zone": "anvil", "recipe": "forge_sword", "mode": "normal"}]
	eq(v.queued_targets(), ["furnace", "anvil"], "the waiting orders' stations, in order")
	v.sync()
	eq(v.station_view("furnace").marks, [1], "① over the furnace")
	eq(v.station_view("anvil").marks, [2], "② over the anvil")
	v.free()


func test_routine_strip_follows_the_season() -> void:
	var sim := Sim.new(NewGame.from_scenario("family_routines")["state"], cat)
	var who := str(Kin.group(sim.state, SimQuery.player_family(sim.state))[0])
	var ed: RoutineEditor = (load("res://game/ui/routine_editor.tscn") as PackedScene).instantiate()
	ed.setup(sim, who, who)
	var strip := ed.get_node("%Strip") as HBoxContainer
	eq(strip.get_child_count(), 4, "one block per phase")
	var night := func(season: String) -> float:
		var t: Dictionary = cat.time
		var st: Dictionary = t["phase_starts"][season]
		return float(int(st["dawn"]) + 1440 - int(st["night"])) / 1440.0
	var shares := ed.phase_shares()
	check(absf(float(shares["night"]) - float(night.call(str(sim.now()["season"])))) < 0.001, "the night's share of this season")
	check(night.call("winter") > night.call("summer"), "a winter night is wider than a summer one")
	eq((strip.get_child(0) as Button).size_flags_stretch_ratio, float(shares["dawn"]), "blocks as wide as their phase")
	(strip.get_node("Block_night") as Button).pressed.emit()
	eq(ed.picked, "night", "a click picks the night")
	check((ed.get_node("%Rows").get_node("Action_night") as Control).visible, "its detail shows")
	check(not (ed.get_node("%Rows").get_node("Action_day") as Control).visible, "the others hide")
	ed.free()
