extends "res://tests/test_case.gd"
## docs/ui/mecanicas/titulos_y_reputacion.md, its acceptance criteria: in title_ready the town hall shows the ladder and,
## without the mouse, what is missing and how much; with a Mayor below the affinity, «no te aprueba» with who and the
## affinity; from far away the panel is consulted, asking says one must go and «Ir allí» walks; asking asks first
## with the gold left; the Reputation tab groups the changes of the same reason and day; the ceremony lights the
## new step of the ladder.

const FAM := "fam_0001"
const HERO := "chr_0001"

var _orders: Array = []


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], Catalog.load_from())


func _sink(o: Dictionary) -> void:
	_orders.append(o.duplicate(true))


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _es() -> String:
	var b := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return b


func _at_hall(sim: Sim) -> void:
	var svc := Titles.service(sim)
	var ch: Dictionary = sim.state.characters[HERO]
	ch["location"] = ""
	ch["path"] = []
	ch["position"] = [int(svc[0]), int(svc[1])]


func test_ladder_and_what_is_missing() -> void:
	var before := _es()
	var sim := _sim("title_ready")
	_at_hall(sim)
	sim.state.families[FAM]["reputation"] = 10
	var p: TownHallPanel = _scene("res://game/ui/town_hall_panel.tscn")
	p.order_sink = _sink
	p.open_for(sim, HERO)
	var ladder := p.get_node("%Ladder")
	eq(ladder.get_child_count(), sim.catalog.title_ladder().size(), "the five steps")
	var cur := Titles.current(sim, FAM)
	check(bool((ladder.get_node(cur) as PanelContainer).get_meta("current", false)), "the current one marked")
	var rep := p.get_node("%ReqList").get_node("reputation")
	check(rep.get_node("Bar") is ProgressBar, "the requirement as a bar")
	eq((rep.get_node("Value") as Label).theme_type_variation, &"ReasonLabel", "missing: red")
	check((p.get_node("%AskButton") as Button).disabled, "Ask off")
	var why := (p.get_node("%Reason") as Label).text
	check((p.get_node("%Reason") as Label).visible and why.contains("Falta reputación") and why.contains("10/"), "what and how much (%s)" % why)
	p.free()
	TranslationServer.set_locale(before)


func test_the_mayor_does_not_approve() -> void:
	var before := _es()
	var sim := _sim("office_campaign")
	_at_hall(sim)
	var npc := ""
	for id: String in Population.townsfolk(sim.state):
		if Kin.is_adult(sim, id) and npc == "":
			npc = id
	(sim.state.offices["mayor"]["seats"][0] as Dictionary)["holder"] = npc
	var p: TownHallPanel = _scene("res://game/ui/town_hall_panel.tscn")
	p.open_for(sim, HERO)
	var a := Titles.approver(sim, HERO)
	eq(str(a.get("character", "")), npc, "the Mayor approves")
	check(not bool(a["ok"]), "with not enough affinity")
	check((p.get_node("%ApproverName") as Label).text.contains(str(sim.state.characters[npc]["name"])), "who")
	check((p.get_node("%ApproverAffinity") as Label).text.contains("/ %d" % int(a["need"])), "the affinity it needs")
	p.free()
	TranslationServer.set_locale(before)


func test_consult_from_far_and_go_there() -> void:
	var before := _es()
	var sim := _sim("title_ready")
	sim.state.characters[HERO]["location"] = ""
	sim.state.characters[HERO]["position"] = [2, 19]
	var p: TownHallPanel = _scene("res://game/ui/town_hall_panel.tscn")
	p.order_sink = _sink
	p.open_consult(sim, HERO)
	p._process(0.0)
	check(p.visible, "consult mode does not close when far")
	check((p.get_node("%AskButton") as Button).disabled, "asking needs to be there")
	check((p.get_node("%GoButton") as Button).visible, "«Ir allí»")
	_orders = []
	(p.get_node("%GoButton") as Button).pressed.emit()
	eq(str(_orders.back()["type"]), "move_to", "walks")
	eq(_orders.back()["tile"], Titles.service(sim), "to the town hall")
	check(Orders.apply(sim, _orders.back())["ok"], "the sim takes it")
	p.free()
	TranslationServer.set_locale(before)


func test_asking_asks_with_the_gold_left() -> void:
	var before := _es()
	var sim := _sim("title_ready")
	_at_hall(sim)
	var p: TownHallPanel = _scene("res://game/ui/town_hall_panel.tscn")
	p.order_sink = _sink
	p.open_for(sim, HERO)
	check(not (p.get_node("%AskButton") as Button).disabled, "ready to ask")
	_orders = []
	(p.get_node("%AskButton") as Button).pressed.emit()
	var st := Titles.status(sim, HERO)
	var left := Money.gold(sim.state, FAM) - int(st["cost"])
	check(str(SocialKit.pending(p).get("body", "")).contains("Te quedan %d" % left), "the gold left")
	eq(_orders.size(), 0, "no order before the answer")
	check(SocialKit.accept_pending(p), "confirmed")
	check(Orders.apply(sim, _orders[0])["ok"], "granted")
	p.free()
	TranslationServer.set_locale(before)


func test_reputation_changes_grouped() -> void:
	var sim := _sim("title_ready")
	var now := int(sim.state.clock["minute"])
	var log: Array = sim.state.families[FAM]["reputation_log"]
	log.clear()
	for i: int in 3:
		log.append({"minute": now - 10 * i, "amount": 1, "reason": "fair_trade"})
	log.append({"minute": now, "amount": 2, "reason": "contract_done"})
	var groups := ReputationView.grouped(log)
	eq(groups.size(), 2, "two rows: same reason and day together")
	var fair: Array = groups.filter(func(g: Dictionary) -> bool: return str(g["reason"]) == "fair_trade")
	eq(int(fair[0]["count"]), 3, "×3")
	eq(int(fair[0]["amount"]), 3, "+3")
	var p: LedgerPanel = _scene("res://game/ui/ledger_panel.tscn")
	p.open_for(sim, FAM, HERO, "reputation")
	check(p.row_of("log_0") != null and p.row_of("log_2") == null, "two log rows in the tab")
	p.free()


func test_ceremony_lights_the_new_step() -> void:
	var sim := _sim("title_ready")
	var c: TitleCard = _scene("res://game/ui/title_card.tscn")
	c.show_for(sim, {"type": "title_granted", "family": FAM, "actor": HERO, "title": "citizen", "from": "common"})
	var step := c.get_node("%Ladder").get_node("citizen") as Label
	eq(step.theme_type_variation, &"GoldLabel", "the new step lit")
	eq((c.get_node("%Ladder").get_node("common") as Label).theme_type_variation, &"DimLabel", "the others not")
	check((c.get_node("%Initial") as Label).text != "", "the seal with the initial")
	c.free()
