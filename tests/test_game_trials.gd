extends "res://tests/test_case.gd"
## H11 view (docs/contratos/h11_tribunal.md), windowless: the trial panel in preparation (scale with hidden proofs,
## witnesses with Convince / Bribe / Threaten that walk first when far) and in the hearing (Question, Rest), the
## accusation and verdict card, «Accuse…» on the townsperson's sheet and the banished person hidden from the map.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func _sim(id: String) -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func test_panel_in_preparation() -> void:
	var sim := _sim("accused_player")
	var t := Tribunal.of_family(sim, FAM)
	var p: TrialPanel = _scene("res://game/ui/trial_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO, str(t["id"]))
	check((p.get_node("%AccusationLabel") as Label).text.contains("?"), "the accuser's proofs are hidden")
	var box := p.get_node("%Witnesses") as VBoxContainer
	eq(box.get_child_count(), (t["witnesses"] as Array).size(), "a row per witness")
	var against := ""
	for w: Dictionary in t["witnesses"]:
		if str(w["disposition"]) == "against":
			against = str(w["character"])
			break
	var conv := box.get_node("W_%s/Convince" % against) as Button
	check(not conv.disabled, "convince (far: walks first)")
	conv.pressed.emit()
	eq(str(got[got.size() - 1]["type"]), "witness_action", "the action queued last")
	check(bool(got[got.size() - 1].get("queued", false)) or got.size() == 1, "behind the walk")
	check(not (p.get_node("%RestButton") as Button).visible, "no resting before the hearing")
	p.free()


func test_panel_in_the_hearing() -> void:
	var sim := _sim("trial_hearing")
	sim.run_minutes(6)
	var t := Tribunal.of_family(sim, FAM)
	var p: TrialPanel = _scene("res://game/ui/trial_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO, str(t["id"]))
	check(not (p.get_node("%AccusationLabel") as Label).text.contains("?"), "the proofs show at the hearing")
	var crosses := 0
	for row: Node in (p.get_node("%Witnesses") as Node).get_children():
		if row.get_node_or_null("Cross") != null:
			crosses += 1
	eq(crosses, 2, "Question on the two witnesses against")
	var rest := p.get_node("%RestButton") as Button
	check(rest.visible and not rest.disabled, "rest the defense")
	rest.pressed.emit()
	eq(got[0], {"type": "trial_rest", "actor": HERO, "trial": str(t["id"])}, "trial_rest")
	check(not (p.get_node("%JudgeRow") as Control).visible, "Hugo is not the judge")
	p.free()


func test_cards() -> void:
	var sim := _sim("accused_player")
	var t := Tribunal.of_family(sim, FAM)
	var c: TrialCard = _scene("res://game/ui/trial_card.tscn")
	var asked: Array = []
	c.prepare_requested.connect(func(id: String) -> void: asked.append(id))
	c.show_accusation(sim, str(t["id"]))
	check((c.get_node("%Text") as Label).text.contains(SimQuery.t_("charge.tax_evasion")), "the charge")
	(c.get_node("%PrepareButton") as Button).pressed.emit()
	eq(asked, [str(t["id"])], "«Prepare the defense» opens the trial")
	Tribunal.rule(sim, t)
	c.show_verdict(sim, {"trial": str(t["id"])})
	eq((c.get_node("%Stamp") as Label).text, SimQuery.t_("ui.trial_card.guilty"), "GUILTY")
	check((c.get_node("%Detail") as Label).text.contains("4"), "four swords confiscated")
	c.free()


func test_accuse_on_the_sheet() -> void:
	var sim := _sim("rival_accused")
	var p: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.setup(sim, HERO, RIVAL)
	var row := (p.get_node("%Actions") as Node).get_node("AccuseRow")
	var b := row.get_node("Accuse") as Button
	check(not b.disabled, "he can accuse with the public fact")
	b.pressed.emit()
	eq(got.size(), 0, "accusing asks first")
	check(SocialKit.accept_pending(p), "confirmed")
	eq(str(got[0]["type"]), "accuse", "accuse")
	check(str(got[0].get("fact", "")) != "", "with the fact")
	p.free()


func test_banished_is_hidden() -> void:
	var st: WorldState = NewGame.from_scenario("accused_player", 1)["state"]
	var sim := Sim.new(st, cat)
	Tribunal.banish(sim, HERO, 8)
	var v: WorldView = _scene("res://game/world/world_view.tscn")
	v.setup(st, cat)
	v.sync(0.0)
	var views: Dictionary = v.get("_views")
	check(views.has(HERO), "Hugo has a view")
	check(not (views[HERO] as Node2D).visible, "the banished is not drawn")
	v.free()
