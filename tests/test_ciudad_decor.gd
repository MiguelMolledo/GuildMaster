extends "res://tests/test_case.gd"
## The town builder's dressing (data/maps "decor", tools/city/ciudad.py, docs/protocolos/generar-ciudad.md) as the
## game draws it (WorldView._add_decor, _door_facing): filler houses with their door to the street (mirrored or seen
## from behind), lanterns, props and fences; the sim never reads it.

var cat := Catalog.load_from()


func _view(scenario: String = "town_e_start") -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario(scenario)["state"], cat)
	return v


func _id(n: Node) -> String:
	return str(n.scene_file_path).get_file().get_basename() if n != null else ""


func _count(v: WorldView, id: String) -> int:
	var n := 0
	for c: Node in v.objects().get_children():
		if _id(c) == id:
			n += 1
	return n


func test_every_decor_house_is_drawn_with_its_look_and_mirror() -> void:
	var v := _view()
	var items: Array = cat.maps()["town_e"]["decor"]["items"]
	var houses := 0
	for it: Dictionary in items:
		if str(it["kind"]) != "house" or str(it.get("site", "")) != "":
			continue  # the lots of a site are drawn only without its building (next tests)
		houses += 1
		var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
		var p := v.prop_at(t)
		eq(_id(p), str(it["id"]), "house at %s" % t)
		eq(p.scale.x, -1.0 if bool(it.get("flip", false)) else 1.0, "mirror of the house at %s" % t)
	check(houses >= 2, "town_e has decor houses (%d)" % houses)
	v.free()


func test_lanterns_fences_and_props_are_placed() -> void:
	var v := _view()
	var want := {}
	for it: Dictionary in cat.maps()["town_e"]["decor"]["items"]:
		if str(it["kind"]) in ["lantern", "fence", "prop"]:
			want[str(it["id"])] = int(want.get(str(it["id"]), 0)) + 1
	check(int(want.get("lantern", 0)) >= 8, "lanterns along the streets (%d)" % int(want.get("lantern", 0)))
	check(int(want.get("fence", 0)) >= 20, "fences round the fields (%d)" % int(want.get("fence", 0)))
	for id: String in ["lantern", "fence"]:
		eq(_count(v, id), int(want[id]), "every %s of the decor is drawn" % id)
	v.free()


func test_a_house_whose_door_is_hidden_is_seen_from_behind() -> void:
	var v := _view()
	var ids := {}
	for id: String in v.state.buildings:
		var b: Dictionary = v.state.buildings[id]
		if str(b["type"]) == "house" and b["origin"] == [25, 8]:
			ids["ne"] = id  # house_ne: door (26, 7) on its -row side; its look house_ochre has a back view
		if str(b["type"]) == "forge" and b["origin"] == [25, 20]:
			ids["forge"] = id
	eq(_id(v.building_visual(str(ids["ne"]))), "house_ochre_back", "house_ne is drawn from behind")
	# the player's forge: door (26, 19) on its NE face; the forge draws its door on SE, so its back (NW) mirrored
	eq(_id(v.building_visual(str(ids["forge"]))), "forge_back", "the forge is drawn from behind")
	eq(v.building_visual(str(ids["forge"])).scale.x, -1.0, "mirrored: its back view's door is on NW")
	v.free()


func test_door_on_the_other_visible_face_mirrors_the_building() -> void:
	var v := _view()
	var b := {"id": "bld_test", "type": "house", "origin": [10, 10], "footprint": [3, 3], "door": [13, 11]}
	var f: Dictionary = v._door_facing(b, "house")
	eq(f, {"scene": "house", "flip": true}, "door to +col: the house (door drawn on the +row face) mirrored")
	b["door"] = [11, 13]
	eq(v._door_facing(b, "house"), {"scene": "house", "flip": false}, "door to +row: as drawn")
	b["door"] = [9, 11]
	eq(v._door_facing(b, "house_slate"), {"scene": "house_slate_back", "flip": true}, "door to -col: back view, mirrored")
	b["door"] = [13, 11]
	eq(v._door_facing(b, "tailor_shop"), {"scene": "tailor_shop", "flip": false}, "the tailor's door is drawn on +col")
	b["door"] = [11, 13]
	eq(v._door_facing(b, "tailor_shop"), {"scene": "tailor_shop", "flip": true},
		"the fal tailor's sign has no text: mirrored for a door on SW (its Door marker: mirror = true)")
	b["door"] = [11, 9]
	eq(v._door_facing(b, "tailor_shop"), {"scene": "tailor_shop_back", "flip": true},
		"door on NE: its back view (door on NW) mirrored")
	v.free()


func test_a_lot_with_a_building_of_this_game_is_skipped() -> void:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	var st: WorldState = NewGame.from_scenario("town_e_start")["state"]
	v.setup(st, cat)
	var filler := {Vector2i(17, 9): true}
	var n := v._add_decor({"items": [{"kind": "house", "id": "lot_house_a", "at": [17, 9], "size": [3, 3]}]}, filler, {})
	eq(n, 0, "a lot whose tiles are not all free filler is not drawn")
	eq(filler.size(), 1, "and its tiles stay for the old filler")
	v.free()


func test_a_site_without_its_building_gets_its_own_dressing() -> void:
	# town_e_start (the sandbox) leaves the carpentry, the masonry and the tailor's sites empty: their footprints take
	# the decor lots made for them ("site"), not the old random filler, and their barrels and crates stay away
	var v := _view()
	var items: Array = cat.maps()["town_e"]["decor"]["items"]
	var lots := 0
	for it: Dictionary in items:
		if str(it.get("site", "")) != "workshop_carpentry":
			continue
		var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
		if str(it["kind"]) in ["house", "yard"]:
			lots += 1
			eq(_id(v.prop_at(t)), str(it["id"]), "the empty carpentry site at %s takes its decor lot" % t)
		elif str(it["kind"]) == "prop":
			var off: Array = it.get("off", [0, 0])
			var where := Iso.tile_to_world(t) + Vector2(float(off[0]), float(off[1]))
			for c: Node in v.objects().get_children():
				if _id(c) == str(it["id"]) and (c as Node2D).position + VisualPaths.feet(c as Node2D) == where:
					check(false, "the carpentry's %s at %s is not drawn without the carpentry" % [it["id"], t])
	check(lots >= 2, "the carpentry site has its own lots (%d)" % lots)
	v.free()


func test_the_rival_of_the_same_trade_takes_the_forge_plot_cleanly() -> void:
	# H12 1b: in the carpenter's game rival_carpentry stands on player_forge's plot (25, 20): the plot's reserve
	# lots are not drawn over it, nor the forge's barrels and crates; the carpentry draws where its door is
	for start: String in ["artisan_carpenter", "artisan_mason", "artisan_tailor"]:
		var r := NewGame.from_start(cat, start, "normal", {}, 1)
		check(bool(r["ok"]), "%s starts" % start)
		if not r["ok"]:
			continue
		var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
		v.setup(r["state"], cat)
		var on_plot := ""
		for id: String in v.state.buildings:
			var o: Array = v.state.buildings[id]["origin"]
			if int(o[0]) == 25 and int(o[1]) == 20:
				on_plot = id
		check(on_plot != "", "%s: a building on the forge's plot" % start)
		var footprint: Array = v.state.buildings.get(on_plot, {}).get("footprint", [3, 4])
		for dr: int in int(footprint[1]):
			for dc: int in int(footprint[0]):
				eq(v.prop_at(Vector2i(25 + dc, 20 + dr)), null, "%s: no filler on the rival's tile %s" % [start,
					Vector2i(25 + dc, 20 + dr)])
		for it: Dictionary in cat.maps()["town_e"]["decor"]["items"]:
			if str(it.get("site", "")) == "player_forge" and str(it["kind"]) == "prop":
				var t := Vector2i(int(it["at"][0]), int(it["at"][1]))
				for c: Node in v.objects().get_children():
					check(not (_id(c) == str(it["id"]) and Iso.world_to_tile((c as Node2D).position + VisualPaths.feet(c as Node2D)) == t),
						"%s: the forge's %s is not drawn" % [start, it["id"]])
		v.free()


func test_fal_facades_show_works_and_damage() -> void:
	# the fal facades (tools/city/enchufar_fachadas.py): the Sprite takes LookConstruction while under upgrade works
	# and LookDamaged while damaged, its own texture otherwise
	var v := _view()
	var forge := ""
	for id: String in v.state.buildings:
		if str(v.state.buildings[id]["type"]) == "forge" and v.state.buildings[id]["origin"] == [25, 20]:
			forge = id
	var vis := v.building_visual(forge)
	var spr := vis.get_node("Sprite") as Sprite2D
	var normal := spr.texture
	check(vis.get_node_or_null("LookConstruction") != null and vis.get_node_or_null("LookDamaged") != null,
		"the forge's scene has its two states")
	v.state.buildings[forge]["state"] = "damaged"
	v.sync(0.0)
	eq(spr.texture, (vis.get_node("LookDamaged") as Sprite2D).texture, "damaged: the damaged facade")
	v.state.buildings[forge]["state"] = "normal"
	v.state.buildings[forge]["upgrade_work"] = {"upgrade": "x", "actor": "", "start": 0, "end": 60}
	v.sync(0.0)
	eq(spr.texture, (vis.get_node("LookConstruction") as Sprite2D).texture, "under works: the works facade")
	v.state.buildings[forge]["upgrade_work"] = null
	v.sync(0.0)
	eq(spr.texture, normal, "back to normal")
	v.free()


func test_the_town_hall_is_seen_from_behind_when_its_door_is_hidden() -> void:
	# town_e's town hall is served from (20, 25), on its NE (hidden) face: the back view
	var v := _view()
	var th: Node = null
	for c: Node in v.objects().get_children():
		if str(c.name) == "town_hall_visual":
			th = c
	check(th != null, "the town hall is drawn")
	if th != null:
		eq(_id(th), "town_hall_back", "seen from behind")
	v.free()
