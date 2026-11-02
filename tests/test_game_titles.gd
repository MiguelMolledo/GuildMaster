extends "res://tests/test_case.gd"
## H9 view (docs/contratos/h9_titulos.md), windowless: the town hall as a service of the map and its building visual
## (no filler houses on its tiles), the town hall panel (requirements met / pending, the button gives request_title,
## disabled with the reason), the ceremony card and the Reputation tab of the book.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func test_town_hall_is_a_service_of_the_map() -> void:
	var sim := _sim()
	var th := {}
	for s: Dictionary in SimQuery.map_services(sim.state, cat):
		if str(s["kind"]) == "town_hall":
			th = s
	check(not th.is_empty(), "the town hall is a service")
	eq((th["tiles"] as Array).size(), 24, "6×4 tiles")
	eq(th["service"], Vector2i(20, 25), "asked for on its service tile")
	check(VisualPaths.has_scene("buildings", "town_hall"), "its scene exists")
	var v: Node2D = VisualPaths.instantiate("buildings", "town_hall")
	check(v.get_node_or_null("Feet") != null and v.get_node_or_null("Top") != null, "Feet and Top")
	check(v.get_node_or_null("Sprite") != null, "the Guild Renew sprite")
	v.free()


func test_world_view_draws_the_town_hall() -> void:
	var v: WorldView = _scene("res://game/world/world_view.tscn")
	v.setup(NewGame.from_scenario("title_ready", 1)["state"], cat)
	var hall := v.prop_at(Vector2i(20, 26))
	check(hall != null and hall.name == "town_hall_visual", "the town hall stands on its sign tile")
	check(v.service_sign_of("town_hall") != null, "with its sign")
	for t: Vector2i in [Vector2i(17, 26), Vector2i(22, 29)]:
		var p := v.prop_at(t)
		check(p == null or p == hall, "no filler house on %s" % t)
	eq(str(v.pick_service(v.service_screen("town_hall")).get("kind", "")), "town_hall", "a click on it finds it")
	v.free()


func test_panel_requirements_and_order() -> void:
	var sim := _sim()
	var p: TownHallPanel = _scene("res://game/ui/town_hall_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO)
	var list := p.get_node("%ReqList") as VBoxContainer
	eq(list.get_child_count(), 3, "citizen: reputation, businesses, gold")
	check((p.get_node("%NextLabel") as Label).text.contains("100"), "next: citizen, 100 gold")
	var ask := p.get_node("%AskButton") as Button
	check(not ask.disabled, "he can ask")
	ask.pressed.emit()
	eq(got, [{"type": "request_title", "actor": HERO}], "the order")
	check(sim.step(got).all(func(e: Dictionary) -> bool: return str(e["type"]) != "order_refused"), "granted")
	p.refresh(true)
	eq(list.get_child_count(), 3, "patrician: reputation, employees, gold")
	var emp := list.get_node_or_null("employees") as Label
	check(emp != null and emp.text.contains("1 / 2"), "employees 1 / 2 pending")
	check(ask.disabled, "disabled")
	eq(ask.tooltip_text, SimQuery.reason_text("title_needs_reputation"), "the first missing requirement as the reason")
	sim.state.characters[HERO]["position"] = [20, 21]
	p._process(0.0)
	check(not p.visible, "it closes when he leaves")
	p.free()


func test_title_card() -> void:
	var sim := _sim()
	var c: TitleCard = _scene("res://game/ui/title_card.tscn")
	c.show_for(sim, {"type": "title_granted", "family": FAM, "actor": HERO, "title": "citizen", "from": "common"})
	check(c.visible, "shown")
	check((c.get_node("%Text") as Label).text.contains(str(sim.state.characters[HERO]["name"])), "who received it")
	eq((c.get_node("%TitleName") as Label).text, SimQuery.title_name("citizen").to_upper(), "the title")
	check((c.get_node("%Unlocks") as Label).text != "", "what it opens")
	c._process(100.0)
	check(not c.visible, "it closes by itself")
	c.free()


func test_reputation_tab() -> void:
	var sim := _sim()
	var p: LedgerPanel = _scene("res://game/ui/ledger_panel.tscn")
	p.open_for(sim, FAM, HERO, "reputation")
	eq(p.tab, "reputation", "the tab")
	var g := p.row_of("rep_global")
	check(g != null and (g.get_node("Value") as Label).text == "60", "global 60")
	for c: String in ["artisan", "patron", "scholar", "rogue"]:
		check(p.row_of("rep_" + c) != null, "a row per class (%s)" % c)
	check(p.row_of("req_reputation") != null, "the next title's requirements")
	p.free()
