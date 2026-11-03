class_name Upkeep
extends RefCounted
## Daily upkeep of buildings (D12, GDD 4.19): charged at dawn to the owner family (category upkeep). Unpaid upkeep
## accumulates as debt with the town (building.upkeep_debt), is charged as soon as there is gold, and after 3 days
## unpaid the building becomes damaged (D15 = b, provisional); it goes back to normal when the debt is settled.
## Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
## The upkeep of each type: data/buildings/<type>.json "upkeep"; the days: data/accounts.json upkeep_damage_days.


static func step(sim: Sim) -> void:
	var dawn := Ledger.is_dawn(sim)
	var richer := {}  # families whose gold went up this step: they pay what they owe right away
	if not dawn:
		for e: Dictionary in sim.events:
			if str(e["type"]) == "gold_changed" and int(e["amount"]) > 0:
				richer[str(e["family"])] = true
		if richer.is_empty():
			return
	var st := sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = st.buildings[b]
		var fam := Money.family_of(st, b)
		if fam == "":
			continue
		if dawn:
			_charge(sim, b, fam, int(sim.catalog.buildings().get(str(bld["type"]), {}).get("upkeep", 0)))
		elif richer.has(fam) and int(bld.get("upkeep_debt", 0)) > 0:
			_charge(sim, b, fam, 0)


## Charges the debt plus `today` (the day's upkeep, 0 when only settling) as far as the family's gold goes.
static func _charge(sim: Sim, b: String, fam: String, today: int) -> void:
	var st := sim.state
	var bld: Dictionary = st.buildings[b]
	var debt := int(bld.get("upkeep_debt", 0))
	var due := debt + today
	if due <= 0:
		return
	var pay := mini(due, maxi(0, Money.gold(st, fam)))
	if pay > 0:
		Money.change(sim, fam, -pay, Money.UPKEEP, "upkeep", b)
		sim.events.append({"type": "upkeep_charged", "family": fam, "building": b, "amount": pay})
	var left := due - pay
	bld["upkeep_debt"] = left
	var day := Clock.day(int(st.clock["minute"]))
	if OS.is_debug_build():
		print("[Upkeep] %s (%s): debía %d + hoy %d, paga %d, queda %d" % [b, fam, debt, today, pay, left])
	if left == 0:
		if debt > 0:
			bld["upkeep_unpaid_since"] = -1
			var was_damaged := str(bld.get("state", "")) == "damaged"
			if was_damaged:
				bld["state"] = "normal"
				sim.events.append({"type": "building_repaired", "building": b})
			Notices.add(sim, fam, Notices.INFO, "notice.upkeep_settled", {"building": b, "amount": debt}, b)
		return
	if today <= 0:
		return  # settling part of the debt between dawns: the warning was given at dawn
	if int(bld.get("upkeep_unpaid_since", -1)) < 0:
		bld["upkeep_unpaid_since"] = day
	var days := day - int(bld["upkeep_unpaid_since"])
	var limit := int(sim.catalog.accounts.get("upkeep_damage_days", 3))
	sim.events.append({"type": "upkeep_unpaid", "family": fam, "building": b, "debt": left})
	if days >= limit and str(bld.get("state", "")) == "normal":
		bld["state"] = "damaged"
		sim.events.append({"type": "building_damaged", "building": b})
		Notices.add(sim, fam, Notices.URGENT, "notice.building_damaged", {"building": b, "debt": left}, b)
		if OS.is_debug_build():
			print("[Upkeep] %s pasa a dañado: %d días sin pagar (deuda=%d)" % [b, days, left])
	elif str(bld.get("state", "")) == "normal":
		Notices.add(sim, fam, Notices.WARNING, "notice.upkeep_unpaid",
			{"building": b, "debt": left, "days": limit - days}, b)



## What the next dawn will charge `fam`: every building's upkeep plus what it owes, and the wages of its employees
## ({upkeep, wages, total}). Read only (the confirmation of a payment that leaves the gold under it, mercado_y_libro.md).
static func due_next_dawn(sim: Sim, fam: String) -> Dictionary:
	var st := sim.state
	var upkeep := 0
	var wages := 0
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) != fam:
			continue
		var bld: Dictionary = st.buildings[b]
		upkeep += int(sim.catalog.buildings().get(str(bld["type"]), {}).get("upkeep", 0)) + int(bld.get("upkeep_debt", 0))
		for c: Variant in Staff.employees_of(st, b):
			wages += Staff.wage(sim, str(c))
	return {"upkeep": upkeep, "wages": wages, "total": upkeep + wages}
