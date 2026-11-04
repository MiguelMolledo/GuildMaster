extends "res://tests/test_case.gd"
## The region (docs/gdd/09b_region.md): data/world/region.json read by the view (RegionView) and the «Mapa de la
## región» screen (RegionScreen): home, distances over the open routes, the routes a world event cuts, the card of a
## settlement with «Viajar» off. View only: opening the map changes nothing of the state but the pause.

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


func test_the_card_shows_the_settlement_and_travel_is_off() -> void:
	var sim := _sim()
	var before := JSON.stringify(sim.state.to_dict())
	var sc := (load("res://game/ui/region_screen.tscn") as PackedScene).instantiate() as RegionScreen
	sc.sim = sim
	sc.open()
	eq(sc.home, "villa", "home is the villa")
	eq(sc.markers.size(), 6, "a seal per settlement")
	var d := sc.card_data("quarry")
	eq(str(d["template"]), "card", "a PageCard card")
	var b: Dictionary = (d["buttons"] as Array)[0]
	check(bool(b["disabled"]), "«Viajar» is off")
	check(str(b["text"]).contains(SimQuery.t_("ui.region.soon")), "and says «Próximamente»")
	sc.show_card("capital", true)
	eq(sc.selected, "capital", "the capital's card is open")
	var card := sc.get_node("SettlementCard") as PageCard
	check(card.visible, "the card is shown")
	var tb := card.find_child("Button_travel", true, false) as Button
	check(tb != null and tb.disabled, "its travel button is drawn off")
	sc.close()
	eq(JSON.stringify(sim.state.to_dict()), before, "opening the map changes nothing of the state")
	sc.free()
