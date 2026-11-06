extends "res://tests/test_case.gd"
## H12.2 · the Loan grows (docs/gdd/04d_otras_clases.md 4.22.5.6, P8; O12 a; sim/econ/loans.gd): the town's
## moneylender lends to any family up to half its estimated wealth, at 25 % a year prorated to the term, in equal
## installments every 2 days; a payment covers the installments in order; an installment unpaid on its day is the
## extension of 4.16; and the debt of the start keeps its single payment and no interest.

const FAM := "fam_0001"
const HUGO := "chr_0001"
const START := "lon_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func _ask(sim: Sim, amount: int, term: int) -> Dictionary:
	return Orders.apply(sim, {"type": "request_loan", "actor": HUGO, "lender": "moneylender", "amount": amount,
		"term_days": term})


func _new_loan(sim: Sim) -> String:
	for id: String in Loans.of_family(sim, FAM):
		if str(sim.state.loans[id].get("kind", "")) == "moneylender":
			return id
	return ""


func _pay_start(sim: Sim) -> void:
	sim.state.families[FAM]["gold"] = 500
	check(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": START, "amount": 200})["ok"],
		"setup: the start's debt paid")
	sim.state.families[FAM]["gold"] = 30


func test_the_start_debt_does_not_change() -> void:
	var sim := _sim()
	var l: Dictionary = sim.state.loans[START]
	check(not l.has("installments") or (l["installments"] as Array).is_empty(), "no installments")
	eq(float(l.get("interest", 0.0)), 0.0, "no interest")
	var s := Loans.status(sim, START)
	eq([int(s["next_due"]), int(s["next_amount"]), str(s["kind"])], [int(l["due_minute"]), 200, ""],
		"one payment of all it owes, at its due date")


func test_a_loan_from_the_moneylender() -> void:
	var sim := _sim()
	_pay_start(sim)
	var lim := Loans.borrow_limit(sim, FAM)
	eq(str(lim["reason"]), "", "it may ask")
	check(int(lim["max"]) >= 60, "half of its wealth (%d)" % int(lim["max"]))
	var gold0 := Money.gold(sim.state, FAM)
	var r := _ask(sim, 60, 8)
	check(r["ok"], "lends: %s" % r["reason"])
	var id := _new_loan(sim)
	var l: Dictionary = sim.state.loans[id]
	eq(Money.gold(sim.state, FAM), gold0 + 60, "60 gold now")
	near(float(l["interest"]), 0.25, 0.0001, "8 days = a year: 25 %")
	eq(int(l["outstanding"]), 75, "75 owed")
	var amounts: Array = (l["installments"] as Array).map(func(i: Dictionary) -> int: return int(i["amount"]))
	eq(amounts, [18, 18, 18, 21], "four installments, the last one with the rest")
	var now := int(sim.state.clock["minute"])
	eq(int((l["installments"] as Array)[0]["due_minute"]), now + 2 * Clock.MINUTES_PER_DAY, "the first in 2 days")
	eq(str(l["collateral"]["kind"]), "building", "a building answers for it")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([str(e["category"]), int(e["amount"])], ["loans", 60], "a loans entry")


func test_the_limits() -> void:
	var sim := _sim()
	eq(_ask(sim, 60, 5)["reason"], "bad_term", "8 or 16 days")
	eq(_ask(sim, 5, 8)["reason"], "bad_amount", "at least 20")
	var lim := int(Loans.borrow_limit(sim, FAM)["max"])
	eq(_ask(sim, lim + 1, 8)["reason"], "over_limit", "not more than half its wealth")
	eq(Orders.apply(sim, {"type": "request_loan", "actor": HUGO, "lender": "fam_0002", "amount": 30,
		"term_days": 8})["reason"], "unknown_lender", "no family's bank yet")
	check(_ask(sim, 30, 16)["ok"], "a first one")
	near(float(sim.state.loans[_new_loan(sim)]["interest"]), 0.5, 0.0001, "16 days = two years: 50 %")
	eq(_ask(sim, 30, 8)["reason"], "has_moneylender_loan", "one at a time")


func test_no_loan_in_default() -> void:
	var sim := _sim()
	sim.state.clock["minute"] = int(sim.state.loans[START]["due_minute"])
	sim.step()
	eq(str(sim.state.loans[START]["state"]), "extended", "setup: the start debt in its extension")
	eq(_ask(sim, 30, 8)["reason"], "in_default", "not with a loan in default")


func test_installments_in_order_and_a_missed_one() -> void:
	var sim := _sim()
	_pay_start(sim)
	check(_ask(sim, 60, 8)["ok"], "setup: a loan")
	var id := _new_loan(sim)
	sim.state.families[FAM]["gold"] = 100
	check(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": id, "amount": 20})["ok"], "pays 20")
	var inst: Array = sim.state.loans[id]["installments"]
	eq([int(inst[0]["paid"]), int(inst[1]["paid"])], [18, 2], "the first covered and 2 of the second")
	var s := Loans.status(sim, id)
	eq([int(s["next_due"]), int(s["next_amount"]), int(s["installments_left"])],
		[int(inst[1]["due_minute"]), 16, 3], "the next one: 16 left of the second")
	var rep0 := int(sim.state.families[FAM].get("reputation", 0))
	sim.state.families[FAM]["gold"] = 0
	sim.state.clock["minute"] = int(inst[1]["due_minute"]) - 1
	sim.step()
	sim.step()
	var l: Dictionary = sim.state.loans[id]
	eq(str(l["state"]), "extended", "the second unpaid on its day: the extension")
	eq(int(l["outstanding"]), roundi(55 * 1.25), "the surcharge over what was owed")
	check((l["installments"] as Array).is_empty(), "all owed at the new date")
	eq(int(sim.state.families[FAM]["reputation"]), rep0 - 10, "the reputation of a debt overdue")
	eq(int(l["due_minute"]), int(inst[1]["due_minute"]) + int(cat.time["days_per_season"]) * Clock.MINUTES_PER_DAY,
		"one season after the missed installment")


func test_paid_in_full() -> void:
	var sim := _sim()
	_pay_start(sim)
	check(_ask(sim, 40, 8)["ok"], "setup: a loan")
	var id := _new_loan(sim)
	sim.state.families[FAM]["gold"] = 200
	check(Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": id, "amount": 999})["ok"], "pays it all")
	eq([str(sim.state.loans[id]["state"]), int(sim.state.loans[id]["outstanding"])], ["paid", 0], "paid")
	eq(str(Loans.borrow_limit(sim, FAM)["reason"]), "", "it may ask again")


func test_a_saved_loan() -> void:
	var sim := _sim()
	_pay_start(sim)
	check(_ask(sim, 40, 16)["ok"], "setup: a loan")
	var back: WorldState = SaveFile.from_text(JSON.stringify(sim.state.to_dict()))["state"]
	var b := Sim.new(back, cat)
	var id := _new_loan(sim)
	eq(SaveFile.canonical(back.loans[id]), SaveFile.canonical(sim.state.loans[id]), "the loan survives the save")
	eq(Loans.status(b, id), Loans.status(sim, id), "and reads the same")
