extends SceneTree
## Builds the title scenario of H9 (GDD 4.12, docs/contratos/h9_titulos.md) from a real new game (artisan_blacksmith,
## normal, seed 1), so it is reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_title_scenarios.gd
## Same code + same data = same file. Re-run after changing the start, the map (town_hall), data/titles or the shape
## of the family state.
##   title_ready   day 3, 10:00: no loan, 400 gold, reputation 60 (a few contracts, trade and the passive of the forge
##                 with a journeyman), Hugo standing on the town hall's service tile. He can ask for Citizen now; after
##                 the ceremony Patrician shows its requirements still pending (reputation 200, 2 employees, 500 gold).

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_title_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _title_ready() else 1)


func _title_ready() -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)
	if not r["ok"]:
		print("make_title_scenarios: new game: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}  # an old game: the start's loan already repaid
	st.families[FAM]["gold"] = 400
	st.clock["minute"] = 3 * Clock.MINUTES_PER_DAY + 10 * 60
	var smith := _first(sim, "journeyman", int(cat.recipes()["forge_sword"]["min_craft"]))
	if smith == "":
		return false
	st.characters[smith]["job"] = Staff.new_job(sim, FORGE, 0, "any")
	st.characters[smith]["location"] = FORGE
	# The reputation of three days of trade and contracts (GDD 4.12.1): through Reputation.change, so the log and the
	# class modifiers are the real ones.
	for reason: String in ["contract_done", "fair_trade", "passive", "contract_done", "fair_trade", "passive",
			"contract_done", "quality_trade"]:
		Reputation.change(sim, FAM, 2 if reason == "contract_done" else 1, reason)
	Reputation.change(sim, FAM, 60 - Reputation.of(st, FAM), "start_scenario")
	var svc := Titles.service(sim)
	if svc.size() != 2:
		print("make_title_scenarios: the map has no town_hall")
		return false
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = [int(svc[0]), int(svc[1])]
	st.characters[HERO]["path"] = []
	if Titles.status(sim, HERO)["reason"] != "":
		print("make_title_scenarios: Hugo cannot ask for citizen: %s" % Titles.status(sim, HERO)["reason"])
		return false
	return _save(sim, "title_ready", "Listo para pedir título",
		"Día 3, 10:00: sin deuda, 400 de oro, reputación 60 y la Forja con un oficial. Hugo está delante del Ayuntamiento: puede pedir el título de Ciudadano (100 de oro, reputación 50, 1 negocio). Después, el de Patricio sale con sus requisitos pendientes.")


## The first unemployed townsperson (by id) of `rank` with at least `min_craft`.
func _first(sim: Sim, rank: String, min_craft: int) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		if Staff.is_unemployed(sim, id) and str(ch["rank"]) == rank and int(ch["stats"]["craft"]) >= min_craft:
			return id
	print("make_title_scenarios: no %s with craft >= %d" % [rank, min_craft])
	return ""


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_title_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_title_scenarios: %s (%s) minuto %d, oro %d, reputación %d" % [id, error_string(e),
		int(st.clock["minute"]), Money.gold(st, FAM), Reputation.of(st, FAM)])
	return e == OK
