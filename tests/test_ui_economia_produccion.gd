extends "res://tests/test_case.gd"
## The production panel (docs/ui/mecanicas/produccion.md §10): three tabs, the stalled strip in Now and Queue with the
## «!» on the bar, Loop and Pause in words, «Espada ×5» in two clicks, the Recipes tab's duration for a journeyman as the
## sim's, the station rows and «da para N». Orders through the sim.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String = "two_employees") -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func _panel(sim: Sim) -> Array:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = func(o: Dictionary) -> void: _orders.append(o.duplicate(true))
	v.setup(sim, BLD, "", true)
	v.show_production(true)
	_orders.clear()
	return [v, v.production_panel()]


func test_three_tabs_and_the_stations() -> void:
	var sim := _sim()
	var vp := _panel(sim)
	var p: ProductionPanel = vp[1]
	eq(p.tab, "now", "Now by default")
	check((p.get_node("%NowPage") as Control).visible and not (p.get_node("%QueuePage") as Control).visible, "Now shows")
	check((p.get_node("%Stations") as Node).get_child_count() >= 2, "a row per station")
	p.show_tab("queue")
	check((p.get_node("%QueuePage") as Control).visible, "Queue")
	p.show_tab("recipes")
	check((p.get_node("%RecipesPage") as Control).visible, "Recipes")
	check((p.get_node("%RecipesList").get_node("Chain") as Label).text.contains("→"), "the chain of the building")
	(vp[0] as Node).free()


func test_two_clicks_for_five_swords_and_words_on_the_toggles() -> void:
	var sim := _sim()
	var vp := _panel(sim)
	var p: ProductionPanel = vp[1]
	p.show_tab("queue")
	var sword := (p.get_node("%RecipeGrid") as Node).get_node("forge_sword") as Button
	sword.pressed.emit()                                   # click 1: the sword in the grid
	(p.get_node("%Add5") as Button).pressed.emit()          # click 2: +5
	eq(_orders.size(), 1, "one order")
	eq(str(_orders[0]["type"]), "queue_add", "queue_add")
	eq(str(_orders[0]["recipe"]), "forge_sword", "the sword")
	eq(int(_orders[0]["qty"]), 5, "×5")
	check((p.get_node("%LoopButton") as Button).text.contains(":"), "Loop says its state («Bucle: no»)")
	check((p.get_node("%PauseButton") as Button).text.contains(":"), "Pause says its state")
	(vp[0] as Node).free()


func test_stalled_strip_and_badge() -> void:
	var sim := _sim()
	sim.state.buildings[BLD]["inventory"] = {"stacks": []}
	for i: int in 300:
		sim.step()
		if str(SimQuery.queue_view(sim, BLD)["stalled"]) != "":
			break
	var stalled := str(SimQuery.queue_view(sim, BLD)["stalled"])
	check(stalled != "", "the empty storage stalls the queue (%s)" % stalled)
	var vp := _panel(sim)
	var p: ProductionPanel = vp[1]
	for t: String in ["now", "queue"]:
		p.show_tab(t)
		check((p.get_node("%Stalled") as Control).visible, "the red strip in %s" % t)
		check((p.get_node("%StalledLabel") as Label).text.contains(SimQuery.reason_text(stalled)), "with the reason in %s" % t)
	(vp[0] as InteriorView).refresh_status()
	check(bool((vp[0] as InteriorView).badges()["production"]), "and «!» on the bar's Production")
	(vp[0] as Node).free()


func test_recipes_tab_durations_are_the_sims() -> void:
	var sim := _sim()
	var vp := _panel(sim)
	var p: ProductionPanel = vp[1]
	p.show_tab("recipes")
	var rec: Dictionary = cat.recipes()["forge_sword"]
	var times := (p.get_node("%RecipesList").get_node("Recipe_forge_sword").get_node("Times") as Label).text
	var journeyman := SimQuery.duration_label(Production.rank_cycle_minutes(sim, BLD, rec, "normal", "journeyman"))
	check(times.contains(journeyman), "a journeyman's duration (%s in %s)" % [journeyman, times])
	var staff := Staff.employees_of(sim.state, BLD)
	for c: Variant in staff:
		if str(sim.state.characters[str(c)].get("rank", "")) == "journeyman":
			eq(Production.employee_cycle_minutes(sim, str(c), rec, "normal"),
				Production.rank_cycle_minutes(sim, BLD, rec, "normal", "journeyman"), "the same as the real journeyman's")
	(vp[0] as Node).free()


func test_can_make_counts_the_storage() -> void:
	var sim := _sim()
	sim.state.buildings[BLD]["inventory"]["stacks"] = []
	Inventory.add(sim.state.buildings[BLD]["inventory"], cat, "iron", 0, 5)
	eq(WorkQueue.can_make(sim, BLD, "forge_ingot"), 2, "5 iron gives for 2 ingots (2 each)")
	eq(WorkQueue.can_make(sim, BLD, "forge_sword"), 0, "no ingots: no sword")
