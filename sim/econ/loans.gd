class_name Loans
extends RefCounted
## Debts (GDD 4.16): the starting loan, repaying, warnings, the extension with its surcharge, the seizure and the
## ruin that ends the game (D18). Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
##
## Loan: {id, family, lender, principal, outstanding, due_minute, extended, state: active|extended|paid|seized,
##        building (the forge it pays for: the seizure takes its goods), overdue_reputation, extension_seasons,
##        extension_surcharge, warned: [days already warned for the current due date]}.
## The terms come from the start (data/starts/<id>.json "loan"), the warning days from data/accounts.json.
## H12.2 (04d 4.22.5.6, P8; O12 a): the Loan grows, read with defaults (no save version): kind ("" for the start's
## debt and the fines, "emergency", "moneylender"), interest (the term's rate, 0-1), installments ([{due_minute,
## amount, paid}]; [] = one payment at due_minute, as in H3), collateral ({kind: building, id}), lender_family ("": the
## town's moneylender) and notarized. The debt of the start and the fines keep interest 0 and one payment: their rules
## do not change. request_loan: any family asks the town's moneylender (data/accounts.json "moneylender") for up to
## max_share of its estimated wealth (Dynasty.wealth: gold, buildings, upgrades), for one of terms_days, at
## annual_interest prorated to the term (a year = days_per_year), paid in equal installments every installment_days;
## refused with another moneylender loan open or a loan in default (extended). An installment due unpaid is a default:
## the whole loan goes to the extension of 4.16 (reputation, surcharge, one more season; then the seizure). A payment
## covers the installments in order.

const ACTIVE: String = "active"
const EXTENDED: String = "extended"
const PAID: String = "paid"
const SEIZED: String = "seized"


## A fine `amount` (category, ref, building): paid from the gold above fine_loan.keep_gold; the rest is owed to the town
## as a loan (added to the family's open town loan, else a new one due in term_days; data/upgrade_rules.json
## fine_loan) [provisional, pulido del MVP]. Returns {paid, owed, loan}.
static func charge_fine(sim: Sim, fam: String, amount: int, category: String, ref: String, building: String,
		actor: String = "") -> Dictionary:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.upgrade_rules.get("fine_loan", {})
	var pay := clampi(Money.gold(st, fam) - int(cfg.get("keep_gold", 30)), 0, amount)
	if pay > 0:
		Money.change(sim, fam, -pay, category, ref, building, actor)
	var owed := amount - pay
	var id := ""
	if owed > 0:
		var lender := str(cfg.get("lender", "town"))
		for lid: String in of_family(sim, fam):
			var l: Dictionary = st.loans[lid]
			if str(l.get("lender", "")) == lender and is_open(l):
				id = lid
		if id != "":
			st.loans[id]["outstanding"] = int(st.loans[id]["outstanding"]) + owed
			st.loans[id]["principal"] = int(st.loans[id]["principal"]) + owed
		else:
			var due := (Clock.day(int(st.clock["minute"])) + int(cfg.get("term_days", 8))) * Clock.MINUTES_PER_DAY
			id = create(st, fam, cfg, owed, due, building)
		sim.events.append({"type": "fine_owed", "family": fam, "loan": id, "amount": owed, "ref": ref})
		Notices.add(sim, fam, Notices.URGENT, "notice.fine_loan", {"amount": owed, "paid": pay,
			"day": Clock.day(int(st.loans[id]["due_minute"]))}, building)
	if OS.is_debug_build():
		print("[Loans] multa %s de %s: paga %d, debe %d a la ciudad (%s)" % [ref, fam, pay, owed, id])
	return {"paid": pay, "owed": owed, "loan": id}


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
	_pay_installments(loan, pay)
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
		var due := next_due(loan)
		if now >= due:
			if str(loan["state"]) == ACTIVE:
				_extend(sim, id, due)
			else:
				_seize(sim, id)
			continue
		_warn(sim, id, due - now)


## {} | {id, family, lender, principal, outstanding, due_minute, extended, state, days_left, kind, interest,
## next_due, next_amount, installments_left} for the UI. days_left: whole days (rounded up) until the due date, 0 once
## due. next_due / next_amount: the next installment (the due date and all that is owed without installments).
static func status(sim: Sim, id: String) -> Dictionary:
	if not sim.state.loans.has(id):
		return {}
	var loan: Dictionary = sim.state.loans[id]
	var left := int(loan["due_minute"]) - int(sim.state.clock["minute"])
	var nxt := next_due(loan)
	var left_inst := 0
	for i: Dictionary in loan.get("installments", []):
		if int(i.get("paid", 0)) < int(i.get("amount", 0)):
			left_inst += 1
	return {"id": id, "family": str(loan["family"]), "lender": str(loan["lender"]),
		"principal": int(loan["principal"]), "outstanding": int(loan["outstanding"]),
		"due_minute": int(loan["due_minute"]), "extended": bool(loan["extended"]), "state": str(loan["state"]),
		"days_left": maxi(0, ceili(float(left) / Clock.MINUTES_PER_DAY)), "kind": str(loan.get("kind", "")),
		"interest": float(loan.get("interest", 0.0)), "next_due": nxt, "next_amount": next_amount(loan),
		"installments_left": left_inst}


## The minute the next payment falls due: the first installment not paid in full (while the loan is active and has
## installments), else the loan's due date.
static func next_due(loan: Dictionary) -> int:
	if str(loan.get("state", "")) == ACTIVE:
		for i: Dictionary in loan.get("installments", []):
			if int(i.get("paid", 0)) < int(i.get("amount", 0)):
				return int(i["due_minute"])
	return int(loan["due_minute"])


## What the next payment asks: what is left of the first installment not paid, else all that is owed.
static func next_amount(loan: Dictionary) -> int:
	if str(loan.get("state", "")) == ACTIVE:
		for i: Dictionary in loan.get("installments", []):
			if int(i.get("paid", 0)) < int(i.get("amount", 0)):
				return int(i["amount"]) - int(i.get("paid", 0))
	return int(loan.get("outstanding", 0))


## A payment of `pay` covers the installments in order (a paid one restarts the warnings for the next).
static func _pay_installments(loan: Dictionary, pay: int) -> void:
	var left := pay
	for i: Dictionary in loan.get("installments", []):
		if left <= 0:
			break
		var owed := int(i.get("amount", 0)) - int(i.get("paid", 0))
		if owed <= 0:
			continue
		var n := mini(owed, left)
		i["paid"] = int(i.get("paid", 0)) + n
		left -= n
		if int(i["paid"]) >= int(i["amount"]):
			loan["warned"] = []


## The moneylender's terms (data/accounts.json "moneylender").
static func moneylender(sim: Sim) -> Dictionary:
	return sim.catalog.accounts.get("moneylender", {})


## The most `fam` may ask the moneylender for now (0 if it may not ask): max_share × its estimated wealth, and why not
## ("" | has_moneylender_loan | in_default).
static func borrow_limit(sim: Sim, fam: String) -> Dictionary:
	var cfg := moneylender(sim)
	for id: String in of_family(sim, fam):
		var l: Dictionary = sim.state.loans[id]
		if str(l.get("state", "")) == EXTENDED:
			return {"max": 0, "reason": "in_default"}
		if str(l.get("kind", "")) == "moneylender":
			return {"max": 0, "reason": "has_moneylender_loan"}
	var w := maxi(0, Dynasty.wealth(sim, fam))
	return {"max": floori(float(w) * float(cfg.get("max_share", 0.5))), "reason": ""}


## What a loan of `amount` for `term_days` costs: {interest (rate of the term), owed, installments [{due_minute, amount}]}
## from now.
static func quote(sim: Sim, amount: int, term_days: int) -> Dictionary:
	var cfg := moneylender(sim)
	var year := maxi(1, Clock.days_per_year(sim.catalog.time))
	var rate := float(cfg.get("annual_interest", 0.25)) * float(term_days) / float(year)
	var owed := roundi(float(amount) * (1.0 + rate))
	var every := maxi(1, int(cfg.get("installment_days", 2)))
	var n := maxi(1, term_days / every)
	var now := int(sim.state.clock["minute"])
	var out: Array = []
	var given := 0
	for k: int in n:
		var a := owed / n if k < n - 1 else owed - given
		given += a
		out.append({"due_minute": now + (k + 1) * every * Clock.MINUTES_PER_DAY, "amount": a, "paid": 0})
	return {"interest": rate, "owed": owed, "installments": out}


## {"type": "request_loan", "actor", "lender": "moneylender", "amount", "term_days"}: the town's moneylender lends
## `amount` now (category loans) against the family's main building. Reasons: unknown_actor, no_family, too_young,
## unknown_lender, bad_term, bad_amount, in_default, has_moneylender_loan, over_limit.
static func order_request(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	if not Kin.is_adult(sim, actor):
		return Orders.fail("too_young")
	if str(o.get("lender", "moneylender")) != "moneylender":
		return Orders.fail("unknown_lender")  # the Banks of the families come with the banker (4.22.5.6)
	var cfg := moneylender(sim)
	var term := int(o.get("term_days", 0))
	if not term in (cfg.get("terms_days", [8, 16]) as Array).map(func(x: Variant) -> int: return int(x)):
		return Orders.fail("bad_term")
	var amount := int(o.get("amount", 0))
	if amount < int(cfg.get("min_amount", 20)):
		return Orders.fail("bad_amount")
	var lim := borrow_limit(sim, fam)
	if str(lim["reason"]) != "":
		return Orders.fail(str(lim["reason"]))
	if amount > int(lim["max"]):
		return Orders.fail("over_limit")
	var q := quote(sim, amount, term)
	var inst: Array = q["installments"]
	var due := int((inst[inst.size() - 1] as Dictionary)["due_minute"])
	var terms := {"lender": "moneylender", "overdue_reputation": int(cfg.get("overdue_reputation", -10)),
		"extension_seasons": int(cfg.get("extension_seasons", 1)),
		"extension_surcharge": float(cfg.get("extension_surcharge", 0.25))}
	var home := _collateral_of(st, fam)
	var id := create(st, fam, terms, amount, due, home)
	var loan: Dictionary = st.loans[id]
	loan["kind"] = "moneylender"
	loan["interest"] = float(q["interest"])
	loan["outstanding"] = int(q["owed"])
	loan["installments"] = inst
	loan["collateral"] = {"kind": "building", "id": home}
	loan["lender_family"] = ""
	loan["notarized"] = false
	Money.change(sim, fam, amount, Money.LOANS, id, "", actor)
	sim.events.append({"type": "loan_granted", "family": fam, "actor": actor, "loan": id, "lender": "moneylender",
		"amount": amount, "owed": int(q["owed"]), "term_days": term})
	Notices.add(sim, fam, Notices.INFO, "notice.loan_granted", {"amount": amount, "owed": int(q["owed"]),
		"installments": inst.size(), "days": term})
	if OS.is_debug_build():
		print("[Loans] el prestamista presta %d a %s (%s): debe %d en %d cuotas, %d días (interés %.3f)" % [amount, fam,
			id, int(q["owed"]), inst.size(), term, float(q["interest"])])
	return Orders.ok()


## The building that answers for a loan (its seizure takes that building's goods, 4.16): the family's first building
## by id (its home or workshop at the start).
static func _collateral_of(st: WorldState, fam: String) -> String:
	var ids: Array = st.buildings.keys()
	ids.sort()
	var first := ""
	for b: String in ids:
		if str(st.buildings[b].get("owner", "")) != fam:
			continue
		if first == "":
			first = b
	return first


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


## Due unpaid (the loan's date or, H12.2, an installment's: `due`): reputation + overdue_reputation, the outstanding
## grows by the surcharge and the due date moves extension_seasons seasons on from it (all owed then: no more
## installments).
static func _extend(sim: Sim, id: String, due: int = -1) -> void:
	var st := sim.state
	var loan: Dictionary = st.loans[id]
	var fam := str(loan["family"])
	var rep := int(loan["overdue_reputation"])
	Reputation.change(sim, fam, rep, "loan_overdue")  # H9
	var before := int(loan["outstanding"])
	loan["outstanding"] = roundi(before * (1.0 + float(loan["extension_surcharge"])))
	var days := int(loan["extension_seasons"]) * int(sim.catalog.time["days_per_season"])
	var from := due if due >= 0 else int(loan["due_minute"])
	loan["due_minute"] = from + days * Clock.MINUTES_PER_DAY
	if loan.get("installments") is Array and not (loan["installments"] as Array).is_empty():
		loan["installments"] = []
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
	if str(loan.get("kind", "")) == Emergency.KIND and Emergency.seize_good(sim, fam, "emergency_loan"):
		return  # Equilibrio 2: an emergency loan takes a good (not the home) before the ruin
	Notices.add(sim, fam, Notices.URGENT, "notice.ruin", {"loan": id, "missing": owed}, bld)
	if st.ending.is_empty():
		st.ending = {"kind": "ruin", "family": fam, "minute": int(st.clock["minute"]), "loan": id}
		sim.events.append({"type": "game_over", "kind": "ruin", "family": fam})
		if OS.is_debug_build():
			print("[Loans] RUINA: %s no cubre %s (faltan %d). Fin de la partida." % [fam, id, owed])
