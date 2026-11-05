extends "res://tests/test_case.gd"
## The start debt (GDD 4.16, D18): repaying in parts or whole, urgent notices 2 and 1 days before, the extension
## with its surcharge and reputation loss, the seizure (gold, then goods at sell price) and the ruin.

const FAM := "fam_0001"
const HUGO := "chr_0001"
const FORGE := "bld_0001"
const LOAN := "lon_0001"

var cat := Catalog.load_from()


func _sim(difficulty: String = "normal") -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", difficulty, {"cast": "fixed"}, 1)["state"], cat)


func _loan(sim: Sim) -> Dictionary:
	return sim.state.loans[LOAN]


func _keys(sim: Sim) -> Array:
	return Notices.list(sim, FAM).map(func(n: Dictionary) -> String: return n["key"])


func test_start_loan() -> void:
	var sim := _sim()
	eq(Loans.of_family(sim, FAM), [LOAN], "one open loan")
	var s := Loans.status(sim, LOAN)
	eq([int(s["principal"]), int(s["outstanding"]), int(s["due_minute"]), s["extended"], s["state"], int(s["days_left"])],
		[200, 200, 8 * Clock.MINUTES_PER_DAY, false, "active", 8], "200 due at the end of day 8")
	eq(Money.gold(sim.state, FAM), 30, "the loan brings no gold")
	check(sim.state.ledger["entries"].is_empty(), "nor an entry")
	eq(Loans.status(sim, "lon_0099"), {}, "unknown")


func test_repay_in_parts_then_whole() -> void:
	var sim := _sim()
	var r := Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 20})
	check(r["ok"], "pays a part: %s" % r["reason"])
	eq([int(_loan(sim)["outstanding"]), Money.gold(sim.state, FAM)], [180, 10], "180 left, 10 gold")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([e["category"], int(e["amount"]), e["ref"], e["actor"]], ["loans", -20, LOAN, HUGO], "a loans entry")
	var pay: Array = sim.events.filter(func(x: Dictionary) -> bool: return x["type"] == "loan_payment")
	eq(pay[0], {"type": "loan_payment", "actor": HUGO, "family": FAM, "loan": LOAN, "amount": 20, "outstanding": 180},
		"event")
	var h := sim.state_hash()
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 50})["reason"],
		"not_enough_gold", "only 10 gold")
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 0})["reason"], "bad_amount", "0")
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": "lon_0099", "amount": 5})["reason"],
		"unknown_loan", "unknown loan")
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": "chr_0002", "loan": LOAN, "amount": 5})["reason"],
		"not_your_loan", "Bernat (the rival) cannot pay it")
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": "nobody", "loan": LOAN, "amount": 5})["reason"],
		"unknown_actor", "nobody")
	eq(sim.state_hash(), h, "refusals change nothing")
	Money.change(sim, FAM, 500, Money.MARKET_SALES, "test")
	sim.events = []
	check(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 999})["ok"], "pays all")
	eq([int(_loan(sim)["outstanding"]), str(_loan(sim)["state"]), Money.gold(sim.state, FAM)], [0, "paid", 330],
		"only what was owed")
	var done: Array = sim.events.filter(func(x: Dictionary) -> bool: return x["type"] == "loan_repaid")
	eq(done[0], {"type": "loan_repaid", "actor": HUGO, "family": FAM, "loan": LOAN, "extended": false}, "repaid")
	check("notice.loan_repaid" in _keys(sim), "a notice")
	eq(Loans.of_family(sim, FAM), [], "no open loans")
	eq(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 5})["reason"], "loan_closed",
		"closed")


func test_warnings_two_and_one_days_before() -> void:
	var sim := _sim()
	var due := int(_loan(sim)["due_minute"])
	sim.state.clock["minute"] = due - 2 * Clock.MINUTES_PER_DAY - 2
	sim.step()
	check(not "notice.loan_due_soon" in _keys(sim), "not yet")
	sim.step()
	sim.step()
	var n: Array = Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.loan_due_soon")
	eq([n[0]["key"], n[0]["severity"], int(n[0]["params"]["days"]), int(n[0]["params"]["amount"])],
		["notice.loan_due_soon", "urgent", 2, 200], "2 days before (03b: the unlock notices of day 7 may come too)")
	sim.state.clock["minute"] = due - Clock.MINUTES_PER_DAY
	sim.step()
	sim.step()
	eq(_keys(sim).count("notice.loan_due_soon"), 2, "and 1 day before, once each")
	eq(int(Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.loan_due_soon")[0][
		"params"]["days"]), 1, "1 day")


func test_extension_with_surcharge() -> void:
	var sim := _sim()
	Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 20})
	var due := int(_loan(sim)["due_minute"])
	sim.state.clock["minute"] = due - 1
	sim.step()
	var l := _loan(sim)
	eq([int(l["outstanding"]), l["extended"], str(l["state"])], [225, true, "extended"], "180 × 1.25, extended")
	eq(int(l["due_minute"]), due + 2 * Clock.MINUTES_PER_DAY, "one season (2 days) more")
	eq(int(sim.state.families[FAM]["reputation"]), -10, "reputation −10")
	check(sim.events.any(func(x: Dictionary) -> bool: return x["type"] == "loan_extended" and int(x["outstanding"]) == 225),
		"loan_extended")
	check(sim.events.any(func(x: Dictionary) -> bool: return x["type"] == "reputation_changed" and int(x["amount"]) == -10),
		"reputation_changed")
	check("notice.loan_extended" in _keys(sim), "urgent notice")
	sim.step()
	check("notice.loan_extension_due_soon" in _keys(sim), "the extension's own 2-day warning")
	Money.change(sim, FAM, 300, Money.MARKET_SALES, "test")
	sim.events = []
	Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": LOAN, "amount": 225})
	check(sim.events.any(func(x: Dictionary) -> bool: return x["type"] == "loan_repaid" and x["extended"] == true),
		"repaid late: extended (the objective wants it on time)")


func test_seizure_takes_gold_then_goods() -> void:
	var sim := _sim()
	var l := _loan(sim)
	l["state"] = "extended"
	l["extended"] = true
	l["outstanding"] = 40
	var price := Market.price(sim, "iron", 0, "sell")
	check(price > 0, "iron has a sell price")
	sim.state.clock["minute"] = int(l["due_minute"]) - 1
	sim.step()
	eq(Money.gold(sim.state, FAM), 0, "all the gold (30)")
	var units := ceili(10.0 / price)
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron"), 8 - units, "then iron for the 10 left")
	eq(str(l["state"]), "seized", "closed by seizure")
	eq(int(l["outstanding"]), 0, "nothing owed")
	check(sim.state.ending.is_empty(), "no ruin")
	var ev: Array = sim.events.filter(func(x: Dictionary) -> bool: return x["type"] == "loan_seized")
	eq([int(ev[0]["gold"]), ev[0]["items"]], [30, [{"item": "iron", "quality": 0, "qty": units, "value": units * price}]],
		"what was taken")
	check("notice.loan_seized" in _keys(sim), "notice")
	eq(Money.gold(sim.state, FAM) - 30, Ledger.total(sim.state, FAM), "the ledger adds up")


func test_ruin_when_seizure_falls_short() -> void:
	var sim := _sim()
	var l := _loan(sim)
	l["state"] = "extended"
	l["extended"] = true
	l["outstanding"] = 250
	sim.state.clock["minute"] = int(l["due_minute"]) - 1
	sim.step()
	eq(Money.gold(sim.state, FAM), 0, "the gold goes")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron"), 0, "and the iron")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "coal"), 0, "and the coal")
	eq(str(l["state"]), "seized", "closed")
	check(int(l["outstanding"]) > 0, "still owed")
	eq([sim.state.ending.get("kind"), sim.state.ending.get("family")], ["ruin", FAM], "the game ends in ruin")
	check(sim.events.any(func(x: Dictionary) -> bool: return x == {"type": "game_over", "kind": "ruin", "family": FAM}),
		"game_over")
	check("notice.ruin" in _keys(sim), "notice")
	var again := sim.events.size()
	sim.step()
	check(not sim.events.any(func(x: Dictionary) -> bool: return x["type"] == "game_over"), "only once (%d)" % again)


func test_debt_scenarios() -> void:
	var r := NewGame.from_scenario("debt_due", 1)
	check(r["ok"], "debt_due loads")
	var sim := Sim.new(r["state"], cat)
	sim.run_minutes(120)
	eq(str(_loan(sim)["state"]), "extended", "debt_due: the debt falls due and is extended")
	eq(int(_loan(sim)["outstanding"]), 250, "with the 25 % surcharge")
	r = NewGame.from_scenario("debt_extension_due", 1)
	check(r["ok"], "debt_extension_due loads")
	sim = Sim.new(r["state"], cat)
	sim.run_minutes(120)
	eq(str(_loan(sim)["state"]), "seized", "debt_extension_due: seizure")
	eq(sim.state.ending.get("kind"), "ruin", "and ruin")
