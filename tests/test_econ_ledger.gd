extends "res://tests/test_case.gd"
## The account book (GDD 4.18, docs/contratos/h3_mercado.md): the panel's queries, retention into yearly
## summaries, the notices log (read, order, retention) and conservation under the random_clicker bot.

const FAM := "fam_0001"
const HUGO := "chr_0001"
const FORGE := "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


func _at(sim: Sim, day: int, minute_of_day: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + minute_of_day


func test_summary_today_days_and_buildings() -> void:
	var sim := _sim()
	_at(sim, 2, 600)
	Money.change(sim, FAM, 40, Money.MARKET_SALES, "sell", "", HUGO)
	Money.change(sim, FAM, -10, Money.PURCHASES, "buy", FORGE, HUGO)
	_at(sim, 3, 600)
	Money.change(sim, FAM, 25, Money.CONTRACTS, "ctr_0001", "", HUGO)
	Money.change(sim, FAM, -2, Money.UPKEEP, "upkeep", FORGE)
	Money.change(sim, FAM, -5, Money.ERRANDS, "dlv_0001", FORGE, HUGO)
	Money.change(sim, "fam_0003", 99, Money.MARKET_SALES, "sell")  # another family: not counted
	var today: Dictionary = Ledger.summary(sim, FAM, "today")
	eq([int(today["income"]), int(today["expense"]), int(today["net"])], [25, -7, 18], "today")
	eq(today["by_category"], {"contracts": 25, "upkeep": -2, "errands": -5}, "today by category")
	var days: Array = Ledger.summary(sim, FAM, "days")
	eq(days.size(), 4, "days 0..3 (the game is 4 days old)")
	eq(days[2], {"day": 2, "income": 40, "expense": -10, "net": 30}, "day 2")
	eq(days[0], {"day": 0, "income": 0, "expense": 0, "net": 0}, "an empty day")
	_at(sim, 20, 600)
	eq((Ledger.summary(sim, FAM, "days") as Array).size(), 8, "only the last 8 days")
	eq(int((Ledger.summary(sim, FAM, "days") as Array)[0]["day"]), 13, "from day 13 to 20")
	var blds: Dictionary = Ledger.summary(sim, FAM, "buildings")
	eq(blds, {"": {"market_sales": 40, "contracts": 25}, FORGE: {"purchases": -10, "upkeep": -2, "errands": -5}},
		"by building")
	eq(Ledger.entries(sim, FAM, 3, 3).size(), 3, "entries of day 3")
	eq(Ledger.entries(sim, FAM, 0, 99).size(), 5, "all of them")
	eq(int(Ledger.entries(sim, FAM, 2, 2)[0]["amount"]), 40, "oldest first")


func test_summary_debts() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	var d: Dictionary = Ledger.summary(sim, FAM, "debts")
	eq((d["loans"] as Array).size(), 1, "the start loan")
	eq(int(d["loans"][0]["outstanding"]), 200, "200 owed")
	eq(int(d["loans"][0]["days_left"]), 8, "8 days left")
	eq(d["contracts"], [], "nothing accepted")
	sim.state.buildings[FORGE]["upkeep_debt"] = 4
	sim.state.buildings[FORGE]["upkeep_unpaid_since"] = 0
	_at(sim, 2, 600)
	d = Ledger.summary(sim, FAM, "debts")
	eq(d["upkeep"], [{"building": FORGE, "debt": 4, "unpaid_since": 0, "days_unpaid": 2}], "the upkeep owed")


func test_retention_keeps_two_years_and_sums_the_rest() -> void:
	var sim := _sim()
	var gold0 := Money.gold(sim.state, FAM)
	for d: int in [0, 1, 5, 10]:
		_at(sim, d, 600)
		Money.change(sim, FAM, -3, Money.UPKEEP, "upkeep", FORGE)
		Money.change(sim, FAM, 10, Money.MARKET_SALES, "sell", "", HUGO)
	_at(sim, 17, 299)  # the dawn of day 17: detail kept for days 2..17 (16 days = 2 years)
	sim.step()
	var entries: Array = Ledger.entries(sim, FAM, 0, 99)
	eq(entries.size(), 4 + 1, "days 5 and 10 kept, plus today's dawn upkeep")
	check((sim.state.ledger["entries"] as Array).all(func(e: Dictionary) -> bool: return int(e["day"]) >= 2),
		"nothing before day 2 in detail")
	eq(sim.state.ledger["summaries"][FAM], {"0": {"upkeep": {FORGE: -6}, "market_sales": {"": 20}}},
		"days 0 and 1 summed in year 0 by category and building")
	eq(Money.gold(sim.state, FAM) - gold0, Ledger.total(sim.state, FAM), "the book still adds up to the gold")


func test_read_notices_and_order() -> void:
	var sim := _sim()
	var a := Notices.add(sim, FAM, Notices.INFO, "notice.loan_repaid")
	var b := Notices.add(sim, FAM, Notices.URGENT, "notice.ruin", {"missing": 3})
	var c := Notices.add(sim, "fam_0003", Notices.WARNING, "notice.upkeep_unpaid")
	eq(Notices.list(sim, FAM).map(func(n: Dictionary) -> String: return n["id"]), [b, a], "newest first, own only")
	eq(Notices.unread_count(sim, FAM), 2, "two unread")
	var r := Orders.apply(sim, {"type": "read_notices", "actor": HUGO, "ids": [a]})
	check(r["ok"], "reads: %s" % r["reason"])
	eq(Notices.list(sim, FAM, true).map(func(n: Dictionary) -> String: return n["id"]), [b], "only b unread")
	var h := sim.state_hash()
	eq(Orders.apply(sim, {"type": "read_notices", "actor": HUGO, "ids": [b, c]})["reason"], "unknown_notice",
		"not another family's")
	eq(Orders.apply(sim, {"type": "read_notices", "actor": HUGO, "ids": ["ntc_9999"]})["reason"], "unknown_notice",
		"unknown")
	eq(Orders.apply(sim, {"type": "read_notices", "actor": "nobody", "ids": [b]})["reason"], "unknown_actor", "nobody")
	eq(sim.state_hash(), h, "refused orders change nothing")
	check(Orders.apply(sim, {"type": "read_notices", "actor": HUGO, "ids": []})["ok"], "nothing to read is fine")


func test_notices_kept_one_year() -> void:
	var sim := _sim()
	_at(sim, 0, 600)
	Notices.add(sim, FAM, Notices.INFO, "notice.loan_repaid")
	_at(sim, 3, 600)
	var keep := Notices.add(sim, FAM, Notices.INFO, "notice.loan_repaid")
	_at(sim, 8, 299)  # dawn of day 8: one year = days 1..8 kept
	sim.step()
	var ids: Array = sim.state.notices.map(func(n: Dictionary) -> String: return n["id"])
	check(keep in ids, "the one from day 3 stays")
	eq(sim.state.notices.filter(func(n: Dictionary) -> bool: return int(n["day"]) == 0).size(), 0, "day 0 goes")


func test_conservation_random_clicker_10_days() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
	var sim := Sim.new(r["state"], cat)
	var before := {}
	for f: String in sim.state.families:
		before[f] = Money.gold(sim.state, f)
	var refused := 0
	var bot := BotRandomClicker.new()
	for i: int in 10 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == "order_refused":
				refused += 1
	check(refused > 100, "the bot gave plenty of nonsense (%d refused)" % refused)
	check(not sim.state.ledger["entries"].is_empty(), "gold moved")
	for f: String in sim.state.families:
		eq(Money.gold(sim.state, f) - int(before.get(f, 0)), Ledger.total(sim.state, f), "%s: entries = change of gold" % f)  # vida: families made later start at 0
		check(Money.gold(sim.state, f) >= 0, "%s: never below 0" % f)
