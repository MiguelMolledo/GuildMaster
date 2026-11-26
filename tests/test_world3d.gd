extends "res://tests/test_case.gd"
## The 3D town (docs/3d/plan.md, M3D-1), what can be checked without a tree: the live feed is the state of the game
## (the catalog's map, the sim's buildings and people, who is inside), people are placed where the sim has them
## (interpolated between tiles with the step fraction), what each one does is read from the state, and which view the
## game shows. The clicks and the camera are checked with a window (--smoke-script=pueblo3d).

var cat := Catalog.load_from()
const SMOKE_3D: Array = ["pueblo3d"]


func _town() -> Town3D:
	var r := NewGame.from_scenario("town_e_start")
	var t := Town3D.new()
	t.setup(Sim.new(r["state"], cat))
	return t


func test_feed_is_the_state() -> void:
	var t := _town()
	var st := t.sim.state
	eq(t.mapd.get("rows", []), cat.maps()["town_e"]["rows"], "the map of the game (catalog), not a file")
	for b: String in st.buildings:
		check(t.trace.buildings.has(b), "building %s in the feed" % b)
	var alive := 0
	for id: String in st.characters:
		var ch: Dictionary = st.characters[id]
		if bool(ch.get("alive", true)) and ch.has("position"):
			alive += 1
			eq(str(t.trace.characters[id]["family"]), str(ch.get("family", "")), "%s: its family" % id)
	eq(t.trace.characters.size(), alive, "every living person")
	eq(t.trace.meta.minutes_per_tile, Movement.minutes_per_tile(cat), "the sim's walking pace")
	var walk: Array = t.trace.map.walkable
	var grid := Grid.for_state(cat, st)
	eq(walk.size(), grid.height, "the sim's walkable grid")
	t.free()


func test_positions_interpolate() -> void:
	var t := _town()
	var ch: Dictionary = t.sim.state.characters["chr_0001"]
	ch["location"] = ""
	ch["position"] = [20, 18]
	ch["path"] = [[21, 18]]
	ch["move_progress"] = 0
	t.frac = 0.5
	var mpt := float(Movement.minutes_per_tile(cat))
	t.mpt = mpt
	var p := {"id": "chr_0001"}
	near(t.tile_at(p, 0.0).x, 20.0 + 0.5 / mpt, 0.0001, "half a minute into the step")
	near(t.tile_at(p, 0.0).y, 18.0, 0.0001, "same row")
	eq(t.motion_at(p, 0.0), Vector2(2.0 / mpt, 0.0), "2 m per tile towards +col, in plan metres per minute")
	ch["path"] = []
	eq(t.motion_at(p, 0.0), Vector2.ZERO, "standing: no speed")
	eq(t.tile_at(p, 0.0), Vector2(20, 18), "standing on its tile")
	t.free()


func test_inside_and_who_changes() -> void:
	var t := _town()
	var st := t.sim.state
	var now := int(st.clock["minute"])
	var ch: Dictionary = st.characters["chr_0001"]
	ch["location"] = "bld_0001"
	t._refresh_minute(now + 1)
	eq(str(t.trace.characters["chr_0001"]["st"][0][1]), "bld_0001", "inside: the feed says where")
	ch["location"] = ""
	t._refresh_minute(now + 2)
	eq(str(t.trace.characters["chr_0001"]["st"][0][1]), "", "back in the street")
	ch["alive"] = false
	t._refresh_minute(now + 3)
	check(not t.trace.characters.has("chr_0001"), "the dead leave the feed")
	t.free()


func test_doing_reads_the_state() -> void:
	var r := NewGame.from_scenario("town_e_start")
	var sim := Sim.new(r["state"], cat)
	var ch: Dictionary = sim.state.characters["chr_0001"]
	ch["location"] = ""
	ch["path"] = [[1, 1]]
	eq(SimQuery.doing(sim, "chr_0001", int(sim.state.clock["minute"])), "walk", "outside with a path: walking")
	ch["path"] = []
	ch.erase("town")
	eq(SimQuery.doing(sim, "chr_0001", int(sim.state.clock["minute"])), "stand", "outside, nothing to do: standing")
	eq(SimQuery.family_role(sim.state, "chr_0001"), "head", "the protagonist heads the family")


func test_view_mode() -> void:
	eq(ViewConfig.view_mode(PackedStringArray(["--view=2d"]), "", SMOKE_3D), "2d", "--view=2d")
	eq(ViewConfig.view_mode(PackedStringArray([]), "forja", SMOKE_3D), "2d", "an old capture script keeps the 2D")
	eq(ViewConfig.view_mode(PackedStringArray([]), "pueblo3d", SMOKE_3D), "3d", "the 3D capture")
	eq(ViewConfig.view_mode(PackedStringArray(["--gallery"]), "", SMOKE_3D), "2d", "the gallery")
	eq(ViewConfig.view_mode(PackedStringArray([]), "", SMOKE_3D), "3d", "the game: data/view.json view_mode")
