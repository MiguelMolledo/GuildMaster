class_name Inspections
extends RefCounted
## Inspections of the Secrets branch (GDD 4.8): every dawn, each building whose upgrades carry inspection_risk rolls
## p = sum(inspection_risk) x (1 - honesty / honesty_divisor) with state.rng. Caught: a fine (category fines, the town)
## and reputation; the hidden passage (inspection_escape) avoids one, then needs escape_ready_day. The automatic trial
## of GDD 4.12 comes later (H11): "multa por ahora". Memory in building.inspection (Upgrades.new_inspection()).
## Contract: docs/contratos/h5_mejoras.md. Figures: data/upgrade_rules.json "inspections".
##
## Base (H5): the queries are done; step belongs to subgrim «arbol».


## At dawn (Ledger.is_dawn), after Upkeep and before Loans: buildings in id order (String), one roll each with
## risk() > 0. Owner: «arbol».
static func step(_sim: Sim) -> void:
	pass


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
