class_name Loans
extends RefCounted
## Debts (GDD 4.16): the starting loan, repaying, warnings, the extension with its surcharge, the seizure and the
## ruin that ends the game (D18). Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
##
## Loan: {id, family, lender, principal, outstanding, due_minute, extended, state: active|extended|paid|seized,
##        building (the forge it pays for: the seizure takes its goods), overdue_reputation, extension_seasons,
##        extension_surcharge, warned: [days already warned for the current due date]}.
## The terms come from the start (data/starts/<id>.json "loan"), the warning days from data/accounts.json.

const ACTIVE: String = "active"
const EXTENDED: String = "extended"
const PAID: String = "paid"
const SEIZED: String = "seized"


## A new loan for `fam` (NewGame.from_start). The debt does not bring gold in: the loan already paid the building.
static func create(state: WorldState, fam: String, terms: Dictionary, principal: int, due_minute: int,
		building: String) -> String:
	var id := Ids.next(state, "lon")
	state.loans[id] = {"id": id, "family": fam, "lender": str(terms.get("lender", "moneylender")),
		"principal": principal, "outstanding": principal, "due_minute": due_minute, "extended": false,
		"state": ACTIVE, "building": building, "overdue_reputation": int(terms.get("overdue_reputation", -10)),
		"extension_seasons": int(terms.get("extension_seasons", 1)),
		"extension_surcharge": float(terms.get("extension_surcharge", 0.25)), "warned": []}
	return id


## {"type": "repay_loan", "actor", "loan", "amount"}: pays min(amount, outstanding) from the family purse
## (category loans), from anywhere. Reasons: unknown_actor, unknown_loan, not_your_loan, loan_closed, bad_amount,
## not_enough_gold.
static func order_repay(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var id := str(o.get("loan", ""))
	if not st.loans.has(id):
		return Orders.fail("unknown_loan")
	var loan: Dictionary = st.loans[id]
	var fam := str(loan["family"])
	if str(st.characters[actor].get("family", "")) != fam:
		return Orders.fail("not_your_loan")
	if not is_open(loan):
		return Orders.fail("loan_closed")
	var amount := int(o.get("amount", 0))
	if amount <= 0:
		return Orders.fail("bad_amount")
	var pay := mini(amount, int(loan["outstanding"]))
	if not Money.can_pay(st, fam, pay):
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -pay, Money.LOANS, id, "", actor)
	loan["outstanding"] = int(loan["outstanding"]) - pay
	sim.events.append({"type": "loan_payment", "actor": actor, "family": fam, "loan": id, "amount": pay,
		"outstanding": int(loan["outstanding"])})
	if OS.is_debug_build():
		print("[Loans] %s paga %d de %s (%s): quedan %d" % [actor, pay, id, fam, int(loan["outstanding"])])
	if int(loan["outstanding"]) == 0:
		loan["state"] = PAID
		sim.events.append({"type": "loan_repaid", "actor": actor, "family": fam, "loan": id,
			"extended": bool(loan["extended"])})
		Notices.add(sim, fam, Notices.INFO, "notice.loan_repaid", {"loan": id, "lender": str(loan["lender"])})
		if OS.is_debug_build():
			print("[Loans] %s saldado (prórroga=%s)" % [id, loan["extended"]])
	return Orders.ok()


## Warnings before the due date, the due date (extension), the end of the extension (seizure, ruin).
static func step(sim: Sim) -> void:
	var st := sim.state
	if st.loans.is_empty():
		return
	var now := int(st.clock["minute"])
	var ids: Array = st.loans.keys()
	ids.sort()
	for id: String in ids:
		var loan: Dictionary = st.loans[id]
		if not is_open(loan):
			continue
		var due := int(loan["due_minute"])
		if now >= due:
			if str(loan["state"]) == ACTIVE:
				_extend(sim, id)
			else:
				_seize(sim, id)
			continue
		_warn(sim, id, due - now)


## {} | {id, family, lender, principal, outstanding, due_minute, extended, state, days_left} for the UI.
## days_left: whole days (rounded up) until the due date, 0 once due.
static func status(sim: Sim, id: String) -> Dictionary:
	if not sim.state.loans.has(id):
		return {}
	var loan: Dictionary = sim.state.loans[id]
	var left := int(loan["due_minute"]) - int(sim.state.clock["minute"])
	return {"id": id, "family": str(loan["family"]), "lender": str(loan["lender"]),
		"principal": int(loan["principal"]), "outstanding": int(loan["outstanding"]),
		"due_minute": int(loan["due_minute"]), "extended": bool(loan["extended"]), "state": str(loan["state"]),
		"days_left": maxi(0, ceili(float(left) / Clock.MINUTES_PER_DAY))}


## The open loans of `fam` (ids, sorted).
static func of_family(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for id: String in sim.state.loans:
		var loan: Dictionary = sim.state.loans[id]
		if str(loan["family"]) == fam and is_open(loan):
			out.append(id)
	out.sort()
	return out


static func is_open(loan: Dictionary) -> bool:
	return str(loan.get("state", "")) in [ACTIVE, EXTENDED]


## Urgent notices when the due date is within one of loan_warn_days. If several thresholds were crossed at once
## (a game loaded late), only the most urgent one is said.
static func _warn(sim: Sim, id: String, minutes_left: int) -> void:
	var loan: Dictionary = sim.state.loans[id]
	var warned: Array = loan.get("warned", [])
	var say := -1
	for d: Variant in sim.catalog.accounts.get("loan_warn_days", [2, 1]):
		var days := int(d)
		if minutes_left <= days * Clock.MINUTES_PER_DAY and not days in warned:
			warned.append(days)
			if say < 0 or days < say:
				say = days
	if say < 0:
		return
	loan["warned"] = warned
	var fam := str(loan["family"])
	var key := "notice.loan_extension_due_soon" if bool(loan["extended"]) else "notice.loan_due_soon"
	Notices.add(sim, fam, Notices.URGENT, key, {"loan": id, "days": say, "amount": int(loan["outstanding"])})
	if OS.is_debug_build():
		print("[Loans] aviso: %s vence en %d días (pendiente=%d, prórroga=%s)" % [id, say, int(loan["outstanding"]),
			loan["extended"]])


## Due unpaid: reputation + overdue_reputation, the outstanding grows by the surcharge and the due date moves
## extension_seasons seasons on.
static func _extend(sim: Sim, id: String) -> void:
	var st := sim.state
	var loan: Dictionary = st.loans[id]
	var fam := str(loan["family"])
	var rep := int(loan["overdue_reputation"])
	Reputation.change(sim, fam, rep, "loan_overdue")  # H9
	var before := int(loan["outstanding"])
	loan["outstanding"] = roundi(before * (1.0 + float(loan["extension_surcharge"])))
	var days := int(loan["extension_seasons"]) * int(sim.catalog.time["days_per_season"])
	loan["due_minute"] = int(loan["due_minute"]) + days * Clock.MINUTES_PER_DAY
	loan["extended"] = true
	loan["state"] = EXTENDED
	loan["warned"] = []
	sim.events.append({"type": "loan_extended", "family": fam, "loan": id, "outstanding": int(loan["outstanding"])})
	Notices.add(sim, fam, Notices.URGENT, "notice.loan_extended",
		{"loan": id, "amount": int(loan["outstanding"]), "days": days, "reputation": rep})
	if OS.is_debug_build():
		print("[Loans] %s vence sin pagar: reputación %+d, pendiente %d -> %d, prórroga hasta el minuto %d" % [id, rep,
			before, int(loan["outstanding"]), int(loan["due_minute"])])


## The extension is due: the lender takes the gold, then the goods of the building's storage at the market's sell
## price (whole units, in storage order, the last unit may cover more than what is left: no change is given). If it
## is not enough, ruin: the game ends (D18).
static func _seize(sim: Sim, id: String) -> void:
	var st := sim.state
	var loan: Dictionary = st.loans[id]
	var fam := str(loan["family"])
	var owed := int(loan["outstanding"])
	var take := mini(maxi(0, Money.gold(st, fam)), owed)
	if take > 0:
		Money.change(sim, fam, -take, Money.LOANS, id)
		owed -= take
	var items: Array = []
	var bld := str(loan.get("building", ""))
	if owed > 0 and st.buildings.has(bld) and Money.family_of(st, bld) == fam:
		var inv: Dictionary = st.buildings[bld]["inventory"]
		for s: Dictionary in (inv["stacks"] as Array).duplicate(true):
			if owed <= 0:
				break
			var item := str(s["item"])
			var q := int(s["quality"])
			var price := Market.price(sim, item, q, "sell")
			if price <= 0:
				continue
			var units := mini(int(s["qty"]), ceili(float(owed) / price))
			Inventory.remove(inv, item, q, units)
			owed -= units * price
			items.append({"item": item, "quality": q, "qty": units, "value": units * price})
	loan["outstanding"] = maxi(0, owed)
	loan["state"] = SEIZED
	sim.events.append({"type": "loan_seized", "family": fam, "loan": id, "gold": take, "items": items})
	if OS.is_debug_build():
		print("[Loans] embargo de %s (%s): oro=%d, mercancía=%s, falta=%d" % [id, fam, take, str(items), maxi(0, owed)])
	if owed <= 0:
		Notices.add(sim, fam, Notices.URGENT, "notice.loan_seized", {"loan": id, "gold": take, "items": items.size()},
			bld)
		return
	Notices.add(sim, fam, Notices.URGENT, "notice.ruin", {"loan": id, "missing": owed}, bld)
	if st.ending.is_empty():
		st.ending = {"kind": "ruin", "family": fam, "minute": int(st.clock["minute"]), "loan": id}
		sim.events.append({"type": "game_over", "kind": "ruin", "family": fam})
		if OS.is_debug_build():
			print("[Loans] RUINA: %s no cubre %s (faltan %d). Fin de la partida." % [fam, id, owed])
