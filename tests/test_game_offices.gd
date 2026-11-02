extends "res://tests/test_case.gd"
## H10 view (docs/contratos/h10_cargos.md), windowless: the offices panel (chart with holders and vacancies, «Run» gives
## run_for_office at the chosen level or is off with its reason, the campaign section, the inspector's powers), the
## vote's card with the count, the campaign actions on a townsperson's sheet and the office on the sheets.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func _sim(id: String) -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func test_chart_and_running() -> void:
	var sim := _sim("office_campaign")
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO)
	var chart := p.get_node("%Chart") as VBoxContainer
	for o: String in cat.office_chart():
		check(chart.get_node_or_null("Office_" + o) != null, "a row for %s" % o)
	eq(str(chart.get_child(0).name), "Office_mayor", "the mayor at the top")
	var judge := chart.get_node("Office_judge") as HBoxContainer
	check((judge.get_child(1) as Label).text.contains("Soler"), "the judge's family")
	var insp := chart.get_node("Office_market_inspector") as HBoxContainer
	check((insp.get_child(1) as Label).text.begins_with(SimQuery.t_("ui.offices.vacant")), "the inspector is vacant")
	check((insp.get_child(1) as Label).text.contains("9"), "and votes on day 9")
	check(not (insp.get_node("Run") as Button).disabled, "Hugo can run for inspector")
	check((chart.get_node("Office_judge/Run") as Button).disabled, "not for judge (title)")
	var lv := p.get_node("%LevelOption") as OptionButton
	lv.select(1)
	lv.item_selected.emit(1)
	(chart.get_node("Office_market_inspector/Run") as Button).pressed.emit()
	eq(got, [{"type": "run_for_office", "actor": HERO, "office": "market_inspector", "level": "medium"}],
		"the order at the chosen level")
	Orders.apply(sim, got[0])
	p.refresh(true)
	check((p.get_node("%CampaignBox") as Control).visible, "the campaign section")
	check(chart.get_node_or_null("Election_market_inspector") != null, "the open election under its office")
	check((p.get_node("%SpeechButton") as Button).disabled, "no speech before winter")
	p.free()


func test_powers_section() -> void:
	var sim := _sim("office_inspector")
	var p: OfficesPanel = _scene("res://game/ui/offices_panel.tscn")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.open_for(sim, HERO)
	check((p.get_node("%PowersBox") as Control).visible, "the inspector's powers")
	var up := p.get_node("%Powers").get_node("Power_regulate_price/Use_regulate_price_up") as Button
	check(not up.disabled, "regulate +10 %")
	up.pressed.emit()
	eq(str(got[0]["power"]), "regulate_price", "use_office_power")
	eq(int(got[0]["args"]["percent"]), 10, "+10 %")
	check(p.get_node("%Powers").get_node_or_null("Power_fine_merchant") != null, "fine a merchant")
	p.free()


func test_vote_card() -> void:
	var sim := _sim("office_election_eve")
	var held: Dictionary = {}
	while held.is_empty():
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "election_held":
				held = e
	check(OfficeCard.concerns_human(sim, held), "Hugo stood")
	var c: OfficeCard = _scene("res://game/ui/office_card.tscn")
	c.show_for(sim, held)
	var rows := c.get_node("%Rows") as VBoxContainer
	eq(rows.get_child_count(), 2, "a bar per candidate")
	check((rows.get_node("Row_" + HERO).get_child(0) as Label).text.begins_with("★"), "the winner marked")
	check((rows.get_node("Row_" + HERO).get_child(2) as Label).text.contains("6"), "6 votes")
	check((c.get_node("%Winner") as Label).text.contains("Hugo"), "Hugo wins")
	c.free()


func test_campaign_on_the_townsperson_sheet() -> void:
	var sim := _sim("office_election_eve")
	var v := str(Elections.voters(sim, [HERO, RIVAL])[0])
	var p: NpcPanel = _scene("res://game/ui/npc_panel.tscn")
	p.setup(sim, HERO, v)
	var acts := p.get_node("%Actions") as HFlowContainer
	check(acts.get_node_or_null("CampaignVisit") != null and acts.get_node_or_null("CampaignBribe") != null,
		"visit and bribe while a candidate")
	check(acts.get_node_or_null("CampaignDefame") == null, "no defame on a voter")
	p.setup(sim, HERO, RIVAL)
	check(acts.get_node_or_null("CampaignDefame") != null, "defame the other candidate")
	var judge: String = Offices.holders(sim, "judge")[0]
	p.setup(sim, HERO, judge)
	check((p.get_node("%Info") as Label).text.contains(SimQuery.office_name("judge")), "the judge's office on the sheet")
	p.free()
