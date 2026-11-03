extends "res://tests/test_case.gd"
## docs/ui/mecanicas/familia.md, its acceptance criteria: in founder_old the tree shows who is the head, the heir and
## who is in the group (with its key); in founder_no_heir the «Sin heredero» band; designate heir and the school ask
## first; the head's death brings the succession card with what is inherited and the regent, and the game is paused
## until Continue (decision (a)); a birth shows the life card with the baby. Windowless: orders caught by a sink.

const GameScript := preload("res://game/autoload/game.gd")
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


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _es() -> String:
	var b := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return b


func test_tree_shows_head_heir_and_group_keys() -> void:
	var before := _es()
	var sim := _sim("founder_old")
	var p: FamilyTreePanel = _scene("res://game/ui/family_tree_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, FAM, HERO)
	var canvas := p.get_node("%Canvas")
	var heir := Kin.heir(sim, FAM)
	check(heir != "", "founder_old has an heir")
	var heir_node := canvas.get_node(heir) as FamilyTreeNode
	check((heir_node.get_node("%Frame").get_node("%Crown") as CanvasItem).visible, "the heir wears the crown")
	var head_node := canvas.get_node(HERO) as FamilyTreeNode
	check(head_node.tooltip_text.contains("cabeza de familia"), "the head says so (%s)" % head_node.tooltip_text)
	check(head_node.tooltip_text.contains("riesgo de muerte este año"), "with the death risk as a band")
	var g := Kin.group(sim.state, FAM)
	for i: int in g.size():
		var n := canvas.get_node(str(g[i])) as FamilyTreeNode
		eq((n.get_node("%Frame").get_node("%Key") as Label).text, str(i + 1), "key %d on %s" % [i + 1, g[i]])
	check(not (p.get_node("%NoHeir") as Control).visible, "no «sin heredero» band")
	check((p.get_node("%Subtitle") as Label).text.contains("generación"), "generation in the header")
	var stats := p.get_node("%Stats")
	check(stats.get_node_or_null("Bar_craft") is ProgressBar, "the stats as bars")
	p.show_tab("dynasty")
	check((p.get_node("%DynastyPage") as Control).visible and not (p.get_node("%TreePage") as Control).visible, "Dinastía tab")
	check(p.get_node("%Goals").get_child_count() > 0, "the goals")
	p.free()
	TranslationServer.set_locale(before)


func test_no_heir_band() -> void:
	var before := _es()
	var sim := _sim("founder_no_heir")
	var p: FamilyTreePanel = _scene("res://game/ui/family_tree_panel.tscn")
	p.setup(sim, FAM, HERO)
	check((p.get_node("%NoHeir") as Control).visible, "the band")
	check((p.get_node("%NoHeirLabel") as Label).text.contains("Sin heredero"), "says so")
	p.free()
	TranslationServer.set_locale(before)


func test_designate_heir_asks_and_the_crown_moves() -> void:
	var sim := _sim("founder_old")
	var p: FamilyTreePanel = _scene("res://game/ui/family_tree_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, FAM, HERO)
	var heir := Kin.heir(sim, FAM)
	var other := ""
	for k: Variant in sim.state.characters[HERO]["children"]:
		if str(k) != heir:
			other = str(k)
	p.pick(heir)
	check((p.get_node("%HeirButton") as Button).disabled, "the heir: off")
	check((p.get_node("%HeirReason") as Label).visible, "with its reason")
	p.pick(other)
	_orders = []
	(p.get_node("%HeirButton") as Button).pressed.emit()
	eq(_orders.size(), 0, "asks first")
	check(str(SocialKit.pending(p).get("body", "")) != "", "saying who it replaces")
	check(SocialKit.accept_pending(p), "confirmed")
	check(Orders.apply(sim, _orders[0])["ok"], "the sim takes it")
	eq(Kin.heir(sim, FAM), other, "the new heir")
	p.refresh(true)
	check((p.get_node("%Canvas").get_node(other).get_node("%Frame").get_node("%Crown") as CanvasItem).visible, "the crown moved")
	p.free()


func test_succession_card_pauses_and_says_what_is_inherited() -> void:
	var before := _es()
	var sim := _sim("founder_old")
	var g: Node = GameScript.new()
	g.start(sim.state, cat)
	var heir := Kin.heir(g.sim, FAM)
	g.sim.events.clear()
	Lifecycle.die(g.sim, HERO, "old_age")
	var e := {}
	for x: Dictionary in g.sim.events:
		if str(x["type"]) == "inheritance":
			e = x
	check(not e.is_empty(), "the head died: inheritance")
	var card: SuccessionCard = _scene("res://game/ui/succession_card.tscn")
	card.game = g
	card.show_for(g.sim, e, g.sim.events)
	check(card.visible and g.paused, "shown, and the game paused (decision a)")
	eq(str(card.data["heir"]), heir, "the heir")
	check((card.get_node("%Inherits") as Label).text.contains("oro"), "the gold inherited")
	check((card.get_node("%ContinueButton") as Button).text.contains(str(g.sim.state.characters[heir]["name"])), "Continue with the heir")
	(card.get_node("%ContinueButton") as Button).pressed.emit()
	check(not card.visible and not g.paused, "Continue: back as it was")
	card.free()
	g.free()
	TranslationServer.set_locale(before)


func test_life_card_birth_and_school() -> void:
	var before := _es()
	var sim := _sim("founder_old")
	var kid := str(sim.state.characters[HERO]["children"][0])
	var c: FamilyCard = _scene("res://game/ui/family_card.tscn")
	c.order_sink = _sink
	c.show_event(sim, {"type": "child_born", "family": FAM, "character": kid})
	check(c.visible, "a birth shows the card")
	check((c.get_node("%Title") as Label).text.contains("Ha nacido"), "ha nacido")
	check((c.get_node("%Body") as Label).text.contains(str(sim.state.characters[HERO]["name"])), "with the parents")
	check(c.get_node("%PortraitSlot").get_child_count() == 1, "the baby's portrait")
	c.shown = {}
	sim.state.characters[kid]["life"] = {"school": "pending"}
	c.follow(sim)
	check(c.visible and (c.get_node("%SchoolBox") as Control).visible, "the school card")
	check((c.get_node("%Preview") as Label).text.contains("→"), "with the preview")
	_orders = []
	(c.get_node("%PickButton") as Button).pressed.emit()
	eq(_orders.size(), 0, "asks first")
	check(SocialKit.accept_pending(c), "confirmed")
	eq(str(_orders[0]["type"]), "school_choice", "school_choice")
	check(Orders.apply(sim, _orders[0])["ok"], "the sim takes it")
	c.follow(sim)
	check(not c.visible, "done: hidden")
	c.free()
	TranslationServer.set_locale(before)
