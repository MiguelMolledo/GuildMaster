extends "res://tests/test_case.gd"
## The towns made by the town builder (tools/city/ciudad.py generar, docs/protocolos/generar-ciudad.md): each loads
## as a map of the catalog, its test start (data/scenarios/<map>_start.json, tools/scenarios/make_city_scenarios.gd)
## is a real new game on it, the sim walks it and the view draws its decor.

const MAPS: Array[String] = ["town_road", "town_square", "town_crossroads", "town_river", "region_capital", "region_port",
	"region_quarry", "region_hamlet", "region_abbey"]

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


func test_the_view_draws_the_landmarks_and_boats_of_an_organic_town() -> void:
	# tools/city/organic.py: the landmarks (map "landmarks", "H" tiles) and the boats (map "boats", on the water) are
	# drawn as blocks of their footprint; filler houses of other lot sizes as house blocks
	var m: Dictionary = cat.maps().get("region_port", {})
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("region_port_start")["state"], cat)
	var marks := 0
	var boats := 0
	var blocks := 0
	for c: Node in v.objects().get_children():
		var scene := str(c.scene_file_path).get_file().get_basename()
		if scene == "hito":
			marks += 1
		elif scene == "boat":
			boats += 1
		elif scene == "house_block":
			blocks += 1
	eq(marks, (m.get("landmarks", []) as Array).size(), "one block per landmark of region_port")
	eq(boats, (m.get("boats", []) as Array).size(), "one boat per boat of region_port")
	check(blocks > 0, "house blocks of mixed lot sizes (%d)" % blocks)
	var signs := 0
	for c: Node in v.overlay().get_children():
		if str(c.name).begins_with("sign_"):
			signs += 1
	check(signs > 0, "the landmarks' names on signs (%d)" % signs)
	v.free()


func test_the_new_tile_kinds_walk_as_the_table_says() -> void:
	# piers and fords are walkable, walls, rock and landmark tiles are not (data/tiles.json; no rule of the sim changes)
	eq(cat.tile_kind_of_char("m"), "dock", "m is a pier")
	check(cat.tiles["dock"]["walk_cost"] != null and cat.tiles["ford"]["walk_cost"] != null, "piers and fords walk")
	for k: String in ["wall", "rock", "landmark"]:
		check(cat.tiles[k]["walk_cost"] == null, "%s blocks" % k)
	var g := Grid.of(cat, "region_port")
	var m: Dictionary = cat.maps()["region_port"]
	var from: Array = m["spawns"]["player"]
	var pier := Vector2i(-1, -1)
	var rows: Array = m["rows"]
	for r: int in rows.size():
		var c := str(rows[r]).find("m")
		if c >= 0:
			pier = Vector2i(c, r)
			break
	check(pier.x >= 0, "region_port has piers")
	check(not Pathfinder.find(g, Vector2i(int(from[0]), int(from[1])), pier).is_empty(), "a path from the plaza onto a pier")


func test_the_ground_smooths_the_stairs_of_the_diagonal_streets() -> void:
	# data/view.json ground_corners: a tile with street on two sides that meet at a corner gets a triangle of street
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("region_capital_start")["state"], cat)
	check(v.ground().corner_count() > 50, "corner pieces along the diagonal streets of region_capital (%d)" %
		v.ground().corner_count())
	v.free()
