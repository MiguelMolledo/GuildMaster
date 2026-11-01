extends "res://tests/test_case.gd"
## The start objectives (GDD 4.16): a chain per family from data/objectives/, advanced by the events of each step;
## only the current one counts; each one done goes to the notices log. And the save round trip of everything
## «cuentas» keeps in the state: ledger (with summaries), loan, notices, objectives, upkeep debt, ending.

const FAM := "fam_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)


## Feeds `events` to Objectives as if a step had emitted them.
func _feed(sim: Sim, events: Array) -> void:
	sim.events = events.duplicate(true)
	Objectives.step(sim)


func _work(item: String) -> Dictionary:
	return {"type": "work_done", "actor": HUGO, "building": "bld_0001", "zone": "anvil", "item": item, "quality": 0,
		"qty": 1}


func test_chain_advances_with_events() -> void:
	var sim := _sim()
	_feed(sim, [_work("sword")])
	eq(Objectives.view(sim, FAM)["progress"], [{"have": 0, "need": 2}, {"have": 1, "need": 1}], "a sword counts")
	_feed(sim, [_work("iron_ingot"), _work("iron_ingot"), _work("iron_ingot")])
	var v := Objectives.view(sim, FAM)
	eq([v["current"], v["done"]], ["sell_in_armory", ["forge_sword"]], "done: the next one")
	eq(v["progress"], [{"have": 0, "need": 1}], "fresh progress")
	check(sim.events.any(func(e: Dictionary) -> bool: return e == {"type": "objective_done", "family": FAM,
		"objective": "forge_sword"}), "objective_done")
	var n: Dictionary = Notices.list(sim, FAM)[0]
	eq([n["key"], n["severity"], n["params"]["objective"]], ["notice.objective_done", "info", "forge_sword"], "notice")
	# Not the current one: does not count. Another family's: does not count.
	_feed(sim, [{"type": "loan_repaid", "actor": HUGO, "family": FAM, "loan": "lon_0001", "extended": false}])
	eq(Objectives.view(sim, FAM)["current"], "sell_in_armory", "repaying now does not skip ahead")
	_feed(sim, [{"type": "market_sold", "actor": "chr_0002", "family": "fam_0002", "stall": "armory", "item": "sword",
		"quality": 0, "qty": 1, "price": 10, "total": 10}])
	eq(Objectives.view(sim, FAM)["current"], "sell_in_armory", "the rival's sale is not ours")
	_feed(sim, [{"type": "market_sold", "actor": HUGO, "family": FAM, "stall": "resources", "item": "sword",
		"quality": 0, "qty": 1, "price": 10, "total": 10}])
	eq(Objectives.view(sim, FAM)["current"], "sell_in_armory", "not at the armory")
	_feed(sim, [{"type": "market_sold", "actor": HUGO, "family": FAM, "stall": "armory", "item": "sword",
		"quality": 0, "qty": 1, "price": 10, "total": 10}])
	eq(Objectives.view(sim, FAM)["current"], "carpenter_hammers", "sold at the armory")
	_feed(sim, [{"type": "contract_delivered", "actor": HUGO, "family": FAM, "contract": "ctr_0001", "client": "carpenter",
		"item": "hammer", "qty": 2, "min_quality": 0, "pay": 20, "script": "carpenter_hammers"}])
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "the carpenter's")
	_feed(sim, [{"type": "contract_delivered", "actor": HUGO, "family": FAM, "contract": "ctr_0003", "client": "farmer",
		"item": "hammer", "qty": 1, "min_quality": 0, "pay": 9, "script": ""}])
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "normal quality: no")
	_feed(sim, [{"type": "contract_delivered", "actor": HUGO, "family": FAM, "contract": "ctr_0002", "client": "guard_captain",
		"item": "sword", "qty": 1, "min_quality": 1, "pay": 20, "script": "guard_good_sword"}])
	eq(Objectives.view(sim, FAM)["current"], "errand_purchase", "good quality (gte 1)")
	_feed(sim, [{"type": "errand_sent", "actor": HUGO, "family": FAM, "delivery": "dlv_0001"}])
	eq(Objectives.view(sim, FAM)["current"], "repay_debt", "an errand")
	_feed(sim, [{"type": "loan_repaid", "actor": HUGO, "family": FAM, "loan": "lon_0001", "extended": true}])
	eq(Objectives.view(sim, FAM)["current"], "repay_debt", "late does not count")
	_feed(sim, [{"type": "loan_repaid", "actor": HUGO, "family": FAM, "loan": "lon_0001", "extended": false}])
	v = Objectives.view(sim, FAM)
	eq([v["current"], (v["done"] as Array).size(), v["progress"]], ["", 6, []], "the whole chain")
	_feed(sim, [_work("sword")])
	eq((Objectives.view(sim, FAM)["done"] as Array).size(), 6, "nothing more")
	eq(Objectives.view(sim, "fam_0002"), {}, "the rival has no chain")


func test_repaying_through_the_order_completes_the_objective() -> void:
	var sim := _sim()
	sim.state.objectives[FAM]["index"] = 5  # repay_debt
	sim.state.objectives[FAM]["have"] = [0]
	Money.change(sim, FAM, 200, Money.MARKET_SALES, "test")
	sim.step([{"type": "repay_loan", "actor": HUGO, "loan": "lon_0001", "amount": 200}])
	eq(Objectives.view(sim, FAM)["current"], "", "repaid on time: done in the same step")


func test_save_round_trip_with_accounts() -> void:
	var sim := _sim()
	Money.change(sim, FAM, 50, Money.MARKET_SALES, "sell", "", HUGO)
	Orders.apply(sim, {"type": "repay_loan", "actor": HUGO, "loan": "lon_0001", "amount": 30})
	_feed(sim, [_work("sword")])
	sim.events = []
	Notices.add(sim, FAM, Notices.URGENT, "notice.loan_due_soon", {"days": 2, "amount": 170})
	Orders.apply(sim, {"type": "read_notices", "actor": HUGO, "ids": ["ntc_0001"]})
	sim.state.buildings["bld_0001"]["upkeep_debt"] = 3
	sim.state.buildings["bld_0001"]["upkeep_unpaid_since"] = 0
	sim.state.ledger["summaries"] = {FAM: {"0": {"upkeep": {"bld_0001": -4}}}}
	sim.state.loans["lon_0001"]["warned"] = [2]
	sim.state.ending = {"kind": "ruin", "family": FAM, "minute": 99, "loan": "lon_0001"}
	var path := "user://test_meta_accounts.json"
	eq(SaveFile.save(sim.state, path), OK, "saves")
	var r := SaveFile.load_file(path)
	check(r["ok"], "loads")
	var back := Sim.new(r["state"], cat)
	eq(back.state_hash(), sim.state_hash(), "same state after the round trip")
	eq(Loans.status(back, "lon_0001"), Loans.status(sim, "lon_0001"), "the loan")
	eq(Notices.list(back, FAM), Notices.list(sim, FAM), "the notices")
	eq(Objectives.view(back, FAM), Objectives.view(sim, FAM), "the objectives")
	eq(Ledger.summary(back, FAM, "today"), Ledger.summary(sim, FAM, "today"), "the ledger")
	eq(Ledger.total(back.state, FAM), Ledger.total(sim.state, FAM), "with its summaries")
	eq(Ledger.summary(back, FAM, "debts"), Ledger.summary(sim, FAM, "debts"), "debts")
	eq(back.state.ending, sim.state.ending, "the ending")
	# And both go on the same way.
	back.state.ending = {}
	sim.state.ending = {}
	sim.run_minutes(Clock.MINUTES_PER_DAY)
	back.run_minutes(Clock.MINUTES_PER_DAY)
	eq(back.state_hash(), sim.state_hash(), "and plays on the same")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
