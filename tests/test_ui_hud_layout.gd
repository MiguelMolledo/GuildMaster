extends "res://tests/test_case.gd"
## The HUD's zones and rules (docs/ui/01_hud.md §4, §5, §9, §13): the fixed zones do not overlap at 960×540 (nor on a
## wider window), the scene puts each zone where HudLayout says, one management panel at a time (the interior's
## too), the keys of the input map, the notices by gravity (4 urgent → 3 shown), the column folds before overlapping,
## the camera reveals what a panel covers, the interior's bar sits in zone 6 and the room is centred in the free view.
## The HUD itself needs the autoloads: ESC's order, the pause menu request and the live notices are checked by
## --smoke-script=hud (game/smoke/smoke_hud.gd).

const BASE := Vector2(960, 540)

var cat := Catalog.load_from()


## The rect of `c` laid out on a 960×540 parent from its anchors and offsets (no tree needed).
func _rect(c: Control, parent: Vector2 = BASE) -> Rect2:
	var p := Vector2(c.anchor_left * parent.x + c.offset_left, c.anchor_top * parent.y + c.offset_top)
	var e := Vector2(c.anchor_right * parent.x + c.offset_right, c.anchor_bottom * parent.y + c.offset_bottom)
	return Rect2(p, e - p)


## The nodes of a .tscn as {path: {prop: value}} (the HUD's script needs the autoloads, so the scene is read as text).
func _scene_nodes(path: String) -> Dictionary:
	var out := {}
	var cur := ""
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("[node "):
			var name := line.get_slice('name="', 1).get_slice('"', 0)
			var parent := line.get_slice('parent="', 1).get_slice('"', 0) if line.contains('parent="') else ""
			cur = name if parent == "" else (name if parent == "." else parent + "/" + name)
			out[cur] = {"_parent": parent}
		elif line.begins_with("["):
			cur = ""
		elif cur != "" and line.contains(" = "):
			out[cur][line.get_slice(" = ", 0)] = line.get_slice(" = ", 1)
	return out


func _scene_rect(props: Dictionary, parent: Vector2 = BASE) -> Rect2:
	var f := func(k: String) -> float: return float(str(props.get(k, "0")))
	var p := Vector2(f.call("anchor_left") * parent.x + f.call("offset_left"), f.call("anchor_top") * parent.y + f.call("offset_top"))
	var e := Vector2(f.call("anchor_right") * parent.x + f.call("offset_right"),
		f.call("anchor_bottom") * parent.y + f.call("offset_bottom"))
	return Rect2(p, e - p)


func test_fixed_zones_do_not_overlap() -> void:
	for size: Vector2 in [BASE, Vector2(1280, 720), Vector2(1024, 600), Vector2(960, 600)]:
		var z := HudLayout.zones(size)
		eq(HudLayout.overlaps(z), [], "no two fixed zones overlap at %s" % size)
		for k: String in HudLayout.FIXED:
			check(Rect2(Vector2.ZERO, size).encloses(z[k]), "%s inside the screen at %s" % [k, size])
	var z0 := HudLayout.zones()
	eq(z0["manage"], Rect2(600, 58, 356, 430), "zone 5 as in the document")
	eq(z0["selection"], Rect2(244, 492, 472, 44), "zone 6 as in the document")
	check(not (z0["manage"] as Rect2).intersects(z0["selection"]), "the book (5) never covers the building (6): §13")
	eq(HudLayout.view_rect(), HudLayout.VIEW, "the free view")
	eq(HudLayout.view_center(), Vector2(420, 273), "its centre")
	eq(HudLayout.big_modal(), Rect2(24, 58, 912, 440), "the big modal under the top bar")


func test_scene_puts_each_zone_in_its_rect() -> void:
	var n := _scene_nodes("res://game/ui/hud.tscn")
	var names := {"card": "Root/Card", "status": "Root/StatusBar", "clock": "Root/ClockPanel", "column": "Root/Column",
		"manage": "Root/ManageZone", "selection": "Root/SelectionBar", "notices": "Root/NoticePopups"}
	for k: String in names:
		check(n.has(names[k]), "%s exists" % names[k])
		eq(_scene_rect(n.get(names[k], {})), HudLayout.ZONES[k], "%s in its zone" % k)
	eq(_scene_rect(n["Root/ModalZone"]), HudLayout.big_modal(), "the big modals")
	check(_scene_rect(n["Root/PausedTag"]).position.y >= (HudLayout.ZONES["status"] as Rect2).end.y,
		"«EN PAUSA» hangs under the status bar")
	check(not n.has("Root/HelpLabel"), "the help line of the bottom edge is gone")
	for p: String in ["MarketPanel", "BoardPanel", "LedgerPanel", "NpcPanel", "CourtshipPanel", "TownHallPanel",
			"KinAiPanel", "CharacterPanel"]:
		check(n.has("Root/ManageZone/" + p), "%s opens in zone 5" % p)
	for p: String in ["FamilyTreePanel", "OfficesPanel", "TrialPanel"]:
		check(n.has("Root/ModalZone/" + p), "%s is a big modal" % p)
	check(n.has("Root/Column/MicroeventCard"), "the cards go in the column (_social.md)")
	check(n.has("Root/Card/HBox/GroupBar"), "the group's portraits in the card")
	check(str(n["Root"].get("theme", "")).contains("3_theme"), "the theme at the HUD's root")


func test_one_management_panel_at_a_time() -> void:
	var ledger: Control = (load("res://game/ui/ledger_panel.tscn") as PackedScene).instantiate()
	var market: Control = (load("res://game/ui/market_panel.tscn") as PackedScene).instantiate()
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	var members: Array = [ledger, market, v.production_panel(), v.storage_panel()]
	ledger.visible = true
	market.visible = true
	eq(ManageSlot.close_others(market, members), [ledger], "opening the market closes the book")
	check(market.visible and not ledger.visible, "only the market is open")
	v.production_panel().visible = true
	ManageSlot.close_others(v.production_panel(), members)
	check(not market.visible, "the interior's production closes the HUD's panel (one slot for both)")
	for p: Control in [ledger, market]:
		p.free()
	v.free()


func test_keys_of_the_input_map() -> void:
	HudKeys.ensure()
	for a: String in HudKeys.KEYS:
		check(InputMap.has_action(a), "action %s" % a)
	var one := InputEventKey.new()
	one.physical_keycode = KEY_1
	one.pressed = true
	var shift_one := one.duplicate() as InputEventKey
	shift_one.shift_pressed = true
	check(HudKeys.pressed(one, "group_1") and not HudKeys.pressed(one, "speed_1"), "1 picks the group, not the speed")
	check(HudKeys.pressed(shift_one, "speed_1") and not HudKeys.pressed(shift_one, "group_1"), "Shift+1 is speed ×1")
	for pair: Array in [[KEY_B, "build_mode"], [KEY_P, "panel_production"], [KEY_A, "panel_storage"],
			[KEY_E, "panel_staff"], [KEY_M, "panel_upgrades"], [KEY_ENTER, "confirm"], [KEY_L, "ledger"], [KEY_F, "family_tree"],
			[KEY_I, "inventory"], [KEY_O, "offices"], [KEY_J, "trials"]]:
		var e := InputEventKey.new()
		e.physical_keycode = pair[0]
		e.pressed = true
		check(HudKeys.pressed(e, str(pair[1])), "%s -> %s" % [OS.get_keycode_string(pair[0]), pair[1]])
	var ids := HelpPanel.key_ids()
	for k: String in ["space", "speeds", "group", "tree", "inventory", "ledger", "offices", "trials", "build", "inside",
			"confirm", "esc", "help"]:
		check(k in ids, "the help lists %s" % k)


func test_notices_by_gravity_three_at_most() -> void:
	var done: Array = ["notice.objective_done"]
	eq(HudLayout.notice_gravity("urgent", "notice.loan_due_soon", done), "urgent", "urgent")
	eq(HudLayout.notice_gravity("warning", "notice.employee_idle", done), "warning", "warning pops up too (owner)")
	eq(HudLayout.notice_gravity("info", "notice.objective_done", done), "done", "a goal met")
	eq(HudLayout.notice_gravity("info", "notice.child_born", done), "", "info only in the book")
	var shown: Array = []
	for i: int in 4:
		shown = HudLayout.push_notice(shown, "urgent %d" % i, 3)
	eq(shown, ["urgent 1", "urgent 2", "urgent 3"], "4 urgent: 3 shown, the first one went to the book")
	var cfg: Dictionary = ViewConfig.value("notices", {})
	check((cfg.get("done_keys", []) as Array).has("notice.objective_done"), "done keys in data/view.json")


func test_column_folds_before_overlapping() -> void:
	check(not HudLayout.fold_objective(104, 46), "objective + 2 orders fit (the interior's mock-up)")
	check(HudLayout.fold_objective(150, 60), "too tall: the objective folds")
	check(not HudLayout.fold_objective(186, 0), "no queue: nothing to fold for")


func test_camera_reveals_what_a_panel_covers() -> void:
	var z := HudLayout.zones()
	var view := HudLayout.view_rect()
	var d := HudLayout.reveal_delta(Vector2(700, 200), [z["manage"]], view)
	var after := Vector2(700, 200) - d
	check(view.has_point(after) and not (z["manage"] as Rect2).has_point(after), "out from under the panel: %s" % after)
	eq(HudLayout.reveal_delta(Vector2(400, 200), [z["manage"]], view), Vector2.ZERO, "already in sight: no move")
	var d2 := HudLayout.reveal_delta(Vector2(450, 510), [z["selection"]], view)
	check(view.has_point(Vector2(450, 510) - d2), "out from under the selection bar")


func test_interior_bar_in_zone_six_and_room_centred() -> void:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	eq(_rect(v.get_node("%BuildingBar") as Control), HudLayout.ZONES["selection"], "the building's bar in zone 6")
	check(not v.has_node("%Toolbar") or (v.get_node("%Toolbar") as Node).get_parent().get_parent().name == "BuildingBar",
		"the old toolbar (top right) is inside the bar")
	eq(_rect(v.get_node("%ManageZone") as Control), HudLayout.ZONES["manage"], "the interior's zone 5")
	eq(_rect(v.get_node("%WideZone") as Control), Rect2(244, 58, 712, 430), "the wide panel (_comun.md)")
	for p: Control in [v.storage_panel(), v.production_panel(), v.staff_panel()]:
		eq(str(p.get_parent().name), "ManageZone", "%s in zone 5" % p.name)
	eq(str(v.upgrade_panel().get_parent().name), "WideZone", "the upgrade tree in the wide panel")
	var r := NewGame.from_scenario("town_e_start")
	var sim := Sim.new(r["state"], cat)
	v.order_sink = func(_o: Dictionary) -> void: pass
	v.setup(sim, "bld_0001", "", true)
	eq(v.world_to_screen(v.screen_to_world(Vector2(300, 200))), Vector2(300, 200), "screen ↔ world round trip")
	eq(v.view_center(), HudLayout.view_center(), "the room is centred in the free view")
	check(not (v.get_node("%StatusLabel") as Label).text.is_empty(), "the bar says who works and the queue")
	v.free()
