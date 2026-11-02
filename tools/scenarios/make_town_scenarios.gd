extends SceneTree
## Builds the town scenarios of H7 (GDD 4.11, 4.5.4, 4.20, docs/contratos/h7_ciudad.md) from a real new game
## (artisan_blacksmith, normal, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_town_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, the map, data/town.json or the shape of the
## town state.
##   plaza_dusk         day 1, 18:40: the townsfolk at their trades (out of their houses, the armory clerk inside the
##                      armory), Hugo in the plaza, no loan. At 19:00 dusk starts and they go to socialise.
##   town_microevents   day 0, dawn (05:00): the forge with the sales counter (forge_commerce_1) and a bedroom
##                      (forge_staff_1: 2 employee places), an apprentice at the counter (role counter) and a journeyman
##                      at any station making swords, a stocked storage (140 swords, ingots, iron, coal: a month of customers), 300 gold, no loan,
##                      Hugo inside the forge. The sandbox of the microevents and the counter customers (30-day target).
##   microevent_card    town_microevents at dawn of day 1 with a sick_employee microevent waiting for an answer.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_town_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var ok := _plaza_dusk() and _town_microevents() and _microevent_card()
	quit(0 if ok else 1)


func _new_game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)
	if not r["ok"]:
		print("make_town_scenarios: new game: %s" % r["error"])
		return null
	var sim := Sim.new(r["state"], cat)
	sim.state.loans = {}  # an old game: the start's loan already repaid
	sim.state.families[FAM]["gold"] = 300
	return sim


func _at(sim: Sim, day: int, hh: int, mm: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + hh * 60 + mm


## The building of the state placed at map site type `type` with no owner (the armory).
func _public(sim: Sim, type: String) -> String:
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["type"]) == type and str(sim.state.buildings[b]["owner"]) == "":
			return b
	return ""


func _plaza_dusk() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	var st := sim.state
	_at(sim, 1, 18, 40)
	var armory := _public(sim, "armory")
	var ids: Array = st.characters.keys()
	ids.sort()
	var placed := 0
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		if not TownLife.is_townsperson(st, id) or str(ch.get("occupation", "")) == "":
			continue
		var wp := TownLife.workplace(st, cat, str(ch["occupation"]))
		ch["position"] = (wp["tile"] as Array).duplicate()
		ch["location"] = armory if str(wp.get("kind", "")) == "shop" else ""
		ch["town"] = {"state": "working", "plan": "work", "day": 1, "leave_at": 0}
		placed += 1
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = [20, 21]
	return _save(sim, "plaza_dusk", "Plaza al atardecer",
		"Día 1, 18:40: los %d vecinos en sus oficios (puestos del mercado, Armería, iglesia, ayuntamiento, campos, río, pozo y puertas) y Hugo en la plaza. A las 19:00 empieza el atardecer: dejan el trabajo y van a los bancos, a charlar, a los dados, a pasear el mercado o a mirar un edificio; a las 21:00 todos vuelven a casa." % placed)


func _town_microevents() -> bool:
	var sim := _build_microevents()
	if sim == null:
		return false
	return _save(sim, "town_microevents", "Mostrador y microeventos",
		"Día 0, amanecer: la forja con Mostrador y Dormitorio (2 huecos), %s (aprendiz, en el mostrador) y %s (oficial, hace espadas), almacén con 140 espadas, lingotes, hierro y carbón (un mes de clientes), 300 de oro y sin deuda; Hugo dentro. Llegan clientes al mostrador y, algún amanecer, microeventos (regateo, empleado enfermo, ladrón nocturno)." % [
		sim.state.characters[_counter_employee(sim)]["name"], sim.state.characters[_any_employee(sim)]["name"]])


func _build_microevents() -> Sim:
	var sim := _new_game()
	if sim == null:
		return null
	var st := sim.state
	for id: String in ["forge_commerce_1", "forge_staff_1"]:
		if not Upgrades.complete(sim, FORGE, id):
			print("make_town_scenarios: cannot finish %s" % id)
			return null
	var counter := _first(sim, "apprentice", 1)
	if counter == "":
		return null
	st.characters[counter]["job"] = Staff.new_job(sim, FORGE, -1, "counter")
	var smith := _first(sim, "journeyman", int(cat.recipes()["forge_sword"]["min_craft"]))
	if smith == "":
		return null
	st.characters[smith]["job"] = Staff.new_job(sim, FORGE, -1, "any")
	var forge: Dictionary = st.buildings[FORGE]
	forge["inventory"]["stacks"] = []
	# a month of customers (1 every 1-2 h of day, GDD 4.5.4): 7 stacks of swords and inputs for more
	for it: Array in [["sword", 140], ["iron_ingot", 20], ["iron", 99], ["coal", 50]]:
		if not Inventory.add(forge["inventory"], cat, str(it[0]), Inventory.NORMAL, int(it[1])):
			print("make_town_scenarios: %s does not fit" % it[0])
			return null
	forge["queue"] = {"entries": [{"id": Ids.next(st, "qen"), "recipe": "forge_sword", "qty": -1, "done": 0}],
		"loop": false, "paused": false}
	st.characters[HERO]["location"] = FORGE
	st.characters[HERO]["position"] = (forge["door"] as Array).duplicate()
	return sim


func _microevent_card() -> bool:
	var sim := _build_microevents()
	if sim == null:
		return false
	var st := sim.state
	var dawn := int(cat.time["phase_starts"][Clock.season(Clock.MINUTES_PER_DAY, cat.time)]["dawn"])
	st.clock["minute"] = Clock.MINUTES_PER_DAY + dawn
	if not FileAccess.file_exists("res://sim/town/microevents.gd"):
		print("make_town_scenarios: microevent_card skipped (no Microevents yet)")
		return true
	var mev := _start_sick(sim)
	if mev == "":
		print("make_town_scenarios: the sick_employee microevent did not start")
		return false
	return _save(sim, "microevent_card", "Tarjeta de microevento",
		"Día 1, amanecer: como «Mostrador y microeventos», con %s enfermo esperando decisión (pagar al médico, día libre pagado o descontarle el día). Si no se elige en 2 h de juego, se aplica el día libre pagado." % st.characters[_any_employee(sim)]["name"])


## Starts the sick_employee microevent for the journeyman (through the class by name: it exists from the sim phase).
func _start_sick(sim: Sim) -> String:
	var script: Script = load("res://sim/town/microevents.gd")
	return str(script.call("start", sim, "sick_employee", FAM, FORGE, _any_employee(sim)))


func _counter_employee(sim: Sim) -> String:
	for id: String in Staff.employees_of(sim.state, FORGE):
		if str(sim.state.characters[id]["job"]["role"]) == "counter":
			return id
	return ""


func _any_employee(sim: Sim) -> String:
	for id: String in Staff.employees_of(sim.state, FORGE):
		if str(sim.state.characters[id]["job"]["role"]) == "any":
			return id
	return ""


## The first unemployed townsperson (by id) of `rank` with at least `min_craft`.
func _first(sim: Sim, rank: String, min_craft: int) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		if Staff.is_unemployed(sim, id) and str(ch["rank"]) == rank and int(ch["stats"]["craft"]) >= min_craft:
			return id
	print("make_town_scenarios: no %s with craft >= %d" % [rank, min_craft])
	return ""


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_town_scenarios.gd"}
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_town_scenarios: %s (%s) minuto %d, oro %d, activos %d" % [id, error_string(e), int(st.clock["minute"]),
		Money.gold(st, FAM), (st.microevents.get("active", []) as Array).size()])
	return e == OK
