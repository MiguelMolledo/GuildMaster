extends "res://tests/test_case.gd"
## Visual scenes by id (docs/protocolos/editar-a-mano.md): VisualPaths turns ids into game/visuals/<kind>/<id>.tscn
## with a generic fallback, every building and station of data/ has its scene, the interiors have a Marker2D per
## station, the Feet / Top markers place the visuals, the characters get their visual id, and the views build from
## the scenes (no rule reads them).

var cat := Catalog.load_from()


func test_scene_path_and_generic_fallback() -> void:
	eq(VisualPaths.scene_path("buildings", "forge"), "res://game/visuals/buildings/forge.tscn", "path by convention")
	check(VisualPaths.has_scene("buildings", "forge"), "the forge has its scene")
	check(not VisualPaths.has_scene("buildings", "no_such_building"), "an unknown id has none")
	var n := VisualPaths.instantiate("buildings", "no_such_building")
	eq(str(n.name), "Generic", "falls back to buildings/_generic.tscn")
	n.free()
	for kind: String in VisualPaths.KINDS:
		check(VisualPaths.has_scene(kind, VisualPaths.GENERIC), "%s has its generic scene" % kind)


func test_every_building_and_station_has_its_scene() -> void:
	for id: String in cat.buildings():
		check(VisualPaths.has_scene("buildings", id), "buildings/%s.tscn" % id)
		var zones: Array = cat.buildings()[id].get("zones", [])
		if zones.is_empty():
			continue
		check(VisualPaths.has_scene("interiors", id), "interiors/%s.tscn (it has stations)" % id)
		var room := VisualPaths.instantiate("interiors", id)
		for z: Dictionary in zones:
			var m := room.get_node_or_null("Stations/" + str(z["id"]))
			check(m is Marker2D, "%s: a Marker2D for the station %s" % [id, z["id"]])
			check(VisualPaths.has_scene("stations", str(z["id"])), "stations/%s.tscn" % z["id"])
		check(room.get_node_or_null("Kit") is GreyboxKit, "%s: the room's kit (size and door)" % id)
		room.free()


func test_feet_and_top_markers_place_the_visual() -> void:
	var v := VisualPaths.instantiate("props", "tree")
	VisualPaths.place(v, Vector2(100, 50))
	eq(v.position, Vector2(100, 50) - VisualPaths.feet(v), "Feet lands on the anchor")
	eq(VisualPaths.top_height(v, 0.0), 30.0, "the tree's Top: 30 px above its feet")
	(v.get_node("Feet") as Marker2D).position = Vector2(0, 4)
	VisualPaths.place(v, Vector2(100, 50))
	eq(v.position, Vector2(100, 46), "moving Feet in the scene moves the visual")
	eq(VisualPaths.top_height(v, 0.0), 34.0, "the height counts from the feet")
	v.free()
	var bare := Node2D.new()
	eq(VisualPaths.top_height(bare, 12.0), 12.0, "no Top marker: the default")
	bare.free()


func test_character_visual_ids() -> void:
	eq(VisualPaths.character_id({"controlled_by": "human", "female": false}, {}), "artisan_m", "the player's family")
	eq(VisualPaths.character_id({"controlled_by": "ai", "female": true}, {"ai_profile": "rival_smith"}), "artisan_f",
		"a rival family")
	eq(VisualPaths.character_id({"controlled_by": "ai", "female": true, "job": {"building": "bld_0001"}}, {}), "worker_f",
		"an employee")
	eq(VisualPaths.character_id({"controlled_by": "ai", "female": false, "job": null}, {}), "townsfolk_m", "a neighbour")
	for id: String in ["artisan_m", "artisan_f", "worker_m", "worker_f", "townsfolk_m", "townsfolk_f"]:
		var n := VisualPaths.instantiate("characters", id)
		check(n.get_node_or_null("Sprite") is AnimatedSprite2D, "%s: AnimatedSprite2D" % id)
		var sf := (n.get_node("Sprite") as AnimatedSprite2D).sprite_frames
		check(sf != null and sf.has_animation("idle") and sf.has_animation("walk"), "%s: its SpriteFrames" % id)
		eq(VisualPaths.top_height(n, 0.0), 48.0, "%s: 48 px" % id)
		n.free()


func test_missing_icon_and_audio_are_empty() -> void:
	check(VisualPaths.icon("sword") == null, "no icon yet: null (no path in data/items)")
	eq(VisualPaths.audio_files("sfx", "sfx_hammer").size(), 0, "no sound file yet")


func test_world_view_builds_from_the_scenes() -> void:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	var r := NewGame.from_scenario("town_e_start")
	v.setup(r["state"], cat)
	var forge := v.building_visual("bld_0001")
	check(forge != null and str(forge.scene_file_path).ends_with("buildings/forge.tscn"), "the forge is its scene")
	eq(v.sign_of("bld_0001").position.y, (forge.position + VisualPaths.feet(forge)).y - 40.0 - 20.0,
		"the sign hangs 20 px over the Top marker")
	var stall := v.prop_at(Vector2i(16, 14))
	check(stall != null and str(stall.scene_file_path).ends_with("props/stall_resources.tscn"), "the stall by its id")
	var cv := v.view_of("chr_0001")
	check(cv != null and cv.visual() != null and cv.visual_id == "artisan_m", "Hugo is an artisan_m scene")
	v.free()


func test_interior_view_builds_from_the_interior_scene() -> void:
	var r := NewGame.from_scenario("town_e_start")
	var sim := Sim.new(r["state"], cat)
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, "bld_0001", "", true)
	eq(v.size_tiles, Vector2i(8, 6), "size from the kit")
	eq(v.door_tile, Vector2i(0, 3), "door from the kit")
	var room := VisualPaths.instantiate("interiors", "forge")
	for z: String in ["furnace", "anvil", "counter", "storage"]:
		var m := room.get_node("Stations/" + z) as Marker2D
		eq(v.station_view(z).position, m.position, "%s at its marker" % z)
		check(v.station_view(z).look() is Node2D and v.station_view(z).look().get_node_or_null("Greybox") is StationBlock,
			"%s keeps its look from the scene" % z)
	room.free()
	v.free()


func test_upgrade_visuals_follow_the_finished_upgrades() -> void:
	var r := NewGame.from_scenario("forge_upgrades")
	check(bool(r["ok"]), "scenario forge_upgrades (H5)")
	if not bool(r["ok"]):
		return
	var sim := Sim.new(r["state"], cat)
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, "bld_0001", "", true)
	var owned := Upgrades.visuals(sim, "bld_0001")["interior"] as Array
	check(not owned.is_empty(), "the scenario has upgrades with interior visuals")
	for e: Dictionary in owned:
		var n := v.upgrade_visual(str(e["node"]))
		check(n != null and n.visible, "%s shown (%s)" % [e["node"], e["upgrade"]])
	check(v.upgrade_visual("upgrade_strongbox") != null and not v.upgrade_visual("upgrade_strongbox").visible,
		"an upgrade not built stays hidden")
	check(v.station_view("anvil_2") != null, "the second anvil (new_zone) has its station at its marker")
	check(v.station_view("furnace_2") == null, "the third furnace is not built: no station")
	v.free()
	var plain: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	plain.setup(Sim.new(NewGame.from_scenario("town_e_start")["state"], cat), "bld_0001", "", true)
	check(plain.station_view("anvil_2") == null, "without the upgrade: no second anvil")
	plain.free()
	var w: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	w.setup(sim.state, cat, sim)
	w.refresh_upgrades()
	var ups := w.building_visual("bld_0001").get_node("Upgrades")
	for u: Node in ups.get_children():
		check(not (u as CanvasItem).visible, "%s: no exterior upgrade built in the scenario" % u.name)
	w.free()
