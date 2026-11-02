class_name Inspections
extends RefCounted
## Inspections of the Secrets branch (GDD 4.8): every dawn, each building whose upgrades carry inspection_risk rolls
## p = sum(inspection_risk) x (1 - honesty / honesty_divisor) with state.rng. Caught: a fine (category fines, the town)
## and reputation; the hidden passage (inspection_escape) avoids one, then needs escape_ready_day. The automatic trial
## of GDD 4.12 comes later (H11): "multa por ahora". Memory in building.inspection (Upgrades.new_inspection()).
## Contract: docs/contratos/h5_mejoras.md. Figures: data/upgrade_rules.json "inspections".
##
## Base (H5): the queries; step and the fine debt: subgrim «arbol».


## At dawn (Ledger.is_dawn), after Upkeep and before Loans: buildings in id order (String), one roll each with
## risk() > 0 (state.rng.randf() < risk). Caught: the hidden passage saves it if can_escape() (escaped, cooldown,
## warning notice); otherwise a fine (whole gold in inspections.fine, state.rng; category fines, ref "inspection"),
## reputation inspections.reputation and an urgent notice. last_day = today whenever it rolls.
## A fine the family cannot pay in full becomes debt with the town (inspection.fine_debt, like the upkeep, D15;
## manager 2026-11-01, provisional): what it has is charged now, the rest as soon as there is gold (at dawn or in a
## step where the family's gold went up).
static func step(sim: Sim) -> void:
	var dawn := Ledger.is_dawn(sim)
	var richer := {}  # families whose gold went up this step: they pay their fine debts right away
	if not dawn:
		for e: Dictionary in sim.events:
			if str(e["type"]) == "gold_changed" and int(e["amount"]) > 0:
				richer[str(e["family"])] = true
		if richer.is_empty():
			return
	var st := sim.state
	var ids: Array = st.buildings.keys().map(func(k: Variant) -> String: return str(k))
	ids.sort()
	for b: String in ids:
		var fam := Money.family_of(st, b)
		if fam == "":
			continue
		var debt := int(st.buildings[b].get("inspection", {}).get("fine_debt", 0))
		if debt > 0 and (dawn or richer.has(fam)):
			_collect(sim, b, fam, 0)
		if dawn:
			_roll(sim, b, fam)


static func _roll(sim: Sim, b: String, fam: String) -> void:
	var p := risk(sim, b)
	if p <= 0.0:
		return
	var st := sim.state
	var bld: Dictionary = st.buildings[b]
	if not bld.get("inspection") is Dictionary:
		bld["inspection"] = Upgrades.new_inspection()
	var mem: Dictionary = bld["inspection"]
	var today := Clock.day(int(st.clock["minute"]))
	mem["last_day"] = today
	var r := st.rng.randf()
	if OS.is_debug_build():
		print("[Inspections] %s (%s): tirada %.3f < riesgo %.3f ?" % [b, fam, r, p])
	if r >= p:
		return
	var cfg: Dictionary = sim.catalog.upgrade_rules.get("inspections", {})
	if can_escape(sim, b):
		mem["escaped"] = int(mem.get("escaped", 0)) + 1
		mem["escape_ready_day"] = today + int(cfg.get("escape_cooldown_days", 8))
		sim.events.append({"type": "inspection", "family": fam, "building": b, "caught": false, "escaped": true,
			"fine": 0})
		Notices.add(sim, fam, Notices.WARNING, "notice.inspection_escaped", {"building": b}, b)
		if OS.is_debug_build():
			print("[Inspections] %s se libra por el pasadizo (vuelve a servir el día %d)" % [b, int(mem["escape_ready_day"])])
		return
	var span: Array = cfg.get("fine", [10, 50])
	var fine := st.rng.randi_range(int(span[0]), int(span[1]))
	mem["caught"] = int(mem.get("caught", 0)) + 1
	mem["fines"] = int(mem.get("fines", 0)) + fine
	var rep := int(cfg.get("reputation", -10))
	Reputation.change(sim, fam, rep, "inspection")  # H9
	sim.events.append({"type": "inspection", "family": fam, "building": b, "caught": true, "escaped": false,
		"fine": fine})
	Notices.add(sim, fam, Notices.URGENT, "notice.inspection_fined", {"building": b, "amount": fine}, b)
	if OS.is_debug_build():
		print("[Inspections] %s pillado: multa %d, reputación %+d" % [b, fine, rep])
	_collect(sim, b, fam, fine)


## Charges the fine debt plus `fine` (0 when only settling) as far as the family's gold goes; the rest stays as
## inspection.fine_debt. Urgent notice notice.inspection_debt when a new fine leaves debt.
static func _collect(sim: Sim, b: String, fam: String, fine: int) -> void:
	var st := sim.state
	var mem: Dictionary = st.buildings[b]["inspection"]
	var debt := int(mem.get("fine_debt", 0))
	var due := debt + fine
	if due <= 0:
		return
	var pay := mini(due, maxi(0, Money.gold(st, fam)))
	if pay > 0:
		Money.change(sim, fam, -pay, Money.FINES, "inspection", b)
	var left := due - pay
	mem["fine_debt"] = left
	if OS.is_debug_build():
		print("[Inspections] %s (%s): debía %d + multa %d, paga %d, queda %d" % [b, fam, debt, fine, pay, left])
	if left > 0 and fine > 0:
		Notices.add(sim, fam, Notices.URGENT, "notice.inspection_debt", {"building": b, "debt": left}, b)


## The daily chance of an inspection catching the building (0..1): sum of its inspection_risk effects (stack "all")
## scaled by the owner family's honesty.
static func risk(sim: Sim, bld: String) -> float:
	var base := Upgrades.amount(sim, bld, "inspection_risk")
	if base <= 0.0:
		return 0.0
	var div := maxf(1.0, float(sim.catalog.upgrade_rules.get("inspections", {}).get("honesty_divisor", 200)))
	var honesty := float(honesty_of(sim, Money.family_of(sim.state, bld)))
	return clampf(base * (1.0 - honesty / div), 0.0, 1.0)


## Honesty of a family (GDD 4.2.3: the dynasty's attitude, -100..100). Neither families nor characters carry attitudes
## yet: family.attitudes.honesty when it exists, else 0 [provisional].
static func honesty_of(sim: Sim, fam: String) -> int:
	return clampi(int(sim.state.families.get(fam, {}).get("attitudes", {}).get("honesty", 0)), -100, 100)


## Whether the hidden passage can save the building from an inspection today.
static func can_escape(sim: Sim, bld: String) -> bool:
	if not Upgrades.flag(sim, bld, "inspection_escape"):
		return false
	var day := Clock.day(int(sim.state.clock["minute"]))
	return day >= int(sim.state.buildings.get(bld, {}).get("inspection", {}).get("escape_ready_day", 0))


## The inspection panel of a building (UI query, fixed shape): {risk, last_day, caught, escaped, fines, can_escape}.
static func view(sim: Sim, bld: String) -> Dictionary:
	var mem: Dictionary = sim.state.buildings.get(bld, {}).get("inspection", {})
	return {"risk": risk(sim, bld), "last_day": int(mem.get("last_day", -1)), "caught": int(mem.get("caught", 0)),
		"escaped": int(mem.get("escaped", 0)), "fines": int(mem.get("fines", 0)), "can_escape": can_escape(sim, bld)}


## Gold of fines the building's family still owes the town (inspection.fine_debt, 0 if none).
static func fine_debt(sim: Sim, bld: String) -> int:
	return int(sim.state.buildings.get(bld, {}).get("inspection", {}).get("fine_debt", 0))
