extends SceneTree
## Builds the office scenarios of H10 (GDD 4.12.3, 4.12.4, docs/contratos/h10_cargos.md) from a real new game
## (artisan_blacksmith, normal, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_office_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, the offices, politics.json or the shape of the
## office state.
##   office_campaign      day 4 (autumn of year 1), 10:00: no loan, 300 gold, Citizen, reputation 60, Hugo on the
##                        town hall's service tile. The inspector and the collector are vacant: he can run (chart).
##   office_election_eve  day 7 (winter), 23:30: Hugo (medium) and Bernat, the rival (medium, Citizen, reputation 45,
##                        friends with four voters) run for market inspector; the vote falls at midnight.
##   office_inspector     day 9, 10:00: Hugo has been market inspector since day 9; he can regulate a price.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"
const INSPECTOR: String = "market_inspector"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_office_scenarios: data problems: %s" % errs)
		quit(1)
		return
	quit(0 if _campaign() and _eve() and _inspector() else 1)


## The common start of the three: a Citizen family with gold and reputation, no loan, day 4 at 10:00.
func _base() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)
	if not r["ok"]:
		print("make_office_scenarios: new game: %s" % r["error"])
		return null
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}  # an old game: the start's loan already repaid
	st.families[FAM]["gold"] = 300
	st.families[FAM]["title"] = "citizen"
	st.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 10 * 60
	for reason: String in ["contract_done", "fair_trade", "passive", "contract_done", "quality_trade"]:
		Reputation.change(sim, FAM, 2 if reason == "contract_done" else 1, reason)
	Reputation.change(sim, FAM, 60 - Reputation.of(st, FAM), "start_scenario")
	return sim


func _campaign() -> bool:
	var sim := _base()
	if sim == null:
		return false
	var svc := Titles.service(sim)
	if svc.size() != 2:
		print("make_office_scenarios: the map has no town_hall")
		return false
	var st := sim.state
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = [int(svc[0]), int(svc[1])]
	st.characters[HERO]["path"] = []
	var why := Elections.run_status(sim, HERO, INSPECTOR, "medium")
	if why != "":
		print("make_office_scenarios: Hugo cannot run for inspector: %s" % why)
		return false
	return _save(sim, "office_campaign", "Presentarse a un cargo",
		"Día 5 (otoño del año 1), 10:00: la familia es Ciudadana, sin deuda, 300 de oro y reputación 60. Hugo está en el Ayuntamiento: el Inspector de mercado y el Recaudador están vacantes y puede presentarse (organigrama, pestaña Cargos). La votación es al cambiar de año (día 9); la campaña, el invierno (días 7 y 8).")


func _eve() -> bool:
	var sim := _base()
	if sim == null:
		return false
	var st := sim.state
	st.families[RIVAL_FAM]["title"] = "citizen"
	st.families[RIVAL_FAM]["gold"] = maxi(150, Money.gold(st, RIVAL_FAM))
	Reputation.change(sim, RIVAL_FAM, 45, "start_scenario")
	for o: Dictionary in [{"type": "run_for_office", "actor": HERO, "office": INSPECTOR, "level": "medium"},
			{"type": "run_for_office", "actor": RIVAL, "office": INSPECTOR, "level": "medium"}]:
		var r := Orders.apply(sim, o)
		if not r["ok"]:
			print("make_office_scenarios: %s cannot run: %s" % [o["actor"], r["reason"]])
			return false
	var friends := 0  # Bernat has dealt with four voters for years: they like him more than the newcomer
	for v: String in Elections.voters(sim, [HERO, RIVAL]):
		if friends < 4:
			Emotions.change_relation(sim, RIVAL, v, 25, "start_scenario")
			friends += 1
	st.clock["minute"] = 7 * Clock.MINUTES_PER_DAY + 23 * 60 + 30
	return _save(sim, "office_election_eve", "Víspera de la votación",
		"Día 8 (invierno), 23:30: Hugo (campaña media, reputación 60) y Bernat, el herrero rival (campaña media, reputación 45, amigo de cuatro votantes), se presentan a Inspector de mercado. A medianoche cambia el año y se vota: sale la tarjeta con el recuento.")


func _inspector() -> bool:
	var sim := _base()
	if sim == null:
		return false
	var st := sim.state
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 10 * 60
	Offices.take(sim, INSPECTOR, 0, HERO)
	if Offices.power_status(sim, HERO, "regulate_price", {"item": "sword", "percent": 10}) != "":
		print("make_office_scenarios: the inspector cannot regulate swords")
		return false
	return _save(sim, "office_inspector", "Inspector de mercado",
		"Día 10, 10:00: Hugo es Inspector de mercado desde hoy (hasta el día 18). Desde el panel de poderes puede regular el precio de un objeto ±10 % durante 2 días (se nota en el mercado), multar a un comerciante o, si fuera Recaudador, fijar el impuesto.")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_office_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_office_scenarios: %s (%s) minuto %d, oro %d, reputación %d" % [id, error_string(e),
		int(st.clock["minute"]), Money.gold(st, FAM), Reputation.of(st, FAM)])
	return e == OK
