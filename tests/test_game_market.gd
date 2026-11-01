extends "res://tests/test_case.gd"
## H3 seen and played by hand (GDD 4.5.1-4.5.2, 4.5.6-4.5.7, 4.16-4.18, 4.23): the stalls, the board and the rival's
## forge on the map, and each panel giving the exact order of docs/contratos/h3_mercado.md (buy with and without
## deliver_to, sell, accept/deliver/abandon_contract, repay_loan, read_notices), then the sim taking it. The new
## game screen calls NewGame.from_start with what was chosen (5 free points, no more). Windowless: real scenes.

const FORGE := "bld_0001"
const RIVAL_FORGE := "bld_0002"
const ARMORY := "bld_0003"
const HUGO := "chr_0001"
const RESOURCES_SERVICE := Vector2i(16, 15)
const BOARD_SERVICE := Vector2i(16, 21)

var cat := Catalog.load_from()


func _sim(scenario: String = "town_e_start") -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func _scene(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _click(target: Object, button: MouseButton, screen: Vector2) -> bool:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = screen
	return target.call("handle_input", ev)


func _same(got: Dictionary, want: Dictionary, msg: String) -> void:
	eq(SaveFile.canonical(got), SaveFile.canonical(want), msg)


func _refusals(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused")


## Puts `who` standing on `tile` of the map (no path, outside), the way the walk would leave them.
func _stand(sim: Sim, who: String, tile: Vector2i) -> void:
	var ch: Dictionary = sim.state.characters[who]
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["position"] = [tile.x, tile.y]


## Moves the clock to `hour`:00 of the same day (the market opens in the day and at dusk).
func _at(sim: Sim, hour: int) -> void:
	var now := int(sim.state.clock["minute"])
	sim.state.clock["minute"] = Clock.day(now) * Clock.MINUTES_PER_DAY + hour * 60


func _add(inv: Dictionary, item: String, quality: int, qty: int) -> void:
	check(Inventory.add(inv, cat, item, quality, qty), "setup: add %s x%d" % [item, qty])


# --- the map -------------------------------------------------------------------------------------------------------

func test_stalls_board_and_rival_forge_on_the_map() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	var v: WorldView = _scene("res://game/world/world_view.tscn")
	v.setup(sim.state, cat)
	for id: String in ["resources", "food", "materials", "board"]:
		check(v.service_sign_of(id) != null, "a sign over %s" % id)
	eq((v.service_sign_of("board") as BuildingMarks.Sign).text, "Tablón de encargos", "the board's sign")
	eq((v.service_sign_of("resources") as BuildingMarks.Sign).text, "Recursos", "a stall's sign")
	eq((v.sign_of(RIVAL_FORGE) as BuildingMarks.Sign).text, "Forja de Ferrer", "the rival's forge carries the family")
	eq((v.sign_of(FORGE) as BuildingMarks.Sign).text, "Forja", "the player's forge")
	eq((v.sign_of(ARMORY) as BuildingMarks.Sign).text, "Armería", "the armory has its sign")
	check(SimQuery.is_public(sim.state, cat, ARMORY), "the armory is a public shop")
	check(not SimQuery.is_own(sim.state, HUGO, RIVAL_FORGE), "the rival's forge is not Hugo's: no Manage")
	TranslationServer.set_locale(before)
	v.free()


func test_right_click_on_a_stall_or_the_board_walks_to_its_service_tile() -> void:
	var sim := _sim()
	var v: WorldView = _scene("res://game/world/world_view.tscn")
	v.setup(sim.state, cat)
	var got: Array = []
	var asked: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	v.service_requested.connect(func(a: String, k: String, id: String, svc: Vector2i) -> void: asked.append([a, k, id, svc]))
	v.select(HUGO)
	check(_click(v, MOUSE_BUTTON_RIGHT, v.service_screen("resources")), "the click is used")
	_same(got[0], {"type": "move_to", "actor": HUGO, "tile": [16, 15]}, "move_to the stall's service tile")
	eq(asked[0], [HUGO, "stall", "resources", RESOURCES_SERVICE], "the HUD is told which panel to open on arrival")
	check(_click(v, MOUSE_BUTTON_RIGHT, v.service_screen("board")), "the board is clicked")
	_same(got[1], {"type": "move_to", "actor": HUGO, "tile": [16, 21]}, "move_to the board's service tile")
	eq(asked[1], [HUGO, "board", "board", BOARD_SERVICE], "board panel on arrival")
	eq(_refusals(sim.step(got.slice(1))).size(), 0, "the sim takes the walk")
	var events: Array = []
	for i: int in 60:
		events.append_array(sim.step())
	check(SimQuery.stands_on(sim.state, HUGO, BOARD_SERVICE), "Hugo stands at the board")
	check(Contracts.at_board(sim, HUGO), "and the sim agrees he is at the board")
	asked.clear()
	_click(v, MOUSE_BUTTON_RIGHT, v.service_screen("board"))
	eq(got.size(), 2, "already there: no new walk")
	eq(asked[0][1], "board", "the panel opens at once")
	v.command_move(Vector2i(20, 20))
	eq(asked[1][1], "", "another order forgets the pending panel")
	v.free()


# --- the market panel ----------------------------------------------------------------------------------------------

func _market(sim: Sim, stall: String) -> MarketPanel:
	var p: MarketPanel = _scene("res://game/ui/market_panel.tscn")
	p.open_for(sim, HUGO, stall)
	return p


func test_market_panel_buys_with_and_without_errand() -> void:
	var sim := _sim()
	_at(sim, 10)
	_stand(sim, HUGO, RESOURCES_SERVICE)
	eq(SimQuery.stall_at(sim, HUGO), "resources", "Hugo is at the resources stall")
	var p := _market(sim, "resources")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	check((p.get_node("%GoldLabel") as Label).text.contains("100"), "the family gold is shown")
	var row := p.row_of("iron", 0)
	check(row != null, "iron is sold here")
	check(p.row_of("sword", 0) == null, "no swords at the resources stall (filtered by the stall)")
	check((row.get_node("Top/Price") as Label).text.contains(str(Market.price(sim, "iron", 0, "buy"))), "unit price")
	(row.get_node("Controls/Plus") as Button).pressed.emit()
	row = p.row_of("iron", 0)
	eq((row.get_node("Controls/Qty") as Label).text, "2", "+ raises the quantity")
	(row.get_node("Controls/Buy") as Button).pressed.emit()
	_same(got[0], {"type": "buy", "actor": HUGO, "stall": "resources", "item": "iron", "quality": 0, "qty": 2}, "buy 2 iron")
	var send := row.get_node("Controls/Send") as MenuButton
	check(not send.disabled, "Buy and send to… is offered")
	eq(send.get_popup().item_count, 1, "one own building to send to")
	send.get_popup().id_pressed.emit(0)
	_same(got[1], {"type": "buy", "actor": HUGO, "stall": "resources", "item": "iron", "quality": 0, "qty": 2,
		"deliver_to": FORGE}, "buy 2 iron sent to the forge")
	var before := Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes both purchases")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "iron"), 2, "Hugo carries 2 iron")
	for i: int in Market.errand_minutes(sim) + 1:
		sim.step()
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron"), before + 2, "the errand reached the forge")
	p.free()


func test_market_panel_buy_disabled_with_reason() -> void:
	var sim := _sim()
	_at(sim, 10)
	_stand(sim, HUGO, RESOURCES_SERVICE)
	sim.state.families["fam_0001"]["gold"] = 0
	var p := _market(sim, "resources")
	var buy := p.row_of("iron", 0).get_node("Controls/Buy") as Button
	check(buy.disabled, "no gold: Buy disabled")
	eq(buy.tooltip_text, SimQuery.t_("reason.not_enough_gold"), "with the reason in the tooltip")
	check((p.row_of("iron", 0).get_node("Controls/Send") as MenuButton).disabled, "and no errand either")
	p.free()
	sim.state.families["fam_0001"]["gold"] = 100
	_at(sim, 2)
	p = _market(sim, "resources")
	check((p.get_node("%StatusLabel") as Label).visible, "closed at night: the reason is shown")
	eq((p.row_of("iron", 0).get_node("Controls/Buy") as Button).tooltip_text, SimQuery.t_("reason.market_closed"),
		"Buy says the market is closed")
	p.free()


func test_market_panel_sells_and_never_more_than_carried() -> void:
	var sim := _sim()
	_at(sim, 10)
	_add(sim.state.characters[HUGO]["inventory"], "sword", 0, 2)
	_add(sim.state.characters[HUGO]["inventory"], "sword", 1, 1)
	var ev := sim.step([{"type": "enter_building", "actor": HUGO, "building": ARMORY}])
	for i: int in 60:
		if str(sim.state.characters[HUGO]["location"]) == ARMORY:
			break
		ev.append_array(sim.step())
	eq(str(sim.state.characters[HUGO]["location"]), ARMORY, "Hugo walks into the armory (public shop)")
	eq(SimQuery.stall_at(sim, HUGO), "armory", "inside the armory = at its stall")
	var p := _market(sim, "armory")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	(p.get_node("%SellTab") as Button).pressed.emit()
	eq(p.tab, "sell", "the Sell tab")
	var row := p.row_of("sword", 0)
	check(row != null and (row.get_node("Name") as Label).text.ends_with("×2"), "2 normal swords to sell")
	(row.get_node("SellOne") as Button).pressed.emit()
	_same(got[0], {"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": 0, "qty": 1}, "sell 1")
	(p.row_of("sword", 1).get_node("SellAll") as Button).pressed.emit()
	_same(got[1], {"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": 1, "qty": 1},
		"sell all = what he carries of that quality")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes both sales")
	got.clear()
	p.refresh()
	row = p.row_of("sword", 0)
	check((row.get_node("Name") as Label).text.ends_with("×1"), "the list refreshes after the sale")
	(row.get_node("SellAll") as Button).pressed.emit()
	_same(got[0], {"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": 0, "qty": 1},
		"sell all asks only for the one left")
	sim.step(got)
	p.refresh()
	check(p.row_of("sword", 0) == null and p.row_of("sword", 1) == null, "nothing left: no Sell button")
	check((p.get_node("%Hint") as Label).visible, "the panel says there is nothing to sell")
	eq(_refusals(sim.step([{"type": "sell", "actor": HUGO, "stall": "armory", "item": "sword", "quality": 0,
		"qty": 1}]))[0]["reason"], "not_enough", "and the sim refuses selling what he does not have")
	p.free()


func test_market_panel_shows_sell_disabled_when_closed_and_closes_when_away() -> void:
	var sim := _sim()
	_at(sim, 10)
	_stand(sim, HUGO, RESOURCES_SERVICE)
	_add(sim.state.characters[HUGO]["inventory"], "iron", 0, 3)
	var p := _market(sim, "resources")
	p.show_tab("sell")
	check(not (p.row_of("iron", 0).get_node("SellOne") as Button).disabled, "open: Sell 1 enabled")
	_at(sim, 2)
	p.refresh()
	var one := p.row_of("iron", 0).get_node("SellOne") as Button
	check(one.disabled, "closed: Sell disabled")
	eq(one.tooltip_text, SimQuery.t_("reason.market_closed"), "with the reason")
	var closed := [false]
	p.closed.connect(func() -> void: closed[0] = true)
	check(p.still_there(), "still at the stall")
	_stand(sim, HUGO, Vector2i(20, 21))
	p._process(0.0)
	check(not p.visible and closed[0], "he walked away: the panel closes (GDD 4.5.2)")
	p.free()


func test_armory_is_entered_and_its_counter_opens_the_market() -> void:
	var sim := _sim()
	_at(sim, 10)
	sim.step([{"type": "enter_building", "actor": HUGO, "building": ARMORY}])
	for i: int in 60:
		if str(sim.state.characters[HUGO]["location"]) == ARMORY:
			break
		sim.step()
	var v: InteriorView = _scene("res://game/interior/interior_view.tscn")
	v.setup(sim, ARMORY, HUGO, false)
	eq(v.shop_stall, "armory", "the armory serves the armory stall")
	check(not (v.get_node("%StorageButton") as Button).visible, "a shop is not managed: no storage button")
	check((v.get_node("%ExitButton") as Button).visible, "only the way out")
	var asked: Array = []
	v.shop_requested.connect(func(a: String, s: String) -> void: asked.append([a, s]))
	check(_click(v, MOUSE_BUTTON_LEFT, v.station_screen("counter")), "a click on the counter")
	eq(asked, [[HUGO, "armory"]], "opens the market panel of the armory for Hugo")
	_click(v, MOUSE_BUTTON_RIGHT, v.station_screen("counter"))
	eq(asked.size(), 2, "the right click too")
	v.free()


# --- the board -----------------------------------------------------------------------------------------------------

func test_board_panel_accepts_delivers_and_abandons() -> void:
	var sim := _sim()
	_at(sim, 10)
	var defs: Array = cat.starts()["artisan_blacksmith"]["contracts"]
	Contracts.post_scripted(sim.state, cat, defs)
	_stand(sim, HUGO, BOARD_SERVICE)
	var p: BoardPanel = _scene("res://game/ui/board_panel.tscn")
	p.open_for(sim, HUGO)
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	var board: Array = sim.state.contracts["board"]
	eq(board.size(), 2, "the two scripted contracts are on the board")
	var hammers := str(board[0]["id"])
	var sword := str(board[1]["id"])
	var row := p.row_of(hammers, false)
	check(row != null, "a row per open contract")
	check((row.get_node("Bottom/Terms") as Label).text != "" and (row.get_node("Top/Pay") as Label).text.contains(str(int(board[0]["pay"]))),
		"terms and pay")
	(row.get_node("Bottom/Accept") as Button).pressed.emit()
	_same(got[0], {"type": "accept_contract", "actor": HUGO, "contract": hammers}, "accept")
	(p.row_of(sword, false).get_node("Bottom/Accept") as Button).pressed.emit()
	_same(got[1], {"type": "accept_contract", "actor": HUGO, "contract": sword}, "accept the second")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes both")
	got.clear()
	p.refresh()
	var mine := p.row_of(hammers, true)
	check(mine != null, "it moved to your contracts")
	var deliver := mine.get_node("Bottom/Deliver") as Button
	check(deliver.disabled, "without the hammers: Deliver disabled")
	eq(deliver.tooltip_text, SimQuery.t_("reason.missing_items"), "with the reason")
	_add(sim.state.characters[HUGO]["inventory"], "hammer", 0, 2)
	p.refresh()
	deliver = p.row_of(hammers, true).get_node("Bottom/Deliver") as Button
	check(not deliver.disabled, "with 2 hammers: Deliver enabled")
	deliver.pressed.emit()
	_same(got[0], {"type": "deliver_contract", "actor": HUGO, "contract": hammers}, "deliver")
	(p.row_of(sword, true).get_node("Bottom/Abandon") as Button).pressed.emit()
	_same(got[1], {"type": "abandon_contract", "actor": HUGO, "contract": sword}, "abandon")
	var gold := Money.gold(sim.state, "fam_0001")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes both")
	check(Money.gold(sim.state, "fam_0001") > gold, "the delivered contract is paid")
	p.refresh()
	check(p.row_of(hammers, true) == null and p.row_of(sword, true) == null, "both closed")
	_stand(sim, HUGO, Vector2i(20, 21))
	p._process(0.0)
	check(not p.visible, "left the board: the panel closes")
	p.free()


# --- the account book ----------------------------------------------------------------------------------------------

func _started() -> WorldState:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"name": "Hugo", "female": false,
		"family_name": "Herrero", "colors": {"primary": "#8b2e2e", "secondary": "#c8a84e"}, "stats_add": {}}, 7)
	check(bool(r.get("ok", false)), "from_start works: %s" % r.get("error", ""))
	return r["state"]


func test_ledger_panel_repays_the_debt_and_reads_notices() -> void:
	var sim := Sim.new(_started(), cat)
	var fam := SimQuery.player_family(sim.state)
	var who := SimQuery.family_actor(sim.state, fam)
	var loans := Loans.of_family(sim, fam)
	eq(loans.size(), 1, "the start brings its debt")
	var loan := str(loans[0])
	sim.state.families[fam]["gold"] = 500
	var p: LedgerPanel = _scene("res://game/ui/ledger_panel.tscn")
	p.open_for(sim, fam, who, "debts")
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	var pay := p.row_of(loan + "_pay")
	check(pay != null, "a payment row for the loan")
	(pay.get_node("Amount") as SpinBox).value = 50
	(pay.get_node("Pay") as Button).pressed.emit()
	_same(got[0], {"type": "repay_loan", "actor": who, "loan": loan, "amount": 50}, "pay an amount")
	eq(_refusals(sim.step(got)).size(), 0, "the sim takes it")
	var owed := int(Loans.status(sim, loan)["outstanding"])
	eq(owed, 150, "150 left of 200")
	got.clear()
	p.refresh()
	(p.row_of(loan + "_pay").get_node("PayAll") as Button).pressed.emit()
	_same(got[0], {"type": "repay_loan", "actor": who, "loan": loan, "amount": owed}, "pay it all")
	eq(_refusals(sim.step(got)).size(), 0, "paid")
	got.clear()
	for t: String in LedgerPanel.TABS:
		p.show_tab(t)
		check(p.tab == t, "tab %s" % t)
	got.clear()
	p.show_tab("today")
	check(p.row_of("loans") != null, "today shows the debt payments in their category")
	var n := Notices.add(sim, fam, "urgent", "notice.objective_done", {"objective": "forge_sword"}, FORGE_OF(sim, fam))
	p.show_tab("notices")
	_same(got[0], {"type": "read_notices", "actor": who, "ids": got[0]["ids"]}, "showing the notices reads them")
	check(n in (got[0]["ids"] as Array), "including the new one")
	var clicked: Array = []
	p.notice_clicked.connect(func(x: Dictionary) -> void: clicked.append(x))
	(p.row_of(n) as Button).pressed.emit()
	eq(str(clicked[0]["id"]), n, "a click on a notice tells the HUD (centre the camera)")
	eq(_refusals(sim.step(got)).size(), 0, "read")
	eq(Notices.list(sim, fam, true).size(), 0, "no unread notices left")
	p.free()


func FORGE_OF(sim: Sim, fam: String) -> String:
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["owner"]) == fam:
			return b
	return ""


func test_ledger_pay_all_disabled_without_gold() -> void:
	var sim := Sim.new(_started(), cat)
	var fam := SimQuery.player_family(sim.state)
	var loan := str(Loans.of_family(sim, fam)[0])
	var p: LedgerPanel = _scene("res://game/ui/ledger_panel.tscn")
	p.open_for(sim, fam, SimQuery.family_actor(sim.state, fam), "debts")
	var all := p.row_of(loan + "_pay").get_node("PayAll") as Button
	check(all.disabled, "30 gold cannot pay 200")
	eq(all.tooltip_text, SimQuery.t_("reason.not_enough_gold"), "with the reason")
	p.free()


# --- new game and ending -------------------------------------------------------------------------------------------

func test_new_game_screen_calls_from_start_with_the_choices() -> void:
	var s: NewGameScreen = _scene("res://game/ui/new_game_screen.tscn")
	s.setup(cat, 42)
	eq(s.points_left(), 5, "5 free points (D5)")
	var calls: Array = []
	s.from_start = func(c: Catalog, start: String, diff: String, ch: Dictionary, sd: int) -> Dictionary:
		calls.append([c, start, diff, ch, sd])
		return NewGame.from_start(c, start, diff, ch, sd)
	var started: Array = []
	s.started.connect(func(st: WorldState) -> void: started.append(st))
	(s.get_node("%NameEdit") as LineEdit).text = "Marta"
	(s.get_node("%FamilyEdit") as LineEdit).text = "Ferran"
	(s.get_node("%Female") as Button).pressed.emit()
	((s.get_node("%Difficulty") as HBoxContainer).get_node("Hard") as Button).pressed.emit()
	for i: int in 3:
		((s.get_node("%Stats") as GridContainer).get_node("craft_plus") as Button).pressed.emit()
	for i: int in 2:
		check(s.add_point("charisma", 1), "a point on charisma")
	eq(s.points_left(), 0, "all spent")
	check(((s.get_node("%Stats") as GridContainer).get_node("negotiation_plus") as Button).disabled, "+ disabled with 0 left")
	check(not s.add_point("negotiation", 1), "a sixth point is refused")
	check(s.add_point("charisma", -1), "a point back")
	check(s.add_point("negotiation", 1), "and spent elsewhere")
	check(not s.add_point("arcane", -1), "never below the base")
	((s.get_node("%Primary") as HBoxContainer).get_node("2e4f8b") as Button).pressed.emit()
	((s.get_node("%Secondary") as HBoxContainer).get_node("e0e0d0") as Button).pressed.emit()
	(s.get_node("%StartButton") as Button).pressed.emit()
	eq(calls.size(), 1, "from_start called once")
	eq(calls[0][1], "artisan_blacksmith", "the start")
	eq(calls[0][2], "hard", "the difficulty chosen")
	eq(calls[0][4], 42, "the seed")
	_same(calls[0][3], {"name": "Marta", "female": true, "family_name": "Ferran",
		"colors": {"primary": "#2e4f8b", "secondary": "#e0e0d0"},
		"stats_add": {"craft": 3, "charisma": 1, "negotiation": 1}}, "what was chosen, 5 points")
	eq(started.size(), 1, "the game starts with the state")
	if not started.is_empty():
		var st: WorldState = started[0]
		eq(st.difficulty, "hard", "a hard game")
		var fam := SimQuery.player_family(st)
		eq(str(st.families[fam]["name"]), "Ferran", "the family name")
	s.free()


func test_new_game_screen_needs_names() -> void:
	var s: NewGameScreen = _scene("res://game/ui/new_game_screen.tscn")
	s.setup(cat, 1)
	var calls: Array = []
	s.from_start = func(_c: Catalog, _a: String, _b: String, _ch: Dictionary, _sd: int) -> Dictionary:
		calls.append(1)
		return {"ok": false, "error": "x"}
	(s.get_node("%NameEdit") as LineEdit).text = "  "
	s.start_game()
	eq(calls.size(), 0, "no name: not even asked")
	check((s.get_node("%ErrorLabel") as Label).visible, "says why")
	(s.get_node("%NameEdit") as LineEdit).text = "Ana"
	s.start_game()
	eq(calls.size(), 1, "asked")
	check((s.get_node("%ErrorLabel") as Label).visible, "a refused start shows its error")
	s.free()


func test_new_game_is_the_default_start() -> void:
	var GameScript: GDScript = load("res://game/autoload/game.gd")
	check(bool(GameScript.parse_args(PackedStringArray([]))["new_game"]), "no options: the new game screen")
	check(not bool(GameScript.parse_args(PackedStringArray(["--scenario=town_e_start"]))["new_game"]), "--scenario: straight in")
	check(not bool(GameScript.parse_args(PackedStringArray(["--smoke", "--shots=2"]))["new_game"]), "smoke: straight in")
	check(not bool(GameScript.parse_args(PackedStringArray(["--smoke-script=forja"]))["new_game"]), "smoke script: straight in")
	check(bool(GameScript.parse_args(PackedStringArray(["--smoke", "--new-game"]))["new_game"]), "--new-game forces it")


func test_ending_screen_shows_the_ruin() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	sim.state.ending = {"kind": "ruin", "family": "fam_0001", "minute": 9 * Clock.MINUTES_PER_DAY + 600}
	var e: EndingScreen = _scene("res://game/ui/ending_screen.tscn")
	e.show_ending(sim.state)
	check(e.visible, "shown")
	eq((e.get_node("%Title") as Label).text, "Ruina", "the ruin")
	check((e.get_node("%Body") as Label).text.contains("Herrero"), "names the family")
	check((e.get_node("%Summary") as Label).text.contains("10"), "the day")
	var pressed: Array = []
	e.new_game_pressed.connect(func() -> void: pressed.append(1))
	(e.get_node("%NewGameButton") as Button).pressed.emit()
	eq(pressed.size(), 1, "New game")
	TranslationServer.set_locale(before)
	e.free()


# --- texts ---------------------------------------------------------------------------------------------------------

func test_notice_text_and_queue_labels() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	var t := SimQuery.notice_text(sim.state, cat, {"key": "notice.objective_done", "params": {"objective": "forge_sword"}})
	eq(t, "Objetivo cumplido: Funde dos lingotes y forja una espada", "the notice with names, not ids")
	eq(SimQuery.order_label(sim.state, cat, {"type": "buy", "actor": HUGO, "stall": "resources", "item": "iron",
		"quality": 0, "qty": 2, "deliver_to": FORGE}), "Comprar 2 Hierro → Forja", "a queued errand")
	TranslationServer.set_locale(before)
