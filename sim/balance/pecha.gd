class_name Pecha
extends RefCounted
## The pecha: a yearly tax on wealth, progressive by brackets, charged at the close of each year (Equilibrio 5,
## docs/decisiones.json; GDD 4.19 sumideros). Figures: data/accounts.json "pecha" [balance].
##
## At year_changed, every family that owns a business (not the service families) pays on its wealth (gold plus the
## goods of its buildings at the market's sell price): each bracket [from, rate] taxes the part of the wealth above
## its `from` (marginal). The gold is paid at once (ledger taxes, ref "pecha"); what the gold does not cover is owed to
## the town like a fine (Loans.charge_fine: it keeps its working gold). The big sinks (build, buy, restore) are H6.
## State: families[fam].pecha_log [{year, wealth, amount}] (the last years_kept; read with defaults: no save version).


static func _cfg(sim: Sim) -> Dictionary:
	return sim.catalog.accounts.get("pecha", {})


static func step(sim: Sim) -> void:
	var year := -1
	for e: Dictionary in sim.events:
		if str(e["type"]) == "year_changed":
			year = int(e.get("year", 0))
	if year < 0 or _cfg(sim).is_empty() or not bool(_cfg(sim).get("enabled", true)):
		return
	var st := sim.state
	var ids: Array = st.families.keys()
	ids.sort()
	for fam: String in ids:
		if Life.is_service(st, fam) or not _has_business(st, fam):
			continue
		var wealth := wealth_of(sim, fam)
		var amount := due(sim, wealth)
		var f: Dictionary = st.families[fam]
		var log: Array = f.get("pecha_log", []) if f.get("pecha_log") is Array else []
		log.append({"year": year - 1, "wealth": wealth, "amount": amount})
		while log.size() > int(_cfg(sim).get("years_kept", 4)):
			log.pop_front()
		f["pecha_log"] = log
		if amount <= 0:
			continue
		var r := Loans.charge_fine(sim, fam, amount, Money.TAXES, "pecha", _a_business(st, fam))
		sim.events.append({"type": "pecha_paid", "family": fam, "wealth": wealth, "amount": amount,
			"paid": int(r["paid"]), "owed": int(r["owed"])})
		Notices.add(sim, fam, Notices.INFO, "notice.pecha", {"amount": amount, "wealth": wealth, "paid": int(r["paid"])})
		if OS.is_debug_build():
			print("[Pecha] cierre del año %d: %s, patrimonio %d -> pecha %d (pagado %d, debe %d)" % [year - 1, fam, wealth,
				amount, int(r["paid"]), int(r["owed"])])


## The pecha of a wealth: the sum over the brackets of (wealth − from) × rate, for the part inside each bracket.
static func due(sim: Sim, wealth: int) -> int:
	var brackets: Array = _cfg(sim).get("brackets", [])
	var total := 0.0
	for i: int in brackets.size():
		var lo := int(brackets[i][0])
		var hi := int(brackets[i + 1][0]) if i + 1 < brackets.size() else -1
		var rate := float(brackets[i][1])
		if wealth <= lo:
			break
		var top := wealth if hi < 0 else mini(wealth, hi)
		total += float(top - lo) * rate
	return roundi(total)


## Gold plus the goods of the family's buildings at the market's sell price.
static func wealth_of(sim: Sim, fam: String) -> int:
	var st := sim.state
	var w := maxi(0, Money.gold(st, fam))
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) != fam:
			continue
		for s: Dictionary in st.buildings[b].get("inventory", {}).get("stacks", []):
			w += Market.price(sim, str(s["item"]), int(s["quality"]), "sell") * int(s["qty"])
	return w


## What the pecha of `fam` would be if the year closed now (the UI): {wealth, amount}.
static func preview(sim: Sim, fam: String) -> Dictionary:
	var w := wealth_of(sim, fam)
	return {"wealth": w, "amount": due(sim, w)}


static func _has_business(st: WorldState, fam: String) -> bool:
	return _a_business(st, fam) != ""


static func _a_business(st: WorldState, fam: String) -> String:
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) == fam and str(st.buildings[b].get("type", "")) != "house":
			return b
	return ""
