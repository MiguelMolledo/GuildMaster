extends "res://tests/test_case.gd"
## The towns made by the town builder (tools/city/ciudad.py generar, docs/protocolos/generar-ciudad.md): each loads
## as a map of the catalog, its test start (data/scenarios/<map>_start.json, tools/scenarios/make_city_scenarios.gd)
## is a real new game on it, the sim walks it and the view draws its decor.

const MAPS: Array[String] = ["town_road", "town_square", "town_crossroads", "town_river"]

var cat := Catalog.load_from()


func test_every_generated_town_is_a_map_with_its_start() -> void:
	for id: String in MAPS:
		var m: Dictionary = cat.maps().get(id, {})
		check(not m.is_empty(), "%s is a map" % id)
		if m.is_empty():
			continue
		check((m.get("generated", {}) as Dictionary).has("layout"), "%s says how it was made" % id)
		var r := NewGame.from_scenario(id + "_start")
		check(bool(r["ok"]), "%s_start loads" % id)
		if not r["ok"]:
			continue
		var st: WorldState = r["state"]
		eq(st.map_id, id, "%s_start plays on %s" % [id, id])
		var types := {}
		for b: String in st.buildings:
			types[str(st.buildings[b]["type"])] = int(types.get(str(st.buildings[b]["type"]), 0)) + 1
		eq(int(types.get("forge", 0)), 2, "%s: the player's and the rival's forge" % id)
		eq(int(types.get("house", 0)), (m["population"] as Array).size(), "%s: one house per household" % id)
		check(Grid.of(cat, id) != null, "%s has a walk grid" % id)


func test_every_door_of_a_generated_town_is_reachable_from_the_plaza() -> void:
	for id: String in MAPS:
		var m: Dictionary = cat.maps().get(id, {})
		if m.is_empty():
			continue
		var g := Grid.of(cat, id)
		var from: Array = m["spawns"]["player"]
		var start := Vector2i(int(from[0]), int(from[1]))
		for site: String in m["buildings"]:
			var d: Array = m["buildings"][site]["door"]
			var path := Pathfinder.find(g, start, Vector2i(int(d[0]), int(d[1])))
			check(not path.is_empty() or start == Vector2i(int(d[0]), int(d[1])), "%s: a path from the plaza to %s" % [id, site])


func test_the_view_draws_a_generated_town() -> void:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("town_square_start")["state"], cat)
	var lanterns := 0
	for c: Node in v.objects().get_children():
		if str(c.scene_file_path).get_file().get_basename() == "lantern":
			lanterns += 1
	check(lanterns >= 6, "lanterns along the streets of town_square (%d)" % lanterns)
	v.free()


func test_every_artisan_start_plays_on_every_generated_town() -> void:
	# a generated town has the sites of the starts it was made for ("generated.starts"): each one is a real new
	# game there (H12: the rival of the player's own trade on the plot the player's forge has in the smith's game)
	for id: String in MAPS:
		var m: Dictionary = cat.maps().get(id, {})
		if m.is_empty():
			continue
		for start_id: Variant in (m["generated"] as Dictionary).get("starts", []):
			var start: Dictionary = cat.starts()[str(start_id)]
			var before := str(start["map"])
			start["map"] = id
			var r := NewGame.from_start(cat, str(start_id), "normal", {}, 1)
			start["map"] = before
			check(bool(r["ok"]), "%s plays on %s (%s)" % [start_id, id, r.get("error", "")])
			if r["ok"]:
				var types := {}
				for b: String in (r["state"] as WorldState).buildings:
					var bb: Dictionary = (r["state"] as WorldState).buildings[b]
					var key := "%s,%s" % [bb["origin"][0], bb["origin"][1]]
					check(not types.has(key), "%s on %s: one building per plot (%s)" % [start_id, id, key])
					types[key] = true
