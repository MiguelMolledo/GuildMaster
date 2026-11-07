extends "res://tests/test_case.gd"
## H12.2 · the banker (docs/gdd/04d_otras_clases.md 4.22.5.6; sim/econ/bank.gd): the start, the households'
## applications at dawn, granting a loan (the capital out, the installments, the interest of the term), the households'
## installments (principal and interest), a default and its collateral (60 / 30 %, the loss), a late payment, a family's
## loan from the Banco (4.16 rules, what it pays goes to the banker), an AI owner's decision, and a saved game.

const FAM := "fam_0001"
const BANKER := "chr_0001"
const BANK := "bld_0001"


func _cat(edit: Callable = Callable()) -> Catalog:
	var c := Catalog.load_from()
	if edit.is_valid():
		edit.call(c)
	return c


func _sim(c: Catalog = null) -> Sim:
	var cat := c if c != null else _cat()
	return Sim.new(NewGame.from_start(cat, "scholar_banker", "normal", {"cast": "fixed"}, 1)["state"], cat)


func _to_dawn(sim: Sim) -> Array:
	var ev: Array = []
	for i: int in 1500:
		var e := sim.step()
		ev.append_array(e)
		if e.any(func(x: Dictionary) -> bool: return str(x["type"]) == "phase_changed" and str(x.get("phase", "")) == "dawn"):
			break
	return ev


func _run(sim: Sim, minutes: int) -> Array:
	var ev: Array = []
	for i: int in minutes:
		ev.append_array(sim.step())
	return ev


func _of(ev: Array, type: String) -> Array:
	return ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


## An application of a household waiting at the Banco now (as Bank._new_applications leaves it).
func _app(sim: Sim, risk: String, amount: int, term: int) -> String:
	var who := ""
	for id: String in sim.state.characters:
		if TownLife.is_townsperson(sim.state, id) and TownLife.is_adult(sim.state, sim.catalog, id):
			who = id
			break
	var a := Bank._add(sim, BANK, "household", str(sim.state.characters[who]["family"]), who, amount, term, risk)
	return str(a["id"])


func _gold(sim: Sim) -> int:
	return Money.gold(sim.state, FAM)


func _ledger_adds_up(sim: Sim, fam: String, gold0: int) -> bool:
	var total := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["family"]) == fam:
			total += int(e["amount"])
	return gold0 + total == Money.gold(sim.state, fam)


func test_the_start() -> void:
	var sim := _sim()
	var st := sim.state
	var b: Dictionary = st.buildings[BANK]
	eq([str(b["type"]), str(b["owner"])], ["bank", FAM], "the Banco is the family's")
	eq(b["origin"], [25, 20], "on the player forge's plot")
	eq(str(st.families[FAM].get("title", "")), "citizen", "a Citizen (the title of a Banco)")
	eq(_gold(sim), int(sim.catalog.starts()["scholar_banker"]["family"]["gold"]), "the capital of a money-changer's house")
	eq(int(Loans.status(sim, "lon_0001")["outstanding"]), 200, "and the start's debt, as every start")
	eq(Bank.banks(st), [BANK], "one Banco in town")


func test_applications_come_at_dawn_and_expire() -> void:
	var sim := _sim()
	var ev := _to_dawn(sim)
	var apps := Bank.applications(sim.state, BANK)
	check(not apps.is_empty(), "applications at dawn (%d)" % apps.size())
	eq(_of(ev, "loan_application").size(), apps.size(), "one event each")
	var cfg: Dictionary = Bank.cfg(sim)
	for a: Dictionary in apps:
		check(str(a["risk"]) in ["A", "B", "C"], "a risk")
		check(int(a["amount"]) >= int(cfg["applications"]["amount"][0]) and int(a["amount"]) <= int(cfg["applications"]["amount"][1]),
			"an amount in range (%d)" % int(a["amount"]))
		check(int(a["term_days"]) in (cfg["applications"]["terms"] as Array), "a term of the table")
		near(float(a["max_interest"]), float(cfg["risks"][str(a["risk"])]["max_interest"]), 0.0001, "its risk's maximum")
	var fams := apps.map(func(a: Dictionary) -> String: return str(a["borrower_family"]))
	var uniq := {}
	for f: String in fams:
		uniq[f] = true
	eq(uniq.size(), fams.size(), "one per household")
	var first := str(apps[0]["id"])
	_to_dawn(sim)
	_to_dawn(sim)
	check(Bank.find_application(sim.state, first).is_empty(), "gone after two days")


func test_granting_a_loan() -> void:
	var sim := _sim()
	var id := _app(sim, "B", 300, 8)
	var gold0 := _gold(sim)
	eq(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.3})["reason"],
		"too_expensive", "more than the 25 % a B accepts")
	var r := Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.25})
	check(r["ok"], "lends: %s" % r["reason"])
	eq(_gold(sim), gold0 - 300, "300 out of the banker")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([str(e["category"]), int(e["amount"])], ["bank_lent", -300], "as capital lent, not an expense")
	var loan := ""
	for l: String in Bank.portfolio(sim.state, FAM):
		loan = l
	var L: Dictionary = sim.state.loans[loan]
	near(float(L["interest"]), 0.25, 0.0001, "8 days = a year at 25 %")
	eq([int(L["outstanding"]), int(L["principal_left"]), bool(L["household"]), str(L["kind"])], [375, 300, true, "bank"],
		"375 owed by the household")
	var amounts: Array = (L["installments"] as Array).map(func(i: Dictionary) -> int: return int(i["amount"]))
	eq(amounts, [93, 93, 93, 96], "four installments every 2 days")
	check(Bank.find_application(sim.state, id).is_empty(), "the application is gone")
	var poor := _app(sim, "A", 3000, 4)
	eq(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": poor, "interest": 0.1})["reason"],
		"not_enough_gold", "not more than its gold")
	var other := ""
	for c: String in sim.state.characters:
		if str(sim.state.characters[c].get("family", "")) == "fam_0002":
			other = c
	eq(Orders.apply(sim, {"type": "grant_loan", "actor": other, "application": poor, "interest": 0.1})["reason"],
		"not_owner", "only the Banco's owner")
	eq(Orders.apply(sim, {"type": "reject_application", "actor": BANKER, "application": poor})["ok"], true, "turned down")


func test_installments_pay_principal_and_interest() -> void:
	var sim := _sim(_cat(func(c: Catalog) -> void:
		for r: String in c.bank["risks"]:
			c.bank["risks"][r]["default"] = 0.0))
	var gold0 := _gold(sim)
	var id := _app(sim, "B", 300, 8)
	check(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.25})["ok"], "lent")
	var ev := _run(sim, 8 * Clock.MINUTES_PER_DAY + 10)
	var paid := _of(ev, "installment_paid")
	eq(paid.size(), 4, "four installments paid from outside")
	var p := 0
	var i := 0
	for x: Dictionary in paid:
		p += int(x["principal"])
		i += int(x["interest"])
	eq([p, i], [300, 75], "the capital back and 75 of interest")
	eq(_of(ev, "bank_loan_closed").size(), 1, "the loan closes")
	check(_ledger_adds_up(sim, FAM, gold0), "the ledger adds up to the gold")


func test_a_default_and_its_collateral() -> void:
	var sim := _sim(_cat(func(c: Catalog) -> void:
		for r: String in c.bank["risks"]:
			c.bank["risks"][r]["default"] = 1.0
		c.bank["late_payment"]["chance_per_day"] = 0.0))
	var gold0 := _gold(sim)
	var id := _app(sim, "C", 200, 4)
	check(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.4})["ok"], "lent")
	var loan: String = Bank.portfolio(sim.state, FAM)[0]
	var ev := _run(sim, 2 * Clock.MINUTES_PER_DAY + 5)
	eq(_of(ev, "loan_defaulted").size(), 1, "the first installment unpaid: default")
	eq(str(sim.state.loans[loan]["state"]), "defaulted", "in default")
	eq(Orders.apply(sim, {"type": "claim_collateral", "actor": BANKER, "loan": loan})["reason"], "too_soon", "a day first")
	_run(sim, Clock.MINUTES_PER_DAY)
	var owed := int(sim.state.loans[loan]["outstanding"])
	var back := Bank.recovery(sim, loan)
	eq(back, roundi(owed * 0.3), "30 % of what is owed (not notarial)")
	var g := _gold(sim)
	check(Orders.apply(sim, {"type": "claim_collateral", "actor": BANKER, "loan": loan})["ok"], "claims")
	eq(_gold(sim), g + back, "the town gives it back")
	eq(str(sim.state.loans[loan]["state"]), "seized", "the loan is closed")
	var lost := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["category"]) == "bank_losses":
			lost -= int(e["amount"])
	eq(lost, 200 - back, "the capital not recovered is a loss")
	check(_ledger_adds_up(sim, FAM, gold0), "the ledger adds up to the gold")


func test_a_late_payment() -> void:
	var sim := _sim(_cat(func(c: Catalog) -> void:
		for r: String in c.bank["risks"]:
			c.bank["risks"][r]["default"] = 1.0
		c.bank["late_payment"]["chance_per_day"] = 1.0))
	var id := _app(sim, "C", 200, 4)
	check(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.4})["ok"], "lent")
	var loan: String = Bank.portfolio(sim.state, FAM)[0]
	var owed := int(sim.state.loans[loan]["outstanding"])
	var ev := _run(sim, 3 * Clock.MINUTES_PER_DAY + 5)
	eq(_of(ev, "loan_defaulted").size(), 1, "a default")
	eq(str(sim.state.loans[loan]["state"]), "paid", "then paid late")
	var got := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["ref"]) == loan and int(e["amount"]) > 0:
			got += int(e["amount"])
	eq(got, roundi(owed * 1.1), "all it owed and 10 % more")


func test_a_familys_loan_from_the_bank() -> void:
	var sim := _sim()
	var rival := ""
	for c: String in sim.state.characters:
		if str(sim.state.characters[c].get("family", "")) == "fam_0002" and Kin.is_adult(sim, c):
			rival = c
			break
	eq(Orders.apply(sim, {"type": "request_loan", "actor": BANKER, "lender": BANK, "amount": 100, "term_days": 8})["reason"],
		"own_bank", "not its own Banco")
	var r := Orders.apply(sim, {"type": "request_loan", "actor": rival, "lender": BANK, "amount": 100, "term_days": 8})
	check(r["ok"], "the rival asks the Banco: %s" % r["reason"])
	var apps := Bank.applications(sim.state, BANK).filter(func(a: Dictionary) -> bool: return str(a["kind"]) == "family")
	eq(apps.size(), 1, "its application waits there")
	eq(Orders.apply(sim, {"type": "request_loan", "actor": rival, "lender": BANK, "amount": 100, "term_days": 8})["reason"],
		"already_asked", "once")
	var rg := Money.gold(sim.state, "fam_0002")
	check(Orders.apply(sim, {"type": "grant_loan", "actor": BANKER, "application": str(apps[0]["id"]),
		"interest": float(apps[0]["max_interest"])})["ok"], "the banker lends")
	eq(Money.gold(sim.state, "fam_0002"), rg + 100, "the family gets the gold")
	var loan: String = Bank.portfolio(sim.state, FAM)[0]
	check(not Bank.is_household(sim.state.loans[loan]), "a family's loan: the debts of 4.16")
	var g := _gold(sim)
	var pay := Loans.next_amount(sim.state.loans[loan])
	check(Orders.apply(sim, {"type": "repay_loan", "actor": rival, "loan": loan, "amount": pay})["ok"], "pays an installment")
	eq(_gold(sim), g + pay, "what it pays goes to the banker")
	eq(Orders.apply(sim, {"type": "claim_collateral", "actor": BANKER, "loan": loan})["reason"], "family_debt",
		"a family's loan has no collateral to claim")


func test_an_ai_owner_decides() -> void:
	var sim := _sim()
	sim.state.buildings[BANK]["owner"] = "fam_0002"   # the rival's Banco (capture only)
	sim.state.families["fam_0002"]["gold"] = 1000
	check(Orders.apply(sim, {"type": "request_loan", "actor": BANKER, "lender": BANK, "amount": 100, "term_days": 8})["ok"],
		"the player asks the rival's Banco")
	var g := _gold(sim)
	var ev := _to_dawn(sim)
	eq(_of(ev, "loan_granted").filter(func(e: Dictionary) -> bool: return str(e["borrower_family"]) == FAM).size(), 1,
		"the AI accepts: the player's wealth covers it")
	eq(_gold(sim), g + 100, "the gold comes")


func test_a_saved_game_with_loans() -> void:
	var a := _sim()
	_to_dawn(a)
	var id := _app(a, "A", 200, 8)
	check(Orders.apply(a, {"type": "grant_loan", "actor": BANKER, "application": id, "interest": 0.15})["ok"], "lent")
	var back: WorldState = SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.town.get("bank", {})), SaveFile.canonical(a.state.town["bank"]), "the applications survive")
	var b := Sim.new(back, a.catalog)
	var e1 := _run(a, 3 * Clock.MINUTES_PER_DAY)
	var e2 := _run(b, 3 * Clock.MINUTES_PER_DAY)
	eq(SaveFile.canonical({"e": _of(e2, "installment_paid")}), SaveFile.canonical({"e": _of(e1, "installment_paid")}),
		"the loaded game goes on the same")
