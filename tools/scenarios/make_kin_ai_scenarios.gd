extends SceneTree
## Builds the family AI scenarios of H14 (GDD 4.10.6, 4.2.6; docs/contratos/h14_ia_familiar.md) from a real new game
## (artisan_blacksmith, normal, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_kin_ai_scenarios.gd
##   kin_trader  day 9, 06:00: Hugo married to Agnès (the spouse, run by AI) with the directives Trade, Work; the forge
##               with no iron nor coal; 200 gold, no loan. Nobody gives orders: Agnès supplies the forge when the market
##               opens (the criterion of H14).
##   kin_tired   the same, with Agnès hungry and tired (low needs, low morale): she goes home first; notices.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_kin_ai_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _make(false) and _make(true) else 1)


func _make(tired: bool) -> bool:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)
	if not r["ok"]:
		print("make_kin_ai_scenarios: new game: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}
	st.families[FAM]["gold"] = 200
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 6 * 60
	var wife := ""
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(st.characters[id].get("name", "")) == "Agnès" and str(st.characters[id].get("home", "")) != "":
			wife = id
	if wife == "":
		print("make_kin_ai_scenarios: no Agnès")
		return false
	Courtship.marry(sim, HERO, wife)
	var w: Dictionary = st.characters[wife]
	w["location"] = FORGE
	w["position"] = (st.buildings[FORGE]["door"] as Array).duplicate()
	w["path"] = []
	w["order_queue"] = []
	w["directives"] = ["trade", "work"]
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	for it: String in ["iron", "coal"]:
		Inventory.remove(inv, it, 0, Inventory.count(inv, it, 0))
	if tired:
		w["needs"] = {"hunger": 10, "rest": 20, "social": 40, "fun": 30}
		return _save(sim, "kin_tired", "Familiar agotada",
			"Día 10, 06:00: Agnès, la mujer de Hugo, tiene hambre y está cansada (moral baja): antes que comerciar se va a casa a recuperarse. Salen avisos.")
	return _save(sim, "kin_trader", "Familiar que comercia",
		"Día 10, 06:00: Agnès, la mujer de Hugo, tiene las directivas Comerciar y Trabajar; la forja no tiene hierro ni carbón y hay 200 de oro. Sin tocar nada, cuando abra el mercado irá a comprar y aprovisionará la forja.")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_kin_ai_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_kin_ai_scenarios: %s (%s) minuto %d, oro %d" % [id, error_string(e), int(st.clock["minute"]),
		Money.gold(st, FAM)])
	return e == OK
