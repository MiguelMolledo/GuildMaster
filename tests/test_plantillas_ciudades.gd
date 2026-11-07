extends "res://tests/test_case.gd"
## Plantillas (where you start): a new game in any settlement of the region (NewGame.from_start choices.city, the
## «Dónde empiezas» of the new game screen, --start-city). The default start does not move; every city plays every
## artisan start on its own map, full (5 per house), governed, with its market, its gates and its watch; an unknown
## city is refused; the screen sends the city only when it is not the home town.

const START: String = "artisan_blacksmith"
const STARTS: Array[String] = ["artisan_blacksmith", "artisan_carpenter", "artisan_mason", "artisan_tailor"]
const GameScript := preload("res://game/autoload/game.gd")

var cat := Catalog.load_from()


func _game(choices: Dictionary, seed_value: int = 1, start: String = START) -> WorldState:
	var r := NewGame.from_start(cat, start, "normal", choices, seed_value)
	check(bool(r.get("ok", false)), "from_start %s %s: %s" % [start, choices.get("city", ""), r.get("error", "")])
	return r.get("state") as WorldState


func _map_of(city: String) -> Dictionary:
	return cat.maps().get(str(NewGame.city(cat, city).get("map", "")), {})


func test_the_cities_are_the_region_with_the_home_town_first() -> void:
	var ids := NewGame.cities(cat)
	eq(ids.size(), (cat.region.get("settlements", []) as Array).size(), "one per settlement of data/world/region.json")
	eq(str(ids[0]), str(cat.region.get("home", "")), "the home town first")
	eq(NewGame.start_city(cat, START), "villa", "the blacksmith's own town is Vilarrasa")


func test_the_default_start_does_not_move() -> void:
	for cast: String in ["fixed", "random"]:
		var a := _game({"cast": cast})
		var b := _game({"cast": cast, "city": "villa"})
		eq(a.map_id, "town_e", "no city: the start's town (%s)" % cast)
		check(not a.meta.has("city"), "no city in the meta of a default game")
		b.meta.erase("city")
		eq(JSON.stringify(b.to_dict()), JSON.stringify(a.to_dict()), "the home town chosen = the game of always (%s)" % cast)


func test_every_city_plays_every_artisan_start_on_its_map() -> void:
	for id: String in NewGame.cities(cat):
		for start: String in STARTS:
			eq(NewGame.city_problem(cat, start, id), "", "%s can be played in %s" % [start, id])
			var st := _game({"city": id}, 2, start)
			if st == null:
				continue
			eq(st.map_id, str(NewGame.city(cat, id)["map"]), "%s in %s: its map" % [start, id])
			eq(Region.home_id(Sim.new(st, cat)), id, "%s in %s: at home there (the region screen, the visitors)" % [start, id])


func test_every_city_is_full_governed_and_has_its_market_gates_and_watch() -> void:
	var houses_per := int(Life.cfg(cat).get("population", {}).get("per_house", 5))
	for id: String in NewGame.cities(cat):
		if id == "villa":
			continue  # the home town is the start of the targets: as it was
		var m := _map_of(id)
		var st := _game({"city": id, "cast": "fixed"})
		var sim := Sim.new(st, cat)
		var houses := (m.get("population", []) as Array).size()
		var folk := Population.townsfolk(st).size()
		check(folk <= houses_per * houses, "%s: at most %d per house (%d in %d)" % [id, houses_per, folk, houses])
		eq(folk, int(m.get("population_max", -1)), "%s: the town starts full (population_max)" % id)
		eq(Population.max_total(sim), folk, "%s: its cap is its own figure" % id)
		eq((m.get("stalls", {}) as Dictionary).size(), 6, "%s: the six stalls of the market (H12.2: the apothecary)" % id)
		check(not (m.get("board", {}) as Dictionary).is_empty(), "%s: the board" % id)
		check(Offices.has_town_hall(st, cat) and not st.offices.is_empty(), "%s: the town hall and its offices" % id)
		var rival := ""
		for f: String in st.families:
			if str(st.families[f].get("ai_profile", "")) == "rival_smith":
				rival = f
		check(rival != "", "%s: the rival of the trade" % id)
		var gates := Life.gates(sim)
		for g: Variant in Life.cfg(cat).get("watch", {}).get("gates", []):
			check(gates.has(str(g)), "%s: the watch's gate %s" % [id, g])
		check(not (m.get("patrols", []) as Array).is_empty(), "%s: night rounds" % id)
		var kinds := {}
		for p: Dictionary in m.get("social_points", []):
			kinds[str(p.get("kind", ""))] = true
		for k: String in ["square", "gate", "well", "chat"]:
			check(kinds.has(k), "%s: a meeting point %s" % [id, k])


func test_the_life_starts_in_every_city() -> void:
	for id: String in NewGame.cities(cat):
		var sim := Sim.new(_game({"city": id}), cat)
		for i: int in 5:
			sim.step()
		var guards: Dictionary = sim.state.town.get("watch", {}).get("guards", {})
		check(guards.size() >= 2, "%s: the watch is hired (%d)" % [id, guards.size()])


func test_an_unknown_city_is_refused() -> void:
	var r := NewGame.from_start(cat, START, "normal", {"city": "atlantis"}, 1)
	check(not bool(r["ok"]), "refused")
	eq(r.get("error", ""), "unknown_city", "unknown_city")


func test_the_new_game_screen_chooses_where_you_start() -> void:
	var g: Node = GameScript.new()
	g.start(NewGame.from_scenario("town_e_start")["state"], cat)
	var ng: NewGameScreen = (load("res://game/ui/new_game_screen.tscn") as PackedScene).instantiate()
	ng.setup(cat, 11)
	ng.open()
	eq(ng.city, "villa", "Vilarrasa by default")
	check(not ng.choices().has("city"), "the default game does not send a city")
	eq((ng.get_node("%Cities") as HBoxContainer).get_child_count(), NewGame.cities(cat).size(), "a button per city")
	var name_before := (ng.get_node("%NameEdit") as LineEdit).text
	check(ng.set_city("port"), "Portvell")
	eq(str(ng.choices().get("city", "")), "port", "the city goes in the choices")
	check((ng.get_node("%CityLine") as Label).text != "", "its line")
	var folk := 0
	for hh: Dictionary in _map_of("port").get("population", []):
		folk += (hh.get("members", []) as Array).size()
	check((ng.get_node("%CityName") as Label).text.contains(str(folk)), "its townsfolk (%s)" % (ng.get_node("%CityName") as Label).text)
	check((ng.get_node("%NameEdit") as LineEdit).text != "" and name_before != "", "a name proposed")
	check(not ng.set_city("atlantis"), "an unknown city is not chosen")
	var started: Array = []
	ng.started.connect(func(st: WorldState) -> void: started.append(st))
	ng.start_game()
	eq(started.size(), 1, "the game starts")
	if started.size() == 1:
		eq((started[0] as WorldState).map_id, "region_port", "on the port's map")
	check(ng.set_city("villa"), "back home")
	check(not ng.choices().has("city"), "home again: no city")
	ng.free()
	g.free()


func test_the_start_city_flag_opens_the_new_game_screen() -> void:
	var a: Dictionary = GameScript.parse_args(PackedStringArray(["--start-city=capital"]))
	eq(str(a["start_city"]), "capital", "the city")
	check(bool(a["new_game"]) and not bool(a["title"]), "straight to the new game screen")
	a = GameScript.parse_args(PackedStringArray([]))
	eq(str(a["start_city"]), "", "none by default")


## H13 · O-R1 (a proposal for the owner): region.json default_city, off by default. Turned on, the new game screen
## offers the capital first; the sim without a city still plays the start's own map (the targets do not move).
func test_the_capital_as_default_town_is_ready_behind_an_option() -> void:
	eq(str(cat.region.get("default_city", "x")), "", "off in data/world/region.json")
	eq(NewGame.default_city(cat, START), "villa", "off: the start's own town")
	var c := Catalog.load_from()
	c.region["default_city"] = "capital"
	eq(NewGame.default_city(c, START), "capital", "on: Bellcaire")
	c.region["default_city"] = "atlantis"
	eq(NewGame.default_city(c, START), "villa", "an unknown town falls back to the start's own")
	c.region["default_city"] = "capital"
	var g: Node = GameScript.new()
	g.start(NewGame.from_scenario("town_e_start")["state"], c)
	var ng: NewGameScreen = (load("res://game/ui/new_game_screen.tscn") as PackedScene).instantiate()
	ng.setup(c, 11)
	ng.open()
	eq(ng.city, "capital", "the screen opens on Bellcaire")
	eq(str(ng.choices().get("city", "")), "capital", "and sends it")
	check(ng.set_city("villa") and not ng.choices().has("city"), "Vilarrasa can still be chosen: the game of always")
	ng.free()
	g.free()
	var r := NewGame.from_start(c, START, "normal", {"cast": "fixed"}, 1)
	eq((r["state"] as WorldState).map_id, "town_e", "the sim without a city: the start's map, as always")
