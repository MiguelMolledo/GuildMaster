extends "res://tests/test_case.gd"
## The region (docs/gdd/09b_region.md): data/world/region.json read by the view (RegionView) and the «Mapa de la
## región» screen (RegionScreen): home, distances over the open routes, the routes a world event cuts, the card of a
## settlement: «Viajar» off with the reason for a commoner, on for a citizen, and its order through order_sink.

var cat := Catalog.load_from()


func _sim(scenario: String = "town_e_start") -> Sim:
	return Sim.new(NewGame.from_scenario(scenario)["state"], cat)


func test_every_settlement_has_its_map_and_the_region_is_connected() -> void:
	var ids := {}
	for s: Dictionary in RegionView.settlements():
		ids[str(s["id"])] = true
		check(cat.maps().has(str(s["map"])), "%s: its map %s is in the catalog" % [s["id"], s["map"]])
	eq(ids.size(), 6, "six settlements")
	var d := RegionView.hours_from("villa")
	eq(d.size(), ids.size(), "every settlement is reachable from the villa")


func test_home_is_the_settlement_of_the_game_map() -> void:
	eq(RegionView.home_of("town_e"), "villa", "town_e is the villa")
	eq(RegionView.home_of("region_port"), "port", "a game on the port's map is at home in the port")
	eq(RegionView.home_of("town_road"), "villa", "a map outside the region falls back to the region's home")


func test_hours_take_the_shortest_open_way() -> void:
	var d := RegionView.hours_from("villa")
	near(float(d["capital"]), 7.0, 0.001, "villa -> capital by the hamlet and the ford (3 + 4) before the royal road (8)")
	var cut := RegionView.hours_from("villa", ["r7"])
	near(float(cut["capital"]), 8.0, 0.001, "with the ford cut, the royal road")
	var none := RegionView.hours_from("villa", ["r2", "r3", "r4"])
	check(not none.has("port"), "with the war's cuts there is no open way to the port")


func test_the_war_cuts_its_routes_and_nothing_else() -> void:
	var sim := _sim()
	eq(RegionView.cut_routes(sim), {}, "no event in force: no route cut")
	WorldEvents.start(sim, "war")
	var cut := RegionView.cut_routes(sim)
	var keys: Array = cut.keys()
	keys.sort()
	eq(keys, ["r2", "r3", "r4"], "the war cuts the routes with war in cut_by")


func test_the_card_travels_only_with_the_citizen_title() -> void:
	var sim := _sim()
	var sc := (load("res://game/ui/region_screen.tscn") as PackedScene).instantiate() as RegionScreen
	sc.sim = sim
	var given: Array = []
	sc.order_sink = func(o: Dictionary) -> void: given.append(o)
	sc.open()
	eq(sc.home, "villa", "home is the villa")
	eq(sc.markers.size(), 6, "a seal per settlement")
	var d := sc.card_data("quarry")
	eq(str(d["template"]), "card", "a PageCard card")
	var b: Dictionary = (d["buttons"] as Array)[0]
	eq(str(b["id"]), "travel", "the first button travels")
	check(bool(b["disabled"]), "a commoner cannot travel")
	eq(str(b["tip"]), SimQuery.reason_text("title_needed"), "and the tip says why")
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["title"] = "citizen"
	b = (sc.card_data("quarry")["buttons"] as Array)[0]
	check(not bool(b["disabled"]), "a citizen can")
	var before := sim.state.to_dict()
	sc.show_card("capital", true)
	sc._on_card_button("travel")
	eq(given.size(), 1, "the button gives one order")
	eq(str(given[0]["type"]), "travel", "travel")
	eq(str(given[0]["to"]), "capital", "to the capital")
	var card := sc.get_node("SettlementCard") as PageCard
	check(card.visible, "the card is shown")
	var after := sim.state.to_dict()
	before.erase("region")
	after.erase("region")
	eq(JSON.stringify(after), JSON.stringify(before), "the map gives orders, it changes nothing of the state itself")
	sc.close()
	sc.free()
