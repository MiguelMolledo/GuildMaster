extends "res://tests/test_case.gd"
## Upgrade tree (docs/ui/mecanicas/mejoras.md §10): the 24 names whole and not forced to capitals; Second anvil with 65
## gold, 2 ingots and 3 wood shows the tick on the gold and the wood, the warning on the ingots and «Missing: 3 …»
## by the disabled button; hovering Commercial reputation lights Stone facade; Build always asks and says when the
## works end; during works the other available cells say «one at a time»; each status has its own icon (it reads in
## grey); «what you will see» lights the new station in gold. Orders through the sim.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func _panel(sim: Sim) -> UpgradePanel:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = func(o: Dictionary) -> void: _orders.append(o)
	v.setup(sim, BLD, HUGO, true)
	v.show_upgrades(true)
	_orders.clear()
	return v.upgrade_panel()


func _free(p: UpgradePanel) -> void:
	p.get_parent().get_parent().get_parent().get_parent().free()


func _es() -> String:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return before


func _texts(n: Node) -> String:
	var out: PackedStringArray = []
	if n is Label:
		out.append((n as Label).text)
	for c: Node in n.get_children():
		out.append(_texts(c))
	return " ".join(out)


func _second_anvil_short(sim: Sim) -> void:
	var fam := SimQuery.building_family(sim.state, BLD)
	sim.state.families[fam]["gold"] = 65
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	inv["stacks"] = []
	Inventory.add(inv, cat, "iron_ingot", 0, 2)
	Inventory.add(inv, cat, "wood", 0, 3)


func test_the_24_names_whole_without_capitals() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim)
	var n := 0
	for br: Variant in cat.upgrade_rules.get("branches", []):
		for id: String in cat.upgrade_tree("forge"):
			if str(cat.upgrade(id).get("branch", "")) != str(br):
				continue
			var name_l := p.cell_of(id).find_child("Name", true, false) as Label
			eq(name_l.text, SimQuery.upgrade_name(cat, id), "%s: its name as written" % id)
			n += 1
	eq(n, 24, "24 cells")
	_free(p)


func test_second_anvil_says_what_is_missing_item_by_item() -> void:
	var before := _es()
	var sim := _sim("town_e_start")
	_second_anvil_short(sim)
	var p := _panel(sim)
	p.select("forge_capacity_1")
	eq(p.status_of("forge_capacity_1"), "missing_materials", "short of ingots")
	var cost := p.get_node("%DetailLines").get_node("Cost") as Control
	var txt := _texts(cost)
	check(txt.contains("50 de oro (tienes 65)"), "the gold with what you have (%s)" % txt)
	check(txt.contains("5 %s (hay 2)" % SimQuery.item_name(cat, "iron_ingot")), "the ingots: 5 (there are 2)")
	check(txt.contains("3 %s (hay 3)" % SimQuery.item_name(cat, "wood")), "the wood: 3 (there are 3)")
	var icons: Array = []
	for c: Node in cost.get_children():
		if c is TextureRect and (c as TextureRect).texture != null:
			icons.append((c as TextureRect).texture.resource_path.get_file())
	eq(icons.count("icon_completed.png"), 2, "a tick on the gold and the wood (%s)" % [icons])
	eq(icons.count("icon_warning.png"), 1, "a warning on the ingots")
	var miss := p.get_node("%Missing") as Label
	check(miss.visible and miss.text.contains("Falta: 3 %s" % SimQuery.item_name(cat, "iron_ingot")), "the reason (%s)" % miss.text)
	check((p.get_node("%BuyButton") as Button).disabled, "by the disabled button")
	TranslationServer.set_locale(before)
	_free(p)


func test_hovering_commercial_reputation_lights_stone_facade() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim)
	p.hover("forge_commerce_3")
	check(p.prereq_marked("forge_facade_1"), "Stone facade with the gold edge")
	check(p.prereq_marked("forge_commerce_2"), "and its own branch's step")
	check(not p.prereq_marked("forge_production_1"), "nothing else")
	check(p.cell_of("forge_commerce_3").get_node_or_null("Row/Cross") != null, "the cross-branch key on its cell")
	p.hover("")
	_free(p)


func test_build_always_asks_and_says_when_it_ends() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim)
	var spec := p.buy_spec("forge_production_1")
	check(bool(spec["irreversible"]) and bool(spec["seal"]), "irreversible, with the seal")
	check(str(spec["body"]).contains(SimQuery.minute_label(p.end_minute("forge_production_1")).to_lower()),
		"when the works end (%s)" % spec["body"])
	_free(p)


func test_during_works_the_rest_say_one_at_a_time() -> void:
	var before := _es()
	var sim := _sim("forge_upgrade_works")
	var p := _panel(sim)
	var busy := ""
	for id: String in cat.upgrade_tree("forge"):
		if p.status_of(id) == "busy" and p.waits_for_works(id):
			busy = id
			break
	check(busy != "", "some cell waits for the works")
	var price := p.cell_of(busy).find_child("Price", true, false) as Label
	eq(price.text, "una a la vez", "it says one at a time")
	var locked := ""
	for id: String in cat.upgrade_tree("forge"):
		if p.status_of(id) == "busy" and not p.waits_for_works(id):
			locked = id
			break
	var icon := p.cell_of(locked).find_child("Status", true, false) as TextureRect
	check(icon != null and icon.texture.resource_path.ends_with("icon_locked.png"), "one that also lacks a prerequisite keeps its lock")
	check(p.get_node("%WorksBar").visible, "the works strip with its bar")
	TranslationServer.set_locale(before)
	_free(p)


func test_each_status_has_its_own_icon() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim)
	var icons := {}
	for st: String in ["owned", "in_works", "available", "needs_upgrade", "title_too_low"]:
		icons[p.status_icon(st)] = true
	eq(icons.size(), 5, "five icons for five states (not only the colour)")
	eq(p.status_icon("missing_materials"), "", "short of something: the dot")
	_free(p)


func test_what_you_will_see_lights_the_new_anvil() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim)
	p.select("forge_capacity_1")
	var pv := p.get_node("%Preview") as UpgradePreview
	eq(pv.side(), "interior", "drawn inside")
	check(pv.lit() != null and str(pv.lit().name) == "anvil_2", "the second anvil lit")
	check(pv.lit().visible, "and shown")
	check(p.cell_of("forge_capacity_1").find_child("Thumb", true, false) != null, "the cell's thumbnail")
	p.select("forge_facade_1")
	eq(pv.side(), "exterior", "a facade is drawn outside")
	_free(p)
