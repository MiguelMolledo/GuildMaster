extends SceneTree
## Builds the scenarios of the balance pass (rama equilibrio) from a real new game (artisan_blacksmith, normal, seed 1):
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_equilibrio_scenarios.gd
##   broke_forge  day 9, 06:00: the start loan is paid, but the forge has spent everything: 0 gold, 1 coal and nothing
##                else (the chaos player's dead end, Equilibrio 2). The moneylender offers the emergency loan.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"


func _init() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		quit(1)
		return
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}
	st.families[FAM]["gold"] = 0
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 6 * 60
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	inv["stacks"] = []
	Inventory.add(inv, cat, "coal", 0, 1)
	for c: Variant in st.families[FAM]["members"]:
		st.characters[str(c)]["inventory"]["stacks"] = []
	st.meta = {"title": "Sin blanca ni existencias", "description": "Día 9, 06:00: la deuda inicial está pagada, pero la forja se lo ha gastado todo: 0 de oro y 1 carbón. Antes la partida se quedaba muerta; ahora el prestamista ofrece un préstamo de urgencia (60 ahora, 90 en 4 días) y, si no, llega el embargo de un bien (Equilibrio 2).", "origin": "tools/scenarios/make_equilibrio_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join("broke_forge.json"))
	print("make_equilibrio_scenarios: broke_forge (%s) oro %d" % [error_string(e), Money.gold(st, FAM)])
	quit(0 if e == OK else 1)
