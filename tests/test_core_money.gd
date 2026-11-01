extends "res://tests/test_case.gd"
## Money (GDD 4.18, 4.19, docs/contratos/h3_mercado.md): one purse per family, the only way to change gold, every
## movement in the ledger, nothing below 0 unless asked.

const FAM := "fam_0001"
const HUGO := "chr_0001"
const FORGE := "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


func test_change_moves_gold_and_writes_the_ledger() -> void:
	var sim := _sim()
	sim.state.clock["minute"] = 1440 + 600
	eq(Money.gold(sim.state, FAM), 100, "the scenario's purse")
	check(Money.change(sim, FAM, 35, Money.MARKET_SALES, "sell", "", HUGO), "earns")
	check(Money.change(sim, FAM, -15, Money.PURCHASES, "buy", FORGE, HUGO), "pays")
	eq(Money.gold(sim.state, FAM), 120, "100 + 35 - 15")
	var e: Array = sim.state.ledger["entries"]
	eq(e.size(), 2, "two entries")
	eq(e[1], {"day": 1, "minute": 2040, "family": FAM, "building": FORGE, "actor": HUGO, "category": "purchases",
		"amount": -15, "ref": "buy"}, "the entry")
	var ev: Array = sim.events.filter(func(x: Dictionary) -> bool: return x["type"] == "gold_changed")
	eq(ev.size(), 2, "one event each")
	eq(ev[1], {"type": "gold_changed", "family": FAM, "amount": -15, "category": "purchases", "gold": 120}, "event")


func test_change_refuses_without_changing_anything() -> void:
	var sim := _sim()
	var h := sim.state_hash()
	check(not Money.change(sim, FAM, -101, Money.UPKEEP, "upkeep"), "not below 0")
	check(not Money.change(sim, "fam_0099", 10, Money.MARKET_SALES, "x"), "unknown family")
	eq(sim.state_hash(), h, "nothing changed")
	check(Money.change(sim, FAM, 0, Money.UPKEEP, "upkeep"), "0 is fine")
	eq(sim.state_hash(), h, "and writes nothing")
	check(Money.change(sim, FAM, -130, Money.UPKEEP, "upkeep", FORGE, "", true), "below 0 when asked")
	eq(Money.gold(sim.state, FAM), -30, "owes 30")


func test_family_of() -> void:
	var st := _sim().state
	eq(Money.family_of(st, HUGO), FAM, "a character's family")
	eq(Money.family_of(st, FAM), FAM, "a family is itself")
	eq(Money.family_of(st, FORGE), FAM, "a building's owner")
	eq(Money.family_of(st, "bld_0002"), "fam_0003", "the rival's forge")
	eq(Money.family_of(st, "bld_0003"), "", "the armory is the town's")
	eq(Money.family_of(st, "nobody"), "", "unknown")


func test_buy_raw_pays_through_money() -> void:
	var sim := _sim()
	sim.state.characters[HUGO]["location"] = FORGE
	var r := Orders.apply(sim, {"type": "buy_raw", "actor": HUGO, "building": FORGE, "item": "iron", "qty": 2})
	check(r["ok"], "buys: %s" % r["reason"])
	var e: Dictionary = sim.state.ledger["entries"][0]
	eq([e["category"], int(e["amount"]), e["building"], e["actor"]], ["purchases", -10, FORGE, HUGO], "purchases entry")


func test_ledger_adds_up_to_the_gold() -> void:
	var sim := _sim()
	var before := {}
	for f: String in sim.state.families:
		before[f] = Money.gold(sim.state, f)
	sim.run_days(1, BotSmith.new())
	var sums := {}
	for e: Dictionary in sim.state.ledger["entries"]:
		sums[e["family"]] = int(sums.get(e["family"], 0)) + int(e["amount"])
	check(not sim.state.ledger["entries"].is_empty(), "the smith bot spent something")
	for f: String in sim.state.families:
		eq(Money.gold(sim.state, f) - int(before[f]), int(sums.get(f, 0)), "%s: entries = change of gold" % f)
