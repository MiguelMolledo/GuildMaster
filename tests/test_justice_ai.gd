extends "res://tests/test_case.gd"
## H11 criterion (10, fila H11): «en el sim, una familia IA acusa al jugador solo con motivo real o con pruebas
## fabricadas si su honestidad es baja». The rival's minimal rule (data/ai_profiles/rival_smith.json accuse_rule,
## provisional until 04c): a public fact not yet tried against the player's family, or fabricated if honesty <= -30;
## never in the first year; once a year.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL_FAM: String = "fam_0002"

var cat := Catalog.load_from()


func _sim(day: int) -> Sim:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)
	sim.state.families[RIVAL_FAM]["title"] = "citizen"
	sim.state.families[RIVAL_FAM]["gold"] = 0  # no campaign, no title: only the accusation is on its mind
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + 4 * 60
	return sim


## Runs `hours` and returns the accusations the rival made: [{trial, fabricated, fact}] (+ failed fabrications).
func _accusations(sim: Sim, hours: int) -> Array:
	var out: Array = []
	for i: int in hours * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "trial_opened" and str(e["accuser_family"]) == RIVAL_FAM:
				var t := Tribunal.trial(sim.state, str(e["trial"]))
				out.append({"trial": str(e["trial"]), "fabricated": bool(t["fabricated"]), "fact": str(t["fact"])})
			elif str(e["type"]) == "accusation_failed":
				out.append({"trial": "", "fabricated": true, "fact": ""})
	return out


func test_no_motive_no_accusation() -> void:
	var sim := _sim(9)
	eq(Tribunal.honesty(sim, RIVAL_FAM), 20, "an honest rival (20)")
	eq(_accusations(sim, 30), [], "with no fact and honesty 20 it never accuses")


func test_real_motive_accusation() -> void:
	var sim := _sim(9)
	var f := Tribunal.add_fact(sim, "bribe_scandal", FAM, HERO)
	var acc := _accusations(sim, 24)
	eq(acc.size(), 1, "it accuses once")
	eq(str(acc[0]["fact"]), f, "with the real fact")
	check(not bool(acc[0]["fabricated"]), "not fabricated")
	eq(str(Tribunal.of_family(sim, FAM)["accused"]), HERO, "the head of the player's family")


func test_low_honesty_fabricates() -> void:
	var sim := _sim(9)
	sim.state.families[RIVAL_FAM]["attitudes"]["honesty"] = -50
	var acc := _accusations(sim, 24)
	eq(acc.size(), 1, "a dishonest rival (-50) accuses without motive")
	check(bool(acc[0]["fabricated"]), "with fabricated proofs (or found out trying)")
	sim = _sim(9)
	sim.state.families[RIVAL_FAM]["attitudes"]["honesty"] = -29
	eq(_accusations(sim, 24), [], "-29 is not low enough (04c: <= -30)")


func test_first_year_and_cooldown() -> void:
	var sim := _sim(2)
	Tribunal.add_fact(sim, "bribe_scandal", FAM, HERO)
	eq(_accusations(sim, 24), [], "not in the first year (protection of the start)")
	sim = _sim(9)
	Tribunal.add_fact(sim, "bribe_scandal", FAM, HERO)
	Tribunal.add_fact(sim, "witness_threat", FAM, HERO)
	eq(_accusations(sim, 24).size(), 1, "one")
	var t := Tribunal.of_family(sim, FAM)
	t["status"] = "done"
	eq(_accusations(sim, 48), [], "and not again within the year")
