extends "res://tests/test_case.gd"
## The town's ground painted by the shader (data/view.json "ground_shader", game/world/ground.gdshader, rama
## ciudad-2d): world materials with no tile grid, ragged borders, the river's own bank, loose detail; the ruin and the
## free lot with art; the apothecary's stall; the roof variants of the filler houses.

var cat := Catalog.load_from()


func _view(scenario: String = "town_e_start") -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario(scenario)["state"], cat)
	return v


func _id(n: Node) -> String:
	return str(n.scene_file_path).get_file().get_basename() if n != null else ""


func test_the_ground_is_painted_by_the_shader() -> void:
	var v := _view()
	var g := v.ground()
	check(g.shader_on(), "the shader quad paints the ground")
	var quad := g.get_node_or_null("ShaderGround") as Polygon2D
	check(quad != null and quad.show_behind_parent, "the quad sits behind the ground layer (edges and decals on top)")
	var mat := quad.material as ShaderMaterial
	var kmap := mat.get_shader_parameter("kind_map") as ImageTexture
	var size: Vector2i = mat.get_shader_parameter("map_size")
	var ring := int((ViewConfig.value("map_border", {}) as Dictionary).get("tiles", 0))
	eq(size, Vector2i(40 + 2 * ring, 40 + 2 * ring), "one texel per tile of the map and its border ring")
	eq(kmap.get_width(), size.x, "the kind map is that size")
	var infos: PackedVector4Array = mat.get_shader_parameter("mat_info")
	var names: Array = (ViewConfig.value("ground_shader", {}) as Dictionary)["materials"].keys()
	var street := names.find("street")
	var plaza := names.find("plaza")
	var water := names.find("water")
	check(infos[street].x == 0.0 and infos[plaza].x == 0.0, "street and plaza are world materials (no tile grid)")
	check(infos[plaza].y > infos[street].y and infos[street].w > 0.0, "the plaza wins over the street; the street has a curb")
	var extras: PackedVector4Array = mat.get_shader_parameter("mat_extra")
	check(extras[water].y == 1.0 and infos[water].z == 0.0, "the river is soft water with its own bank")
	# the street tile at (7, 10) and the plaza tile at (17, 17) carry their material index in the kind map
	var img := kmap.get_image()
	eq(int(round(img.get_pixel(7 + ring, 10 + ring).r * 255.0)), street, "a street tile maps to the street material")
	eq(int(round(img.get_pixel(17 + ring, 17 + ring).r * 255.0)), plaza, "a plaza tile maps to the plaza material")
	check(g.decal_count() > 10, "loose detail on the streets, the plaza and the dirt (%d)" % g.decal_count())
	v.free()


func test_shader_off_falls_back_to_the_tiles() -> void:
	var v := _view()
	var g := v.ground()
	g.get_node("ShaderGround").visible = false
	check(not g.shader_on(), "with the quad hidden the per-tile drawing is back")
	check(g.texture_at(Vector2i(7, 10)) != null, "the street tile still has its texture for the fallback")
	v.free()


func test_ruin_and_lot_have_art() -> void:
	var v := _view()
	var wall := v.prop_at(Vector2i(18, 9))
	eq(_id(wall), "ruin_wall", "the ruin's edge tile is a broken wall")
	var sp := wall.get_node_or_null("Sprite") as Sprite2D
	check(sp != null and sp.hframes == 3, "the broken wall is a strip of 3 heights")
	eq(wall.scale, Vector2.ONE, "never scaled: one pixel density")
	for scene: String in ["ruin_rubble", "plot_ground", "plot_stake"]:
		var n := VisualPaths.instantiate("props", scene)
		check(n.get_node_or_null("Sprite") != null and n.get_node_or_null("Greybox") == null,
			"%s has its sprite (no greybox)" % scene)
		n.free()
	v.free()


func test_apothecary_stall_and_roof_variants() -> void:
	var st := VisualPaths.instantiate("props", "stall_apothecary")
	check(st != null and st.get_node_or_null("Sprite") != null, "the apothecary's stall has its own sprite")
	st.free()
	var houses: Array = (ViewConfig.value("filler", {}) as Dictionary)["houses"]
	for v: String in ["g", "h", "i", "j"]:
		check(houses.has("lot_house_" + v), "lot_house_%s is a filler house" % v)
		for suffix: String in ["", "_back"]:
			var n := VisualPaths.instantiate("props", "lot_house_%s%s" % [v, suffix])
			var sp := n.get_node("Sprite") as Sprite2D
			check(sp.texture.resource_path.ends_with("escala_b/house_%s%s.png" % [v, suffix]),
				"lot_house_%s%s draws its own roof" % [v, suffix])
			n.free()


func test_block_houses_of_the_organic_towns_have_art() -> void:
	var v := _view("region_port_start")
	var dressed := 0
	var mirrored := 0
	var blocks := 0
	for c: Node in v.objects().get_children():
		if _id(c) != "house_block":
			continue
		blocks += 1
		var sp := c.get_node_or_null("Sprite") as Sprite2D
		if sp == null:
			continue
		dressed += 1
		if sp.flip_h:
			mirrored += 1
		check(not (c.get_node("Greybox") as Node2D).visible, "the greybox block hides under its house")
		check(sp.texture.resource_path.contains("/buildings/block/house_"), "a block house of assets/art/buildings/block")
	check(blocks > 0 and dressed == blocks, "every house block of region_port has its house (%d of %d)" % [dressed, blocks])
	check(mirrored > 0, "the lots turned the other way take the mirrored sprite (%d)" % mirrored)
	v.free()
