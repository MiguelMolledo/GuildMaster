extends "res://tests/test_case.gd"
## Posada · the tavern's panel refreshes in place (verifica 2026-11-05): every 5 game minutes it rebuilt its rows and
## the keyboard lost the focus. Now the rows are updated on the same nodes when their shape is the same, and when it
## changes the focused control (by its place) and the scroll are kept.

const HERO: String = "chr_0001"
const TABLE: Array = ["tavern_inn_ambience_1", "tavern_inn_ambience_2", "tavern_inn_ambience_3"]

var cat := Catalog.load_from()


func _setup() -> Dictionary:
	var sim := Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], cat)
	var t := ""
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Inn.is_inn(sim, b):
			t = b
	var panel: InnPanel = (load("res://game/inn/inn_panel.tscn") as PackedScene).instantiate()
	panel.order_sink = func(o: Dictionary) -> void: sim.step([o])
	panel.setup(sim, t, HERO)
	return {"sim": sim, "t": t, "panel": panel}


func _body(panel: InnPanel) -> VBoxContainer:
	return panel.get_node("%Body") as VBoxContainer


func test_a_refresh_keeps_the_rows_and_updates_their_text() -> void:
	var r := _setup()
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var panel: InnPanel = r["panel"]
	panel.show_tab("menu")
	var row := _body(panel).get_node("Dish_ale") as HBoxContainer
	check(row != null, "the ale's row")
	var check_box := row.get_child(0)
	var mult := row.get_child(4) as Label
	var before := panel.in_place_updates
	var builds := panel.rebuilds
	for i: int in 5:
		sim.step([])
	panel.refresh()
	eq(panel.in_place_updates, before + 1, "updated in place")
	eq(panel.rebuilds, builds, "not rebuilt")
	check(is_instance_valid(check_box) and check_box.get_parent() == row, "the same check box")
	sim.step([{"type": "inn_set_price", "actor": HERO, "building": t, "dish": "ale", "mult": 1.5}])
	panel.refresh()
	check(is_instance_valid(mult) and mult.text.contains("1"), "the same label")
	eq(mult.text, "×" + SimQuery._num(Inn.price_mult(sim, t, "ale")), "with the new price")
	panel.free()


func test_a_new_shape_rebuilds_and_another_tab_too() -> void:
	var r := _setup()
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var panel: InnPanel = r["panel"]
	panel.show_tab("rooms")
	var builds := panel.rebuilds
	panel.refresh()
	eq(panel.rebuilds, builds, "same beds: in place")
	(Inn.ensure(sim, t)["beds"] as Array)[0]["state"] = "dirty"
	panel.refresh()
	eq(panel.rebuilds, builds + 1, "a dirty bed adds its button: rebuilt")
	panel.show_tab("turn")
	eq(panel.rebuilds, builds + 2, "another tab: rebuilt")
	panel.free()


func test_the_focus_survives_a_rebuild() -> void:
	var r := _setup()
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var panel: InnPanel = r["panel"]
	(sim.state.buildings[t]["upgrades"] as Array).append_array(TABLE)
	Inn.ensure(sim, t)["license_until"] = 40
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	for i: int in int(w[0]) + 5 - int(sim.state.clock["minute"]):
		sim.step([])
	panel.open()
	panel.show_tab("games")
	var buttons: Array = _body(panel).get_children().filter(func(c: Node) -> bool: return c is Button)
	check(buttons.size() >= 3, "the three games")
	var b := buttons[1] as Button
	b.focus_mode = Control.FOCUS_ALL
	panel.focus_probe = b   # out of a tree (the tests run before the main loop): the focused control
	var text := b.text
	InnGames.make_offer(sim, t, Inn.state_of(sim, t))  # the offer adds its rows: a new shape
	var builds := panel.rebuilds
	panel.refresh()
	eq(panel.rebuilds, builds + 1, "rebuilt")
	var again := panel.focus_target
	check(again != null and again is Button and (again as Button).text == text, "the focus goes to the same game's button")
	check(again != null and again.get_parent() == _body(panel), "in the panel")
	check(again != null and again.focus_mode == Control.FOCUS_ALL, "able to take it")
	panel.focus_probe = again
	panel.focus_target = null
	for i: int in 5:
		sim.step([])
	panel.refresh()
	check(panel.focus_target == null and is_instance_valid(again) and again.get_parent() == _body(panel),
		"an in-place refresh keeps the same node (nothing to give back)")
	panel.free()
