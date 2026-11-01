extends SceneTree
## Builds the upgrade scenarios of H5 (GDD 4.8, docs/contratos/h5_mejoras.md) from the town_e_start sandbox, so they
## are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_upgrade_scenarios.gd
## Same code + same data = same files. Re-run after changing town_e_start (tools/maps/make_town_e.py), the population,
## data/employees.json, data/upgrades/forge/ or the shape of the job or of the upgrade state. The upgrades are finished
## with Upgrades.complete (their effects applied as if built days ago); the jobs are written with Staff.new_job.
##   data/scenarios/forge_upgrades.json       day 1, 04:30 (before dawn): the family forge with 4 upgrades finished
##                                            (Fuelle mejorado, Segundo yunque, Acero templado, Dormitorio de aprendiz:
##                                            2 employee places), an apprentice on the furnace and a journeyman on the
##                                            anvil starting today, 1000 gold, materials for the next upgrades in the
##                                            storage (wood, ingots, coal, stone) and a queue of 10 swords.
##   data/scenarios/forge_upgrade_works.json  the same, with the works of Almacén ampliado (capacity 2) in progress:
##                                            paid (gold through Money, wood from the storage), started 12 h ago, 12 h
##                                            left. For the works view (the forge does not produce meanwhile).

const OUT: String = "res://data/scenarios"
const FORGE: String = "bld_0001"
const FAMILY: String = "fam_0001"
const HERO: String = "chr_0001"
const DONE: Array[String] = ["forge_production_1", "forge_capacity_1", "forge_quality_1", "forge_staff_1"]
const WORKS: String = "forge_capacity_2"


func _init() -> void:
	var cat := Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_upgrade_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var ok := _forge_upgrades(cat, false) and _forge_upgrades(cat, true)
	quit(0 if ok else 1)


func _forge_upgrades(cat: Catalog, works: bool) -> bool:
	var r := NewGame.from_scenario("town_e_start", 1)
	if not r["ok"]:
		print("make_upgrade_scenarios: town_e_start: %s" % r["error"])
		return false
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	var day := 1
	st.clock["minute"] = day * Clock.MINUTES_PER_DAY + 270  # 04:30, before the spring dawn (05:00)
	st.families[FAMILY]["gold"] = 1000  # plenty: the scenario is for buying and looking, not for the economy
	for id: String in DONE:
		if not Upgrades.complete(sim, FORGE, id):
			print("make_upgrade_scenarios: cannot finish %s" % id)
			return false
	var furnace := _first(sim, "apprentice", 1)
	var anvil := _first(sim, "journeyman", int(cat.recipes()["forge_sword"]["min_craft"]))
	if furnace == "" or anvil == "":
		print("make_upgrade_scenarios: no apprentice or journeyman in the population")
		return false
	_hire(sim, furnace, day - 1, "furnace")
	_hire(sim, anvil, day - 1, "anvil")
	var forge: Dictionary = st.buildings[FORGE]
	for it: Array in [["iron", 60], ["coal", 20], ["wood", 20], ["iron_ingot", 10], ["stone", 10]]:
		if not Inventory.add(forge["inventory"], cat, str(it[0]), Inventory.NORMAL, int(it[1])):
			print("make_upgrade_scenarios: %s does not fit" % it[0])
			return false
	forge["queue"] = {"entries": [{"id": Ids.next(st, "qen"), "recipe": "forge_sword", "qty": 10, "done": 0}],
		"loop": false, "paused": false}
	var names := "Fuelle mejorado, Segundo yunque, Acero templado y Dormitorio de aprendiz"
	if not works:
		return _save(sim, "forge_upgrades", "Forja con mejoras",
			"Día 1, 04:30: la forja tiene 4 mejoras terminadas (%s: 2 huecos de empleado y un segundo yunque), %s (aprendiz, horno) y %s (oficial, yunque) empiezan hoy, 1000 de oro, materiales para las siguientes mejoras (madera, lingotes, carbón, piedra) y una cola de 10 espadas." % [
			names, st.characters[furnace]["name"], st.characters[anvil]["name"]])
	# The works of capacity 2, paid as buy_upgrade will pay them, started 12 hours ago.
	if Upgrades.status_of(sim, HERO, FORGE, WORKS) != "available":
		print("make_upgrade_scenarios: %s is %s" % [WORKS, Upgrades.status_of(sim, HERO, FORGE, WORKS)])
		return false
	var u := cat.upgrade(WORKS)
	Money.change(sim, FAMILY, -int(u["cost"]["gold"]), Money.UPGRADES, WORKS, FORGE, HERO)
	for c: Dictionary in u["cost"]["items"]:
		Inventory.remove(forge["inventory"], str(c["item"]), Inventory.NORMAL, int(c["qty"]))
	var now := int(st.clock["minute"])
	var start := now - 720
	forge["upgrade_work"] = {"upgrade": WORKS, "actor": HERO, "start": start,
		"end": start + roundi(float(u["build_days"]) * Clock.MINUTES_PER_DAY)}
	return _save(sim, "forge_upgrade_works", "Forja en obras",
		"Como «Forja con mejoras», con la obra de Almacén ampliado en curso: pagada, empezó hace 12 horas y le quedan 12 (fin a las 16:30). Mientras dura, la forja no produce." )


## The first unemployed townsperson (by id) of `rank` with at least `min_craft`.
func _first(sim: Sim, rank: String, min_craft: int) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		if Staff.is_unemployed(sim, id) and str(ch["rank"]) == rank and int(ch["stats"]["craft"]) >= min_craft:
			return id
	return ""


func _hire(sim: Sim, who: String, hired_day: int, role: String) -> void:
	sim.state.characters[who]["job"] = Staff.new_job(sim, FORGE, hired_day, role)


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_upgrade_scenarios.gd"}
	# The same numbers a loaded game has (SaveFile.intify).
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	var b: Dictionary = st.buildings[FORGE]
	print("make_upgrade_scenarios: %s (%s) minuto %d, mejoras %s, obra %s, huecos %d, puestos %s, oro %d" % [id,
		error_string(e), int(st.clock["minute"]), str(b["upgrades"]), str(b["upgrade_work"]), int(b["employee_slots"]),
		str((b["zones"] as Dictionary).keys()), Money.gold(st, FAMILY)])
	return e == OK
