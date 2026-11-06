class_name BotBroke
extends BotArtisanNovice
## Equilibrio 2 (docs/decisiones.json): the novice of the forge from the scenario broke_forge (0 gold and 1 coal on day
## 9). It takes the moneylender's emergency loan when it is offered (the novice's own habit since 2026-11-06) and then
## plays its usual trade. Measures:
## emergency_taken, emergency_repaid (no emergency loan open at the end), seized (goods seized), ruin.
## Targets: data/targets.json broke.

var _m: Dictionary = {"emergency_taken": 0, "seized": 0}


func orders(sim: Sim) -> Array:
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"emergency_loan":
				_m["emergency_taken"] = int(_m["emergency_taken"]) + 1
			"good_seized":
				_m["seized"] = int(_m["seized"]) + 1
	return super.orders(sim)  # the novice takes the emergency loan when it is offered


func measures(sim: Sim) -> Dictionary:
	var out := _m.duplicate()
	var open := 0
	for id: String in Loans.of_family(sim, _fam(sim)):
		if str(sim.state.loans[id].get("kind", "")) == Emergency.KIND:
			open += 1
	out["emergency_open"] = open
	out["ruin"] = 1 if str(sim.state.ending.get("kind", "")) == "ruin" else 0
	return out
