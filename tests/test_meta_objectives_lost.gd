extends "res://tests/test_case.gd"
## H5 (GDD 4.16, «no bloquean nada»): a start objective tied to a scripted contract does not get stuck when that
## contract can no longer be delivered: accepted and not delivered → it expires → the objective fails with a warning
## and the chain goes on, and the next ones (errand, debt) still count. Abandoning it or another family taking it
## does the same. quality_contract is not tied to a script: the guard's contract expiring does not fail it, any
## «good» contract still counts. The candidates of the hiring panel come with the hireable ones first.

const FAM := "fam_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)


## Feeds `events` to Objectives as if a step had emitted them.
func _feed(sim: Sim, events: Array) -> void:
	sim.events = events.duplicate(true)
	Objectives.step(sim)


func _scripted(sim: Sim, script: String) -> String:
	for c: Dictionary in sim.state.contracts["board"]:
		if str(c["script"]) == script:
			return str(c["id"])
	return ""


## Hugo standing at the board (as after walking there), then the order.
func _accept(sim: Sim, id: String, who: String = HUGO) -> Array:
	var svc := Contracts.board_service(sim)
	sim.state.characters[who]["position"] = [int(svc[0]), int(svc[1])]
	sim.state.characters[who]["path"] = []
	sim.state.characters[who]["location"] = ""
	var ev := sim.step([{"type": "accept_contract", "actor": who, "contract": id}])
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "order_refused"), "%s accepts %s" % [who, id])
	return ev


## The first two objectives done (as in the game: a sword, sold at the armory): the carpenter's is current.
func _to_carpenter(sim: Sim) -> void:
	_feed(sim, [{"type": "work_done", "actor": HUGO, "building": "bld_0001", "zone": "anvil", "item": "iron_ingot",
		"quality": 0, "qty": 1}, {"type": "work_done", "actor": HUGO, "building": "bld_0001", "zone": "anvil",
		"item": "iron_ingot", "quality": 0, "qty": 1}, {"type": "work_done", "actor": HUGO, "building": "bld_0001",
		"zone": "anvil", "item": "sword", "quality": 0, "qty": 1}])
	_feed(sim, [{"type": "market_sold", "actor": HUGO, "family": FAM, "stall": "armory", "item": "sword",
		"quality": 0, "qty": 1, "price": 10, "total": 10}])
	eq(Objectives.view(sim, FAM)["current"], "carpenter_hammers", "the carpenter's is current")


func _run_until(sim: Sim, cond: Callable, max_steps: int = 4000) -> Array:
	var all: Array = []
	for i: int in max_steps:
		all.append_array(sim.step([]))
		if cond.call():
			break
	return all


func test_expired_carpenter_contract_fails_the_objective_and_the_chain_goes_on() -> void:
	var sim := _sim()
	_to_carpenter(sim)
	var id := _scripted(sim, "carpenter_hammers")
	check(id != "", "the carpenter's scripted contract is on the board")
	_accept(sim, id)
	eq(Objectives.view(sim, FAM)["current"], "carpenter_hammers", "accepted: still current")
	var ev := _run_until(sim, func() -> bool: return Objectives.view(sim, FAM)["current"] != "carpenter_hammers")
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "contract_failed" and e["reason"] == "expired"),
		"the contract expires (2 days, not delivered)")
	check(ev.any(func(e: Dictionary) -> bool: return e == {"type": "objective_failed", "family": FAM,
		"objective": "carpenter_hammers", "reason": "expired"}), "objective_failed, because it expired")
	var v := Objectives.view(sim, FAM)
	eq(v["current"], "quality_contract", "the chain goes on")
	check(not "carpenter_hammers" in (v["done"] as Array), "a failed objective is not done")
	var notes: Array = Notices.list(sim, FAM).filter(func(n: Dictionary) -> bool:
		return n["key"] == "notice.objective_failed")
	eq(notes.size(), 1, "one notice explains it")
	eq([str(notes[0]["severity"]), str(notes[0]["params"]["objective"])], ["warning", "carpenter_hammers"], "a warning")
	var text := SimQuery.notice_text(sim.state, cat, notes[0])
	check(not text.contains("{") and text.contains(SimQuery.t_("objective.carpenter_hammers")), "readable: %s" % text)
	# quality_contract is not tied to a script: it stays, and any «good» delivery counts
	eq(Objectives.lost_script(sim, FAM, "quality_contract"), "", "quality_contract is not tied to a script")
	_feed(sim, [{"type": "contract_delivered", "actor": HUGO, "family": FAM, "contract": "ctr_0009",
		"client": "farmer", "item": "hammer", "qty": 1, "min_quality": 1, "pay": 20, "script": ""}])
	eq(Objectives.view(sim, FAM)["current"], "errand_purchase", "a good contract")
	_feed(sim, [{"type": "errand_sent", "actor": HUGO, "family": FAM, "delivery": "dlv_0001"}])
	eq(Objectives.view(sim, FAM)["current"], "repay_debt", "the errand still counts")
	_feed(sim, [{"type": "loan_repaid", "actor": HUGO, "family": FAM, "loan": "lon_0001", "extended": false}])
	v = Objectives.view(sim, FAM)
	eq([v["current"], (v["done"] as Array).size()], ["", 5], "the debt counts: chain over, 5 done and 1 failed")


func test_abandoned_contract_fails_it_too() -> void:
	var sim := _sim()
	_to_carpenter(sim)
	var id := _scripted(sim, "carpenter_hammers")
	_accept(sim, id)
	var ev := sim.step([{"type": "abandon_contract", "actor": HUGO, "contract": id}])
	check(ev.any(func(e: Dictionary) -> bool: return e == {"type": "objective_failed", "family": FAM,
		"objective": "carpenter_hammers", "reason": "abandoned"}), "abandoned: objective_failed")
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "the chain goes on")


func test_contract_taken_by_another_family_and_lost_before_its_turn() -> void:
	var sim := _sim()
	var id := _scripted(sim, "carpenter_hammers")
	var rival := SimQuery.family_actor(sim.state, "fam_0002")
	check(rival != "", "the rival smith")
	_accept(sim, id, rival)
	eq(Objectives.view(sim, FAM)["current"], "forge_sword", "not its turn yet: nothing fails")
	_to_carpenter_failing(sim)


## The chain reaches the carpenter's with its contract already gone: it fails at once («gone»).
func _to_carpenter_failing(sim: Sim) -> void:
	_feed(sim, [{"type": "work_done", "actor": HUGO, "building": "bld_0001", "zone": "anvil", "item": "iron_ingot",
		"quality": 0, "qty": 1}, {"type": "work_done", "actor": HUGO, "building": "bld_0001", "zone": "anvil",
		"item": "iron_ingot", "quality": 0, "qty": 1}, {"type": "work_done", "actor": HUGO, "building": "bld_0001",
		"zone": "anvil", "item": "sword", "quality": 0, "qty": 1}])
	_feed(sim, [{"type": "market_sold", "actor": HUGO, "family": FAM, "stall": "armory", "item": "sword",
		"quality": 0, "qty": 1, "price": 10, "total": 10}])
	check(sim.events.any(func(e: Dictionary) -> bool: return e == {"type": "objective_failed", "family": FAM,
		"objective": "carpenter_hammers", "reason": "gone"}), "taken by the rival: gone")
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "straight to the next one")


func test_delivered_scripted_contract_is_done_not_lost() -> void:
	var sim := _sim()
	_to_carpenter(sim)
	var id := _scripted(sim, "carpenter_hammers")
	_accept(sim, id)
	check(Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "hammer", 0, 2), "two hammers in the bag")
	var ev := sim.step([{"type": "deliver_contract", "actor": HUGO, "contract": id}])
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "objective_failed"), "no failure")
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "done")
	check("carpenter_hammers" in (Objectives.view(sim, FAM)["done"] as Array), "counted as done")


func test_guard_contract_expiring_does_not_fail_quality_contract() -> void:
	var sim := _sim()
	_to_carpenter(sim)
	_feed(sim, [{"type": "contract_delivered", "actor": HUGO, "family": FAM, "contract": "ctr_0001",
		"client": "carpenter", "item": "hammer", "qty": 2, "min_quality": 0, "pay": 20, "script": "carpenter_hammers"}])
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "the quality one is current")
	var id := _scripted(sim, "guard_good_sword")
	_accept(sim, id)
	var ev := _run_until(sim, func() -> bool:
		return not sim.state.contracts["accepted"].any(func(c: Dictionary) -> bool: return str(c["id"]) == id), 6000)
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "contract_failed"), "the guard's contract expires")
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "objective_failed"), "no objective fails")
	eq(Objectives.view(sim, FAM)["current"], "quality_contract", "any «good» contract can still do it")


func test_hireable_candidates_first() -> void:
	var r := NewGame.from_scenario("two_employees")
	var sim := Sim.new(r["state"], cat)
	sim.state.buildings["bld_0001"]["employee_slots"] = 3   # a free place
	var cands := Staff.candidates(sim, HUGO, "bld_0001")
	var seen_other := false
	var oks := 0
	for c: Dictionary in cands:
		if str(c["status"]) == "ok":
			oks += 1
			check(not seen_other, "%s (ok) after one that cannot be hired" % c["character"])
		else:
			seen_other = true
	check(oks > 0 and oks < cands.size(), "some can be hired and some not (masters need an upgrade): %d of %d" % [oks,
		cands.size()])
	var order: Array = cat.employees.get("rank_order", [])
	for i: int in range(1, cands.size()):
		if (str(cands[i - 1]["status"]) == "ok") == (str(cands[i]["status"]) == "ok"):
			check(order.find(str(cands[i - 1]["rank"])) >= order.find(str(cands[i]["rank"])),
				"within each group, best rank first (%s, %s)" % [cands[i - 1]["rank"], cands[i]["rank"]])
