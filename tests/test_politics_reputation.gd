extends "res://tests/test_case.gd"
## H9 reputation (GDD 4.12.1, ap. A; docs/contratos/h9_titulos.md): Reputation.change (global, class modifier, log,
## event), the rules over the step's events with their caps (fair trade, quality sales, wages paid, actions on the
## townsfolk), the passive reputation of a workshop with staff at dawn, the microevent effect and the systems that
## already changed it (contracts) going through it.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)


func _townsperson(sim: Sim) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if TownLife.is_townsperson(sim.state, id):
			return id
	return ""


func _log_reasons(sim: Sim) -> Array:
	return (sim.state.families[FAM]["reputation_log"] as Array).map(func(e: Dictionary) -> String: return str(e["reason"]))


func test_change_moves_global_class_and_log() -> void:
	var sim := _sim()
	var st := sim.state
	var rep := Reputation.of(st, FAM)
	var art := Reputation.class_mod(st, FAM, "artisan")
	sim.events = []
	Reputation.change(sim, FAM, 4, "contract_done")
	eq(Reputation.of(st, FAM), rep + 4, "+4 global")
	eq(Reputation.class_mod(st, FAM, "artisan"), art + 2, "contracts are artisans': +4 × 0,5")
	eq(Reputation.with_class(st, FAM, "artisan"), rep + 4 + art + 2, "with a class = global + modifier")
	var e: Dictionary = sim.events[sim.events.size() - 1]
	eq([e["type"], e["family"], e["amount"], e["reason"], e["class"], e["reputation"]],
		["reputation_changed", FAM, 4, "contract_done", "artisan", rep + 4], "the event")
	Reputation.change(sim, FAM, -3, "inspection")
	eq(Reputation.class_mod(st, FAM, "artisan"), art + 2, "an inspection has no class")
	eq(Reputation.of(st, FAM), rep + 1, "−3")
	for i: int in 20:
		Reputation.change(sim, FAM, 1, "passive")
	eq((st.families[FAM]["reputation_log"] as Array).size(), int(cat.politics["reputation"]["log_size"]), "the log keeps 12")
	Reputation.change(sim, FAM, -100, "test")
	check(Reputation.of(st, FAM) < 0, "it may go below 0 (H3 tests it) [provisional]")


func test_trade_rules_with_daily_cap() -> void:
	var sim := _sim()
	var st := sim.state
	var rep := Reputation.of(st, FAM)
	var sale := {"type": "market_sold", "family": FAM, "actor": HERO, "stall": "armory", "item": "sword", "quality": 0,
		"qty": 1}
	sim.events = [sale, sale.duplicate()]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep + 1, "fair trade: +1, once a day")
	sim.events = [sale.duplicate()]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep + 1, "not twice the same day")
	var good := sale.duplicate()
	good["quality"] = Inventory.GOOD
	sim.events = [good]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep + 2, "a good piece: quality trade +1 (fair trade already given)")
	st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
	sim.events = [good.duplicate()]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep + 4, "next day: both again")
	check("fair_trade" in _log_reasons(sim) and "quality_trade" in _log_reasons(sim), "logged by rule id")


func test_counter_sale_moves_the_customers_class() -> void:
	var sim := _sim()
	var st := sim.state
	var folk := _townsperson(sim)
	st.characters[folk]["class"] = "patron"
	sim.events = [{"type": "counter_sold", "family": FAM, "building": FORGE, "customer": folk, "seller": HERO,
		"item": "sword", "quality": 0, "price": 30}]
	var rep := Reputation.of(st, FAM)
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep + 1, "fair trade at the counter")
	eq(Reputation.class_mod(st, FAM, "patron"), 0, "class_amount 0: the trade does not move the class")


func test_wages_paid_once_a_year() -> void:
	var sim := _sim()
	var st := sim.state
	var paid := {"type": "wage_paid", "family": FAM, "building": FORGE, "employee": "chr_x", "amount": 20}
	var rep := Reputation.of(st, FAM)
	for d: int in 8:
		sim.events = [paid.duplicate()]
		Reputation.step(sim)
		st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
	var year := floori(float(Clock.day(int(st.clock["minute"]) - Clock.MINUTES_PER_DAY)) / 8.0)
	var first := floori(float(Clock.day(int(st.clock["minute"]) - 8 * Clock.MINUTES_PER_DAY)) / 8.0)
	eq(Reputation.of(st, FAM), rep + 2 * (year - first + 1), "+2 per calendar year with wages paid")
	check(Reputation.class_mod(st, FAM, "artisan") > 0, "the artisans like it")


func test_actions_on_townsfolk() -> void:
	var sim := _sim()
	var st := sim.state
	var folk := _townsperson(sim)
	var cls := str(st.characters[folk]["class"])
	var rep := Reputation.of(st, FAM)
	var mod := Reputation.class_mod(st, FAM, cls)
	sim.events = [{"type": "npc_action", "actor": HERO, "target": folk, "action": "insult", "ok": true}]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep - 1, "insult: −1")
	eq(Reputation.class_mod(st, FAM, cls), mod - 2, "insult: −2 with the target's class")
	sim.events = [{"type": "npc_action", "actor": HERO, "target": folk, "action": "gift", "ok": true}]
	Reputation.step(sim)
	eq(Reputation.of(st, FAM), rep - 1, "gift: no global change")
	eq(Reputation.class_mod(st, FAM, cls), mod - 1, "gift: +1 with the class")
	sim.events = [{"type": "npc_action", "actor": HERO, "target": folk, "action": "flatter", "ok": false}]
	Reputation.step(sim)
	eq(Reputation.class_mod(st, FAM, cls), mod - 1, "a failed flattery gives nothing")


func test_real_insult_order_costs_reputation() -> void:
	var sim := _sim()
	var st := sim.state
	var folk := _townsperson(sim)
	st.characters[folk]["location"] = ""
	st.characters[folk]["position"] = (st.characters[HERO]["position"] as Array).duplicate()
	st.characters[folk]["path"] = []
	var rep := Reputation.of(st, FAM)
	sim.step([{"type": "npc_insult", "actor": HERO, "target": folk}])
	check(sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "npc_action"), "the insult happened")
	eq(Reputation.of(st, FAM), rep - 1, "and costs 1 of reputation in the same step")


func test_passive_reputation_at_dawn() -> void:
	var quiet := Catalog.load_from()  # no microevents: a sick employee is not active and gives no passive
	quiet.town["microevents"]["base_chance"] = 0.0
	var sim := Sim.new(NewGame.from_scenario("title_ready", 1)["state"], quiet)
	var st := sim.state
	var rep := Reputation.of(st, FAM)
	var before := _log_reasons(sim).count("passive")  # the scenario's log already has one
	var day := Clock.day(int(st.clock["minute"]))
	var guard := 0
	while Clock.day(int(st.clock["minute"])) == day or sim.now()["phase"] != "day":
		sim.step()
		guard += 1
		if guard > 2 * Clock.MINUTES_PER_DAY:
			break
	check(_log_reasons(sim).count("passive") > before, "the forge with its journeyman: passive at dawn")
	check(Reputation.of(st, FAM) >= rep + 1, "+1 at least")
	eq(_log_reasons(sim).count("passive") - before, 1, "once per dawn and business")


func test_no_staff_no_passive() -> void:
	var sim := _sim()
	var st := sim.state
	for c: String in Staff.employees_of(st, FORGE):
		st.characters[c]["job"] = null
	var before := _log_reasons(sim).count("passive")
	var guard := 0
	var day := Clock.day(int(st.clock["minute"]))
	while Clock.day(int(st.clock["minute"])) == day or sim.now()["phase"] != "day":
		sim.step()
		guard += 1
		if guard > 2 * Clock.MINUTES_PER_DAY:
			break
	eq(_log_reasons(sim).count("passive"), before, "no employee, no passive reputation")


## The tavern with an active employee is an operative business too (ap. A «por negocio operativo con empleados»;
## the manager's decision 2026-11-07, Barón): +1 more at dawn than without it.
func test_the_tavern_with_staff_gives_passive_too() -> void:
	var quiet := Catalog.load_from()
	quiet.town["microevents"]["base_chance"] = 0.0
	var sim := Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], quiet)
	var st := sim.state
	var t := ""
	for b: String in st.buildings:
		if Inn.is_inn(sim, b) and str(st.buildings[b]["owner"]) == FAM:
			t = b
	check(t != "", "the family runs the tavern")
	for c: String in Staff.employees_of(st, t):
		st.characters[c]["job"] = null
	var rep := Reputation.of(st, FAM)
	Reputation._passive(sim)
	var without := Reputation.of(st, FAM) - rep
	var hired := ""
	for c: Dictionary in Staff.candidates(sim, HERO, t):
		if hired == "" and str(c["status"]) == "ok":
			check(Orders.apply(sim, {"type": "hire", "actor": HERO, "building": t, "candidate": str(c["character"])})["ok"],
				"hire")
			hired = str(c["character"])
	st.characters[hired]["job"]["start_day"] = 0
	check(Staff.is_active(sim, hired), "the new barkeeper is active")
	rep = Reputation.of(st, FAM)
	Reputation._passive(sim)
	eq(Reputation.of(st, FAM) - rep, without + 1, "the tavern with its employee: +1 more")


func test_microevent_reputation_effect() -> void:
	var sim := _sim()
	var rep := Reputation.of(sim.state, FAM)
	var m := {"id": "mev_test", "def": "haggling_customer", "family": FAM, "building": FORGE, "target": "", "actor": HERO,
		"context": {}}
	Microevents._apply(sim, m, [{"kind": "reputation", "amount": -1}], "test")
	eq(Reputation.of(sim.state, FAM), rep - 1, "throwing a customer out costs 1")
	check("microevent_haggling_customer" in _log_reasons(sim), "logged")
	var choice: Dictionary = (cat.microevents()["haggling_customer"]["choices"] as Array).filter(
		func(c: Dictionary) -> bool: return str(c["id"]) == "throw_out")[0]
	check((choice["effects"] as Array).any(func(e: Dictionary) -> bool: return str(e["kind"]) == "reputation"),
		"the throw_out choice has it in data")
