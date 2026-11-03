extends "res://tests/test_case.gd"
## docs/ui/mecanicas/cortejo_y_boda.md, its acceptance criteria: in the courtship scenario one sees who is ready to
## propose and why another row is off; the mark of the bar is courtship.propose_min (the data moves it); Propose asks
## with its three consequences and cancelling gives no order; from a single townsperson's sheet one courts without
## the panel; the wedding card has both portraits and both families' colours; the filters keep 20 rows in the panel.

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


func _ready_one(sim: Sim) -> String:
	var c: Dictionary = Courtship.candidates(sim, HERO)[0]
	Courtship.relation(sim.state, HERO, str(c["character"]))["affinity"] = 84
	return str(c["character"])


func test_rows_say_who_is_ready_and_why_others_are_off() -> void:
	var before := _es()
	var sim := _sim("courtship")
	var ready := _ready_one(sim)
	var cands := Courtship.candidates(sim, HERO)
	var angry := str(cands[cands.size() - 1]["character"])
	Emotions.add(sim, angry, "angry", FAM)
	var p: CourtshipPanel = _scene("res://game/ui/courtship_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, HERO)
	var r := p.row_of(ready)
	check((r.find_child("Status", true, false) as Label).text.contains("pedir su mano"), "the ready one says so")
	check(not (r.find_child("Propose", true, false) as Button).disabled or \
		str(Courtship.status(sim, HERO, ready)) == "too_far", "Propose on (or walking)")
	var a := p.row_of(angry)
	var st := (a.find_child("Status", true, false) as Label).text
	check(st.contains("contigo") and (a.find_child("Status", true, false) as Label).theme_type_variation == &"ReasonLabel",
		"the blocked one says why, in red (%s)" % st)
	check((p.get_node("%Ready") as Label).text.contains("1"), "«listos: 1» in the header")
	var bar := r.find_child("Affinity", true, false) as ProgressBar
	eq(float(bar.get_meta("mark")), float(sim.catalog.family["courtship"]["propose_min"]), "the mark is propose_min")
	sim.catalog.family["courtship"]["propose_min"] = 60
	p.refresh(true)
	eq(float((p.row_of(ready).find_child("Affinity", true, false) as ProgressBar).get_meta("mark")), 60.0, "the data moves it")
	p.free()
	TranslationServer.set_locale(before)


func test_propose_asks_with_its_consequences_and_cancel_gives_nothing() -> void:
	var before := _es()
	var sim := _sim("courtship")
	var ready := _ready_one(sim)
	var p: CourtshipPanel = _scene("res://game/ui/courtship_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, HERO)
	_orders = []
	p.request_propose(ready)
	var q := SocialKit.pending(p)
	eq(_orders.size(), 0, "no order before the answer")
	var body := str(q.get("body", ""))
	check(body.contains("Se casará") and body.contains("Vivirá"), "the consequences (%s)" % body)
	eq(body.count("·"), CourtshipPanel.propose_lines(sim, HERO, ready).size(), "one line each")
	SocialKit.cancel_pending(p)
	eq(_orders.size(), 0, "cancelling gives no order")
	p.request_propose(ready)
	check(SocialKit.accept_pending(p), "confirmed")
	check(not _orders.is_empty() and str(_orders.back()["type"]) == "propose", "propose")
	p.free()
	TranslationServer.set_locale(before)


func test_court_from_the_townsperson_sheet() -> void:
	var sim := _sim("courtship")
	var c: Dictionary = Courtship.candidates(sim, HERO)[0]
	var target := str(c["character"])
	var n: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	n.order_sink = _sink
	n.setup(sim, HERO, target)
	check((n.get_node("%CourtBox") as Control).visible, "a single townsperson: the Courtship section")
	_orders = []
	(n.get_node("%CourtActions").get_node("CourtTalk") as Button).pressed.emit()
	check(not _orders.is_empty() and str(_orders.back()["type"]) == "court_talk", "talk as courtship from the sheet")
	var last: Dictionary = _orders.back().duplicate()
	last.erase("queued")
	if _orders.size() == 1:
		check(Orders.apply(sim, last)["ok"], "the sim takes it")
	n.free()


func test_wedding_card_shows_both() -> void:
	var before := _es()
	var sim := _sim("courtship")
	var target := _ready_one(sim)
	sim.events.clear()
	Courtship.marry(sim, HERO, target)
	var e := {}
	for x: Dictionary in sim.events:
		if str(x["type"]) == "wedding":
			e = x
	var w: WeddingCard = _scene("res://game/ui/wedding_card.tscn")
	w.show_for(sim, e, sim.events)
	check(w.visible, "shown")
	# a «Carta» of the page kit (docs/ui/04_kit_de_pagina.md): the title on the ribbon, the portraits with the
	# families' colours under the names, the consequences as lines
	eq(w.find_child("LeftSlot", true, false).get_child_count() + w.find_child("RightSlot", true, false).get_child_count(),
		2, "both portraits")
	var bands := 0
	for side: String in ["Left", "Right"]:
		bands += 1 if w.find_child(side, true, false).find_child("Ribbon", false, false) != null else 0
	eq(bands, 2, "both families' colours")
	check((w.find_child("RibbonText", true, false) as Label).text.contains("se casan"), "¡se casan!")
	var lines := ""
	for l: Node in w.find_child("Block2_effects", true, false).get_children():
		lines += (l as Label).text
	check(lines.contains("vuestra casa"), "the consequences")
	check(str(w.parts.get("page", "")) != "", "on the paper of the page kit")
	w.free()
	TranslationServer.set_locale(before)


func test_filters() -> void:
	var sim := _sim("courtship")
	var ready := _ready_one(sim)
	var p: CourtshipPanel = _scene("res://game/ui/courtship_panel.tscn")
	p.setup(sim, HERO)
	p.set_filter("ready")
	var shown := (p.get_node("%List") as Node).get_children().filter(func(r: Node) -> bool: return (r as Control).visible)
	eq(shown.size(), 1, "Listos: only the ready one")
	eq(str(shown[0].name), ready, "that one")
	check((p.get_node("%Scroll") as ScrollContainer) != null, "the list scrolls inside the panel")
	p.free()
