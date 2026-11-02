extends SceneTree
## Builds the trial scenarios of H11 (GDD 4.12.5, docs/contratos/h11_tribunal.md) from a real new game
## (artisan_blacksmith, normal, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_trial_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, data/justice.json or the shape of the trials.
##   accused_player  day 9, 10:00: the Forge has the double accounting (Secrets 1) and an inspection has just caught
##                   it: the automatic trial is in preparation (2 days). Two townsfolk dislike Hugo (against), one
##                   likes him (favor); 300 gold, Citizen, reputation 60.
##   trial_hearing   the same trial a few minutes before its hearing: the witnesses against can be questioned.
##   rival_accused   day 9, 10:00: Citizen; the rival smith has a public fact not yet tried (a bribe found out in a
##                   campaign): Hugo can accuse him from his sheet.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"
const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_trial_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _accused(false) and _accused(true) and _rival_accused() else 1)


func _base() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)
	if not r["ok"]:
		print("make_trial_scenarios: new game: %s" % r["error"])
		return null
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}  # an old game: the start's loan already repaid
	st.families[FAM]["gold"] = 300
	st.families[FAM]["title"] = "citizen"
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 10 * 60
	Reputation.change(sim, FAM, 60, "start_scenario")
	return sim


func _accused(hearing: bool) -> bool:
	var sim := _base()
	if sim == null:
		return false
	var st := sim.state
	(st.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	Inventory.add(st.buildings[FORGE]["inventory"], cat, "sword", 0, 4)  # goods for sale (what a confiscation takes)
	var folk := Population.townsfolk(st)
	# Three neighbours with a history with Hugo: two dislike him, one likes him (they are picked first as witnesses).
	Emotions.change_relation(sim, str(folk[2]), HERO, -30, "start_scenario")
	Emotions.change_relation(sim, str(folk[5]), HERO, -25, "start_scenario")
	Emotions.change_relation(sim, str(folk[8]), HERO, 30, "start_scenario")
	sim.events = [{"type": "inspection", "family": FAM, "building": FORGE, "caught": true, "escaped": false, "fine": 20}]
	Tribunal.step(sim)
	var open: Array = Tribunal.open_trials(sim)
	if open.is_empty():
		print("make_trial_scenarios: no trial opened")
		return false
	var t: Dictionary = open[0]
	if hearing:
		st.clock["minute"] = int(t["prep_until"]) - 5
		st.characters[HERO]["location"] = ""
		st.characters[HERO]["position"] = (st.buildings[FORGE]["door"] as Array).duplicate()
		return _save(sim, "trial_hearing", "Juicio: la vista oral",
			"El juicio por evasión de impuestos (la Doble contabilidad de la Forja) acaba su preparación: en cinco minutos empieza la vista oral. Hugo puede interrogar a los testigos en contra y concluir la defensa.")
	return _save(sim, "accused_player", "Acusado tras una inspección",
		"Día 10, 10:00: la Forja tiene la Doble contabilidad y una inspección acaba de pillarla. Juicio automático por evasión de impuestos en preparación (2 días): convence, soborna o amenaza a los testigos antes de la vista.")


func _rival_accused() -> bool:
	var sim := _base()
	if sim == null:
		return false
	var st := sim.state
	st.families[RIVAL_FAM]["title"] = "citizen"
	Tribunal.add_fact(sim, "bribe_scandal", RIVAL_FAM, RIVAL)
	var svc := Titles.service(sim)
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = [int(svc[0]), int(svc[1])]
	var o := Tribunal.accuse_options(sim, HERO, RIVAL)
	if (o["facts"] as Array).is_empty() or str(o["reason"]) != "":
		print("make_trial_scenarios: Hugo cannot accuse the rival: %s" % o)
		return false
	return _save(sim, "rival_accused", "Acusar al rival",
		"Día 10, 10:00: la familia es Ciudadana y al herrero rival le descubrieron un soborno en campaña (hecho público sin juzgar). Hugo puede acusarle desde su ficha (Acusar…).")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_trial_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_trial_scenarios: %s (%s) minuto %d, oro %d, juicios %d" % [id, error_string(e), int(st.clock["minute"]),
		Money.gold(st, FAM), st.trials.size()])
	return e == OK
