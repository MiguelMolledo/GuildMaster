class_name Bank
extends RefCounted
## The banker's Banco (docs/gdd/04d_otras_clases.md 4.22.5.6, P8; figures in data/bank.json [balance]).
##
## - **Applications.** At each dawn, each Banco with an owner gets the applications of the town's households (chance
##   per day × its upgrades): {id, bank, kind: household, borrower_family, borrower, amount, term_days, risk A/B/C,
##   max_interest (annual), expires}. Families (human or AI) ask with request_loan and lender = the Banco
##   (Loans.order_request): {kind: family, ...} with the risk of their wealth. They wait expires_days, at most max_open.
##   State: state.town.bank = {seq, applications: []} (read with defaults: no save version).
## - **grant_loan** {actor, application, interest}: the owner family lends; interest = annual rate (at most the
##   application's max_interest), prorated to the term; equal installments every installment_days. The gold goes out of
##   the banker (bank_lent); a family borrower gets it (loans); a household's comes from outside (P4). A «contract» in
##   the Banco's storage is used and the loan is notarial. reject_application {actor, application}.
## - **A household's loan** (this module, every minute): at each installment's day the household pays (from outside:
##   the principal part to bank_lent, the rest to interest) unless the default roll comes out (the risk's default × the
##   bank_default upgrades): the loan is in default (notice). Each later dawn, late_payment.chance_per_day that it pays
##   all it owes + the surcharge. claim_collateral {actor, loan} from claim_after_days in default: the town gives back
##   recovery (notarial or plain, + bank_recovery upgrades) of what is owed, the loan closes and the principal not
##   recovered goes from bank_lent to bank_losses (a zero-sum pair of entries: the ledger keeps adding up to the gold).
## - **A family's loan** follows the debts of 4.16 (Loans: warnings, an installment unpaid = the extension, then the
##   seizure); what it pays and what is seized goes to the banker (Loans.pay_lender). The town's moneylender
##   (Loans.order_request, lender moneylender) is another thing: the town lends from outside.
## - **An AI owner** decides the family applications at dawn: it accepts if the borrower's wealth covers ai_accepts_cover
##   × the amount, at ai_interest × the maximum; else it rejects.
## Loan fields of the bank (with the ones of Loans): kind "bank", bank, lender "bank", lender_family, risk, household,
## principal_left, interest (of the term), installments, notarized, defaulted_at.

const KIND: String = "bank"


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.bank


static func _mem(st: WorldState) -> Dictionary:
	if not st.town.get("bank") is Dictionary:
		st.town["bank"] = {"seq": 0, "applications": []}
	return st.town["bank"]


## The applications waiting at `bld` (all banks if "").
static func applications(st: WorldState, bld: String = "") -> Array:
	var b: Variant = st.town.get("bank")
	if not b is Dictionary:
		return []
	return ((b as Dictionary).get("applications", []) as Array).filter(func(a: Dictionary) -> bool:
		return bld == "" or str(a.get("bank", "")) == bld)


static func find_application(st: WorldState, id: String) -> Dictionary:
	for a: Dictionary in applications(st):
		if str(a["id"]) == id:
			return a
	return {}


## The Bancos with an owner, sorted.
static func banks(st: WorldState) -> Array:
	var out: Array = []
	for b: String in st.buildings:
		if str(st.buildings[b].get("type", "")) == "bank" and str(st.buildings[b].get("owner", "")) != "":
			out.append(b)
	out.sort()
	return out


## The loans granted by `fam`'s Bancos (ids sorted), open or not.
static func portfolio(st: WorldState, fam: String) -> Array:
	var out: Array = []
	for id: String in st.loans:
		var l: Dictionary = st.loans[id]
		if str(l.get("kind", "")) == KIND and str(l.get("lender_family", "")) == fam:
			out.append(id)
	out.sort()
	return out


## Whether `loan` is a household's (paid from outside by this module, not the debts of 4.16).
static func is_household(loan: Dictionary) -> bool:
	return str(loan.get("kind", "")) == KIND and bool(loan.get("household", false))


## A risk's annual maximum interest and default chance per installment at `bld` (its upgrades).
static func risk_of(sim: Sim, bld: String, risk: String) -> Dictionary:
	var r: Dictionary = cfg(sim).get("risks", {}).get(risk, {})
	return {"max_interest": float(r.get("max_interest", 0.25)),
		"default": float(r.get("default", 0.05)) * Upgrades.mult(sim, bld, "bank_default")
			* float(sim.catalog.difficulty_levels(sim.state.difficulty).get("bank_default_mult", 1.0))}


## The term rate of an annual `interest` over `term_days` (a year = the days of a year).
static func term_rate(sim: Sim, interest: float, term_days: int) -> float:
	return interest * float(term_days) / float(maxi(1, Clock.days_per_year(sim.catalog.time)))


## What a loan of `amount` over `term_days` at annual `interest` owes and its installments from now.
static func quote(sim: Sim, amount: int, term_days: int, interest: float) -> Dictionary:
	var rate := term_rate(sim, interest, term_days)
	var owed := roundi(float(amount) * (1.0 + rate))
	var every := maxi(1, int(cfg(sim).get("installment_days", 2)))
	var n := maxi(1, term_days / every)
	var now := int(sim.state.clock["minute"])
	var inst: Array = []
	var given := 0
	for k: int in n:
		var a := owed / n if k < n - 1 else owed - given
		given += a
		inst.append({"due_minute": now + (k + 1) * every * Clock.MINUTES_PER_DAY, "amount": a, "paid": 0})
	return {"rate": rate, "owed": owed, "installments": inst}


# --- Step -------------------------------------------------------------------------------------------------------------

## Every minute: the installments of the households' loans that fall due; at dawn, the applications (new and expired),
## the late payments of the loans in default and the AI owners' decisions.
static func step(sim: Sim) -> void:
	var st := sim.state
	if cfg(sim).is_empty():
		return
	if not st.loans.is_empty():
		_collect(sim)
	if not Ledger.is_dawn(sim):
		return
	var bks := banks(st)
	if bks.is_empty() and applications(st).is_empty():
		return
	_expire(sim)
	for b: String in bks:
		_new_applications(sim, b)
	_late_payments(sim)
	for b: String in bks:
		_ai_decide(sim, b)


static func _collect(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var ids: Array = st.loans.keys()
	ids.sort()
	for id: String in ids:
		var l: Dictionary = st.loans[id]
		if not is_household(l) or str(l.get("state", "")) != Loans.ACTIVE:
			continue
		var inst: Array = l.get("installments", [])
		for k: int in inst.size():
			var i: Dictionary = inst[k]
			if int(i.get("paid", 0)) >= int(i["amount"]):
				continue
			if now < int(i["due_minute"]):
				break
			var r := risk_of(sim, str(l.get("bank", "")), str(l.get("risk", "B")))
			if Kin.roll(st, "bank|pay|%s|%d" % [id, k]) < float(r["default"]):
				_default(sim, id)
			else:
				var owed := int(i["amount"]) - int(i.get("paid", 0))
				i["paid"] = int(i["amount"])
				_receive(sim, id, owed, "installment")
			break


## `amount` comes in for loan `id` from its borrower (a household: from outside): its principal part to bank_lent, the
## rest to interest; the loan closes when nothing is owed.
static func _receive(sim: Sim, id: String, amount: int, why: String) -> void:
	var st := sim.state
	var l: Dictionary = st.loans[id]
	var fam := str(l.get("lender_family", ""))
	var split := principal_part(l, amount)
	if int(split[0]) > 0:
		Money.change(sim, fam, int(split[0]), Money.BANK_LENT, id, str(l.get("bank", "")))
	if int(split[1]) > 0:
		Money.change(sim, fam, int(split[1]), Money.INTEREST, id, str(l.get("bank", "")))
	l["principal_left"] = maxi(0, int(l.get("principal_left", 0)) - int(split[0]))
	l["outstanding"] = maxi(0, int(l["outstanding"]) - amount)
	sim.events.append({"type": "installment_paid", "family": fam, "loan": id, "amount": amount, "to_bank": true,
		"principal": int(split[0]), "interest": int(split[1]), "why": why, "borrower_family": str(l["family"])})
	if int(l["outstanding"]) <= 0:
		l["outstanding"] = 0
		l["state"] = Loans.PAID
		sim.events.append({"type": "bank_loan_closed", "family": fam, "loan": id, "how": why})
	if OS.is_debug_build():
		print("[Bank] %s cobra %d de %s (%s): capital %d, interés %d, quedan %d" % [fam, amount, id, why, int(split[0]),
			int(split[1]), int(l["outstanding"])])


## [principal, interest] of a payment of `amount` on loan `l`: the principal in proportion to what is owed, never more
## than the principal left.
static func principal_part(l: Dictionary, amount: int) -> Array:
	var owed := maxi(1, int(l.get("outstanding", 0)))
	var left := int(l.get("principal_left", 0))
	var p := mini(left, roundi(float(amount) * float(left) / float(owed)))
	if amount >= owed:
		p = left
	return [p, amount - p]


static func _default(sim: Sim, id: String) -> void:
	var st := sim.state
	var l: Dictionary = st.loans[id]
	l["state"] = "defaulted"
	l["defaulted_at"] = int(st.clock["minute"])
	var fam := str(l.get("lender_family", ""))
	var who := str(st.families.get(str(l["family"]), {}).get("name", l["family"]))
	sim.events.append({"type": "loan_defaulted", "family": fam, "loan": id, "borrower_family": str(l["family"]),
		"outstanding": int(l["outstanding"])})
	Notices.add(sim, fam, Notices.URGENT, "notice.bank_default", {"family": who, "amount": int(l["outstanding"])},
		str(l.get("bank", "")))
	if OS.is_debug_build():
		print("[Bank] %s no paga su cuota (%s): en impago, debe %d" % [l["family"], id, int(l["outstanding"])])


static func _expire(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var m := _mem(st)
	for a: Dictionary in (m["applications"] as Array).duplicate():
		if now >= int(a["expires"]):
			(m["applications"] as Array).erase(a)
			sim.events.append({"type": "application_expired", "family": str(st.buildings.get(str(a["bank"]), {}).get(
				"owner", "")), "application": str(a["id"]), "kind": str(a["kind"])})


## The households' applications of today at `bld`: floor(chance) of them, and one more with its fraction.
static func _new_applications(sim: Sim, bld: String) -> void:
	var st := sim.state
	var c: Dictionary = cfg(sim).get("applications", {})
	var chance := float(c.get("chance_per_day", 0.7)) * Upgrades.mult(sim, bld, "bank_applications") \
		+ Upgrades.amount(sim, bld, "bank_extra_applications")
	var day := Clock.day(int(st.clock["minute"]))
	var n := floori(chance)
	if Kin.roll(st, "bank|n|%s|%d" % [bld, day]) < chance - float(n):
		n += 1
	for k: int in n:
		if applications(st, bld).size() >= int(c.get("max_open", 6)):
			return
		var who := _borrower(sim, bld, day, k)
		if who == "":
			return
		var span: Array = c.get("amount", [60, 300])
		var step := maxi(1, int(c.get("round_to", 10)))
		var lo := int(span[0]) / step
		var hi := int(span[1]) / step
		var amount := roundi(float(Kin.randi_range(st, "bank|amt|%s|%d|%d" % [bld, day, k], lo, hi) * step)
			* Upgrades.mult(sim, bld, "bank_amount") / float(step)) * step
		var terms: Array = c.get("terms", [4, 8, 12, 16])
		var term := int(terms[Kin.randi_range(st, "bank|term|%s|%d|%d" % [bld, day, k], 0, terms.size() - 1)])
		var risk := _risk_roll(sim, "bank|risk|%s|%d|%d" % [bld, day, k])
		_add(sim, bld, "household", str(st.characters[who].get("family", "")), who, amount, term, risk)


static func _risk_roll(sim: Sim, key: String) -> String:
	var risks: Dictionary = cfg(sim).get("risks", {})
	var names: Array = risks.keys()
	names.sort()
	var r := Kin.roll(sim.state, key)
	var acc := 0.0
	for n: String in names:
		acc += float(risks[n].get("share", 0.0))
		if r < acc:
			return n
	return str(names[-1]) if not names.is_empty() else "B"


## A townsperson adult of a household family without a bank loan open nor an application waiting.
static func _borrower(sim: Sim, bld: String, day: int, k: int) -> String:
	var st := sim.state
	var busy := {}
	for a: Dictionary in applications(st):
		busy[str(a["borrower_family"])] = true
	for id: String in st.loans:
		var l: Dictionary = st.loans[id]
		if str(l.get("kind", "")) == KIND and str(l.get("state", "")) in [Loans.ACTIVE, "defaulted"]:
			busy[str(l["family"])] = true
	var cands: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		var fam := str(ch.get("family", ""))
		if fam == "" or busy.has(fam) or not bool(ch.get("alive", true)) or not TownLife.is_townsperson(st, id) \
				or not TownLife.is_adult(st, sim.catalog, id):
			continue
		busy[fam] = true   # one per household
		cands.append(id)
	if cands.is_empty():
		return ""
	return str(cands[Kin.randi_range(st, "bank|who|%s|%d|%d" % [bld, day, k], 0, cands.size() - 1)])


static func _add(sim: Sim, bld: String, kind: String, fam: String, who: String, amount: int, term: int,
		risk: String) -> Dictionary:
	var st := sim.state
	var m := _mem(st)
	m["seq"] = int(m["seq"]) + 1
	var c: Dictionary = cfg(sim).get("applications", {})
	var a := {"id": "app_%d" % int(m["seq"]), "bank": bld, "kind": kind, "borrower_family": fam, "borrower": who,
		"amount": amount, "term_days": term, "risk": risk,
		"max_interest": float(cfg(sim).get("risks", {}).get(risk, {}).get("max_interest", 0.25)),
		"expires": (Clock.day(int(st.clock["minute"])) + int(c.get("expires_days", 2))) * Clock.MINUTES_PER_DAY}  # by days (dawn moves with the season)
	(m["applications"] as Array).append(a)
	var owner := str(st.buildings[bld].get("owner", ""))
	sim.events.append({"type": "loan_application", "family": owner, "application": str(a["id"]), "kind": kind,
		"amount": amount, "risk": risk, "borrower_family": fam})
	if OS.is_debug_build():
		print("[Bank] solicitud %s en %s: %s pide %d a %d días (riesgo %s, máx %.0f %%)" % [a["id"], bld, fam, amount,
			term, risk, float(a["max_interest"]) * 100.0])
	return a


## A family's application to `bld` (Loans.order_request with lender = a Banco): its risk from its wealth.
static func family_application(sim: Sim, bld: String, fam: String, who: String, amount: int, term: int) -> Dictionary:
	var w := float(maxi(1, Dynasty.wealth(sim, fam)))
	var risk := "A" if w >= 3.0 * amount else ("B" if w >= 1.5 * amount else "C")
	return _add(sim, bld, "family", fam, who, amount, term, risk)


static func _late_payments(sim: Sim) -> void:
	var st := sim.state
	var lp: Dictionary = cfg(sim).get("late_payment", {})
	var ids: Array = st.loans.keys()
	ids.sort()
	var day := Clock.day(int(st.clock["minute"]))
	for id: String in ids:
		var l: Dictionary = st.loans[id]
		if not is_household(l) or str(l.get("state", "")) != "defaulted":
			continue
		if Kin.roll(st, "bank|late|%s|%d" % [id, day]) < float(lp.get("chance_per_day", 0.2)):
			var amount := roundi(float(l["outstanding"]) * (1.0 + float(lp.get("surcharge", 0.1))))
			var extra := amount - int(l["outstanding"])
			l["state"] = Loans.ACTIVE
			for i: Dictionary in l.get("installments", []):
				i["paid"] = int(i["amount"])
			var fam := str(l.get("lender_family", ""))
			_receive(sim, id, int(l["outstanding"]), "late")
			if extra > 0:
				Money.change(sim, fam, extra, Money.INTEREST, id, str(l.get("bank", "")))
			Notices.add(sim, fam, Notices.INFO, "notice.bank_late_paid", {"family": str(st.families.get(str(l["family"]),
				{}).get("name", l["family"])), "amount": amount}, str(l.get("bank", "")))


## An AI owner decides its family applications (4.22.5.6): it accepts when the wealth covers the amount enough.
static func _ai_decide(sim: Sim, bld: String) -> void:
	var st := sim.state
	var owner := str(st.buildings[bld].get("owner", ""))
	if str(st.families.get(owner, {}).get("controlled_by", "")) == "human":
		return
	var actor := str(st.families.get(owner, {}).get("head", ""))
	var fc: Dictionary = cfg(sim).get("family", {})
	for a: Dictionary in applications(st, bld):
		if str(a["kind"]) != "family":
			continue
		var ok := float(Dynasty.wealth(sim, str(a["borrower_family"]))) >= float(fc.get("ai_accepts_cover", 2.0)) * int(a["amount"])
		if ok:
			var r := order_grant(sim, {"type": "grant_loan", "actor": actor, "application": str(a["id"]),
				"interest": float(a["max_interest"]) * float(fc.get("ai_interest", 1.0))})
			ok = bool(r["ok"])
		if not ok:
			order_reject(sim, {"type": "reject_application", "actor": actor, "application": str(a["id"])})


# --- Orders -----------------------------------------------------------------------------------------------------------

static func _owner_reason(sim: Sim, actor: String, bld: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.buildings.has(bld):
		return "unknown_building"
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or str(st.buildings[bld].get("owner", "")) != fam:
		return "not_owner"
	return ""


## {"type": "grant_loan", "actor", "application", "interest"}: the Banco's owner lends. Reasons: unknown_actor,
## unknown_application, not_owner, bad_interest, too_expensive (over the application's maximum), not_enough_gold.
static func order_grant(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var a := find_application(st, str(o.get("application", "")))
	if a.is_empty():
		return Orders.fail("unknown_application")
	var bld := str(a["bank"])
	var why := _owner_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var interest := float(o.get("interest", a["max_interest"]))
	if interest <= 0.0:
		return Orders.fail("bad_interest")
	if interest > float(a["max_interest"]) + 0.0001:
		return Orders.fail("too_expensive")
	var fam := str(st.characters[actor]["family"])
	var amount := int(a["amount"])
	if not Money.can_pay(st, fam, amount):
		return Orders.fail("not_enough_gold")
	var q := quote(sim, amount, int(a["term_days"]), interest)
	var inst: Array = q["installments"]
	var bfam := str(a["borrower_family"])
	var household := str(a["kind"]) == "household"
	var terms := {"lender": "bank", "overdue_reputation": int(Loans.moneylender(sim).get("overdue_reputation", -10)),
		"extension_seasons": int(Loans.moneylender(sim).get("extension_seasons", 1)),
		"extension_surcharge": float(Loans.moneylender(sim).get("extension_surcharge", 0.25))}
	var home := str(st.characters.get(str(a["borrower"]), {}).get("home", ""))
	var id := Loans.create(st, bfam, terms, amount, int((inst[inst.size() - 1] as Dictionary)["due_minute"]), home)
	var l: Dictionary = st.loans[id]
	l["kind"] = KIND
	l["bank"] = bld
	l["lender_family"] = fam
	l["risk"] = str(a["risk"])
	l["household"] = household
	l["interest"] = float(q["rate"])
	l["annual_interest"] = interest
	l["outstanding"] = int(q["owed"])
	l["principal_left"] = amount
	l["installments"] = inst
	l["collateral"] = {"kind": "building", "id": home}
	var item := str(cfg(sim).get("notarized_item", "contract"))
	var inv: Dictionary = st.buildings[bld]["inventory"]
	l["notarized"] = Inventory.count(inv, item) > 0
	if bool(l["notarized"]):
		for qq: int in Inventory.QUALITIES:
			if Inventory.count(inv, item, qq) > 0:
				Inventory.remove(inv, item, qq, 1)
				break
	Money.change(sim, fam, -amount, Money.BANK_LENT, id, bld, actor)
	if not household:
		Money.change(sim, bfam, amount, Money.LOANS, id, "", str(a["borrower"]))
		Notices.add(sim, bfam, Notices.INFO, "notice.bank_loan_granted", {"amount": amount, "owed": int(q["owed"]),
			"installments": inst.size(), "days": int(a["term_days"])})
	(_mem(st)["applications"] as Array).erase(a)
	sim.events.append({"type": "loan_granted", "family": fam, "actor": actor, "loan": id, "lender": "bank",
		"amount": amount, "owed": int(q["owed"]), "term_days": int(a["term_days"]), "risk": str(a["risk"]),
		"borrower_family": bfam, "household": household, "notarized": bool(l["notarized"])})
	if OS.is_debug_build():
		print("[Bank] %s presta %d a %s (%s): %.0f %% anual, debe %d en %d cuotas, riesgo %s, notarial %s" % [fam, amount,
			bfam, id, interest * 100.0, int(q["owed"]), inst.size(), a["risk"], l["notarized"]])
	return Orders.ok()


## {"type": "reject_application", "actor", "application"}: the owner says no.
static func order_reject(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var a := find_application(st, str(o.get("application", "")))
	if a.is_empty():
		return Orders.fail("unknown_application")
	var why := _owner_reason(sim, str(o.get("actor", "")), str(a["bank"]))
	if why != "":
		return Orders.fail(why)
	(_mem(st)["applications"] as Array).erase(a)
	var fam := str(st.buildings[str(a["bank"])]["owner"])
	sim.events.append({"type": "application_rejected", "family": fam, "application": str(a["id"]), "risk": str(a["risk"]),
		"kind": str(a["kind"]), "borrower_family": str(a["borrower_family"])})
	if str(a["kind"]) == "family":
		Notices.add(sim, str(a["borrower_family"]), Notices.INFO, "notice.bank_rejected", {"amount": int(a["amount"])})
	return Orders.ok()


## How much the town gives back now for a household's loan `id` in default (0 if it cannot be claimed).
static func recovery(sim: Sim, id: String) -> int:
	var l: Dictionary = sim.state.loans.get(id, {})
	if l.is_empty() or not is_household(l):
		return 0
	var rc: Dictionary = cfg(sim).get("recovery", {})
	var share := float(rc.get("notarized" if bool(l.get("notarized", false)) else "plain", 0.3)) \
		+ Upgrades.amount(sim, str(l.get("bank", "")), "bank_recovery")
	return roundi(float(l["outstanding"]) * clampf(share, 0.0, 1.0))


## {"type": "claim_collateral", "actor", "loan"}: the banker claims a household's loan in default, from
## claim_after_days: the town pays recovery() and the loan closes. Reasons: unknown_actor, unknown_loan, not_your_loan,
## family_debt (a family's loan follows 4.16), not_defaulted, too_soon.
static func order_claim(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var id := str(o.get("loan", ""))
	if not st.loans.has(id):
		return Orders.fail("unknown_loan")
	var l: Dictionary = st.loans[id]
	var fam := str(st.characters[actor].get("family", ""))
	if str(l.get("kind", "")) != KIND or str(l.get("lender_family", "")) != fam:
		return Orders.fail("not_your_loan")
	if not is_household(l):
		return Orders.fail("family_debt")
	if str(l.get("state", "")) != "defaulted":
		return Orders.fail("not_defaulted")
	var after := int(cfg(sim).get("recovery", {}).get("claim_after_days", 1)) * Clock.MINUTES_PER_DAY
	if int(st.clock["minute"]) - int(l.get("defaulted_at", 0)) < after:
		return Orders.fail("too_soon")
	var back := recovery(sim, id)
	var split := [mini(back, int(l.get("principal_left", 0))), 0]  # what the town gives back covers the capital first
	split[1] = back - int(split[0])
	var bld := str(l.get("bank", ""))
	if int(split[0]) > 0:
		Money.change(sim, fam, int(split[0]), Money.BANK_LENT, id, bld, actor)
	if int(split[1]) > 0:
		Money.change(sim, fam, int(split[1]), Money.INTEREST, id, bld, actor)
	var lost := maxi(0, int(l.get("principal_left", 0)) - int(split[0]))
	if lost > 0:  # the capital not recovered becomes a loss (gold does not move: two entries that add up to 0)
		Money.change(sim, fam, lost, Money.BANK_LENT, id, bld, actor, true)
		Money.change(sim, fam, -lost, Money.BANK_LOSSES, id, bld, actor, true)
	l["principal_left"] = 0
	l["outstanding"] = 0
	l["state"] = Loans.SEIZED
	sim.events.append({"type": "collateral_claimed", "family": fam, "actor": actor, "loan": id, "recovered": back,
		"lost": lost, "notarized": bool(l.get("notarized", false))})
	if OS.is_debug_build():
		print("[Bank] %s reclama la garantía de %s: recupera %d, pierde %d de capital" % [fam, id, back, lost])
	return Orders.ok()
