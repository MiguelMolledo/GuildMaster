extends SceneTree
## Builds the scenarios of «Forja viva y ritmo» (docs/gdd/03b_diversion_y_ritmo.md) from a real new game
## (artisan_blacksmith, normal, fixed cast, seed 1), so they are reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_forja_scenarios.gd
## Same code + same data = same files. Re-run after changing the start, data/live_forge.json or data/unlocks.json.
##   forge_live_ready  day 1, 08:00: Hugo (Artesanía 7) by his forge, with 40 ingots and 40 coal: the Forja viva
##                     at the anvil (--smoke-script=forja_viva, the tutorial hint of the live forge).
##   pacing_day3       day 3, 09:00 of a game played by the pacing bot: unlocks of the first days already shown and
##                     the open goals (--smoke-script=ritmo: the unlock card, the goals zone, «Saltar hasta…»).

const OUT: String = "res://data/scenarios"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat: Catalog


func _init() -> void:
	cat = Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_forja_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var ok := _forge_live_ready()
	ok = _pacing_day3() and ok
	quit(0 if ok else 1)


func _new_game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_forja_scenarios: new game: %s" % r["error"])
		return null
	return Sim.new(r["state"], cat)


func _forge_live_ready() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	var st := sim.state
	st.clock["minute"] = 8 * 60
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	Inventory.add(inv, cat, "iron_ingot", Inventory.NORMAL, 40)
	Inventory.add(inv, cat, "coal", Inventory.NORMAL, 40)
	return _save(sim, "forge_live_ready", "Forja viva: la forja de Hugo con lingotes",
		"Día 1, 08:00. Hugo (Artesanía 7) junto a su forja, que tiene 40 lingotes y 40 de carbón: el yunque ofrece la " +
		"Forja viva (calentar, batir y templar). --smoke-script=forja_viva.")


func _pacing_day3() -> bool:
	var sim := _new_game()
	if sim == null:
		return false
	var bot: Object = load("res://sim/bots/bot_pacing.gd").new() if ResourceLoader.exists("res://sim/bots/bot_pacing.gd") \
		else null
	if bot == null:
		return true  # the pacing bot arrives with its block: nothing to build yet
	var target := 2 * 1440 + 9 * 60
	while int(sim.state.clock["minute"]) < target:
		sim.step(bot.orders(sim))
	for c: Dictionary in sim.state.characters.values():
		c["order_queue"] = []
	return _save(sim, "pacing_day3", "Ritmo: tercer día de una partida nueva",
		"Día 3, 09:00 de una partida jugada por el bot de ritmo: desbloqueos de los primeros días y metas abiertas. " +
		"--smoke-script=ritmo.")


func _save(sim: Sim, id: String, title: String, description: String) -> bool:
	var st := sim.state
	st.meta = {"title": title, "description": description, "origin": "tools/scenarios/make_forja_scenarios.gd"}
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join(id + ".json"))
	print("make_forja_scenarios: %s -> %s" % [id, error_string(e)])
	return e == OK
