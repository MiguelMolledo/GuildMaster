extends SceneTree
## Builds the employee scenarios of H4 (GDD 4.7, docs/contratos/h4_empleados.md) from the town_e_start sandbox, so
## they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_staff_scenarios.gd
## Same code + same data = same files. Re-run after changing town_e_start (tools/maps/make_town_e.py), the population,
## data/employees.json or the shape of the job. The jobs are written with Staff.new_job (as if hired days ago): hire
## does not exist yet in the base.
##   data/scenarios/two_employees.json        day 1, 04:30 (night, before dawn): the family forge with 2 employee places
##                                            (stands for the Personal upgrade of H5), an apprentice on the furnace and
##                                            a journeyman on the anvil, both at home and starting today; raw materials
##                                            in the storage and a queue of 10 swords. Criterion of H4: 3 days, the forge
##                                            produces without the player going in; each at its station; at night they go.
##   data/scenarios/apprentice_promotion.json day 9, 04:50: an apprentice at the forge with 7 days worked in their rank
##                                            (days 1-7) and loyalty 60. At dawn day 8 is counted: 8 days = 1 year
##                                            worked with loyalty > 50 -> the promotion notice.

const OUT: String = "res://data/scenarios"
const FORGE: String = "bld_0001"


func _init() -> void:
	var cat := Catalog.load_from()
	var ok := _two_employees(cat) and _apprentice_promotion(cat)
	quit(0 if ok else 1)


func _base(cat: Catalog) -> Sim:
	var r := NewGame.from_scenario("town_e_start", 1)
	if not r["ok"]:
		print("make_staff_scenarios: town_e_start: %s" % r["error"])
		return null
	return Sim.new(r["state"], cat)


func _two_employees(cat: Catalog) -> bool:
	var sim := _base(cat)
	if sim == null:
		return false
	var st := sim.state
	var day := 1
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + 270  # 04:30, before the spring dawn (05:00)
	var furnace := _first(sim, "apprentice", 1)
	var anvil := _first(sim, "journeyman", int(cat.recipes()["forge_sword"]["min_craft"]))
	if furnace == "" or anvil == "":
		print("make_staff_scenarios: no apprentice or journeyman in the population")
		return false
	var forge: Dictionary = st.buildings[FORGE]
	forge["employee_slots"] = 2
	_hire(sim, furnace, day - 1, "furnace")
	_hire(sim, anvil, day - 1, "anvil")
	forge["inventory"] = Inventory.create("stacks", float(cat.buildings()["forge"]["storage_stacks"]))
	Inventory.add(forge["inventory"], cat, "iron", Inventory.NORMAL, 60)
	Inventory.add(forge["inventory"], cat, "coal", Inventory.NORMAL, 20)
	forge["queue"] = {"entries": [{"id": Ids.next(st, "qen"), "recipe": "forge_sword", "qty": 10, "done": 0}],
		"loop": false, "paused": false}
	return _save(sim, "two_employees", "Dos empleados",
		"Día 1, 04:30: la forja tiene 2 empleados (%s, aprendiz, en el horno; %s, oficial, en el yunque) que empiezan hoy, hierro ×60 y carbón ×20 en el almacén y una cola de 10 espadas. Al amanecer salen de casa hacia la forja; al atardecer vuelven. El jugador no entra." % [
		st.characters[furnace]["name"], st.characters[anvil]["name"]])


func _apprentice_promotion(cat: Catalog) -> bool:
	var sim := _base(cat)
	if sim == null:
		return false
	var st := sim.state
	var day := 9
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + 290  # 04:50, before the spring dawn (05:00)
	var who := _first(sim, "apprentice", 1)
	if who == "":
		return false
	var job := _hire(sim, who, 0, "furnace")  # hired on day 0, working since day 1
	job["days_worked"] = 7
	job["rank_days"] = 7
	job["loyalty"] = 60
	st.buildings[FORGE]["queue"] = {"entries": [{"id": Ids.next(st, "qen"), "recipe": "forge_ingot", "qty": -1,
		"done": 0}], "loop": false, "paused": false}
	return _save(sim, "apprentice_promotion", "Aprendiz a punto de ascender",
		"Día 9, 04:50: %s, aprendiz de la forja desde el día 1, lleva 7 días trabajados en su rango y lealtad 60. Al amanecer se cuenta el día 8: 1 año trabajado con lealtad > 50, sale el aviso de ascenso (aceptar: +15 lealtad y salario de oficial; rechazar: −10)." % st.characters[who]["name"])


## The first unemployed townsperson (by id) of `rank` with at least `min_craft`.
func _first(sim: Sim, rank: String, min_craft: int) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		if Staff.is_unemployed(sim, id) and str(ch["rank"]) == rank and int(ch["stats"]["craft"]) >= min_craft:
			return id
	return ""


func _hire(sim: Sim, who: String, hired_day: int, role: String) -> Dictionary:
	var job := Staff.new_job(sim, FORGE, hired_day, role)
	sim.state.characters[who]["job"] = job
	return job


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_staff_scenarios.gd"}
	# The same numbers a loaded game has (SaveFile.intify).
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	var staff: Array = []
	for c: String in Staff.employees_of(st, FORGE):
		staff.append("%s %s (%s, %s)" % [c, st.characters[c]["name"], st.characters[c]["rank"], st.characters[c]["job"]["role"]])
	print("make_staff_scenarios: %s (%s) minuto %d, empleados %s" % [id, error_string(e), int(st.clock["minute"]), staff])
	return e == OK
