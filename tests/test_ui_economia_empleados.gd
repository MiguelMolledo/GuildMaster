extends "res://tests/test_case.gd"
## Staff panel (docs/ui/mecanicas/empleados.md §10): «Can:» locks the armour for Craft 5; the ranks' table comes from
## data/employees.json; Hire asks a second click with the daily wage; without a place the reason names the upgrade;
## the loyalty bar has its cuts and the band's effect written; a pending promotion first; firing someone loyal warns of
## the reputation; with many candidates the list scrolls and says how many are below. Orders through the sim.

const BLD := "bld_0001"
const HUGO := "chr_0001"
const JOAN := "chr_0007"
const AGNES := "chr_0008"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func _panel(sim: Sim, tab: String) -> StaffPanel:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = func(o: Dictionary) -> void: _orders.append(o)
	v.setup(sim, BLD, HUGO, false)
	v.show_staff(true, tab)
	_orders.clear()
	return v.staff_panel()


func _free(p: StaffPanel) -> void:
	p.get_parent().get_parent().get_parent().get_parent().free()


func _es() -> String:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return before


func test_craft_five_sees_the_armour_locked() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim, "hire")
	var who := str(SimQuery.candidates(sim, HUGO, BLD)[0]["character"])
	sim.state.characters[who]["stats"]["craft"] = 5
	p.refresh(true)
	var can := p.row_of(who).find_child("Can", true, false) as Control
	var armor := can.get_node("Can_forge_armor") as Control
	var sword := can.get_node("Can_forge_sword") as Control
	check(bool(armor.get_meta("locked")) and armor.get_node_or_null("Lock") != null, "the armour (6) with its lock")
	check(not bool(sword.get_meta("locked")), "the sword (4) without")
	_free(p)


func test_the_ranks_table_comes_from_the_data() -> void:
	var sim := _sim("town_e_start")
	cat.employees["ranks"]["journeyman"]["wage"] = 23
	var p := _panel(sim, "hire")
	var row := p.get_node("%RankRows").get_node("Rank_journeyman") as Control
	var txt := ""
	for c: Node in row.get_children():
		if c is Label:
			txt += (c as Label).text + " "
	check(txt.contains("23"), "the journeyman's wage from data/employees.json (%s)" % txt)
	eq(p.get_node("%RankRows").get_child_count(), (cat.employees["rank_order"] as Array).size(), "one row per rank")
	check(p.get_node("%RankRows").get_node("Rank_master").get_node_or_null("Gate") != null,
		"the master's row names the upgrade it needs")
	cat.employees["ranks"]["journeyman"]["wage"] = 20
	_free(p)


func test_hire_asks_a_second_click_with_the_daily_wage() -> void:
	var before := _es()
	var sim := _sim("town_e_start")
	var p := _panel(sim, "hire")
	var c: Dictionary = SimQuery.candidates(sim, HUGO, BLD)[0]
	var who := str(c["character"])
	(p.row_of(who).find_child("Hire", true, false) as Button).pressed.emit()
	eq(_orders.size(), 0, "the first click gives nothing")
	var b := p.row_of(who).find_child("Hire", true, false) as Button
	check(b.text.contains("¿Contratar?") and b.text.contains("%d/día" % int(c["wage"])), "it says the wage (%s)" % b.text)
	b.pressed.emit()
	eq(str(_orders.back()["type"]) if not _orders.is_empty() else "", "hire", "the second click hires")
	var ev := sim.step(_orders.duplicate(true))
	eq(ev.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused").size(), 0, "the sim takes it")
	TranslationServer.set_locale(before)
	_free(p)


func test_without_a_place_the_reason_names_the_upgrade() -> void:
	var sim := _sim("two_employees")
	var p := _panel(sim, "hire")
	var c: Dictionary = SimQuery.candidates(sim, HUGO, BLD)[0]
	eq(str(c["status"]), "no_slot", "no place")
	var why := p.row_of(str(c["character"])).find_child("Reason", true, false) as Label
	var up := SimQuery.upgrade_name(cat, str(p.slot_upgrades()[0]))
	check(why.text.contains(up) and why.text.contains("2/2"), "names %s (%s)" % [up, why.text])
	check((p.get_node("%Strip") as Control).visible and (p.get_node("%StripLabel") as Label).text.contains(up),
		"and the strip on top too")
	_free(p)


func test_loyalty_bar_has_its_cuts_and_the_effect_written() -> void:
	var before := _es()
	var sim := _sim("two_employees")
	sim.state.characters[JOAN]["job"]["loyalty"] = 30
	var p := _panel(sim, "staff")
	eq(p.band_cuts(), [20, 40, 70], "marks at 20, 40 and 70")
	var row := p.row_of(JOAN)
	check(row.find_child("LoyaltyBar", true, false) != null, "the bar")
	var eff := row.find_child("Effect", true, false) as Label
	check(eff.text.contains("Puede irse sin avisar (5 %/día)"), "the band's effect without tooltip (%s)" % eff.text)
	TranslationServer.set_locale(before)
	_free(p)


func test_a_pending_promotion_goes_first() -> void:
	var sim := _sim("two_employees")
	sim.state.characters[JOAN]["job"]["promotion_offered"] = true
	var p := _panel(sim, "staff")
	var list := p.get_node("%List") as Node
	eq(str(list.get_child(0).name), JOAN, "the promotion on top")
	eq((list.get_child(0) as PanelContainer).theme_type_variation, &"SelectedRow", "with the gold edge")
	_free(p)


func test_firing_someone_loyal_warns_of_the_reputation() -> void:
	var before := _es()
	var sim := _sim("two_employees")
	sim.state.characters[JOAN]["job"]["loyalty"] = 75
	var p := _panel(sim, "staff")
	var spec := p.fire_spec(JOAN)
	check(str(spec["body"]).contains("reputación -2"), "says reputation −2 (%s)" % spec["body"])
	sim.state.characters[JOAN]["job"]["loyalty"] = 50
	check(not str(p.fire_spec(JOAN)["body"]).contains("reputación"), "not when they were not loyal")
	TranslationServer.set_locale(before)
	_free(p)


func test_six_candidates_scroll_and_say_how_many_are_below() -> void:
	var sim := _sim("town_e_start")
	var p := _panel(sim, "hire")
	check(SimQuery.candidates(sim, HUGO, BLD).size() >= 6, "six or more candidates")
	var sc := p.get_node("%Scroll") as ScrollContainer
	eq(sc.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "the list scrolls")
	eq(sc.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "and nothing is cut sideways")
	_free(p)
