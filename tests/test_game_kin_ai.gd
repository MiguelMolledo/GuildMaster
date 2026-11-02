extends "res://tests/test_case.gd"
## H14 view (docs/contratos/h14_ia_familiar.md), windowless: the family AI panel (member picker, directives in order with
## on/off and ▲ ▼ that send one set_directives, the off ones greyed, what it does and why, needs and morale bars) and
## the «AI» buttons of the sheet and the tree.

const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func test_panel() -> void:
	var sim := Sim.new(NewGame.from_scenario("kin_trader", 1)["state"], cat)
	var wife := str(sim.state.characters[HERO]["spouse"])
	var p: KinAiPanel = (load("res://game/ui/kin_ai_panel.tscn") as PackedScene).instantiate()
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO, wife)
	var box := p.get_node("%Directives") as VBoxContainer
	eq(str(box.get_child(0).name), "D_trade", "the first directive on top")
	check((box.get_node("D_learn/On") as CheckBox).disabled, "learn is off (EA)")
	(box.get_node("D_work/Up") as Button).pressed.emit()
	eq(got[0], {"type": "set_directives", "actor": HERO, "character": wife, "directives": ["work", "trade"]},
		"▲ moves work first, one order")
	(box.get_node("D_socialize/On") as CheckBox).button_pressed = true
	eq(got[1]["directives"], ["trade", "work", "socialize"], "ticking adds it last")
	var needs := p.get_node("%Needs") as VBoxContainer
	for n: String in ["N_hunger", "N_rest", "N_social", "N_fun", "Morale"]:
		check(needs.get_node_or_null(n) != null, "a bar: %s" % n)
	sim.run_minutes(90)
	p.refresh(true)
	check((p.get_node("%NowLabel") as Label).text.contains(SimQuery.t_("ui.kin_ai.doing_trade")), "now: trading")
	p.free()


func test_buttons() -> void:
	var c: Node = (load("res://game/ui/character_panel.tscn") as PackedScene).instantiate()
	check(c.get_node_or_null("%KinAiButton") != null, "«AI» on the sheet")
	c.free()
	var t: Node = (load("res://game/ui/family_tree_panel.tscn") as PackedScene).instantiate()
	check(t.get_node_or_null("%KinAiButton") != null, "«AI» on the tree")
	t.free()
