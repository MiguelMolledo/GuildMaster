extends "res://tests/test_case.gd"
## H8 view (GDD 4.10.5, 4.10.7, 4.10.8, 4.10.9, 4.17): the family tree lays out the founder, the spouse beside him and
## the children below, with portraits in the family's colours and each person's hair and skin (a child carries the
## hair or skin of a parent); its sheet gives designate_heir and school_choice; the routine editor gives the whole
## routine as set_schedule; the courtship panel talks at once in range and walks first when far; the ending screen
## breaks the score down. Windowless: the scenes are built by hand and the orders are caught by a sink.

const FAM := "fam_0001"
const HERO := "chr_0001"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _sink(o: Dictionary) -> void:
	_orders.append(o.duplicate(true))


func _texts(n: Node) -> String:
	var out: PackedStringArray = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		out.append(_texts(c))
	return " ".join(out)


func test_tree_layout_and_identity() -> void:
	var sim := _sim("founder_old")
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	var kids: Array = st.characters[HERO]["children"]
	var lay := FamilyTreePanel.layout(st, FAM)
	var nodes: Dictionary = lay["nodes"]
	eq(nodes.size(), 4, "founder, wife and two children")
	eq((nodes[HERO] as Vector2).y, 0.0, "founder at the top")
	eq((nodes[wife] as Vector2), (nodes[HERO] as Vector2) + Vector2(1, 0), "the wife beside him")
	for k: Variant in kids:
		eq((nodes[str(k)] as Vector2).y, 1.0, "children one row below")
	eq(lay["couples"], [[HERO, wife]], "one couple")
	var panel: FamilyTreePanel = (load("res://game/ui/family_tree_panel.tscn") as PackedScene).instantiate()
	panel.order_sink = _sink
	panel.setup(sim, FAM, HERO)
	var canvas := panel.get_node("%Canvas") as Control
	var son := str(kids[0])
	var node := canvas.get_node(son) as FamilyTreeNode
	check(node != null, "a node for the son")
	var frame := node.get_node("%Frame") as PortraitFrame
	var portrait := frame.get_node("%Holder").get_child(0) as Portrait
	var vis: Dictionary = st.characters[son]["visual"]
	eq(portrait.hair, Identity.hair_color(int(vis["hair"])), "his hair from the palette")
	eq(portrait.skin, Identity.skin_color(int(vis["skin"])), "his skin from the palette")
	eq(portrait.primary, ViewConfig.color(str(st.families[FAM]["colors"]["primary"])), "family colours")
	var pv: Array = [st.characters[HERO]["visual"], st.characters[wife]["visual"]]
	check(pv.any(func(v: Dictionary) -> bool: return int(v["hair"]) == int(vis["hair"])) \
		or pv.any(func(v: Dictionary) -> bool: return int(v["skin"]) == int(vis["skin"])), "hair or skin of a parent")
	check((frame.get_node("%Crown") as CanvasItem).visible, "the heir wears the crown")
	check(_texts(panel).contains(str(st.characters[son]["name"])), "names shown")
	# the sheet: designate the daughter, school choice when pending
	var daughter := str(kids[1])
	panel.pick(daughter)
	_orders.clear()
	(panel.get_node("%HeirButton") as Button).pressed.emit()
	eq(_orders.size(), 0, "designate heir asks first (familia.md §4)")
	check(SocialKit.accept_pending(panel), "confirmed")
	eq(_orders, [{"type": "designate_heir", "actor": HERO, "heir": daughter}], "designate_heir")
	st.characters[daughter]["life"]["school"] = "pending"
	panel.refresh(true)
	check((panel.get_node("%SchoolRow") as Control).visible, "school choice row")
	_orders.clear()
	(panel.get_node("%SchoolButton") as Button).pressed.emit()
	check(SocialKit.accept_pending(panel), "the school asks first")
	eq(str(_orders[0]["type"]), "school_choice", "school_choice")
	eq(str(_orders[0]["child"]), daughter, "for her")
	check((panel.get_node("%CloseDynasty") as Control).visible, "the voluntary close (D19 on)")
	panel.free()


func test_routine_editor_gives_set_schedule() -> void:
	var sim := _sim("family_routines")
	var son := str(Kin.group(sim.state, FAM)[1])
	var ed: RoutineEditor = (load("res://game/ui/routine_editor.tscn") as PackedScene).instantiate()
	ed.order_sink = _sink
	ed.setup(sim, son, son)
	check(ed.visible, "shown for a controlled person")
	var rows := ed.get_node("%Rows") as GridContainer
	eq(rows.get_child_count(), 16, "4 phases × (label, action, recipe, mode)")
	var night := rows.get_node("Action_night") as OptionButton
	eq(str(night.get_item_metadata(night.selected)), "rest", "night: rest")
	_orders.clear()
	var day := rows.get_node("Action_day") as OptionButton
	day.select(1)  # rest
	day.item_selected.emit(1)
	eq(_orders.size(), 1, "one order")
	eq(str(_orders[0]["type"]), "set_schedule", "set_schedule")
	eq(str(_orders[0]["schedule"]["day"]["action"]), "rest", "day changed to rest")
	eq(str(_orders[0]["schedule"]["night"]["action"]), "rest", "the rest kept")
	eq(Schedules.check_schedule(sim, FAM, _orders[0]["schedule"]), "", "a valid routine")
	_orders.clear()
	(ed.get_node("%ToggleButton") as Button).pressed.emit()
	eq(_orders[0]["schedule"], null, "turn off")
	ed.free()


func test_courtship_panel_talks_or_walks() -> void:
	var sim := _sim("courtship")
	var cp: CourtshipPanel = (load("res://game/ui/courtship_panel.tscn") as PackedScene).instantiate()
	cp.order_sink = _sink
	cp.setup(sim, HERO)
	var list := cp.get_node("%List") as VBoxContainer
	eq(list.get_child_count(), 8, "eight candidates")
	var first := list.get_child(0)
	var agnes := str(first.name)
	_orders.clear()
	(first.find_child("Talk", true, false) as Button).pressed.emit()
	eq(_orders, [{"type": "court_talk", "actor": HERO, "target": agnes}], "in range: talk at once")
	check((first.find_child("Propose", true, false) as Button).disabled, "propose needs 80")
	var far := ""
	for c: Dictionary in Courtship.candidates(sim, HERO):
		if str(c["status"]) == "too_far":
			far = str(c["character"])
			break
	_orders.clear()
	cp.act(far, {"type": "court_talk"})
	eq(_orders.size(), 2, "walk + talk")
	eq(str(_orders[0]["type"]), "move_to", "walks first")
	eq(_orders[1], {"type": "court_talk", "actor": HERO, "target": far, "queued": true}, "the talk waits behind")
	cp.free()


func test_ending_screen_breaks_the_score_down() -> void:
	var sim := _sim("founder_no_heir")
	sim.run_minutes(15)
	eq(str(sim.state.ending.get("kind", "")), "game_over", "game over")
	var es: EndingScreen = (load("res://game/ui/ending_screen.tscn") as PackedScene).instantiate()
	es.show_ending(sim.state, sim)
	var t := _texts(es)
	var total := int(Dynasty.score(sim, FAM)["total"])
	check(t.contains(str(total)), "the total (%d) in: %s" % [total, t])
	check(t.contains(TranslationServer.translate("score.wedding")), "the wedding line")
	check(t.contains(TranslationServer.translate("score.wealth_peak")), "the wealth line")
	eq(es.kind, "game_over", "kind")
	es.free()
