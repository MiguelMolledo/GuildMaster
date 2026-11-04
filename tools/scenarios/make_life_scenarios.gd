extends SceneTree
## Builds the scenarios of the living town II (docs/gdd/04f_vida_y_fiestas.md §4.24, §4.28.4) from town_e_start played
## 8 days with the life on (so the chronicle, the needs and the rumours are real), reproducibly:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_life_scenarios.gd
##   life_plaza       day 9, 19:10: dusk at the plaza; the hero by the well, the corrillos forming (rumours).
##   life_gate        day 9, 09:40: the hero by the west gate; a merchant from Portvell comes in at 09:50.
##   life_night       day 9, 22:50: the night round passes the plaza; the hero by the well.
##   life_altercation day 9, 19:55: a brawl starts at 20:00 in the plaza, by the hero.
##   life_bandits     day 9, 21:50: a band of bandits comes for the hero's forge at 22:00; raids more likely
##                    (town.incidents.mult de bandit_raid 5): the bot guard_watch plays nights of raids from here.
##   life_kidnap      day 9, 18:40: at 18:50 the bandits take one of the hero's family (not the head).

const OUT: String = "res://data/scenarios"
const DAY: int = 1440
const HERO: String = "chr_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	cat.life_tables["life"]["enabled"] = true
	var r := NewGame.from_scenario("town_e_start", 1)
	if not r["ok"]:
		print("make_life_scenarios: %s" % r["error"])
		quit(1)
		return
	var sim := Sim.new(r["state"], cat)
	sim.run_minutes(8 * DAY + 8 * 60 - int(sim.state.clock["minute"]))  # day 9 (index 8), 08:00: year 2
	var base: Dictionary = sim.state.to_dict()
	var ok := true
	ok = _make(base, "life_plaza", 19 * 60 + 10, "La plaza al atardecer",
		"Día 9, 19:10: atardecer en la plaza de town_e con la vida encendida; los vecinos forman corrillos en el pozo, el atrio y las puertas y cuentan lo que ha pasado estos días. El héroe está junto al pozo: oye los rumores (libro de rumores).",
		func(st: WorldState) -> void: _hero_at(st, [21, 20])) and ok
	ok = _make(base, "life_gate", 9 * 60 + 40, "La guardia en la puerta",
		"Día 9, 09:40: el héroe junto a la puerta oeste; el guardia está en su puesto y a las 09:50 entra un mercader de Portvell (lo saluda).",
		func(st: WorldState) -> void:
			_hero_at(st, [5, 19])
			var v: Dictionary = st.town["visitors"]
			v["day"] = 8
			v["planned"] = [{"at": 8 * DAY + 9 * 60 + 50, "kind": "merchant", "city": "port", "gate": "west_gate", "key": "life|vis|scenario|gate"}]) and ok
	ok = _make(base, "life_night", 22 * 60 + 50, "La ronda de noche",
		"Día 9, 22:50: noche; dos guardias hacen la ronda con farol por la calle mayor y la plaza. El héroe está junto al pozo.",
		func(st: WorldState) -> void: _hero_at(st, [21, 20])) and ok
	ok = _make(base, "life_altercation", 19 * 60 + 55, "Un altercado",
		"Día 9, 19:55: a las 20:00 dos vecinos llegan a las manos en la plaza; el héroe está al lado (puede separarlos) y la guardia acude al grito.",
		func(st: WorldState) -> void:
			_hero_at(st, [19, 21])
			(st.town["incidents"]["planned"] as Array).append({"def": "altercation", "at": 8 * DAY + 20 * 60, "key": "altercation|scenario"})) and ok
	ok = _make(base, "life_bandits", 21 * 60 + 50, "Asalto de bandidos",
		"Día 9, 21:50: a las 22:00 una banda de bandidos del Coll de la Venta viene a por la forja del héroe (el aviso salió esta mañana). Asaltos más probables (town.incidents.mult de bandit_raid 5): el bot guard_watch juega noches de asaltos desde aquí.",
		func(st: WorldState) -> void:
			_hero_in(st, "bld_0001")
			st.town["incidents"]["mult"] = {"bandit_raid": 5.0}
			(st.town["incidents"]["planned"] as Array).append({"def": "bandit_raid", "at": 8 * DAY + 22 * 60, "key": "bandit_raid|scenario", "building": "bld_0001"})
			st.town["incidents"]["warned"]["bandit_raid|scenario"] = {"until": 8 * DAY + 23 * 60, "place_key": "nest.r4", "def": "bandit_raid"}) and ok
	ok = _make(base, "life_kidnap", 18 * 60 + 40, "Un secuestro",
		"Día 9, 18:40: a las 18:50 los bandidos se llevan a un familiar del héroe (nunca el cabeza de familia): llega la carta del rescate (pagar, negociar, rescatar o no hacer nada).",
		func(st: WorldState) -> void:
			_hero_at(st, [21, 20])
			(st.town["incidents"]["planned"] as Array).append({"def": "kidnapping", "at": 8 * DAY + 18 * 60 + 50, "key": "kidnapping|scenario", "victim": _kin(st)})) and ok
	quit(0 if ok else 1)


## The scenario `id`: the base state at `minute_of_day` of day 9 (the sim played up to it), then `edit`.
func _make(base: Dictionary, id: String, minute_of_day: int, title: String, desc: String, edit: Callable) -> bool:
	var st: WorldState = WorldState.from_dict(SaveFile.migrate(base)["data"])
	var sim := Sim.new(st, cat)
	var target := 8 * DAY + minute_of_day
	sim.run_minutes(target - int(st.clock["minute"]))
	edit.call(st)
	st.meta = {"title": title, "description": desc, "origin": "tools/scenarios/make_life_scenarios.gd"}
	var path := OUT.path_join(id + ".json")
	if SaveFile.save(st, path) != OK:
		print("make_life_scenarios: could not write %s" % path)
		return false
	print("make_life_scenarios: %s (minuto %d)" % [path, int(st.clock["minute"])])
	return true


func _hero_at(st: WorldState, tile: Array) -> void:
	var ch: Dictionary = st.characters[HERO]
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["position"] = tile.duplicate()


func _hero_in(st: WorldState, bld: String) -> void:
	var ch: Dictionary = st.characters[HERO]
	ch["location"] = bld
	ch["path"] = []
	ch["position"] = (st.buildings[bld]["door"] as Array).duplicate()


## One of the hero's family who is not the head.
func _kin(st: WorldState) -> String:
	var fam := str(st.characters[HERO].get("family", ""))
	var head := str(st.families[fam].get("head", ""))
	var spouse := str(st.characters.get(head, {}).get("spouse", ""))
	if spouse != "" and bool(st.characters.get(spouse, {}).get("alive", false)):
		return spouse
	for m: Variant in st.families[fam].get("members", []):
		if str(m) != head and bool(st.characters[str(m)].get("alive", true)):
			return str(m)
	return ""
