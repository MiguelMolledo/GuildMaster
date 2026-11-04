extends SceneTree
## Builds the scenarios of the MVP polish (pulido-mvp) from a real new game (artisan_blacksmith, normal, seed 7):
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_pulido_scenarios.gd
##   fined_broke  day 9, 05:30: the forge has the double accounting and has just been fined 50 with 40 gold: it pays
##                10, keeps 30 to work and owes 40 to the town (a Loan due on day 17); iron 2, coal 1, no products.
##                Before pulido-mvp the fine took every coin and the forge stayed at 0 for ever.

const OUT: String = "res://data/scenarios"
const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
	if not r["ok"]:
		quit(1)
		return
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	st.loans = {}
	st.families[FAM]["gold"] = 40
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 5 * 60 + 30
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	inv["stacks"] = []
	Inventory.add(inv, cat, "iron", 0, 2)
	Inventory.add(inv, cat, "coal", 0, 1)
	(st.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_1")
	Loans.charge_fine(sim, FAM, 50, Money.FINES, "inspection", FORGE)
	st.meta = {"title": "Multada y sin blanca", "description": "Día 10, 05:30: a la forja (con la Doble contabilidad) le acaban de poner una multa de 50 con 40 de oro: paga 10, se queda 30 para seguir trabajando y debe 40 a la ciudad hasta el día 17. Antes la multa se llevaba todo y la forja se quedaba a 0 para siempre.", "origin": "tools/scenarios/make_pulido_scenarios.gd"}
	sim.events = []
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join("fined_broke.json"))
	print("make_pulido_scenarios: fined_broke (%s) oro %d, préstamos %s" % [error_string(e), Money.gold(st, FAM), st.loans.keys()])
	quit(0 if e == OK else 1)
