extends "res://tests/test_case.gd"
## docs/ui/mecanicas/cargos_y_elecciones.md, its acceptance criteria: in office_campaign the 7 seats with their holder
## or VACANTE and the Inspector saying when it is voted and whether one can stand; with registration closed, the
## reason says when it opens again; in office_election_eve the Campaign tab says the days left, who stands and what
## was done; bribing and defaming ask with the risk as a band; the count shows the share by family; in
## office_inspector the Powers tab shows what is in force and the cooldown as a bar. And the poll (decision a).

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


func _seats(p: OfficesPanel) -> Array:
	return (p.get_node("%Chart") as Node).find_children("Office_*", "PanelContainer", true, false)


func test_seven_seats_and_the_inspector() -> void:
	var before := _es()
	var sim := _sim("office_campaign")
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	p.open_for(sim, HERO)
	eq(_seats(p).size(), 7, "the 7 seats")
	p.pick("market_inspector")
	var cal := p.get_node("%CalLabels") as Node
	var txt := ""
	for l: Node in cal.get_children():
		txt += (l as Label).text + " "
	check(txt.contains("voto 9"), "when it is voted (%s)" % txt)
	check(not (p.get_node("%RunButton") as Button).disabled, "and that he can stand")
	check((p.get_node("%DetailReq") as Label).text.contains("lo tienes"), "the title it asks, which he has")
	p.free()
	TranslationServer.set_locale(before)


func test_registration_closed_says_when_it_opens() -> void:
	var before := _es()
	var sim := _sim("office_campaign")
	var day := Offices.election_day(sim, "market_inspector")
	var dps := int(sim.catalog.time["days_per_season"])
	sim.state.clock["minute"] = (day - dps) * Clock.MINUTES_PER_DAY + 600
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	p.open_for(sim, HERO)
	p.pick("market_inspector")
	check((p.get_node("%RunButton") as Button).disabled, "closed")
	check((p.get_node("%RunReason") as Label).text.contains("vuelve a abrir el día"), "says when (%s)" % (p.get_node("%RunReason") as Label).text)
	p.free()
	TranslationServer.set_locale(before)


func test_campaign_tab_and_the_poll() -> void:
	var before := _es()
	var sim := _sim("office_election_eve")
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	p.open_for(sim, HERO)
	eq(p.tab, "campaign", "a candidate opens on the campaign")
	check((p.get_node("%DaysLeft") as Label).text.contains("quedan"), "the days left")
	var list := p.get_node("%CampaignList")
	check(list.get_node_or_null("Cand_" + HERO) != null and list.get_node_or_null("Cand_" + RIVAL) != null, "who stands")
	check((list.get_node("Cand_" + HERO).find_child("Done", true, false) as Label).text.contains("discurso hoy"), "what was done")
	var f := Elections.forecast(sim, str(Elections.candidacy(sim.state, HERO)["election"]["office"]))
	check(f.has(HERO) and str(f[HERO]) in ["lead", "close", "behind"], "the poll as a band (%s)" % [f])
	check((p.get_node("%Forecast") as Label).text != "", "shown")
	p.free()
	TranslationServer.set_locale(before)


func test_bribe_and_defame_ask_with_the_risk() -> void:
	var before := _es()
	var sim := _sim("office_election_eve")
	var v := str(Elections.voters(sim, [HERO, RIVAL])[0])
	var n: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	n.order_sink = _sink
	n.setup(sim, HERO, v)
	_orders = []
	n.request_campaign("bribe")
	eq(_orders.size(), 0, "bribing asks first")
	var body := str(SocialKit.pending(n).get("body", ""))
	check(body.contains("Sigilo") and body.contains("Empatía") and (body.contains("fácil") or body.contains("dudoso") or body.contains("difícil")),
		"with the risk as a band (%s)" % body)
	SocialKit.cancel_pending(n)
	n.setup(sim, HERO, RIVAL)
	n.request_campaign("defame")
	check(str(SocialKit.pending(n).get("body", "")).contains("Si sale mal"), "defaming too")
	n.free()
	TranslationServer.set_locale(before)


func test_count_by_family() -> void:
	var sim := _sim("office_election_eve")
	var held: Dictionary = {}
	while held.is_empty():
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "election_held":
				held = e
	var c: OfficeCard = _scene("res://game/ui/office_card.tscn")
	c.show_for(sim, held)
	check((c.get_node("%ByFamily") as Label).visible and (c.get_node("%ByFamily") as Label).text != "", "the share by family")
	check((c.get_node("%Seal") as Control).visible, "the seal")
	c.free()


func test_powers_in_force_and_cooldown() -> void:
	var sim := _sim("office_inspector")
	var o := {"type": "use_office_power", "actor": HERO, "power": "regulate_price", "args": {"item": "sword", "percent": 10}}
	check(Orders.apply(sim, o)["ok"], "a regulation")
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	p.open_for(sim, HERO)
	p.show_tab("powers")
	check((p.get_node("%InForce") as Node).get_node_or_null("Regulation_sword") != null, "in force")
	var row := p.get_node("%Powers").get_node("Power_regulate_price")
	check(row.get_node_or_null("Cooldown") is ProgressBar, "the cooldown as a bar")
	p.free()
