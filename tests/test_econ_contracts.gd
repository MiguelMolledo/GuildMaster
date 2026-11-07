extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## NPC contracts (GDD 4.5.6, docs/contratos/h3_mercado.md): board, accept, deliver, abandon, expiry, warnings, save.
## The rival is switched off here (no ai_profile) so it does not take the contracts of the test.

var cat := Pins.prices(Catalog.load_from())  # the sword at 65: see tests/balance_pins.gd

const HUGO := "chr_0001"
const ELENA := "chr_0002"
const BERNAT := "chr_0006"


func _sim() -> Sim:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	sim.state.families["fam_0003"]["ai_profile"] = ""
	return sim


func _to_board(sim: Sim, actor: String) -> void:
	var ch: Dictionary = sim.state.characters[actor]
	var svc := Contracts.board_service(sim)
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["position"] = [int(svc[0]), int(svc[1])]


func _post(sim: Sim, item: String, qty: int, min_q: int, days: int, client: String = "carpenter") -> String:
	return Contracts.post(sim, {"client": client, "item": item, "qty": qty, "min_quality": min_q,
		"deadline_days": days})


func _accept(sim: Sim, actor: String, id: String) -> Dictionary:
	return Orders.apply(sim, {"type": "accept_contract", "actor": actor, "contract": id})


func _deliver(sim: Sim, actor: String, id: String) -> Dictionary:
	return Orders.apply(sim, {"type": "deliver_contract", "actor": actor, "contract": id})


func test_pay_is_fixed_when_posted() -> void:
	var sim := _sim()
	var id := _post(sim, "sword", 3, 1, 2)
	var c: Dictionary = sim.state.contracts["board"][0]
	eq(str(c["id"]), id, "on the board")
	eq(int(c["pay"]), roundi(3 * Market.price(sim, "sword", 1, "sell") * 1.4), "qty × sell price × 1.4")
	sim.state.market["demand"]["sword"] = 0.6
	eq(int(c["pay"]), roundi(3 * 59 * 1.4), "does not move with the demand afterwards (sword good = 59)")


func test_deliver_pays_and_gives_reputation() -> void:
	var sim := _sim()
	var id := _post(sim, "hammer", 2, 0, 2)
	var pay := int(sim.state.contracts["board"][0]["pay"])
	eq(pay, roundi(2 * Market.price(sim, "hammer", 0, "sell") * 1.4), "pay formula")
	_to_board(sim, HUGO)
	check(_accept(sim, HUGO, id)["ok"], "accepts at the board")
	var bag: Dictionary = sim.state.characters[HUGO]["inventory"]
	Inventory.add(bag, cat, "hammer", Inventory.NORMAL, 1)
	eq(_deliver(sim, HUGO, id)["reason"], "missing_items", "one hammer is not enough")
	Inventory.add(bag, cat, "hammer", Inventory.GOOD, 1)
	Inventory.add(bag, cat, "hammer", Inventory.NORMAL, 1)
	var gold := Money.gold(sim.state, "fam_0001")
	var demand := Market.demand(sim, "hammer")
	sim.events = []
	check(_deliver(sim, HUGO, id)["ok"], "delivers")
	eq(Money.gold(sim.state, "fam_0001") - gold, pay, "pays qty × sell × 1.4")
	eq(int(sim.state.families["fam_0001"]["reputation"]), 2, "+2 reputation")
	eq(Contracts.relation(sim, "fam_0001", "carpenter"), 5, "+5 relation with the client")
	eq(Inventory.count(bag, "hammer", Inventory.NORMAL), 0, "the normal ones went first")
	eq(Inventory.count(bag, "hammer", Inventory.GOOD), 1, "the good one stays")
	near(Market.demand(sim, "hammer"), demand, 0.0001, "the demand does not change")
	var last: Dictionary = sim.state.ledger["entries"][-1]
	eq([str(last["category"]), int(last["amount"]), str(last["ref"])], ["contracts", pay, id], "ledger: contracts")
	check((sim.state.contracts["accepted"] as Array).is_empty(), "closed")
	var types: Array = sim.events.map(func(e: Dictionary) -> String: return str(e["type"]))
	check("contract_delivered" in types and "reputation_changed" in types, "events")


func test_minimum_quality_counts() -> void:
	var sim := _sim()
	var id := _post(sim, "sword", 1, 1, 3, "guard_captain")
	_to_board(sim, HUGO)
	_accept(sim, HUGO, id)
	var bag: Dictionary = sim.state.characters[HUGO]["inventory"]
	Inventory.add(bag, cat, "sword", Inventory.NORMAL, 1)
	eq(_deliver(sim, HUGO, id)["reason"], "missing_items", "a normal sword is not good")
	Inventory.add(bag, cat, "sword", Inventory.EXCELLENT, 1)
	check(_deliver(sim, HUGO, id)["ok"], "an excellent one is")
	eq(Inventory.count(bag, "sword"), 1, "the normal one stays")


func test_accept_rules() -> void:
	var sim := _sim()
	var a := _post(sim, "hammer", 1, 0, 1)
	var b := _post(sim, "hammer", 1, 0, 1, "farmer")
	var c := _post(sim, "sword", 1, 0, 1, "innkeeper")
	eq(_accept(sim, HUGO, a)["reason"], "not_at_board", "far from the board")
	eq(_accept(sim, HUGO, "ctr_9999")["reason"], "unknown_contract", "unknown")
	_to_board(sim, HUGO)
	_to_board(sim, ELENA)
	_to_board(sim, BERNAT)
	check(_accept(sim, HUGO, a)["ok"], "first")
	eq(_accept(sim, BERNAT, a)["reason"], "contract_taken", "the first who accepts keeps it")
	check(_accept(sim, ELENA, b)["ok"], "second for the family (another member)")
	eq(_accept(sim, HUGO, c)["reason"], "too_many_contracts", "at most 2 per family")
	check(_accept(sim, BERNAT, c)["ok"], "another family may")
	eq(_deliver(sim, BERNAT, a)["reason"], "not_your_contract", "not his")
	eq(Orders.apply(sim, {"type": "abandon_contract", "actor": BERNAT, "contract": a})["reason"], "not_your_contract",
		"cannot abandon another's")
	var c0: Dictionary = Contracts.accepted_of(sim, "fam_0001")[0]
	eq(int(c0["due"]), int(c0["accepted"]) + Clock.MINUTES_PER_DAY, "deadline counts from acceptance")
	var view := Contracts.board_view(sim, HUGO)
	check(view["at_board"], "view: at the board")
	eq((view["accepted"] as Array).size(), 2, "view: the family's two")
	eq(str(view["accepted"][0]["status"]), "missing_items", "view: nothing to deliver")
	eq(int(view["accepted"][0]["hours_left"]), 24, "view: hours left")


func test_expiry_costs_reputation_and_relation() -> void:
	var sim := _sim()
	var id := _post(sim, "sword", 1, 0, 2, "farmer")
	_to_board(sim, HUGO)
	_accept(sim, HUGO, id)
	var due := int(Contracts.accepted_of(sim, "fam_0001")[0]["due"])
	var warned: Array = []
	var failed := []
	while int(sim.state.clock["minute"]) < due + 2:
		for e: Dictionary in sim.step():
			if str(e["type"]) == "notice_added" and str(e["key"]) == "notice.contract_due":
				warned.append([int(e["params"]["hours"]), due - int(sim.state.clock["minute"]), str(e["severity"])])
			if str(e["type"]) == "contract_failed":
				failed.append(e)
	eq(warned, [[24, 24 * 60, "warning"], [2, 2 * 60, "urgent"]], "warned 1 day and 2 h before")
	eq(failed.size(), 1, "expired once")
	eq(str(failed[0]["reason"]), "expired", "reason")
	eq(int(sim.state.families["fam_0001"]["reputation"]), -5, "−5 reputation")
	eq(Contracts.relation(sim, "fam_0001", "farmer"), -15, "−15 relation")
	check((sim.state.contracts["accepted"] as Array).is_empty(), "closed")
	eq(int(sim.state.contracts["cooldowns"]["farmer"]), Clock.day(due) + 8, "the client posts nothing for 1 year")


func test_abandon_counts_as_failed() -> void:
	var sim := _sim()
	var id := _post(sim, "hammer", 1, 0, 3, "innkeeper")
	_to_board(sim, HUGO)
	_accept(sim, HUGO, id)
	sim.state.characters[HUGO]["position"] = [20, 21]
	check(Orders.apply(sim, {"type": "abandon_contract", "actor": HUGO, "contract": id})["ok"], "from anywhere")
	eq(int(sim.state.families["fam_0001"]["reputation"]), -5, "−5 reputation")
	eq(Contracts.relation(sim, "fam_0001", "innkeeper"), -15, "−15 relation")
	check(sim.state.contracts["cooldowns"].has("innkeeper"), "cooldown")


func test_board_fills_at_dawn_up_to_three() -> void:
	# H13: without global events (seed 1 rolls a war on day 4: swords ×2 would change the price after posting).
	var quiet := Catalog.load_from()
	quiet.events["enabled"] = false
	quiet.festivals["enabled"] = false  # fiestas: the daily board alone (the feasts post their own contracts)
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], quiet)
	sim.state.families["fam_0003"]["ai_profile"] = ""
	var posted := 0
	for d: int in 5:
		for e: Dictionary in _run_day(sim):
			if str(e["type"]) == "contract_posted":
				posted += 1
	eq(posted, 3, "one per dawn while there is room")
	eq((sim.state.contracts["board"] as Array).size(), 3, "never more than 3 open")
	for c: Dictionary in sim.state.contracts["board"]:
		check(int(c["qty"]) >= 1 and int(c["deadline_days"]) in [1, 2, 3], "qty and deadline in range (%s)" % c["id"])
		check(int(c["min_quality"]) in [0, 1, 2], "quality")
		eq(int(c["pay"]), roundi(int(c["qty"]) * Market.price(sim, str(c["item"]), int(c["min_quality"]), "sell") * 1.4),
			"pay of %s (no sales happened)" % c["id"])


func test_clients_on_cooldown_post_nothing() -> void:
	var sim := _sim()
	for cl: String in ["carpenter", "guard_captain", "farmer", "innkeeper"]:
		sim.state.contracts["cooldowns"][cl] = 99
	eq(Contracts.post_random(sim), "", "nobody to post")
	sim.state.contracts["cooldowns"]["farmer"] = 0
	var id := Contracts.post_random(sim)
	eq(str(sim.state.contracts["board"][0]["client"]), "farmer", "only the free one (%s)" % id)


func test_scripted_contracts_for_the_start() -> void:
	var st: WorldState = NewGame.from_scenario("town_e_start", 1)["state"]
	var defs: Array = cat.starts()["artisan_blacksmith"]["contracts"]
	var ids := Contracts.post_scripted(st, cat, defs)
	eq(ids.size(), 2, "two posted")
	eq(str(st.contracts["board"][0]["script"]), "carpenter_hammers", "with their script id")
	eq(int(st.contracts["board"][1]["min_quality"]), 1, "the good sword")


func test_save_round_trip_with_accepted_contracts() -> void:
	var sim := _sim()
	var a := _post(sim, "hammer", 2, 0, 2)
	_post(sim, "sword", 1, 1, 3, "guard_captain")
	_to_board(sim, HUGO)
	_accept(sim, HUGO, a)
	sim.run_minutes(30 * 60)  # past the 24 h warning
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(sim.state.to_dict()), "same content")
	var sim2 := Sim.new(back, cat)
	sim.run_minutes(Clock.MINUTES_PER_DAY)
	sim2.run_minutes(Clock.MINUTES_PER_DAY)
	eq(sim2.state_hash(), sim.state_hash(), "the loaded game goes on the same (warnings, expiry)")
	eq(int(sim2.state.families["fam_0001"]["reputation"]), -5, "it expired after loading")


func _run_day(sim: Sim) -> Array:
	var all: Array = []
	for i: int in Clock.MINUTES_PER_DAY:
		all.append_array(sim.step())
	return all
