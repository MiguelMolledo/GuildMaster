extends "res://tests/test_case.gd"
## Market and account book (docs/ui/mecanicas/mercado_y_libro.md §10): selling all says the sum unit by unit and the
## demand it leaves, the demand of every row with word and number, the errand button with its surcharge and time (and
## disabled with its reason when the storage is full), the debt card (owed, due, consequences, forecast), the
## confirmation of a payment under the dawn's charges, the 8 bars of By day. The previews are the sim's (read only).

const FORGE := "bld_0001"
const ARMORY := "bld_0003"
const HUGO := "chr_0001"
const RESOURCES_SERVICE := Vector2i(16, 15)

var cat := Catalog.load_from()


func _sim(scenario: String = "town_e_start") -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func _at(sim: Sim, hour: int) -> void:
	var now := int(sim.state.clock["minute"])
	sim.state.clock["minute"] = Clock.day(now) * Clock.MINUTES_PER_DAY + hour * 60


func _stand(sim: Sim, who: String, tile: Vector2i) -> void:
	var ch: Dictionary = sim.state.characters[who]
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["position"] = [tile.x, tile.y]


func _market(sim: Sim, stall: String) -> MarketPanel:
	var p: MarketPanel = (load("res://game/ui/market_panel.tscn") as PackedScene).instantiate()
	p.open_for(sim, HUGO, stall)
	return p


func _in_armory(sim: Sim) -> void:
	_at(sim, 10)
	sim.step([{"type": "enter_building", "actor": HUGO, "building": ARMORY}])
	for i: int in 80:
		if str(sim.state.characters[HUGO]["location"]) == ARMORY:
			break
		sim.step()


func test_sell_all_says_the_sum_unit_by_unit_and_the_demand_after() -> void:
	var sim := _sim()
	_in_armory(sim)
	Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "sword", 1, 3)
	var before := Market.demand(sim, "sword")
	var pv := Market.sell_preview(sim, HUGO, "armory", "sword", 1, 3)
	eq((pv["prices"] as Array).size(), 3, "three prices")
	check(int(pv["prices"][0]) >= int(pv["prices"][2]), "each unit at the demand the last one left")
	eq(Market.demand(sim, "sword"), before, "the preview leaves the demand as it was")
	var p := _market(sim, "armory")
	p.show_tab("sell")
	var row := p.row_of("sword", 1)
	var all := (row.get_node("SellAll") as Button).text
	check(all.contains("%d + %d + %d = %d" % [int(pv["prices"][0]), int(pv["prices"][1]), int(pv["prices"][2]),
		int(pv["total"])]), "Sell all says the sum (%s)" % all)
	var ev := sim.step([{"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": 1, "qty": 3}])
	var sold := ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "market_sold")
	eq(int(sold[0]["total"]), int(pv["total"]), "the sale pays what the preview said")
	near(Market.demand(sim, "sword"), float(pv["demand_after"]), 0.001, "and leaves the demand it said")
	p.free()


func test_every_row_shows_its_demand() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_at(sim, 10)
	_stand(sim, HUGO, RESOURCES_SERVICE)
	sim.state.market["demand"] = {"iron": 0.6}
	var p := _market(sim, "resources")
	var d := p.row_of("iron", 0).get_node("Top/Demand") as Label
	check(d.text.contains("muy baja") and d.text.contains("0,60"), "word and number without the mouse (%s)" % d.text)
	eq(str(p.demand_view("iron")["word"]), "very_low", "below 0,7: very low")
	TranslationServer.set_locale(before)
	p.free()


func test_errand_button_says_cost_and_time_and_why_not() -> void:
	var sim := _sim()
	_at(sim, 10)
	_stand(sim, HUGO, RESOURCES_SERVICE)
	var p := _market(sim, "resources")
	var send := p.row_of("iron", 0).get_node("Controls/Send") as MenuButton
	var extra := Market.errand_surcharge(sim, Market.trade_price(sim, HUGO, "resources", "iron", 0, "buy"), "resources")
	check(send.text.contains("+%d" % extra) and send.text.contains(SimQuery.duration_label(Market.errand_minutes(sim))),
		"the surcharge and the time written (%s)" % send.text)
	p.free()
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	inv["stacks"] = []
	var fill := ["coal", "stone", "wood", "wheat", "wool", "herbs", "cloth", "planks", "flour", "bread", "sword", "armor"]
	for it: String in fill:
		if (inv["stacks"] as Array).size() < int(inv["limit"]):
			Inventory.add(inv, cat, it, 0, 1)
	p = _market(sim, "resources")
	var row := p.row_of("iron", 0)
	check((row.get_node("Controls/Send") as MenuButton).disabled, "the storage full: no errand")
	var r := row.get_node_or_null("Reason") as Label
	check(r != null and r.visible and r.text != "", "with its reason written")
	p.free()


func _started() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 3)
	return Sim.new(r["state"], cat)


func test_debt_card_and_forecast() -> void:
	var sim := _started()
	var fam := SimQuery.player_family(sim.state)
	var loan := str(Loans.of_family(sim, fam)[0])
	var p: LedgerPanel = (load("res://game/ui/ledger_panel.tscn") as PackedScene).instantiate()
	p.open_for(sim, fam, SimQuery.family_actor(sim.state, fam), "debts")
	check(p.row_of(loan) != null, "the loan's head line (owed of total)")
	check(p.row_of(loan + "_bar") != null, "its paid bar")
	check(p.row_of(loan + "_consequences") != null, "what happens if it falls due")
	var f := p.row_of(loan + "_forecast") as Label
	var fc := Ledger.forecast(sim, fam, int(Loans.status(sim, loan)["due_minute"]))
	check(f != null and f.text.contains(str(int(fc["gold_at"]))), "the forecast from the sim (%s)" % (f.text if f != null else ""))
	p.free()


func test_payment_under_the_dawn_charges_asks_first() -> void:
	var sim := _started()
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["gold"] = 30
	var due := Upkeep.due_next_dawn(sim, fam)
	check(int(due["total"]) > 0, "the forge's upkeep is charged at dawn (%s)" % due)
	var p: LedgerPanel = (load("res://game/ui/ledger_panel.tscn") as PackedScene).instantiate()
	p.open_for(sim, fam, SimQuery.family_actor(sim.state, fam), "debts")
	check(p.needs_confirm(30), "paying 30 of 30 leaves less than the dawn charges: confirm")
	sim.state.families[fam]["gold"] = 500
	check(not p.needs_confirm(10), "with 500 it does not ask")
	p.free()


func test_by_day_has_its_chart() -> void:
	var sim := _started()
	var fam := SimQuery.player_family(sim.state)
	var p: LedgerPanel = (load("res://game/ui/ledger_panel.tscn") as PackedScene).instantiate()
	p.open_for(sim, fam, SimQuery.family_actor(sim.state, fam), "days")
	check(p.row_of("Chart") != null, "the bars over the zero line")
	check(p.row_of("Mean") != null, "and the mean of the days")
	p.free()
