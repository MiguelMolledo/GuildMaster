extends "res://tests/test_case.gd"
## H5 «arbol» (docs/contratos/h5_mejoras.md): Inspections.step — the dawn roll with state.rng, the fine (Money,
## category fines) and reputation, the hidden passage with its cooldown, the unpayable fine as debt with the town,
## determinism with a seed, and the memory through save/load.

const FORGE: String = "bld_0001"
const FAM: String = "fam_0001"

var cat := Catalog.load_from()


func _sim(seed: int = 1, risk: float = -1.0) -> Sim:
	var c := cat
	if risk >= 0.0:
		c = Catalog.load_from()  # its own copy: the test changes the risk of Doble contabilidad
		c.tables["upgrades"]["forge_secrets_1"]["effects"] = [{"kind": "tax_mult", "mult": 0.9},
			{"kind": "inspection_risk", "amount": risk}]
	return Sim.new(NewGame.from_scenario("forge_upgrades", seed)["state"], c)


## Runs until just after the next dawn (its hour moves with the season) and returns the events of those steps.
func _to_dawn(sim: Sim) -> Array:
	var all: Array = []
	for i: int in 2 * 1440:
		var ev := sim.step()
		all.append_array(ev)
		if Ledger.is_dawn(sim):
			return all
	return all


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _mem(sim: Sim) -> Dictionary:
	return sim.state.buildings[FORGE]["inspection"]


func test_no_secrets_no_roll() -> void:
	var sim := _sim()
	var ev := _to_dawn(sim)
	eq(_of(ev, "inspection").size(), 0, "no inspection")
	eq(int(_mem(sim)["last_day"]), -1, "never rolled")


func test_caught_pays_a_fine_and_loses_reputation() -> void:
	var sim := _sim(1, 1.0)  # always caught
	var st := sim.state
	Upgrades.complete(sim, FORGE, "forge_secrets_1")
	var rep := int(st.families[FAM].get("reputation", 0))
	var book := Ledger.total(st, FAM)
	var gold := Money.gold(st, FAM)
	var ev := _to_dawn(sim)
	var today := Clock.day(int(st.clock["minute"]))
	var ins := _of(ev, "inspection")
	eq(ins.size(), 1, "one inspection")
	var fine := int(ins[0]["fine"])
	check(fine >= 10 and fine <= 50, "fine in [10, 50] (%d)" % fine)
	eq([ins[0]["family"], ins[0]["building"], ins[0]["caught"], ins[0]["escaped"]], [FAM, FORGE, true, false], "event")
	var fines: Array = (st.ledger["entries"] as Array).filter(func(e: Dictionary) -> bool:
		return str(e["category"]) == "fines" and str(e["family"]) == FAM)
	eq(fines.size(), 1, "one fines entry")
	eq([int(fines[0]["amount"]), str(fines[0]["ref"]), str(fines[0]["building"])], [-fine, "inspection", FORGE],
		"the ledger: category fines, ref inspection")
	eq(Money.gold(st, FAM) - gold, Ledger.total(st, FAM) - book, "the book adds up (wages and upkeep too)")
	var reps := _of(ev, "reputation_changed").filter(func(e: Dictionary) -> bool: return str(e["reason"]) == "inspection")
	eq(reps.size(), 1, "reputation_changed reason inspection")
	eq(int(reps[0]["amount"]), -10, "−10 reputation")
	check(int(st.families[FAM]["reputation"]) - _h9_rep(sim) <= rep - 10, "the family lost the reputation")
	eq([int(_mem(sim)["last_day"]), int(_mem(sim)["caught"]), int(_mem(sim)["fines"])], [today, 1, fine], "memory")
	var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.inspection_fined")
	eq(n.size(), 1, "notice")
	eq([n[0]["severity"], n[0]["params"]], [Notices.URGENT, {"building": FORGE, "amount": fine}], "urgent, with the fine")
	eq(Inspections.fine_debt(sim, FORGE), 0, "paid in full: no debt")


func test_not_caught_only_marks_the_day() -> void:
	var sim := _sim(1, 0.0001)
	Upgrades.complete(sim, FORGE, "forge_secrets_1")
	var ev := _to_dawn(sim)
	eq(_of(ev, "inspection").size(), 0, "not caught")
	eq(int(_mem(sim)["last_day"]), Clock.day(int(sim.state.clock["minute"])), "but it rolled today")
	eq(int(_mem(sim)["caught"]), 0, "never caught")


func test_hidden_passage_saves_once_then_cools_down() -> void:
	var sim := _sim(1, 1.0)
	for id: String in ["forge_secrets_1", "forge_security_1", "forge_secrets_2"]:
		check(Upgrades.complete(sim, FORGE, id), id)
	var ev := _to_dawn(sim)
	var day1 := Clock.day(int(sim.state.clock["minute"]))
	var ins := _of(ev, "inspection")
	eq([ins[0]["caught"], ins[0]["escaped"], ins[0]["fine"]], [false, true, 0], "the passage saves it")
	eq([int(_mem(sim)["escaped"]), int(_mem(sim)["escape_ready_day"])], [1, day1 + 8], "escaped, ready in 8 days")
	var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.inspection_escaped")
	eq(str(n[0]["severity"]), Notices.WARNING, "warning notice")
	check(not Inspections.can_escape(sim, FORGE), "cooling down")
	ev = _to_dawn(sim)
	eq(_of(ev, "inspection")[0]["caught"], true, "the next day it is caught")
	for d: int in 6:
		_to_dawn(sim)
	eq(Clock.day(int(sim.state.clock["minute"])), day1 + 7, "7 days later")
	check(not Inspections.can_escape(sim, FORGE), "still cooling down on day 7")
	eq(int(_mem(sim)["escaped"]), 1, "caught every day of the cooldown")
	ev = _to_dawn(sim)
	eq(Clock.day(int(sim.state.clock["minute"])), day1 + 8, "8 days later")
	eq(_of(ev, "inspection")[0]["escaped"], true, "ready again: the passage saves it")
	eq(int(_mem(sim)["escaped"]), 2, "two escapes")


## Pulido del MVP: an unpayable fine is owed to the town as a Loan with a term (keep_gold kept; was fine_debt, which
## swallowed every income).
func test_unpayable_fine_becomes_debt_with_the_town() -> void:
	var sim := _sim(1, 1.0)
	var st := sim.state
	Upgrades.complete(sim, FORGE, "forge_secrets_1")
	st.families[FAM]["gold"] = 0
	var ev := _to_dawn(sim)
	var fine := int(_of(ev, "inspection")[0]["fine"])
	eq(Money.gold(st, FAM), 0, "nothing to pay with")
	var town := Loans.of_family(sim, FAM).filter(func(id: String) -> bool: return str(st.loans[id]["lender"]) == "town")
	eq(town.size(), 1, "a debt with the town")
	eq(int(st.loans[town[0]]["outstanding"]), fine, "the whole fine is owed")
	eq(Inspections.fine_debt(sim, FORGE), 0, "no old fine debt eating the income")
	eq(int(_mem(sim)["fines"]), fine, "fines counts the fine itself")
	var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.fine_loan")
	eq(n[0]["severity"], Notices.URGENT, "urgent notice with the term")
	Money.change(sim, FAM, 7, Money.MARKET_SALES, "test")
	sim.events = [{"type": "gold_changed", "family": FAM, "amount": 7, "category": "market_sales", "gold": 7}]
	Inspections.step(sim)
	eq(Money.gold(st, FAM), 7, "a sale is not swallowed: the family keeps it")


func test_an_old_fine_debt_is_still_collected() -> void:
	var sim := _sim(1, 1.0)
	var st := sim.state
	_mem(sim)["fine_debt"] = 12  # a save from before pulido-mvp
	Money.change(sim, FAM, 5, Money.MARKET_SALES, "test")
	sim.events = [{"type": "gold_changed", "family": FAM, "amount": 5, "category": "market_sales", "gold": 5}]
	var gold := Money.gold(st, FAM)
	Inspections.step(sim)
	eq(Inspections.fine_debt(sim, FORGE), maxi(0, 12 - gold), "collected as before")


func test_same_seed_same_inspections() -> void:
	var runs: Array = []
	for r: int in 2:
		var sim := _sim(7)
		for id: String in ["forge_secrets_1", "forge_secrets_2", "forge_security_1", "forge_secrets_3"]:
			Upgrades.complete(sim, FORGE, id)
		near(Inspections.risk(sim, FORGE), 0.2, 0.0001, "risk 5 % + 15 %")
		var log: Array = []
		for d: int in 12:
			for e: Dictionary in _of(_to_dawn(sim), "inspection"):
				log.append([Clock.day(int(sim.state.clock["minute"])), e["caught"], e["escaped"], e["fine"]])
		runs.append([log, _mem(sim).duplicate(), sim.state_hash()])
	print("[test_econ_inspections] semilla 7, riesgo 0,2, 12 días: %s" % [runs[0][0]])
	eq(runs[1], runs[0], "same seed: same inspections, same state")
	check(not (runs[0][0] as Array).is_empty(), "with 20 % a day for 12 days something happened")


func test_memory_and_debt_survive_save_load() -> void:
	var sim := _sim(1, 1.0)
	Upgrades.complete(sim, FORGE, "forge_secrets_1")
	sim.state.families[FAM]["gold"] = 0
	_to_dawn(sim)
	check(not Loans.of_family(sim, FAM).is_empty(), "a debt to keep (the town's loan)")
	var r := SaveFile.from_text(JSON.stringify(sim.state.to_dict()))
	check(r["ok"], "loads")
	var back: WorldState = r["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(sim.state.to_dict()), "same content")
	var b := Sim.new(back, sim.catalog)
	eq(Inspections.view(b, FORGE), Inspections.view(sim, FORGE), "same view")
	_to_dawn(sim)
	_to_dawn(b)
	eq(b.state_hash(), sim.state_hash(), "both go on the same")


## H9: reputation from the sources H9 added (passive, trade, wages paid), apart from what this test measures.
func _h9_rep(sim: Sim) -> int:
	var n := 0
	for e: Dictionary in sim.state.families[FAM].get("reputation_log", []):
		if str(e["reason"]) in ["passive", "fair_trade", "quality_trade", "wages_paid"]:
			n += int(e["amount"])
	return n
