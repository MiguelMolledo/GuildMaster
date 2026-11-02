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
	# the 6×4 block north of the plaza (cols 17-22, rows 8-11): two 3×4 lots, one house each
	var west := v.prop_at(Vector2i(17, 8))
	var east := v.prop_at(Vector2i(20, 8))
	check(houses.has(_id(west)) and houses.has(_id(east)), "two houses on the 6×4 block: %s, %s" % [_id(west), _id(east)])
	check(west != east, "one visual per lot")
	eq(v.prop_at(Vector2i(19, 11)), west, "every tile of a lot points to its house")
	var centre := (Iso.tile_to_world(Vector2i(17, 8)) + Iso.tile_to_world(Vector2i(19, 11))) / 2.0
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
	for t: Vector2i in [Vector2i(17, 8), Vector2i(12, 8), Vector2i(9, 11), Vector2i(28, 21), Vector2i(17, 26)]:
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
	eq(UiIcons.item_rect("steel"), null, "no icon yet: no rect")
