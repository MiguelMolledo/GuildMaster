extends "res://tests/test_case.gd"
## H6 × H13 · the contract between the bankruptcy (posada, sim/build/bankruptcy.gd) and the AI's economy (plantillas,
## sim/ai/economy.gd): an AI family whose families[f].ai_state.bankruptcy.stage is not "" (austerity, for_sale) does
## not hire. The same family, the same day and gold: with the stage "" its management hires (the control), in
## austerity and with the «Se vende» sign it does not (the manager's decision, 2026-11-07; plantillas reads the field in
## AIEconomy._manage).

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


## Manager, 2026-11-07 (option a): on the economy maps the bankruptcy starts only once the moneylender's credit has
## failed (seized) and measures the reserve with AIEconomy.reserve.
func test_the_credit_comes_first() -> void:
	var sim := _capital()
	var fam := ""
	for f: String in Hostility._ai_families(sim.state):
		if str(sim.state.families[f]["ai_profile"]) == "rival_smith":
			fam = f
	var forge := Bankruptcy.workshop_of(sim, fam)
	sim.state.clock["minute"] = 17 * Clock.MINUTES_PER_DAY + 600
	sim.state.families[fam]["gold"] = 500
	Money.change(sim, fam, -500, Money.UPKEEP, "test", forge)
	var dawn := func(day: int) -> void:
		sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 360
		sim.events = [{"type": "phase_changed", "phase": "dawn"}]
		Bankruptcy.step(sim)
	dawn.call(18)
	eq(Bankruptcy.stage(sim, fam), Bankruptcy.NORMAL, "losing and without gold, but its credit has not failed: no bankruptcy")
	var id := Loans.create(sim.state, fam, {"lender": "moneylender"}, 144, 16 * Clock.MINUTES_PER_DAY, forge)
	sim.state.loans[id]["kind"] = AIEconomy.CREDIT
	sim.state.loans[id]["state"] = Loans.SEIZED
	dawn.call(19)
	eq(Bankruptcy.stage(sim, fam), Bankruptcy.AUSTERITY, "its credit seized in those days: austerity")
	check(Bankruptcy.in_trouble(sim, fam, 0), "under AIEconomy.reserve")
	sim.state.families[fam]["gold"] = AIEconomy.reserve(sim, fam, Hostility._profile(sim, fam))
	check(not Bankruptcy.in_trouble(sim, fam, 0), "at its reserve it is not in trouble")


## Manager, 2026-11-07 (option b): the adults of a family venida a menos nobody hired earn a day labourer's wage.
func test_a_fallen_family_earns_a_day_wage() -> void:
	var sim := _capital()
	var fam := Hostility._ai_families(sim.state)[0] as String
	sim.state.families[fam]["fallen"] = {"day": 3}
	sim.state.families[fam]["gold"] = 0
	var adults := 0
	for m: Variant in sim.state.families[fam]["members"]:
		var c := str(m)
		if Kin.alive(sim.state, c) and Kin.is_adult(sim, c):
			sim.state.characters[c]["job"] = null
			adults += 1
	check(adults >= 1, "the family has adults (%d)" % adults)
	sim.state.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 360
	sim.events = [{"type": "phase_changed", "phase": "dawn"}]
	AIEconomy._day_labour(sim, fam)
	eq(Money.gold(sim.state, fam), adults * int(cat.ai_rules["economy"]["fallen"]["day_wage"]), "a day wage for each")
