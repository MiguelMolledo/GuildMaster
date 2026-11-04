extends "res://tests/test_case.gd"
## The portrait's picture frame (PortraitFrame, assets/art/ui/portrait_frame/): a carved frame in two sizes (38 for the
## portrait of 32, 76 for the ×2 one), gilded when active, wood when controllable, dark otherwise; cut in 9 with the
## carved corner as its margin (never stretched); the frame does not cover the face (only its corners enter the
## portrait's corners) nor crops the portrait; the family's colours on the plaque of its foot; the big cards (wedding,
## succession, the tree's sheet, the new game) use the big frame instead of scaling the small one.

const SCENE := "res://game/ui/portrait_frame.tscn"


func _sim() -> Sim:
	var r := NewGame.from_scenario("founder_old", 1)
	check(bool(r["ok"]), "founder_old loads")
	return Sim.new(r["state"], Catalog.load_from())


func _frame(big: bool) -> PortraitFrame:
	var f := (load(SCENE) as PackedScene).instantiate() as PortraitFrame
	f.big = big
	return f


func test_sizes_and_finishes() -> void:
	var sim := _sim()
	var hero := str(sim.state.characters.keys()[0])
	for big: bool in [false, true]:
		var f := _frame(big)
		f.show_character(sim.state, hero, {"controlled": true})
		var side := 76.0 if big else 38.0
		var band := 6.0 if big else 3.0
		eq(f.custom_minimum_size, Vector2(side, side), "big=%s: the frame's size" % big)
		var holder := f.get_node("%Holder") as Node2D
		eq(holder.position, Vector2(band, band), "big=%s: the portrait inside the band" % big)
		eq(holder.scale, Vector2(2, 2) if big else Vector2.ONE, "big=%s: the portrait at a whole scale" % big)
		var back := f.get_node("%Back") as ColorRect
		eq(back.size, Vector2(64, 64) if big else Vector2(32, 32), "big=%s: the whole portrait shows (no crop)" % big)
		for flags: Dictionary in [{"active": true, "controlled": true}, {"controlled": true}, {}]:
			f.show_character(sim.state, hero, flags)
			var want := "gold" if flags.get("active", false) else ("wood" if flags.get("controlled", false) else "dark")
			eq(f.finish, want, "big=%s %s: %s" % [big, flags, want])
			var sb := (f.get_node("%Border") as Panel).get_theme_stylebox("panel") as StyleBoxTexture
			check(sb != null and sb.texture.resource_path.ends_with("frame_%s_%s.png" % ["l" if big else "s", want]),
				"big=%s: the %s picture frame" % [big, want])
			if sb != null:
				eq(sb.texture.get_size(), Vector2(side, side), "the frame's art is drawn at its size (no scaling)")
				eq(int(sb.texture_margin_left), 9 if big else 5, "the carved corner is the 9-slice margin")
				check(not sb.draw_center, "the centre is not drawn")
		f.free()


## The frame's art: opaque all along its band, transparent inside except the carved corners (a small square in each
## corner of the portrait, away from the face); the plaque sits on the foot, below the face.
func test_frame_does_not_cover_the_face() -> void:
	for s: String in ["s", "l"]:
		var z: Dictionary = PortraitFrame.SIZES[s]
		var side := int(z["side"])
		var band := int(z["band"])
		var corner := int(z["corner"])
		for fin: String in ["gold", "wood", "dark"]:
			var img := Image.load_from_file(ProjectSettings.globalize_path(PortraitFrame.DIR + "frame_%s_%s.png" % [s,
				fin]))
			check(img != null and img.get_width() == side, "%s_%s: the art exists at %d" % [s, fin, side])
			if img == null:
				continue
			var band_ok := true
			var inside_ok := true
			for x: int in side:
				for y: int in side:
					var d := mini(mini(x, y), mini(side - 1 - x, side - 1 - y))
					var a := img.get_pixel(x, y).a
					var in_corner := (x < corner or x >= side - corner) and (y < corner or y >= side - corner)
					if d < band and a < 0.5:
						band_ok = false
					if d >= band and a > 0.5 and not in_corner:
						inside_ok = false
			check(band_ok, "%s_%s: the band is solid" % [s, fin])
			check(inside_ok, "%s_%s: nothing of the frame over the portrait but its corners" % [s, fin])
		var pr: Rect2 = z["plaque"]
		var inner := float(side - 2 * band)
		check(pr.position.y >= band + inner * 0.8, "%s: the plaque is on the foot, below the face (y %d)" % [s,
			int(pr.position.y)])
		check(pr.end.y <= side, "%s: the plaque stays inside the frame" % s)
		eq(pr.position.x + pr.size.x / 2.0, side / 2.0, "%s: the plaque is centred" % s)


func test_family_colours_on_the_plaque() -> void:
	var sim := _sim()
	var hero := str(sim.state.characters.keys()[0])
	var id := Identity.of(sim.state, hero)
	for big: bool in [false, true]:
		var f := _frame(big)
		f.show_character(sim.state, hero, {})
		eq((f.get_node("%PlaqueTop") as ColorRect).color, id["primary"], "big=%s: the family's primary" % big)
		eq((f.get_node("%PlaqueLow") as ColorRect).color, id["secondary"], "big=%s: and its secondary" % big)
		check((f.get_node("%PlaqueTop") as ColorRect).size.y > (f.get_node("%PlaqueLow") as ColorRect).size.y,
			"big=%s: primary over a thinner band of secondary" % big)
		f.free()


func test_big_cards_use_the_big_frame() -> void:
	var sim := _sim()
	var st := sim.state
	var fam := SimQuery.player_family(st)
	var hero := SimQuery.family_actor(st, fam)
	var other := ""
	for c: String in st.characters:
		if str(st.characters[c].get("family", "")) != fam:
			other = c
			break
	var wc := (load("res://game/ui/wedding_card.tscn") as PackedScene).instantiate() as WeddingCard
	var d := wc.data_for(sim, {"type": "wedding", "character": hero, "spouse": other, "family": fam,
		"from_family": str(st.characters[other].get("family", ""))}, [])
	var people: Dictionary = (d["blocks"] as Array)[0]
	for k: String in ["left_node", "right_node"]:
		var f := people.get(k) as PortraitFrame
		check(f != null and f.big and f.scale == Vector2.ONE, "wedding %s: the big frame, not a scaled one" % k)
		if f != null:
			f.free()
	wc.free()
	var ng := (load("res://game/ui/new_game_screen.tscn") as PackedScene).instantiate()
	var pf := ng.get_node_or_null("%PortraitFrame") as PortraitFrame
	check(pf != null and pf.big, "the new game's preview in the big picture frame")
	ng.free()
