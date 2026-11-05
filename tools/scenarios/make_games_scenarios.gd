extends SceneTree
## Builds the games scenario (docs/gdd/04f_vida_y_fiestas.md §4.26, §4.28.4; docs/contratos/juegos.md) from a real new
## game (artisan_blacksmith, normal, fixed cast, seed 1), so it is reproducible:
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_games_scenarios.gd
##   games_gambler  day 1, 08:00: the smith's family with 3000 gold and a gambling house to play in (meta.games_house:
##                  the house of the Soler family stands in for the licensed tavern until the Posada exists), for the
##                  bot gambler (sim_runner --scenario=games_gambler --bots=gambler).

const OUT: String = "res://data/scenarios"


func _init() -> void:
	var cat := Catalog.load_from()
	var errs := cat.validate()
	if not errs.is_empty():
		print("make_games_scenarios: data problems: %s" % errs)
		quit(1)
		return
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_games_scenarios: new game: %s" % r["error"])
		quit(1)
		return
	var st: WorldState = r["state"]
	var fam := ""
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			fam = f
	st.families[fam]["gold"] = 3000
	var house := ""
	for b: String in st.buildings:
		var owner := Money.family_of(st, b)
		if owner != "" and owner != fam and str(st.buildings[b].get("type", "")) == "house":
			house = b
			break
	st.meta = {"title": "Juegos: la tafurería", "description": "Día 1, 08:00. La familia del herrero con 3000 de oro " +
		"y una casa de juego donde jugar (la casa de los Soler hace de taberna con licencia hasta que llegue la " +
		"Posada): para el bot gambler.", "origin": "tools/scenarios/make_games_scenarios.gd", "games_house": house}
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT.path_join("games_gambler.json"))
	print("make_games_scenarios: games_gambler (casa %s) -> %s" % [house, error_string(e)])
	quit(0 if e == OK else 1)
