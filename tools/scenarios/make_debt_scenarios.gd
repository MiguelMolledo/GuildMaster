extends SceneTree
## Builds the debt scenarios of H3 (GDD 4.16, D18) from a real new game, so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_debt_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, the loan rules or the sim.
##   data/scenarios/debt_due.json            artisan_blacksmith (normal, seed 1, default choices), nobody pays: the sim
##                                           runs the last 2 days (warnings at 2 and 1 days) and stops 1 hour before
##                                           the debt falls due -> extension with surcharge.
##   data/scenarios/debt_extension_due.json  the same game run on: the extension starts, and it stops 1 hour before
##                                           the extension falls due -> seizure (gold, then the forge's goods) and ruin.

const OUT: String = "res://data/scenarios"
const LEAD: int = 60  # minutes left before each due date when the scenario starts


func _init() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_debt_scenarios: %s" % r["error"])
		quit(1)
		return
	var sim := Sim.new(r["state"], cat)
	var loan: Dictionary = sim.state.loans["lon_0001"]
	var due := int(loan["due_minute"])
	# Skip the quiet days: jump to 2 days before the due date and play those 2 days with nobody paying.
	sim.state.clock["minute"] = due - 2 * Clock.MINUTES_PER_DAY - 1
	sim.run_minutes(2 * Clock.MINUTES_PER_DAY + 1 - LEAD)
	_save(sim, "debt_due", "Deuda a punto de vencer",
		"Partida nueva (Normal) sin pagar nada: queda 1 hora para que venza la deuda de 200. Al vencer: reputación −10 y prórroga de 1 estación con recargo del 25 %.")
	sim.run_minutes(LEAD)  # the debt falls due: extension
	due = int(loan["due_minute"])
	sim.run_minutes(due - int(sim.state.clock["minute"]) - LEAD)
	_save(sim, "debt_extension_due", "Prórroga a punto de vencer",
		"La misma partida sin pagar: queda 1 hora para que venza la prórroga (250). El embargo se lleva el oro y la mercancía de la forja y no alcanza: ruina, fin de la partida.")
	quit(0)


func _save(sim: Sim, id: String, title: String, description: String) -> void:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_debt_scenarios.gd"}
	var e := SaveFile.save(st, OUT.path_join(id + ".json"))
	var l: Dictionary = st.loans["lon_0001"]
	print("make_debt_scenarios: %s (%s) minuto %d, oro %d, deuda %d (%s, vence %d)" % [id, error_string(e),
		int(st.clock["minute"]), Money.gold(st, "fam_0001"), int(l["outstanding"]), l["state"], int(l["due_minute"])])
