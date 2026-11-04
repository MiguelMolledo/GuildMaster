extends SceneTree
## The scenario of travel and trade (docs/gdd/09b_region.md): data/scenarios/travel_start.json, for the tutorial's
## chapter «Viajar y comerciar», the capture --smoke-script=viajes and the merchant bot. From two_employees (town_e,
## the forge with two employees): the player's family is made a citizen (the title that opens travelling, O-R2 a),
## gets 900 gold more and 6 swords in the forge's storage; the region is filled (Region.ensure). Nothing else changes.
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_travel_scenario.gd
## Same code + same data = same file.

const BASE: String = "two_employees"
const OUT: String = "res://data/scenarios/travel_start.json"


func _init() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario(BASE)
	if not r["ok"]:
		print("make_travel_scenario: %s: %s" % [BASE, r["error"]])
		quit(1)
		return
	var st: WorldState = r["state"]
	var sim := Sim.new(st, cat)
	var fam := SimQuery.player_family(st)
	st.families[fam]["title"] = "citizen"
	st.families[fam]["gold"] = int(st.families[fam]["gold"]) + 900
	for b: String in st.buildings:
		if str(st.buildings[b]["owner"]) == fam and str(st.buildings[b]["type"]) == "forge":
			Inventory.add(st.buildings[b]["inventory"], cat, "sword", Inventory.NORMAL, 6)
	Region.ensure(sim)
	st.meta = {"title": "Viajar y comerciar", "start": "", "origin": "tools/scenarios/make_travel_scenario.gd",
		"description": "two_employees con la familia del jugador ciudadana (abre los viajes), 900 de oro más y 6 espadas en la forja: el capítulo «Viajar y comerciar», la captura --smoke-script=viajes y el bot merchant."}
	var e := SaveFile.save(WorldState.from_dict(st.to_dict()), OUT)
	print("make_travel_scenario: %s (%s)" % [OUT, error_string(e)])
	quit(0 if e == OK else 1)
