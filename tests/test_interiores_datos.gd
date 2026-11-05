extends "res://tests/test_case.gd"
## Interiors built from data (docs/gdd/04g_interiores.md 4.6.5.2-4.6.5.5): the builder keeps the structure the view
## needs (Kit, Stations, Upgrades, Props), and the stage walks people by doors and stairs, opens the walls of the room
## in focus, shows one floor, places the counter's customers with their bubble, sends the person selected to serve
## them, and fills the display with the products for sale. Windowless: the views are built by hand.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)


func _interior(sim: Sim, manage: bool = false) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, HUGO, manage)
	return v


func _stage(v: InteriorView) -> InteriorStage:
	return v.get_node_or_null("InteriorStage") as InteriorStage


func _hugo_in(sim: Sim) -> void:
	var ch: Dictionary = sim.state.characters[HUGO]
	ch["location"] = BLD
	ch["station"] = ""


func test_forge_is_built_from_its_data() -> void:
	var d := InteriorDefs.def_of("forge")
	check(not d.is_empty(), "data/interiors/forge.json is read")
	var room := InteriorBuilder.instantiate("forge")
	check(room.has_meta("interior_def"), "built from data, not from a scene")
	var kit := room.get_node("Kit") as GreyboxKit
	eq(kit.size, Vector2i(10, 8), "the Kit carries the grid size")
	eq(kit.door, Vector2i(0, 6), "and the street door")
	for z: String in ["furnace", "furnace_2", "anvil", "anvil_2", "counter", "storage"]:
		check(room.get_node_or_null("Stations/" + z) is Marker2D, "a marker for station %s" % z)
	# every interior visual of the forge's upgrade tree has its node (data/upgrades visual.interior_node)
	for id: Variant in cat.upgrade_tree("forge"):
		var uid := str((id as Dictionary).get("id", id)) if id is Dictionary else str(id)
		var vis: Variant = (cat.upgrade(uid).get("visual", {}) as Dictionary).get("interior_node")
		var node := str(vis) if vis != null else ""
		if node != "":
			check(room.get_node_or_null("Upgrades/" + node) != null, "Upgrades/%s for %s" % [node, uid])
	var walls: Array = room.get_meta("walls", [])
	check(walls.size() > 10, "walls between rooms and low front walls (%d)" % walls.size())
	check(walls.any(func(w: InteriorWall) -> bool: return w.kind == "door"), "with doors")
	check(room.get_node_or_null("Backdrops/0_workshop") != null, "a backdrop per room")
	room.free()


func test_station_markers_stand_on_their_tiles() -> void:
	var d := InteriorDefs.def_of("forge")
	var room := InteriorBuilder.instantiate("forge")
	var anvil: Dictionary = d["stations"]["anvil"]
	var t: Array = anvil["tile"]
	eq((room.get_node("Stations/anvil") as Node2D).position, Iso.tile_to_world(Vector2i(int(t[0]), int(t[1]))),
		"the anvil on its tile (flat floor)")
	var furnace: Dictionary = d["stations"]["furnace"]
	var ft: Array = furnace["tile"]
	eq((room.get_node("Stations/furnace") as Node2D).position,
		Iso.tile_to_world(Vector2i(int(ft[0]), int(ft[1]))) + Vector2(0, InteriorDefs.STEP_PX), "the hearth one step down, in its pit")
	room.free()


func test_people_walk_by_doors_and_stairs() -> void:
	var sim := _sim()
	_hugo_in(sim)
	var v := _interior(sim)
	var s := _stage(v)
	check(s != null, "the forge has its stage")
	var d := InteriorDefs.def_of("forge")
	var e: Array = d["entrance"]["tile"]
	var stand: Array = d["stations"]["furnace"]["stand"]
	var p := s.path(0, Vector2i(int(e[0]), int(e[1])), 0, Vector2i(int(stand[0]), int(stand[1])))
	check(not p.is_empty(), "a way from the street door to the hearth")
	check(p.any(func(x: Array) -> bool: return (x[1] as Vector2i) == Vector2i(2, 4)), "through the workshop's door")
	var up := s.path(0, Vector2i(int(e[0]), int(e[1])), 1, Vector2i(3, 1))
	check(not up.is_empty() and up.any(func(x: Array) -> bool: return int(x[0]) == 1), "and up the stairs to the kitchen")
	# Hugo, sent to the anvil, walks there (he is not just placed)
	sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	v.sync()
	s.tick(0.05)
	var a: Dictionary = d["stations"]["anvil"]
	var target := InteriorDefs.spot_world(d, 0, Vector2(float(a["tile"][0]) - 1.0, float(a["tile"][1])))
	check(v.view_of(HUGO).position.distance_to(target) > 4.0, "on his way after a frame")
	for i: int in 40:
		s.tick(0.1)
	eq(v.view_of(HUGO).position, target.round(), "at the anvil's spot after walking")
	v.free()


func test_walls_open_in_front_of_the_room_in_focus() -> void:
	var sim := _sim()
	var v := _interior(sim, true)
	var s := _stage(v)
	s.set_focus("workshop")
	var walls: Array = v.room().get_meta("walls", [])
	var front := walls.filter(func(w: InteriorWall) -> bool: return w.behind == "workshop" and w.level == 0)
	check(not front.is_empty(), "the workshop has walls in front of it")
	check(front.all(func(w: InteriorWall) -> bool: return w.faded), "they turn transparent while it is in focus")
	s.set_focus("storage")
	check(front.all(func(w: InteriorWall) -> bool: return not w.faded), "and whole again when the focus moves on")
	check(walls.filter(func(w: InteriorWall) -> bool: return w.kind == "low").all(func(w: InteriorWall) -> bool:
		return not w.faded), "the low front walls never fade")
	v.free()


func test_the_cellar_is_hidden_from_above() -> void:
	eq(InteriorStage.show_mode(0, 0), 2, "the floor shown, whole")
	eq(InteriorStage.show_mode(0, 1), 1, "the ground floor in shade under the upper one")
	eq(InteriorStage.show_mode(1, 0), 0, "the upper floor hidden from below")
	eq(InteriorStage.show_mode(-1, 0), 0, "the cellar hidden from above (under the ground)")
	eq(InteriorStage.show_mode(0, -1), 0, "and the ground floor hidden from the cellar")


func test_one_floor_is_shown_at_a_time() -> void:
	var sim := _sim()
	var v := _interior(sim, true)
	var s := _stage(v)
	var up := v.objects().get_node_or_null("Level1") as Node2D
	check(up != null, "the upper floor's things sort in their own layer")
	s.tick(0.0)
	check(not up.visible, "the upper floor is hidden while the ground floor is shown")
	s.show_level(1)
	check(up.visible, "shown when the upper floor is picked (wheel, keys or button)")
	eq(s.active, 1, "the floor shown")
	var shop := v.room().get_node("Backdrops/0_shop") as CanvasItem
	check(shop.modulate.r < 0.9, "the ground floor in shade below it")
	s.show_level(0)
	check(not up.visible, "hidden again")
	v.free()


func test_a_townsperson_walks_in_to_the_counter() -> void:
	var sim := _sim()
	_hugo_in(sim)
	var st := sim.state
	check(Inventory.add(st.buildings[BLD]["inventory"], cat, "sword", 1, 2), "two swords for sale")
	var who := ""
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: Variant in ids:
		if TownLife.is_townsperson(st, str(id)) and st.characters[id].get("town") is Dictionary:
			who = str(id)
			break
	check(who != "", "a townsperson")
	st.characters[who]["town"]["customer"] = BLD
	st.characters[who]["town"]["customer_since"] = int(st.clock["minute"])
	st.characters[who]["location"] = BLD
	var v := _interior(sim)
	var s := _stage(v)
	v.sync()
	s.tick(0.05)
	var d := InteriorDefs.def_of("forge")
	var spot: Array = d["customers"]["counter"][0]["tile"]
	var at_spot := InteriorDefs.spot_world(d, 0, Vector2(float(spot[0]), float(spot[1]))).round()
	var door: Array = d["entrance"]["tile"]
	check(v.view_of(who).position.distance_to(at_spot) > 32.0, "a townsperson comes in by the street door, walking")
	check(v.view_of(who).position.distance_to(InteriorDefs.spot_world(d, 0, Vector2(float(door[0]), float(door[1])))) < 16.0,
		"(it starts at the door)")
	for i: int in 60:
		s.tick(0.1)
	eq(v.view_of(who).position, at_spot, "and stands at the first counter spot")
	var b := v.view_of(who).get_node_or_null("OrderBubble") as OrderBubble
	check(b != null and b.item == "sword", "its bubble shows what it wants (the sword)")
	check(b != null and b.patience > 0.9, "with its patience full")
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	check(s.attend_at(v.world_to_screen(v.view_of(who).position + Vector2(0, -20))), "the click is the customer's")
	eq(got.size(), 1, "one order")
	if got.size() == 1:
		eq(str(got[0]["type"]) + "/" + str(got[0]["zone"]), "go_to_station/counter", "Hugo goes to serve")
	v.free()


func test_a_countryside_customer_appears_and_fades_away() -> void:
	var sim := _sim()
	_hugo_in(sim)
	var st := sim.state
	var now := int(st.clock["minute"])
	var rec := {"id": "cmc_%s_1" % BLD, "item": "hammer", "since": now, "served_at": -1}
	st.town["clientele"] = {BLD: {"next_at": -1, "seq": 1, "waiting": [rec]}}
	var v := _interior(sim)
	var s := _stage(v)
	v.sync()
	s.tick(0.05)
	var fig: CharacterView = null
	for n: Node in v.objects().get_children():
		if n is CharacterView and (n as CharacterView).char_id == str(rec["id"]):
			fig = n
	check(fig != null, "a figure for the countryside customer (it is not a character of the town)")
	if fig == null:
		v.free()
		return
	var d := InteriorDefs.def_of("forge")
	var spot: Array = d["customers"]["counter"][0]["tile"]
	eq(fig.position, InteriorDefs.spot_world(d, 0, Vector2(float(spot[0]), float(spot[1]))).round(), "right at its spot")
	check(fig.modulate.a < 1.0, "fading in")
	var b := fig.get_node_or_null("OrderBubble") as OrderBubble
	check(b != null and b.item == "hammer", "wanting what it came for (a hammer)")
	s.tick(0.5)
	check(fig.modulate.a >= 1.0, "then fully shown")
	var got: Array = []
	v.order_sink = func(o: Dictionary) -> void: got.append(o)
	check(s.attend_at(v.world_to_screen(fig.position + Vector2(0, -20))), "a click on it serves it too")
	eq(got.size(), 1, "Hugo goes to the counter")
	(st.town["clientele"][BLD]["waiting"] as Array).clear()   # it bought, or left
	s.tick(0.1)
	check(is_instance_valid(fig) and fig.modulate.a < 1.0, "fading away where it stood")
	s.tick(0.5)
	check(not is_instance_valid(fig) or fig.is_queued_for_deletion(), "and gone")
	v.free()


func test_the_display_shows_the_products_for_sale() -> void:
	var sim := _sim()
	var st := sim.state
	check(Inventory.add(st.buildings[BLD]["inventory"], cat, "sword", 1, 2), "two swords for sale")
	var v := _interior(sim, true)
	var s := _stage(v)
	s.tick(0.0)
	var wares := 0
	for n: Node in v.objects().get_children():
		if n.has_meta("display"):
			for c: Node in n.get_children():
				if str(c.name).begins_with("Ware"):
					wares += 1
	eq(wares, 2, "the two swords on the display shelf")
	v.free()


func test_every_interior_from_data_has_its_stations_and_upgrade_nodes() -> void:
	for f: String in DirAccess.get_files_at(InteriorDefs.DIR):
		if not f.ends_with(".json") or f.begins_with("_") or f == "lights.json":
			continue
		var type := f.get_basename()
		var room := InteriorBuilder.instantiate(type)
		var b: Dictionary = cat.buildings().get(type, {})
		for z: Dictionary in b.get("zones", []):
			check(room.get_node_or_null("Stations/" + str(z["id"])) is Marker2D, "%s: station %s" % [type, z["id"]])
		var tree := str(b.get("upgrade_tree", ""))
		if tree != "":
			for id: Variant in cat.upgrade_tree(tree):
				var uid := str((id as Dictionary).get("id", id)) if id is Dictionary else str(id)
				var vis: Variant = (cat.upgrade(uid).get("visual", {}) as Dictionary).get("interior_node")
				if vis != null and str(vis) != "":
					check(room.get_node_or_null("Upgrades/" + str(vis)) != null, "%s: Upgrades/%s" % [type, vis])
		check(room.get_node("Backdrops").get_children().all(func(h: Node) -> bool: return h.get_node_or_null("Painted") != null),
			"%s: every room painted" % type)
		room.free()
