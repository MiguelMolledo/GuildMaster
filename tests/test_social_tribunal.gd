extends "res://tests/test_case.gd"
## docs/ui/mecanicas/tribunal.md: the preparation shows accused against accuser with their portraits, the witnesses
## with theirs, the proofs as «?» with their hint (decision b), why an action is off written; bribing and threatening
## a witness ask first with the charge they risk and the odds as a band, convincing does not; the hearing tells «lo
## que va pasando» from the scale's parts; accusing from the sheet asks with what a false one costs.

const HERO := "chr_0001"
const RIVAL := "chr_0002"

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


func _trial(sim: Sim) -> String:
	return str((sim.state.trials[0] as Dictionary)["id"])


func test_preparation_parties_witnesses_and_risks() -> void:
	var before := _es()
	var sim := _sim("accused_player")
	var p: TrialPanel = _scene("res://game/ui/trial_panel.tscn")
	p.order_sink = _sink
	p.open_for(sim, HERO, _trial(sim))
	eq(p.get_node("%AccusedSlot").get_child_count(), 1, "the accused's portrait")
	check((p.get_node("%AccusedText") as Label).text.contains("acusado"), "named as the accused")
	check((p.get_node("%VsLabel") as Label).text == "contra", "against")
	var box := p.get_node("%Witnesses")
	for row: Node in box.get_children():
		check(row.get_child(0).get_child_count() == 1 and row.get_child(0).get_child(0) is PortraitFrame, "%s with its portrait" % row.name)
	var t := Tribunal.trial(sim.state, _trial(sim))
	var w := str((t["witnesses"] as Array)[0]["character"])
	_orders = []
	p.request({"type": "witness_action", "actor": HERO, "trial": _trial(sim), "witness": w, "kind": "bribe"}, false)
	eq(_orders.size(), 0, "bribing asks first")
	var body := str(SocialKit.pending(p).get("body", ""))
	check(body.contains("Si te denuncia") and body.contains("de oro") and (body.contains("fácil") or body.contains("dudoso") \
		or body.contains("difícil")), "with the gold, the charge and the odds (%s)" % body)
	SocialKit.cancel_pending(p)
	p.request({"type": "witness_action", "actor": HERO, "trial": _trial(sim), "witness": w, "kind": "threaten"}, false)
	check(str(SocialKit.pending(p).get("body", "")).contains("pasa en contra"), "threatening too")
	SocialKit.cancel_pending(p)
	_orders = []
	p.request({"type": "witness_action", "actor": HERO, "trial": _trial(sim), "witness": w, "kind": "convince"}, false)
	eq(_orders.size(), 1, "convincing goes at once")
	sim.state.families["fam_0001"]["gold"] = 0
	p.refresh(true)
	var why := box.get_child(0).get_node_or_null("Why") as Label
	check(why != null and why.text.contains("te faltan"), "no gold: what is missing, written")
	p.free()
	TranslationServer.set_locale(before)


func test_hearing_tells_what_happens() -> void:
	var before := _es()
	var sim := _sim("trial_hearing")
	sim.run_minutes(10)   # the preparation ends: the hearing
	eq(str(Tribunal.trial(sim.state, _trial(sim))["status"]), "hearing", "in the hearing")
	var p: TrialPanel = _scene("res://game/ui/trial_panel.tscn")
	p.open_for(sim, HERO, _trial(sim))
	check((p.get_node("%Steps") as Control).visible, "«Lo que va pasando» in the hearing")
	var steps := p.get_node("%Steps").get_children()
	check(steps.size() >= 3, "the plea, the proofs, the witnesses and the defense (%d)" % steps.size())
	check((steps[0].get_node("Text") as Label).text.contains("Alegato de la acusación"), "the accusation first")
	check(not (p.get_node("%AccusationLabel") as Label).text.contains("?"), "the proofs show at the hearing")
	p.free()
	TranslationServer.set_locale(before)


func test_accusing_from_the_sheet_says_the_risk() -> void:
	var before := _es()
	var sim := _sim("rival_accused")
	var n: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	n.order_sink = _sink
	n.setup(sim, HERO, RIVAL)
	var b := n.get_node("%Actions").get_node("AccuseRow").get_node("Accuse") as Button
	_orders = []
	b.pressed.emit()
	check(str(SocialKit.pending(n).get("body", "")).contains("Si es falsa y pierdes"), "what a false accusation costs")
	check(SocialKit.accept_pending(n), "confirmed")
	check(Orders.apply(sim, _orders[0])["ok"], "the sim takes it")
	n.free()
	TranslationServer.set_locale(before)
