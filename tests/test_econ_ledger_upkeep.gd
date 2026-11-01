extends "res://tests/test_case.gd"
## Daily upkeep (D12, GDD 4.19) and unpaid upkeep (D15 = b, 3 days): charged every dawn to the owner family and in
## the ledger; what cannot be paid is owed to the town, charged as soon as there is gold; after 3 days unpaid the
## building is damaged, and back to normal when settled.

const FAM := "fam_0001"
const FORGE := "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


## Runs until the dawn of `day` has been processed.
func _to_dawn(sim: Sim, day: int) -> void:
	var dawn := int(cat.time["phase_starts"][Clock.season(day * Clock.MINUTES_PER_DAY, cat.time)]["dawn"])
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + dawn - 1
	sim.step()


func _upkeep_entries(sim: Sim, fam: String) -> Array:
	return (sim.state.ledger["entries"] as Array).filter(func(e: Dictionary) -> bool:
		return e["family"] == fam and e["category"] == "upkeep")


func test_upkeep_charged_every_dawn_and_in_the_ledger() -> void:
	var sim := _sim()
	var upkeep := int(cat.buildings()["forge"]["upkeep"])
	sim.run_days(3)  # from day 0 08:00: the dawns of days 1, 2 and 3
	var mine := _upkeep_entries(sim, FAM)
	eq(mine.size(), 3, "one entry per dawn")
	for e: Dictionary in mine:
		eq([int(e["amount"]), e["building"], e["ref"]], [-upkeep, FORGE, "upkeep"], "the forge's upkeep")
	eq(mine.map(func(e: Dictionary) -> int: return int(e["day"])), [1, 2, 3], "days 1, 2, 3")
	eq(_upkeep_entries(sim, "fam_0003").size(), 3, "the rival pays too")
	eq(_upkeep_entries(sim, "fam_0002").size(), 0, "a family without buildings pays nothing")
	check(not _upkeep_entries(sim, "").size(), "the armory is the town's: nobody pays")
	var today: Dictionary = Ledger.summary(sim, FAM, "today")
	eq(int(today["by_category"].get("upkeep", 0)), -upkeep, "it shows in today's ledger")


func test_unpaid_upkeep_accumulates_damages_and_settles() -> void:
	var sim := _sim()
	var upkeep := int(cat.buildings()["forge"]["upkeep"])
	Money.change(sim, FAM, -99, Money.PURCHASES, "test")  # 1 gold left
	_to_dawn(sim, 1)
	var b: Dictionary = sim.state.buildings[FORGE]
	eq(Money.gold(sim.state, FAM), 0, "pays what it has")
	eq([int(b["upkeep_debt"]), int(b["upkeep_unpaid_since"])], [upkeep - 1, 1], "owes the rest since day 1")
	var warn: Array = Notices.list(sim, FAM).filter(func(n: Dictionary) -> bool: return n["key"] == "notice.upkeep_unpaid")
	eq(warn.size(), 1, "a warning")
	eq([warn[0]["severity"], warn[0]["target"], int(warn[0]["params"]["days"])], ["warning", FORGE, 3], "3 days to damage")
	_to_dawn(sim, 2)
	_to_dawn(sim, 3)
	eq(str(b["state"]), "normal", "still normal after 2 days")
	eq(int(b["upkeep_debt"]), upkeep * 3 - 1, "the debt grows")
	_to_dawn(sim, 4)
	eq(str(b["state"]), "damaged", "damaged after 3 days unpaid")
	check(Notices.list(sim, FAM).any(func(n: Dictionary) -> bool: return n["key"] == "notice.building_damaged"),
		"an urgent notice")
	sim.state.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 600
	var owed := int(b["upkeep_debt"])
	sim.events = []  # gold comes in during a step (a sale): Upkeep sees its gold_changed
	Money.change(sim, FAM, 3, Money.MARKET_SALES, "test")
	Upkeep.step(sim)
	eq(int(b["upkeep_debt"]), owed - 3, "gold coming in pays the debt at once")
	eq(Money.gold(sim.state, FAM), 0, "all of it")
	eq(str(b["state"]), "damaged", "still damaged while it owes")
	sim.events = []
	Money.change(sim, FAM, 50, Money.MARKET_SALES, "test")
	Upkeep.step(sim)
	eq([int(b["upkeep_debt"]), int(b["upkeep_unpaid_since"]), str(b["state"])], [0, -1, "normal"], "settled: normal")
	eq(Money.gold(sim.state, FAM), 50 - (owed - 3), "paid the rest")
	check(Notices.list(sim, FAM).any(func(n: Dictionary) -> bool: return n["key"] == "notice.upkeep_settled"),
		"a notice")
	var gold0 := 100
	eq(Money.gold(sim.state, FAM) - gold0, Ledger.total(sim.state, FAM), "the ledger adds up")


func test_damaged_forge_cannot_work() -> void:
	var sim := _sim()
	sim.state.buildings[FORGE]["state"] = "damaged"
	sim.state.characters["chr_0001"]["location"] = FORGE
	sim.state.clock["minute"] = 600
	var r := Orders.apply(sim, {"type": "work_at", "actor": "chr_0001", "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"})
	eq(r["reason"], "building_not_ready", "production refuses a damaged building")
