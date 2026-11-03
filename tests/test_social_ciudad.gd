extends "res://tests/test_case.gd"
## docs/ui/mecanicas/ciudad_viva.md, its acceptance criteria: the townsperson's sheet reads the relation (word and
## number), the emotion towards the family with what it does and why Talk is off, written; Insult, Threaten and
## Abandon ask first, Talk, Flatter and Accept do not; the board marks what the family can already deliver; the
## microevent card says the effects of the data (a figure changed in the data changes the card), «+1 más» opens the
## second one, and a choice the family cannot pay is off. Windowless: orders caught by a sink, given to Orders.apply.

const FAM := "fam_0001"
const HERO := "chr_0001"
const BOARD_SERVICE := Vector2i(16, 21)

var cat := Catalog.load_from()
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
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return before


func _near(sim: Sim, npc: String) -> void:
	var pos: Array = sim.state.characters[npc]["position"]
	sim.state.characters[HERO]["location"] = ""
	sim.state.characters[HERO]["position"] = [int(pos[0]), int(pos[1]) + 1]


func test_sheet_of_an_angry_neighbour_reads_without_hovering() -> void:
	var before := _es()
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	Emotions.add(sim, npc, "angry", FAM)
	Emotions.change_relation(sim, HERO, npc, -30, "test")
	var other := ""
	for f: String in sim.state.families:
		if f != FAM and other == "":
			other = f
	Emotions.add(sim, npc, "grateful", other)
	_near(sim, npc)
	var p: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, HERO, npc)
	p.open()
	var word := (p.get_node("%RelationWord") as Label).text
	check(word.contains("Hostil") and word.contains("−30"), "the relation as word and number (%s)" % word)
	var emo := p.get_node("%Emotions").get_node_or_null("Emotion_angry")
	check(emo != null, "the anger towards the family is listed")
	var fx := (emo.get_node("Effects") as Label).text if emo != null else ""
	check(fx.contains("precios +25") and fx.contains("no comercia por encima de 80"), "with what it does (%s)" % fx)
	check(p.get_node("%Emotions").get_node_or_null("Emotion_grateful") == null, "the other family's is not mixed in")
	check((p.get_node("%Others") as Label).visible, "it is folded in one line")
	check((p.get_node("%Actions").get_node("Talk") as Button).disabled, "Talk off")
	var why := p.reason_text()
	check(why.contains("Conversar") and why.contains("no quiere hablar"), "and why, written (%s)" % why)
	var tip := (p.get_node("%Actions").get_node("Flatter") as Button).tooltip_text
	check(tip.contains("Carisma") and tip.contains("Empatía") and (tip.contains("fácil") or tip.contains("dudoso") \
		or tip.contains("difícil")), "the odds of Flatter as a band (%s)" % tip)
	p.free()
	TranslationServer.set_locale(before)


func test_irreversible_actions_ask_and_cheap_ones_do_not() -> void:
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	_near(sim, npc)
	var p: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, HERO, npc)
	var acts := p.get_node("%Actions")
	for act: String in ["Insult", "Threaten"]:
		_orders = []
		(acts.get_node(act) as Button).pressed.emit()
		eq(_orders.size(), 0, "%s asks first" % act)
		check(not SocialKit.pending(p).is_empty(), "%s: the question waits" % act)
		SocialKit.cancel_pending(p)
	_orders = []
	(acts.get_node("Flatter") as Button).pressed.emit()
	eq(_orders.size(), 1, "Flatter goes at once")
	check(Orders.apply(sim, _orders[0])["ok"], "and the sim takes it")
	_orders = []
	(acts.get_node("Talk") as Button).pressed.emit()
	eq(str(_orders[0]["type"]), "npc_talk", "Talk goes at once")
	check(Orders.apply(sim, _orders[0])["ok"], "and the sim takes it")
	_orders = []
	(acts.get_node("Insult") as Button).pressed.emit()
	check(SocialKit.accept_pending(p), "Insult confirmed")
	check(Orders.apply(sim, _orders[0])["ok"], "the insult is taken")
	check(Emotions.has(sim, npc, "offended", FAM), "and she is offended")
	p.free()


func test_a_valuable_gift_asks_first() -> void:
	var sim := _sim("plaza_dusk")
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	_near(sim, npc)
	var inv: Dictionary = sim.state.characters[HERO]["inventory"]
	inv["stacks"] = []
	check(Inventory.add(inv, cat, "sword", 2, 1), "a good sword")
	var p: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	p.order_sink = _sink
	p.setup(sim, HERO, npc)
	_orders = []
	(p.get_node("%Actions").get_node("Gift") as Button).pressed.emit()
	var value := Market.price(sim, "sword", 2, "sell")
	if value >= 50:
		eq(_orders.size(), 0, "a gift of %d gold asks first" % value)
		check(SocialKit.accept_pending(p), "confirmed")
	eq(str(_orders[0]["type"]), "npc_gift", "the gift")
	check(Orders.apply(sim, _orders[0])["ok"], "the sim takes it")
	p.free()


func test_board_marks_what_the_family_can_deliver_and_abandon_asks() -> void:
	var before := _es()
	var sim := _sim("town_e_start")
	var now := int(sim.state.clock["minute"])
	sim.state.clock["minute"] = Clock.day(now) * Clock.MINUTES_PER_DAY + 10 * 60
	Contracts.post_scripted(sim.state, cat, cat.starts()["artisan_blacksmith"]["contracts"])
	var ch: Dictionary = sim.state.characters[HERO]
	ch["location"] = ""
	ch["path"] = []
	ch["position"] = [BOARD_SERVICE.x, BOARD_SERVICE.y]
	var board: Array = sim.state.contracts["board"]
	var hammers := str(board[0]["id"])
	var forge := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("owner", "")) == FAM and forge == "":
			forge = b
	check(Inventory.add(sim.state.buildings[forge]["inventory"], cat, "hammer", 0, int(board[0]["qty"])), "hammers in store")
	var p: BoardPanel = _scene("res://game/ui/board_panel.tscn")
	p.order_sink = _sink
	p.open_for(sim, HERO)
	var have := p.row_of(hammers, false).get_node("Bottom/Terms") as Label
	check(have.text.contains("tienes %d/%d" % [int(board[0]["qty"]), int(board[0]["qty"])]), "tienes x/y (%s)" % have.text)
	eq(have.theme_type_variation, &"PositiveInkLabel", "in green on the parchment: the family can deliver it")
	var sword := str(board[1]["id"])
	eq((p.row_of(sword, false).get_node("Bottom/Terms") as Label).theme_type_variation, &"InkLabel", "not this one")
	_orders = []
	(p.row_of(hammers, false).get_node("Bottom/Accept") as Button).pressed.emit()
	eq(_orders.size(), 1, "Accept does not ask")
	check(Orders.apply(sim, _orders[0])["ok"], "accepted")
	p.refresh(true)
	var mine := p.row_of(hammers, true)
	check((mine.get_node("Mid/Terms") as Label).text.contains("almacén"), "what the store holds")
	check((mine.get_node("Bottom/Why") as Label).text.contains("Falta"), "Deliver off: what is missing, written")
	_orders = []
	(mine.get_node("Bottom/Abandon") as Button).pressed.emit()
	eq(_orders.size(), 0, "Abandon asks first")
	var q := SocialKit.pending(p)
	check(str(q.get("body", "")).contains("reputación"), "with its cost (%s)" % q.get("body", ""))
	check(SocialKit.accept_pending(p), "confirmed")
	check(Orders.apply(sim, _orders[0])["ok"], "abandoned")
	p.free()
	TranslationServer.set_locale(before)


func test_microevent_card_says_the_effects_of_the_data() -> void:
	var before := _es()
	var sim := _sim("microevent_card")
	var card: MicroeventCard = _scene("res://game/ui/microevent_card.tscn")
	card.order_sink = _sink
	card.follow(sim, HERO)
	var doctor := card.get_node("%Choices").get_node("Doctor") as Button
	var line := SocialKit.button_lines(doctor)
	check(line.contains("Pagar al médico") and line.contains("−10 de oro") and line.contains("lealtad +5"), "two lines (%s)" % line)
	var dock := SocialKit.button_lines(card.get_node("%Choices").get_node("Dock") as Button)
	check(dock.contains("falta 1-2 días") and dock.contains("lealtad −5"), "the dock (%s)" % dock)
	var marked: Array = card.get_node("%Choices").get_children().filter(func(b: Node) -> bool:
		return b.get_node_or_null("DefaultMark") != null)
	eq(marked.size(), 1, "one choice marked as the default")
	check(SocialKit.button_lines(marked[0] as Button).contains("Día libre pagado"), "the paid day off")
	# a figure changed in the data changes the card, no i18n touched
	for c: Dictionary in sim.catalog.microevents()["sick_employee"]["choices"]:
		if str(c["id"]) == "doctor":
			for e: Dictionary in c["effects"]:
				if str(e["kind"]) == "pay":
					e["gold"] = 12
	card.shown_id = ""
	card.follow(sim, HERO)
	check(SocialKit.button_lines(card.get_node("%Choices").get_node("Doctor") as Button).contains("−12 de oro"), "−12 now")
	# cannot pay: off with the reason
	sim.state.families[FAM]["gold"] = 5
	card.shown_id = ""
	card.follow(sim, HERO)
	var off := card.get_node("%Choices").get_node("Doctor") as Button
	check(off.disabled and SocialKit.button_lines(off).contains("No tienes 12 de oro"), "off when it cannot be paid")
	card.free()
	TranslationServer.set_locale(before)


func test_two_microevents_show_more_and_open_the_second() -> void:
	var sim := _sim("microevent_card")
	var first: Dictionary = sim.state.microevents["active"][0]
	var second := first.duplicate(true)
	second["id"] = str(first["id"]) + "_b"
	(sim.state.microevents["active"] as Array).append(second)
	var card: MicroeventCard = _scene("res://game/ui/microevent_card.tscn")
	card.follow(sim, HERO)
	check((card.get_node("%MoreButton") as Button).visible, "«+1 más»")
	eq(card.shown_id, str(first["id"]), "the first one")
	(card.get_node("%MoreButton") as Button).pressed.emit()
	eq(card.shown_id, str(second["id"]), "opens the second")
	(card.get_node("%LaterButton") as Button).pressed.emit()
	check(card.folded and not (card.get_node("%Choices") as Control).visible, "«Más tarde» folds it")
	card.free()


func test_relation_bands() -> void:
	eq(SocialKit.relation_band(-80), "enemy", "enemy")
	eq(SocialKit.relation_band(-30), "hostile", "hostile")
	eq(SocialKit.relation_band(0), "neutral", "neutral")
	eq(SocialKit.relation_band(20), "cordial", "cordial")
	eq(SocialKit.relation_band(70), "friend", "friend")


func test_social_confirmations_use_the_shared_modal() -> void:
	var m: ConfirmModal = (load("res://game/ui/confirm_modal.tscn") as PackedScene).instantiate()
	var owner := Node.new()
	var said: Array = []
	SocialKit.ask(owner, "¿Insultar a Agnès?", "Relación −10", "Insultar", func() -> void: said.append("yes"), "x")
	SocialKit.show_in(m, owner)   # in the game: the HUD's modal (ConfirmModal.of)
	check(m.visible, "the shared modal shows the question")
	eq((m.get_node("%Title") as Label).text, "¿Insultar a Agnès?", "its title")
	check((m.get_node("%Warn") as Label).visible, "irreversible: «No se puede deshacer»")
	m.cancel()
	eq(said.size(), 0, "cancelled: nothing")
	check(SocialKit.pending(owner).is_empty(), "and the question is gone")
	SocialKit.ask(owner, "¿Pedir la mano?", "", "Pedir", func() -> void: said.append("yes"), "", true)
	SocialKit.show_in(m, owner)
	check((m.get_node("%Seal") as Control).visible, "an official one seals")
	m.confirm()
	eq(said, ["yes"], "confirmed: the action runs")
	owner.free()
	m.free()
