extends SceneTree
## Builds the family scenarios of H8 (GDD 4.10, 4.17, docs/contratos/h8_familia.md) from a real new game
## (artisan_blacksmith, normal, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_family_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, the population, data/family.json or the shape
## of the family state. The past is written as it would have happened (weddings and births with their days, the
## chronicle facts, the loan already repaid) without running those years.
##   founder_old       day 0, 06:00: Hugo, 60 (the founder), married for 17 years to Agnès (56); their son Pere (16,
##                     the heir, in the controllable group with the default routine) and daughter Clara (12); 600
##                     gold, the loan repaid. Inheritance from here (GDD 10, H11).
##   founder_no_heir   day 7, 23:50: Hugo, 74, a widower whose only son died young; no heir. At midnight the year
##                     changes, he turns 75 and dies: Game Over with the dynasty score.
##   courtship         day 1, 19:30 (dusk): Hugo, 20, single, at the door of the Soler house with 76 affinity with
##                     Agnès Soler (single, at home): one talk reaches 80 and he can propose.
##   dynasty_start     day 0, dawn: Hugo, 40, single, 400 gold, no loan. The start of the dynasty bot.
##   family_routines   day 2, 04:30: Hugo (40), his wife Agnès and their adult children Pere (18) and Clara (17), the
##                     three of the group with routines (Day = work at the forge, Dawn and Dusk free, Night rest); the
##                     forge with a second anvil, a bigger storage and a second furnace (capacity 1-3: four stations
##                     for the three and the spouse, who follows the Work directive) and stocked for a day of work
##                     (iron, coal, ingots). For the routine test and the routine editor.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_family_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var ok := _founder_old() and _founder_no_heir() and _courtship() and _dynasty_start() and _family_routines()
	quit(0 if ok else 1)


func _new_game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_family_scenarios: new game: %s" % r["error"])
		return null
	return Sim.new(r["state"], cat)


func _at(sim: Sim, day: int, hh: int, mm: int) -> void:
	sim.state.clock["minute"] = day * Clock.MINUTES_PER_DAY + hh * 60 + mm


## A townsperson of the population by name (the first one).
func _townsperson(sim: Sim, name: String) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(sim.state.characters[id].get("name", "")) == name and str(sim.state.characters[id].get("home", "")) != "":
			return id
	return ""


func _set_age(sim: Sim, chr: String, age: int) -> void:
	sim.state.characters[chr]["birth_day"] = Kin.birth_day_for(age, int(sim.state.clock["minute"]), cat.time)


## The loan of the start, already repaid (an old game).
func _no_loan(sim: Sim) -> void:
	sim.state.loans = {}


## A wedding `years_ago` years back: Courtship.marry now, then the wedding day moved back.
func _married(sim: Sim, a: String, b: String, years_ago: int) -> void:
	Courtship.marry(sim, a, b)
	var wife: Dictionary = sim.state.characters[a if bool(sim.state.characters[a].get("female", false)) else b]
	var day := Clock.day(int(sim.state.clock["minute"])) - years_ago * Clock.days_per_year(cat.time)
	wife["life"]["wedding_day"] = day
	_move_fact(sim, "wedding", day)


## A child of `mother` and `father` aged `age`: Births.born now, then renamed, re-aged and moved home as a grown one.
func _child(sim: Sim, mother: String, father: String, name: String, female: bool, age: int) -> String:
	var id := Births.born(sim, mother, father)
	var ch: Dictionary = sim.state.characters[id]
	ch["name"] = name
	ch["female"] = female
	_set_age(sim, id, age)
	sim.state.characters[mother]["life"]["last_birth_day"] = int(ch["birth_day"])
	_move_fact(sim, "birth", int(ch["birth_day"]))
	var life: Dictionary = cat.family.get("life", {})
	if age >= int(life.get("school_age", 8)):
		ch["stats"]["craft"] = mini(10, int(ch["stats"]["craft"]) + 1)
		ch["life"]["school"] = "craft"
	if age >= int(life.get("apprentice_age", 12)):
		ch["profession"] = "blacksmith"
		ch["assigned"] = FORGE
	if age >= int(life.get("majority_age", 16)):
		ch["inventory"]["limit"] = float(life.get("adult_carry_weight", 30.0))
	return id


## The last chronicle fact of `kind` happened on `day` (the scenario writes the past now).
func _move_fact(sim: Sim, kind: String, day: int) -> void:
	for i: int in range(sim.state.chronicle.size() - 1, -1, -1):
		if str(sim.state.chronicle[i].get("kind", "")) == kind:
			sim.state.chronicle[i]["minute"] = day * Clock.MINUTES_PER_DAY
			return


func _clean(sim: Sim) -> void:
	sim.events = []
	sim.state.notices = []


func _save(sim: Sim, id: String, title: String, desc: String) -> bool:
	_clean(sim)
	sim.state.meta = {"title": title, "description": desc, "origin": "tools/scenarios/make_family_scenarios.gd"}
	var path := ProjectSettings.globalize_path(OUT.path_join(id + ".json"))
	var e := SaveFile.save(sim.state, path)
	if e != OK:
		print("make_family_scenarios: cannot save %s (%s)" % [id, error_string(e)])
		return false
	print("make_family_scenarios: %s (día %d, %d personajes)" % [id, Clock.day(int(sim.state.clock["minute"])),
		sim.state.characters.size()])
	return true


func _founder_old() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	_at(sim, 0, 6, 0)
	_no_loan(sim)
	sim.state.families[FAM]["gold"] = 600
	_set_age(sim, HERO, 60)
	var wife := _townsperson(sim, "Agnès")
	_set_age(sim, wife, 56)
	_married(sim, HERO, wife, 17)
	var son := _child(sim, wife, HERO, "Pere", false, 16)
	var daughter := _child(sim, wife, HERO, "Clara", true, 12)
	Lifecycle.join_group(sim, son)
	_place_home(sim, [wife, son, daughter])
	return _save(sim, "founder_old", "Fundador de 60 años",
		"H8/H11: Hugo, el fundador, tiene 60 años; casado con Agnès; su hijo Pere (16) es el heredero y está en el grupo; Clara tiene 12. Para heredar y seguir jugando.")


func _founder_no_heir() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	_at(sim, 0, 6, 0)
	_no_loan(sim)
	sim.state.families[FAM]["gold"] = 1250
	_set_age(sim, HERO, 74)
	var wife := _townsperson(sim, "Agnès")
	_set_age(sim, wife, 70)
	_married(sim, HERO, wife, 50)
	var son := _child(sim, wife, HERO, "Pere", false, 30)
	_place_home(sim, [wife, son])
	Lifecycle.die(sim, son, "illness")
	_move_fact(sim, "death", Clock.day(int(sim.state.clock["minute"])) - 160)
	sim.state.characters[son]["death_day"] = Clock.day(int(sim.state.clock["minute"])) - 160
	Lifecycle.die(sim, wife, "old_age")
	_move_fact(sim, "death", Clock.day(int(sim.state.clock["minute"])) - 24)
	sim.state.characters[wife]["death_day"] = Clock.day(int(sim.state.clock["minute"])) - 24
	Dynasty.record_peak(sim, FAM)
	_at(sim, 7, 23, 50)
	return _save(sim, "founder_no_heir", "Sin heredero",
		"H8: Hugo, 74 años, viudo y sin hijos vivos. A medianoche cambia el año, cumple 75 y muere: fin de la partida con la puntuación de la dinastía.")


func _courtship() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	_at(sim, 1, 19, 30)
	var agnes := _townsperson(sim, "Agnès")
	var door: Array = Courtship.spot(sim.state, agnes)
	sim.state.characters[HERO]["position"] = [int(door[0]), int(door[1])]
	sim.state.characters[HERO]["location"] = ""
	Courtship.relation(sim.state, HERO, agnes)["affinity"] = 76
	return _save(sim, "courtship", "Cortejo",
		"H8: Hugo (20, soltero) ante la casa de los Soler con 76 de afinidad con Agnès: una conversación llega a 80 y puede proponer matrimonio.")


func _dynasty_start() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	_no_loan(sim)
	sim.state.families[FAM]["gold"] = 400
	_set_age(sim, HERO, 40)
	return _save(sim, "dynasty_start", "Comienzo de dinastía",
		"H8: Hugo, 40 años, soltero, 400 de oro y sin deuda. Punto de partida del bot dynasty.")


func _family_routines() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	_at(sim, 2, 4, 30)
	_no_loan(sim)
	sim.state.families[FAM]["gold"] = 300
	_set_age(sim, HERO, 40)
	var wife := _townsperson(sim, "Agnès")
	_set_age(sim, wife, 38)
	_married(sim, HERO, wife, 19)
	var son := _child(sim, wife, HERO, "Pere", false, 18)
	var daughter := _child(sim, wife, HERO, "Clara", true, 17)
	Lifecycle.join_group(sim, son)
	Lifecycle.join_group(sim, daughter)
	var sched := {"dawn": {"action": "free"}, "day": {"action": "work", "building": FORGE}, "dusk": {"action": "free"},
		"night": {"action": "rest"}}
	for c: String in [HERO, son, daughter]:
		sim.state.characters[c]["schedule"] = sched.duplicate(true)
	sim.state.characters[HERO]["location"] = FORGE
	_place_home(sim, [wife, son, daughter])
	for up: String in ["forge_capacity_1", "forge_capacity_2", "forge_capacity_3"]:  # anvil_2, 20 stacks, furnace_2
		Upgrades.complete(sim, FORGE, up)
	for it: Array in [["iron", 60], ["coal", 30], ["iron_ingot", 40]]:
		Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, str(it[0]), Inventory.NORMAL, int(it[1]))
	return _save(sim, "family_routines", "Rutinas de la familia",
		"H8: Hugo, su mujer Agnès y sus hijos Pere (18) y Clara (17). Los tres del grupo con rutina: de día trabajan en la forja (con segundo yunque y segundo horno; la pareja también trabaja por su directiva), al alba y al atardecer libres (directiva Trabajar) y de noche descansan.")


## The family members live at home: inside the forge, standing at its door.
func _place_home(sim: Sim, who: Array) -> void:
	var door: Array = sim.state.buildings[FORGE]["door"]
	for c: Variant in who:
		var ch: Dictionary = sim.state.characters[str(c)]
		if not bool(ch.get("alive", true)):
			continue
		ch["location"] = FORGE
		ch["position"] = [int(door[0]), int(door[1])]
		ch["path"] = []
