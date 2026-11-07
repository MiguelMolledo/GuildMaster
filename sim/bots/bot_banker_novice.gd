class_name BotBankerNovice
extends RefCounted
## H12.2 (docs/gdd/04d_otras_clases.md 4.22.5.8): the novice of the banker's start (scholar_banker). Criterion 1 of H12
## (each profession has a bot that earns money with it): banker_novice in tools/sim_runner.gd, its targets in
## data/targets.json (goldflow.start_banker: net gold per day without the capital lent and returned, nor the debt).
## Every minute, only real orders (management: no walking), read through the same queries as the Bank panel:
##   debt:      pays the start's debt as soon as the family has it plus RESERVE (keeps lending); from the day before it
##              falls due, whatever it has.
##   lend:      grants the applications of risk A and B at their maximum interest while the gold left stays over RESERVE
##              (the debt's money is kept while the debt is open); turns down the ones of risk C (4.22.5.8: «acepta A y B
##              con margen»).
##   claim:     claims the collateral of a loan in default as soon as it may (a day after).
## Choices at the start (bot_choices): none.

const ACTOR: String = "chr_0001"
const RESERVE: int = 60              # gold always kept (two days of upkeep and a little)
const LEND_RISKS: Array[String] = ["A", "B"]


func bot_choices() -> Dictionary:
	return {}


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.ending.is_empty():
		return []
	var fam := str(st.characters[ACTOR].get("family", ""))
	var o := _repay(sim, fam)
	if not o.is_empty():
		return [o]
	for id: String in Bank.portfolio(st, fam):
		var l: Dictionary = st.loans[id]
		if str(l.get("state", "")) == "defaulted" and Bank.is_household(l):
			var after := int(Bank.cfg(sim).get("recovery", {}).get("claim_after_days", 1)) * Clock.MINUTES_PER_DAY
			if int(st.clock["minute"]) - int(l.get("defaulted_at", 0)) >= after:
				return [{"type": "claim_collateral", "actor": ACTOR, "loan": id}]
	var keep := RESERVE + _debt(sim, fam)
	for bld: String in Bank.banks(st):
		if str(st.buildings[bld].get("owner", "")) != fam:
			continue
		for a: Dictionary in Bank.applications(st, bld):
			if not str(a["risk"]) in LEND_RISKS:
				return [{"type": "reject_application", "actor": ACTOR, "application": str(a["id"])}]
			if Money.gold(st, fam) - int(a["amount"]) >= keep:
				return [{"type": "grant_loan", "actor": ACTOR, "application": str(a["id"]),
					"interest": float(a["max_interest"])}]
	return []


## What the open debts of the start ask to keep (all of it while open).
func _debt(sim: Sim, fam: String) -> int:
	var owed := 0
	for id: String in Loans.of_family(sim, fam):
		owed += int(sim.state.loans[id]["outstanding"])
	return owed


func _repay(sim: Sim, fam: String) -> Dictionary:
	var gold := Money.gold(sim.state, fam)
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		var owed := int(s["outstanding"])
		if gold >= owed + RESERVE:
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": owed}
		if int(s["days_left"]) <= 1 and gold > 5:
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": mini(owed, gold - 5)}
	return {}
