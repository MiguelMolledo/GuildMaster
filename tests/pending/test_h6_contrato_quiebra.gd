extends "res://tests/test_case.gd"
## H6 × H13 · the contract between the bankruptcy (posada, sim/build/bankruptcy.gd) and the AI's economy (plantillas,
## sim/ai/economy.gd): an AI family whose families[f].ai_state.bankruptcy.stage is not "" (austerity, for_sale) does
## not hire. The same family, the same day and gold: with the stage "" its management hires (the control), in
## austerity and with the «Se vende» sign it does not. Waits in tests/pending/ until plantillas reads the field; then
## it moves to tests/ (the manager's decision, 2026-11-07).

const START: String = "artisan_blacksmith"

var cat := Catalog.load_from()


func _capital() -> Sim:
	return Sim.new(NewGame.from_start(cat, START, "normal", {"city": "capital", "cast": "fixed"}, 1)["state"], cat)


func _hires(sim: Sim, fam: String) -> bool:
	var st := sim.state
	var head := Kin.head(st, fam)
	var home := Hostility._workshop_of(st, fam)
	var profile := Hostility._profile(sim, fam)
	for o: Dictionary in AIEconomy._manage(sim, fam, head, home, profile, 5):
		if str(o.get("type", "")) == "hire":
			return true
	return false


func _ready_to_hire(sim: Sim, fam: String) -> void:
	sim.state.clock["minute"] = 5 * Clock.MINUTES_PER_DAY + 400
	sim.state.families[fam]["gold"] = 5000
	var ai: Dictionary = sim.state.families[fam].get("ai_state", {})
	ai["recipe"] = str(ai.get("recipe", "forge_sword")) if str(ai.get("recipe", "")) != "" else "forge_sword"
	sim.state.families[fam]["ai_state"] = ai


func test_no_hiring_while_bankrupt() -> void:
	var sim := _capital()
	var fam := ""
	for f: String in Hostility._ai_families(sim.state):
		if str(sim.state.families[f]["ai_profile"]) == "rival_smith":
			fam = f
	check(fam != "", "Ferrer in Bellcaire")
	for stage: String in ["", Bankruptcy.AUSTERITY, Bankruptcy.FOR_SALE]:
		var s := Sim.new(WorldState.from_dict(sim.state.to_dict()), cat)
		_ready_to_hire(s, fam)
		Bankruptcy.mem(s, fam)["stage"] = stage
		if stage == "":
			check(_hires(s, fam), "control: with the stage empty, rich and with a recipe, it hires")
		else:
			check(not _hires(s, fam), "stage %s: no hiring (ai_state.bankruptcy.stage)" % stage)
