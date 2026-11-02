extends "res://tests/test_case.gd"
## Pulido del MVP, arreglo 2: a fine (inspection, court) is paid from the gold above fine_loan.keep_gold and the rest
## is owed to the town as a Loan with a term (GDD 4.16's entity: warnings, extension, seizure). Before, a smith fined
## with no stock stayed at 0 gold forever (the crook bot, seed 7). Here a broke forge with the double accounting is
## fined and the expert bot still buys iron and works.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _broke() -> Sim:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 7)["state"], cat)
	var st := sim.state
	st.loans = {}
	st.families[FAM]["gold"] = 40
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 5 * 60 + 30
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	inv["stacks"] = []
	(st.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	return sim


func test_fine_keeps_the_working_gold() -> void:
	var sim := _broke()
	var st := sim.state
	var r := Loans.charge_fine(sim, FAM, 50, Money.FINES, "inspection", FORGE)
	eq(int(r["paid"]), 10, "pays only what is above keep_gold (40 - 30)")
	eq(int(r["owed"]), 40, "the rest is owed")
	eq(Money.gold(st, FAM), 30, "the family keeps 30 to buy iron")
	var loan: Dictionary = st.loans[str(r["loan"])]
	eq(str(loan["lender"]), "town", "to the town")
	eq(int(loan["outstanding"]), 40, "40 outstanding")
	eq(Clock.day(int(loan["due_minute"])), 9 + 8, "due in a year (term_days 8)")
	var r2 := Loans.charge_fine(sim, FAM, 20, Money.FINES, "inspection", FORGE)
	eq(str(r2["loan"]), str(r["loan"]), "a second fine goes to the same town loan")
	eq(int(loan["outstanding"]), 60, "60 now")
	check(Orders.apply(sim, {"type": "repay_loan", "actor": HERO, "loan": str(r["loan"]), "amount": 10})["ok"],
		"it can be repaid like the start debt")


func test_a_fined_broke_forge_gets_going_again() -> void:
	var sim := Sim.new(NewGame.from_scenario("fined_broke", 7)["state"], cat)
	var st := sim.state
	eq(Money.gold(st, FAM), 30, "the scenario: 30 kept after the fine")
	eq(st.loans.size(), 1, "40 owed to the town")
	var bot := BotArtisanExpert.new()
	bot.crook = 1
	var bought := false
	var worked := false
	var sold := false
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == "market_bought" and str(e.get("family", "")) == FAM:
				bought = true
			if str(e["type"]) == "work_done" and Money.family_of(st, str(e.get("building", ""))) == FAM:
				worked = true
			if str(e["type"]) == "market_sold" and str(e.get("family", "")) == FAM:
				sold = true
	check(worked, "the forge works")
	check(sold, "and sells")
	check(bought, "and buys raw materials again with the gold it kept")
