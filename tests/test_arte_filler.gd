extends "res://tests/test_case.gd"
## The town's free building tiles (#) dressed as house lots and yards (data/view.json "filler", WorldView._add_filler),
## the hand-placed decoration of the map (game/visuals/towns/<map>.tscn) and the item icons of the UI lists.

var cat := Catalog.load_from()


func _view() -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("town_e_start")["state"], cat)
	return v


func _id(n: Node) -> String:
	return str(n.scene_file_path).get_file().get_basename() if n != null else ""


func test_free_blocks_become_house_lots_and_yards() -> void:
	var v := _view()
	var cfg: Dictionary = ViewConfig.value("filler", {})
	var houses: Array = cfg["houses"]
	var yards: Array = []
	for th: Array in cfg["yard_themes"]:
		yards.append_array(th)
	# the 6×4 block north of the plaza (cols 17-22, rows 8-11): the town builder's decor (data/maps "decor",
	# tools/city/) puts two 3×3 houses on the plaza side (rows 9-11, doors to +row) and the yards behind (row 8)
	var west := v.prop_at(Vector2i(17, 9))
	var east := v.prop_at(Vector2i(20, 9))
	check(houses.has(_id(west)) and houses.has(_id(east)), "two houses on the 6×4 block: %s, %s" % [_id(west), _id(east)])
	check(west != east, "one visual per lot")
	eq(v.prop_at(Vector2i(19, 11)), west, "every tile of a lot points to its house")
	for c: int in range(17, 23):
		check(yards.has(_id(v.prop_at(Vector2i(c, 8)))), "yard behind the houses at (%d, 8)" % c)
	var centre := (Iso.tile_to_world(Vector2i(17, 9)) + Iso.tile_to_world(Vector2i(19, 11))) / 2.0
	eq(west.position + VisualPaths.feet(west) * west.scale, centre, "the house stands on the lot's centre")
	# the 2×3 strip beside the forge is too narrow for a house: yards (low props, never over the forge's base)
	for t: Vector2i in [Vector2i(28, 20), Vector2i(29, 22)]:
		check(yards.has(_id(v.prop_at(t))), "yard at %s: %s" % [t, _id(v.prop_at(t))])
		check(VisualPaths.top_height(v.prop_at(t), 0.0) <= 30.0, "a yard is low (%s)" % t)
	eq(_id(v.prop_at(Vector2i(19, 18))), str(cfg["single"]), "the lone # of the plaza is the well")
	var blocks := 0
	for n: Node in v.objects().get_children():
		if _id(n) == "building":
			blocks += 1
	eq(blocks, 0, "no greybox block left for the free # tiles")
	v.free()


func test_the_dressing_is_the_same_every_game() -> void:
	var a := _view()
	var b := _view()
	# H9: (12, 27) instead of (17, 26), which the town hall takes now
	for t: Vector2i in [Vector2i(17, 8), Vector2i(12, 8), Vector2i(9, 11), Vector2i(28, 21), Vector2i(12, 27)]:
		eq(_id(a.prop_at(t)), _id(b.prop_at(t)), "same visual at %s" % t)
		eq(a.prop_at(t).scale, b.prop_at(t).scale, "same mirroring at %s" % t)
	a.free()
	b.free()


func test_building_footprints_keep_their_own_visual() -> void:
	var v := _view()
	for t: Vector2i in [Vector2i(25, 20), Vector2i(27, 23)]:
		eq(v.prop_at(t), null, "the forge's tile %s is not dressed" % t)
	v.free()


func test_town_decor_joins_the_objects_layer() -> void:
	check(VisualPaths.has_scene("towns", "town_e"), "town_e has its decoration scene")
	var decor := VisualPaths.instantiate("towns", "town_e")
	var n := decor.get_child_count()
	check(n > 0, "it has pieces")
	var first := decor.get_child(0) as Node2D
	var where := first.position
	var what := _id(first)
	decor.free()
	var v := _view()
	var found := false
	for c: Node in v.objects().get_children():
		if _id(c) == what and (c as Node2D).position == where:
			found = true
	check(found, "%s at %s in the objects layer (sorts with the walkers)" % [what, where])
	v.free()


func test_item_icons_for_lists() -> void:
	var r := UiIcons.item_rect("sword")
	check(r != null and r.texture != null, "the sword has a 16×16 list icon")
	if r != null:
		eq(r.texture.get_size(), Vector2(16, 16), "16×16")
		r.free()
	eq(UiIcons.item_rect("item_without_icon"), null, "no icon yet: no rect")


func test_trees_take_one_of_their_looks() -> void:
	var v := _view()
	var looks: Array = (ViewConfig.value("prop_variants", {}) as Dictionary)["tree"]
	var seen := {}
	var rows: Array = cat.maps()["town_e"]["rows"]
	for r: int in rows.size():
		for c: int in str(rows[r]).length():
			if str(rows[r])[c] == "T":
				var id := _id(v.prop_at(Vector2i(c, r)))
				check(looks.has(id), "tree at %d,%d is one of its looks (%s)" % [c, r, id])
				seen[id] = true
	check(seen.size() >= 2, "the map mixes tree looks: %s" % [seen.keys()])
	v.free()


func test_river_bank_and_bridge_curb() -> void:
	var v := _view()
	check(v.ground().edge_count() > 0, "the ground draws the river's bank and the bridge's curb")
	v.free()


func test_interior_kit_uses_its_art_and_falls_back() -> void:
	for b: String in ["forge", "armory"]:
		var room := VisualPaths.instantiate("interiors", b)
		var kit := room.get_node("Kit") as GreyboxKit
		check(kit.floor_texture != null and kit.wall_texture_ne != null and kit.door_texture_nw != null, "%s: kit art" % b)
		kit.build()
		var f := kit.floor_layer().get_child(0) as KitFloor
		eq(f.texture, kit.floor_texture, "%s: the floor tiles get the floor art" % b)
		var door := kit.walls().get_node_or_null("Door") as KitWall
		check(door != null and door.texture == (kit.door_texture_ne if door.side == "ne" else kit.door_texture_nw),
			"%s: the door segment gets the door art of its side" % b)
		kit.floor_texture = null
		kit.build()
		eq((kit.floor_layer().get_child(0) as KitFloor).texture, null, "%s: no art = the greybox colours" % b)
		room.free()


func test_forge_works_and_facades_have_art_with_greybox_kept() -> void:
	var f := VisualPaths.instantiate("buildings", "forge")
	check(f.get_node("Works/Scaffold") is Sprite2D and not (f.get_node("Works/Poles") as CanvasItem).visible,
		"the scaffold sprite replaces the greybox poles (kept hidden)")
	for n: String in ["upgrade_stone_facade", "upgrade_noble_facade", "upgrade_garden", "upgrade_shop_window",
			"upgrade_trade_sign", "upgrade_reinforced_lock"]:
		var u := f.get_node("Upgrades/" + n)
		var sprites := 0
		for c: Node in u.get_children():
			if c is Sprite2D:
				sprites += 1
		check(sprites > 0, "%s has its sprite" % n)
		check(u.get_node_or_null("Greybox") != null and not (u.get_node("Greybox") as CanvasItem).visible,
			"%s keeps its greybox, hidden" % n)
	f.free()


func test_interior_upgrades_have_art_with_greybox_kept() -> void:
	var room := VisualPaths.instantiate("interiors", "forge")
	var n := 0
	for u: Node in room.get_node("Upgrades").get_children():
		var gb := u.get_node_or_null("Greybox") as CanvasItem
		if gb == null:
			continue  # the extra stations' nodes (their look is the station's scene)
		n += 1
		check(u.get_node_or_null("Sprite") is Sprite2D, "%s has its sprite" % u.name)
		check(not gb.visible, "%s keeps its greybox, hidden" % u.name)
	check(n >= 15, "every upgrade visual of the forge's interior (%d)" % n)
	room.free()


func test_map_border_ring_with_streets_river_and_trees() -> void:
	var v := _view()
	var cfg: Dictionary = ViewConfig.value("map_border", {})
	var ring := int(cfg["tiles"])
	var cells: Array = v.ground().border_cells()
	check(cells.size() > 0, "the ground draws a border ring")
	var kinds := {}
	var farthest := 0
	for c: Array in cells:
		kinds[str(c[1])] = true
		farthest = maxi(farthest, int(c[3]))
	eq(farthest, ring, "the ring is %d tiles wide" % ring)
	check(kinds.has("street") and kinds.has("water"), "the gate streets and the river carry on outwards: %s" % [kinds.keys()])
	var trees := 0
	for n: Node in v.objects().get_children():
		if str(n.name).begins_with("border_tree_"):
			trees += 1
	check(trees > 50, "a forest around the town (%d trees)" % trees)
	for c: Array in cells:
		var t: Vector2i = c[0]
		check(t.x < 0 or t.y < 0 or t.x >= 40 or t.y >= 40, "border tile %s is outside the grid" % t)
		if t.x >= 0 and t.y >= 0 and t.x < 40 and t.y < 40:
			break
	v.free()


func test_houses_mix_their_looks() -> void:
	var v := _view()
	var looks: Array = (ViewConfig.value("building_variants", {}) as Dictionary)["house"]
	var seen := {}
	for id: String in v.state.buildings:
		if str(v.state.buildings[id]["type"]) == "house":
			var n := _id(v.building_visual(id)).trim_suffix("_back")  # seen from behind when its door is hidden
			check(looks.has(n), "%s is one of the house looks (%s)" % [id, n])
			seen[n] = true
	check(seen.size() >= 3, "the town's houses are not all the same: %s" % [seen.keys()])
	v.free()


func test_fields_change_with_the_season() -> void:
	var v := _view()
	var g := v.ground()
	var field := Vector2i(1, 30)  # an f tile of town_e
	eq(str(cat.maps()["town_e"]["rows"][field.y])[field.x], "f", "the test tile is a field")
	var seen := {}
	for season: String in ["spring", "summer", "autumn", "winter"]:
		g.set_season(season)
		eq(g.season(), season, "the ground shows %s" % season)
		var t := g.texture_at(field)
		check(t != null and str(t.resource_path).ends_with("field_%s.png" % season), "%s: %s" % [season, t.resource_path if t else "null"])
		seen[t] = true
	eq(seen.size(), 4, "four looks")
	var grass := g.texture_at(Vector2i(0, 0))
	g.set_season("winter")
	eq(g.texture_at(Vector2i(0, 0)), grass, "other kinds do not change")
	v.free()


func test_the_view_follows_the_clock_season() -> void:
	var v := _view()
	var expected := Clock.season(int(v.state.clock["minute"]), cat.time)
	eq(v.ground().season(), expected, "the ground starts in the clock's season")
	v.state.clock["minute"] = int(v.state.clock["minute"]) + 1440 * int(cat.time["days_per_season"])
	v.sync(0.0)
	check(v.ground().season() != expected, "a season later the ground follows (%s)" % v.ground().season())
	v.free()
