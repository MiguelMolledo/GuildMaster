extends "res://tests/test_case.gd"
## H5 polish of the vertical slice (3 days playable without the console): the forge interior fits the 960×540 screen
## and no station name is covered by another thing of the room; the stone facade reads (stone rows over both front
## faces); the panels of the interior fit the screen (the upgrade panel grew past it); the HUD help overlay (F1, "?",
## its button, ESC) and the objective's "how to" line in ES and EN; the market says when it opens. Windowless.

const BLD := "bld_0001"
const HUGO := "chr_0001"
const SCREEN := Vector2(960, 540)

var cat := Catalog.load_from()


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _interior(sim: Sim, who: String = "", manage: bool = true) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = func(_o: Dictionary) -> void: pass
	v.setup(sim, BLD, who, manage)
	return v


func _csv() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3:
			out[row[0]] = [row[1], row[2]]
	return out


func test_forge_room_fits_the_screen() -> void:
	var v := _interior(_sim("forge_upgrade_works"))
	var k := v.kit()
	var s := k.size
	var wall := k.wall_height
	var left := v.world_to_screen(Iso.tile_to_world(Vector2i(0, s.y - 1)) + Vector2(-Iso.TILE_W / 2.0, -wall))
	var right := v.world_to_screen(Iso.tile_to_world(Vector2i(s.x - 1, 0)) + Vector2(Iso.TILE_W / 2.0, -wall))
	var top := v.world_to_screen(Iso.tile_to_world(Vector2i.ZERO) + Vector2(0, -Iso.TILE_H / 2.0 - wall))
	var bottom := v.world_to_screen(Iso.tile_to_world(s - Vector2i.ONE) + Vector2(0, Iso.TILE_H / 2.0))
	check(left.x >= 0.0 and right.x <= SCREEN.x, "the room fits across (left %s, right %s)" % [left, right])
	# below the title / works line of the HUD (≈ 85 px) and above the help line at the bottom (≈ 515 px)
	check(top.y >= 90.0 and bottom.y <= 510.0, "the room fits down, clear of the top and bottom texts (top %s, bottom %s)"
		% [top, bottom])
	# the building's panels open on the right from x ≈ 660: the room is centred left of them
	check(right.x <= 680.0, "the room leaves the right side to the panels (right %s)" % right)
	v.free()


## Stations and upgrade visuals each on their own tile of their floor, inside the room; and the stations' names stay
## readable over whatever stands in front of them (04g: they draw over the atrezo, the upgrades and the people).
func test_station_names_are_not_covered() -> void:
	var room: Node2D = InteriorBuilder.instantiate("forge")   # data/interiors/forge.json (04g 4.6.5.2)
	var d := InteriorDefs.def_of("forge")
	var things: Array = []   # [name, position on its floor, level]
	for m: Node in room.get_node("Stations").get_children():
		var lv := int(m.get_meta("level", 0))
		things.append([str(m.name), (m as Node2D).position - InteriorDefs.floor_offset(d, lv), lv])
	for u: Node in room.get_node("Upgrades").get_children():
		if str(u.name) in ["forge_anvil_2", "forge_furnace_2"] or u.get_child_count() == 0:
			continue   # decoration on the station itself
		var lv := int(u.get_meta("level", 0))
		things.append([str(u.name), (u as Node2D).position - InteriorDefs.floor_offset(d, lv), lv])
	var kit := room.get_node("Kit") as GreyboxKit
	var tiles := {}
	for t: Array in things:
		var tile := Iso.world_to_tile((t[1] as Vector2) + Vector2(0, -float(InteriorDefs.STEP_PX)) * 0.0)
		var key := "%d,%d,%d" % [int(t[2]), tile.x, tile.y]
		check(tile.x >= 0 and tile.y >= 0 and tile.x < kit.size.x and tile.y < kit.size.y, "%s inside the room" % t[0])
		check(not tiles.has(key), "%s shares its tile with %s" % [t[0], tiles.get(key, "")])
		tiles[key] = t[0]
	room.free()
	var sv := StationView.new()
	sv.setup("anvil", "Yunque", {})
	check(sv.get_child(sv.get_child_count() - 2) is Label and (sv.get_child(sv.get_child_count() - 2) as Label).z_index > 0,
		"the station's name draws over what stands in front of it")
	sv.free()


func test_stone_facade_covers_both_front_faces() -> void:
	var b: Node2D = (load("res://game/visuals/buildings/forge.tscn") as PackedScene).instantiate()
	var facade := b.get_node("Upgrades/upgrade_stone_facade") as Node2D
	check(not facade.visible, "hidden until the upgrade is done")
	var m := facade.get_node("Greybox") as GreyboxMasonry
	check(m != null, "the facade is a GreyboxMasonry")
	var f: Array = cat.buildings()["forge"]["footprint"]
	m.build()
	eq(m.get_child_count(), m.footprint.x + m.footprint.y, "one stone face per front edge tile")
	var right := 0
	for c: Node in m.get_children():
		if (c as MasonryFace).side == "right":
			right += 1
	eq(right, m.footprint.y, "the right face runs along the footprint's rows")
	eq([m.footprint.x, m.footprint.y], [int(f[0]), int(f[1])], "the facade's footprint is the forge's (data)")
	b.free()


func _fits(c: Control, name: String) -> void:
	var min_size := c.get_combined_minimum_size()
	var bottom := c.offset_top + maxf(min_size.y, c.offset_bottom - c.offset_top)
	check(bottom <= SCREEN.y, "%s fits the screen (bottom %.0f, min %s)" % [name, bottom, min_size])


func test_interior_panels_fit_the_screen() -> void:
	for sc: String in ["two_employees", "forge_upgrade_works"]:
		var v := _interior(_sim(sc), HUGO)
		v.show_upgrades(true)
		_fits(v.upgrade_panel(), sc + " upgrades")
		v.show_staff(true, "hire")
		_fits(v.staff_panel(), sc + " hire")
		v.show_staff(true, "staff")
		_fits(v.staff_panel(), sc + " staff")
		v.show_production(true)
		_fits(v.production_panel(), sc + " production")
		v.show_storage(true)
		_fits(v.storage_panel(), sc + " storage")
		v.free()


func test_help_and_objective_texts_exist() -> void:
	var rows := _csv()
	check(HelpPanel.LINES.size() >= 10, "the help has its lines")
	var keys: Array = ["help.title", "hud.help_more", "hud.help_button", "hud.help_button_tip", "objective_how.free",
		"ui.market.opens", "ui.market.opens_tomorrow"]
	for k: String in HelpPanel.LINES:
		keys.append(k.trim_prefix("#"))
	for k: String in HelpPanel.key_ids():
		keys.append("help.key." + k)
		keys.append("help.key.%s_do" % k)
	for o: Variant in cat.starts()["artisan_blacksmith"]["objectives"]:
		keys.append("objective_how." + str(o))
	for k: String in keys:
		check(rows.has(k), "text %s" % k)
		if rows.has(k):
			check(str(rows[k][0]) != "" and str(rows[k][1]) != "", "%s in EN and ES" % k)
	check(str(rows.get("help.panels_esc", ["", ""])[1]).contains("Objetivo"), "the help points at the objective panel")
	var hud := FileAccess.get_file_as_string("res://game/ui/hud.tscn")
	for n: String in ["HelpPanel", "HelpButton", "ObjectiveHint"]:
		check(hud.contains('[node name="%s"' % n), "the HUD has %s" % n)


func test_help_overlay_keys() -> void:
	var p: HelpPanel = (load("res://game/ui/help_panel.tscn") as PackedScene).instantiate()
	check(not p.visible, "hidden at the start")
	p.toggle()
	check(p.visible, "toggle opens it")
	eq((p.get_node("%HelpLines") as Node).get_child_count(), HelpPanel.LINES.size(), "one line each")
	var sheet := p.get_node("%Sheet") as Control
	check(sheet.get_combined_minimum_size().y <= 420.0 + 1.0, "fits its parchment (min %s)" % sheet.get_combined_minimum_size())
	var keys := 0
	for col: String in ["%KeysLeft", "%KeysRight"]:
		for c: Node in p.get_node(col).get_children():
			keys += 1 if c is HBoxContainer else 0
	eq(keys, HelpPanel.key_ids().size(), "one row per key of the map")
	p.toggle()
	check(not p.visible, "and closes it")
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	check(HelpPanel.is_help_key(f1), "F1")
	var q := InputEventKey.new()
	q.unicode = 63
	q.pressed = true
	check(HelpPanel.is_help_key(q), "?")
	var i := InputEventKey.new()
	i.keycode = KEY_I
	i.pressed = true
	check(not HelpPanel.is_help_key(i), "not I")
	f1.echo = true
	check(not HelpPanel.is_help_key(f1), "not a held key")
	p.free()


func test_market_says_when_it_opens() -> void:
	var sim := _sim("town_e_start")
	var day0 := Clock.day(int(sim.state.clock["minute"])) * Clock.MINUTES_PER_DAY
	var starts: Dictionary = cat.time["phase_starts"][Clock.season(day0, cat.time)]
	var first := 1 << 30
	for ph: Variant in cat.market.get("open_phases", []):
		first = mini(first, int(starts[str(ph)]))
	sim.state.clock["minute"] = day0 + 60   # 01:00, closed
	eq(SimQuery.market_opens_at(sim), day0 + first, "opens today at the first open phase")
	sim.state.clock["minute"] = day0 + 1430   # 23:50, closed
	var next_starts: Dictionary = cat.time["phase_starts"][Clock.season(day0 + 1440, cat.time)]
	var next_first := 1 << 30
	for ph: Variant in cat.market.get("open_phases", []):
		next_first = mini(next_first, int(next_starts[str(ph)]))
	eq(SimQuery.market_opens_at(sim), day0 + 1440 + next_first, "opens tomorrow")
	check(SimQuery.market_opens_text(sim) != "", "and says it")
